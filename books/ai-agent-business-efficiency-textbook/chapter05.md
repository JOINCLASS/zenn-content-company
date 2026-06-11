---
title: "AIエージェント開発（Claude Agent SDK + MCP）"
---

# AIエージェント開発（Claude Agent SDK + MCP）

## この章で学ぶこと

- 業務効率化プロジェクトに最適なAIエージェントアーキテクチャの選定基準
- Claude Agent SDKを用いたエージェント構築の基本パターン
- MCP（Model Context Protocol）サーバーを使った既存システム連携の設計
- 「**業務理解者が読めるコード**」を書くためのスタイルガイド
- PoCから本番運用に移行するために最初から組み込むべき5要素

## はじめに -- プロジェクト推進者がコードを読める必要性

「AI開発はエンジニアに任せる」というスタンスでプロジェクトを進めると、ほぼ確実に失敗する。

なぜなら、AIエージェントの挙動は**プロンプト・ツール定義・コンテキスト**によって決まる。これらはコードと業務知識の境界線上にある。エンジニアだけで設計すると業務知識が抜け、業務担当者だけで考えると技術制約が見えない。

本書のターゲットである**プロジェクト推進者**は、コードの全部を書く必要はない。しかし、**コードの構造を読み、設計判断に関与できる**レベルの理解は必須だ。

本章では、業務理解者がエンジニアと協働するために最低限必要な、AIエージェント開発の構造を解説する。

:::message
**筆者の実践メモ**
筆者は支援する全案件で、業務担当者に最低限のClaude Agent SDKのコードを読めるようになってもらう時間を確保している。最初は3-5時間の勉強会で十分。これをやるかやらないかで、その後の意思決定の質が大きく変わる。
:::

## AIエージェント開発の3つの層

業務効率化向けのAIエージェントは、以下の3層構造で考えると整理しやすい。

```
[Layer 1: 業務知識層]
   ├ プロンプト（業務手順を自然言語で記述）
   ├ コンテキスト（社内マニュアル・FAQ・事例）
   └ 判断基準（業務ルール・例外パターン）

[Layer 2: ツール層]
   ├ 業務システム連携（CRM・ERP・販売管理）
   ├ データ参照（DB・ファイルサーバー）
   └ 外部API（地図・天気・公的データ等）

[Layer 3: 実行制御層]
   ├ エージェントSDK（Claude Agent SDK）
   ├ オーケストレーション（複数ステップの制御）
   └ ガードレール（出力フィルタ・コスト制限）
```

業務担当者が主に関わるのは**Layer 1**。エンジニアが主に担当するのは**Layer 2・3**。両者の境界面で齟齬が出ないよう、明確に分担する。

## なぜClaude Agent SDK + MCPを選ぶか

エージェント開発のフレームワークは複数あるが、業務効率化プロジェクトでは以下の理由でClaude Agent SDK + MCPを推奨する。

### Claude Agent SDKの利点

- **業務システム連携のしやすさ**: Tool定義がシンプル
- **長文コンテキスト対応**: 社内マニュアル等を大量に渡せる
- **企業利用での信頼性**: SOC 2 Type II準拠等
- **ドキュメント・サポートが充実**

### MCPの利点

- **業務システムのアダプタを再利用できる**: 一度作れば他プロジェクトでも使える
- **言語・フレームワーク非依存**: TypeScript・Python・Goで実装可能
- **セキュリティ境界が明確**: AIモデルとシステムの間に明示的な層
- **複数のAIエージェントから共通利用可能**

### 代替案との比較

| 項目 | Claude Agent SDK | LangChain | 独自実装 |
|------|----------------|-----------|---------|
| 学習コスト | 低 | 高 | 中 |
| 業務システム連携 | MCPで標準化 | 個別実装 | 個別実装 |
| 保守性 | 高 | 中 | 低 |
| エンタープライズ要件 | 対応 | プラグイン依存 | 自前 |
| 推奨業務規模 | 中〜大 | 大 | 小 |

業務効率化プロジェクト（中規模）では、Claude Agent SDK + MCPが現時点で最もバランスが良い。

## エージェント開発の基本パターン

### 最小構成のClaude Agentエージェント例

以下は、Claude APIを使った業務支援エージェントの最小例である。プロジェクト推進者が「**こういう構造でできているのか**」を理解できるレベルの説明を心がける。

```python
# 業務支援エージェントの最小実装例
# v1.0 (2026-06-11) / Claude Sonnet 4 想定

from anthropic import Anthropic

# クライアント初期化（APIキーは環境変数から取得）
client = Anthropic()

# システムプロンプト: エージェントの振る舞いを定義
SYSTEM_PROMPT = """
あなたは顧客問い合わせ対応の業務支援エージェントです。

# あなたの役割
- 顧客からのメールを分類する（新規見積/既存契約/クレーム/その他）
- 分類結果と確信度を返す
- 確信度が0.7未満の場合は「人間確認必要」と明示する

# 業務ルール
- 「至急」「緊急」を含むメールは確信度に関わらず高優先度とする
- 金額が明示されているメールは見積関連として扱う
"""

def classify_email(email_body: str) -> dict:
    """メールを分類して結果を返す"""
    response = client.messages.create(
        model="claude-sonnet-4",
        max_tokens=1024,
        system=SYSTEM_PROMPT,
        messages=[
            {
                "role": "user",
                "content": f"以下のメールを分類してください:\n\n{email_body}"
            }
        ]
    )
    return parse_response(response.content[0].text)
```

このコードでも業務担当者が読めば、「**何をしているか**」「**業務ルールがどこに書かれているか**」が分かる。

### Tool（関数呼び出し）を使った構成例

AIエージェントに業務システムを操作させるには、**Tool**を定義する。

```python
# CRM検索ツールの定義例
TOOLS = [
    {
        "name": "search_customer",
        "description": "顧客名から顧客情報を検索する",
        "input_schema": {
            "type": "object",
            "properties": {
                "customer_name": {
                    "type": "string",
                    "description": "検索する顧客名"
                }
            },
            "required": ["customer_name"]
        }
    },
    {
        "name": "create_ticket",
        "description": "サポートチケットを作成する",
        "input_schema": {
            "type": "object",
            "properties": {
                "customer_id": {"type": "string"},
                "subject": {"type": "string"},
                "priority": {
                    "type": "string",
                    "enum": ["low", "medium", "high"]
                }
            },
            "required": ["customer_id", "subject", "priority"]
        }
    }
]
```

業務担当者は、この `description` を書くのに関与する。**自然言語で書かれた説明文**が、AIの判断品質を決める重要な要素になる。

### Tool呼び出しの実装

```python
def handle_email_with_tools(email_body: str) -> dict:
    """ツールを使いながらメール対応"""
    messages = [{"role": "user", "content": email_body}]
    
    while True:
        response = client.messages.create(
            model="claude-sonnet-4",
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages
        )
        
        # Toolを使う必要があるか判定
        if response.stop_reason == "tool_use":
            # AIが要求したツールを実行
            tool_result = execute_tool(response.content)
            messages.append({"role": "assistant", "content": response.content})
            messages.append({
                "role": "user",
                "content": [{"type": "tool_result", "content": tool_result}]
            })
        else:
            # 最終回答が出た
            return extract_final_answer(response.content)
```

このループ構造を理解すると、「**AIが自分で必要な情報を取りに行ける**」というエージェントの本質が見えてくる。

## MCPサーバー設計の指針

MCPサーバーは、AIエージェントから業務システムへの**アダプタ層**だ。直接APIを叩くのではなく、MCPサーバーを挟むことで、以下のメリットが得られる。

### MCPサーバーを使うメリット

1. **権限制御の集約**: アクセス権限・利用ログをMCPサーバーで一元管理
2. **既存システムの保護**: AIから直接DBに繋がず、MCPで読み書きを制限
3. **再利用性**: 一度作ったMCPサーバーは他プロジェクトでも使える
4. **テスト容易性**: AIなしでMCPサーバー単体テスト可能

### MCPサーバー設計のチェックリスト

```
□ 認証・認可が組み込まれているか（APIキー/OAuth）
□ レート制限が実装されているか
□ 監査ログが取られているか（誰が・いつ・何にアクセスしたか）
□ エラー時のレスポンスが標準化されているか
□ Tool定義のdescriptionが業務担当者でも理解できるか
□ 機密情報（個人情報・財務データ）のマスキングがあるか
□ 開発環境/本番環境が分離されているか
□ ヘルスチェックエンドポイントがあるか
□ バージョン管理がされているか
□ ドキュメントが整備されているか
```

### MCPサーバーの設計例

CRMアクセス用のMCPサーバーを設計する場合、以下のような構造になる。

```
crm-mcp-server/
├── server.ts            # MCPサーバーのエントリーポイント
├── tools/
│   ├── search_customer.ts
│   ├── get_customer_history.ts
│   └── create_ticket.ts
├── auth/
│   ├── api_key.ts
│   └── audit_log.ts
├── clients/
│   └── crm_api_client.ts  # CRM APIへの実アクセス
├── config/
│   └── permissions.yaml   # ツールごとの権限定義
└── tests/
    └── tools.test.ts
```

業務担当者は `permissions.yaml` の中身を確認する。「**このツールは誰がアクセスできるか**」「**書き込みか読み取りか**」が業務ルールに合っているかをチェックする。

```yaml
# permissions.yaml の例
tools:
  search_customer:
    access: read
    allowed_users: ["sales_team", "cs_team"]
    rate_limit: 100/hour
    
  get_customer_history:
    access: read
    allowed_users: ["cs_team", "compliance_team"]
    rate_limit: 50/hour
    masking:
      - field: "phone_number"
        rule: "last_4_digits"
      
  create_ticket:
    access: write
    allowed_users: ["cs_team"]
    rate_limit: 30/hour
    require_review: false  # 人レビュー無しで作成可能
```

このYAML設定だけで「**AIに何を許すか**」が決まる。プロジェクト推進者は、ここに業務ルール・コンプライアンス要件を反映する。

## エージェントのスタイルガイド

業務理解者が読めるエージェントコードを書くための、推奨スタイルガイドを示す。

### スタイル1: 業務知識を「コメント」ではなく「プロンプト」に書く

悪い例:

```python
# 顧客の前回連絡日が30日以上前なら「休眠」フラグを立てる
if days_since_contact > 30:
    customer.status = "dormant"
```

良い例: 業務ルールをプロンプトに記述

```python
SYSTEM_PROMPT = """
# 顧客ステータス判定ルール
- 前回連絡から30日以内: アクティブ
- 30-90日: 要フォロー
- 90日以上: 休眠
- 例外: 大口顧客（年間100万円以上）は休眠判定を60日に延長
"""
```

プロンプトに書けば、業務ルールの変更時にコードを触らず、プロンプトだけを修正すればよい。

### スタイル2: ツール名・引数名は業務用語で書く

悪い例: 技術寄りの命名

```python
def get_data(id: str) -> dict: ...
```

良い例: 業務用語で命名

```python
def search_customer_by_id(customer_id: str) -> dict: ...
```

業務担当者が読んだときに「**何の操作か**」が分かる名前にする。

### スタイル3: マジックナンバーを定数化

悪い例:

```python
if confidence < 0.7:
    escalate_to_human()
```

良い例: 業務ルールに紐付けた定数

```python
# 業務ルール: 確信度70%未満は人レビュー必須（コンプラ要件）
CONFIDENCE_THRESHOLD_FOR_HUMAN_REVIEW = 0.7

if confidence < CONFIDENCE_THRESHOLD_FOR_HUMAN_REVIEW:
    escalate_to_human()
```

数字の根拠（業務ルール）が見えるようにする。

### スタイル4: バージョン情報を明示する

```python
# === エージェント定義 ===
AGENT_VERSION = "1.2.0"
PROMPT_VERSION = "2026-06-11"
MODEL = "claude-sonnet-4"

# 変更履歴:
# 1.2.0 (2026-06-11) - 確信度閾値を0.7→0.75に変更
# 1.1.0 (2026-05-20) - クレーム検出ルール追加
# 1.0.0 (2026-04-15) - 初版
```

業務ルール変更とコード変更の対応が追跡できるようにする。

### スタイル5: テストデータを業務に近い形で用意する

```python
# tests/test_classification.py
TEST_CASES = [
    {
        "name": "明確な見積依頼",
        "email": "御社のサービスについて、月間100ユーザーで利用したい場合の見積もりをお願いします。",
        "expected_category": "新規見積",
        "expected_confidence_min": 0.9
    },
    {
        "name": "判断が難しいケース",
        "email": "お世話になります。先日の件、その後いかがでしょうか。",
        "expected_category": None,  # 確信度低くなる想定
        "expected_confidence_max": 0.6
    },
    # ...
]
```

業務担当者がテストケースを追加できる形にしておく。

## PoCから本番運用に移行するために最初から組み込むべき5要素

「**PoCで動いたが本番に乗せられない**」を避けるため、PoC段階から以下の5要素を組み込む。

### 要素1: 認証・認可

- API利用者の特定（誰が使ったか）
- 操作可能なツールの制限（権限管理）
- セッション管理（ログイン状態の管理）

**PoCでよくある手抜き**: APIキーをハードコード、認証なしで全員アクセス可能。
**正しい姿**: 最初からAPIキー or OAuth、最低限のロール分離。

### 要素2: 監査ログ

- 入力（誰が・いつ・何を入力したか）
- 出力（AIが何を返したか）
- ツール呼び出し（どんなシステムを操作したか）
- 確信度・モデルバージョン

**PoCでよくある手抜き**: ログ出力なし、または標準出力のみ。
**正しい姿**: 構造化ログ（JSON）でファイル/データベースに保存。検索可能。

```python
# 監査ログの例
import json
from datetime import datetime

def log_inference(user_id, input_data, output, metadata):
    log_entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "user_id": user_id,
        "input_hash": hash_input(input_data),  # 個人情報は直接記録しない
        "output_category": output.get("category"),
        "confidence": output.get("confidence"),
        "model": metadata["model"],
        "agent_version": metadata["agent_version"],
        "tool_calls": metadata["tool_calls"]
    }
    write_to_log_store(log_entry)
```

### 要素3: コスト管理

- 1日あたりのAPI呼び出し上限
- 1ユーザーあたりの上限
- 異常使用検知（短時間で大量呼び出し）

**PoCでよくある手抜き**: 利用量無制限。
**正しい姿**: レート制限実装、月間予算アラート。

```python
# 簡易レート制限の例
from datetime import datetime, timedelta

class RateLimiter:
    def __init__(self, max_calls: int, period_minutes: int):
        self.max_calls = max_calls
        self.period = timedelta(minutes=period_minutes)
        self.calls = {}
    
    def check(self, user_id: str) -> bool:
        now = datetime.utcnow()
        user_calls = self.calls.get(user_id, [])
        # 期間内の呼び出しのみ残す
        user_calls = [t for t in user_calls if now - t < self.period]
        if len(user_calls) >= self.max_calls:
            return False
        user_calls.append(now)
        self.calls[user_id] = user_calls
        return True
```

### 要素4: フォールバック・エラー処理

- AI API障害時の動作（人にエスカレーション）
- タイムアウト時の動作
- 確信度低下時の動作

**PoCでよくある手抜き**: エラーで停止。
**正しい姿**: 必ず「**人に渡す**」経路を持つ。

```python
def safe_classify(email_body: str) -> dict:
    """フォールバック付きの分類関数"""
    try:
        result = classify_email(email_body)
        if result["confidence"] < 0.7:
            return {"status": "needs_human", "reason": "low_confidence"}
        return {"status": "success", **result}
    except APIError as e:
        log_error(e)
        return {"status": "needs_human", "reason": "api_error"}
    except TimeoutError:
        return {"status": "needs_human", "reason": "timeout"}
```

### 要素5: 性能監視

- レスポンス時間
- エラー率
- 精度（人レビュー時の修正率）
- コスト（モデル/ユーザー/日次）

**PoCでよくある手抜き**: 計測なし。
**正しい姿**: 主要メトリクスをダッシュボード化。

これら5要素は、後付けすると工数が膨大になる。PoC段階で最低限の実装を入れておくべきだ。

## 開発の進め方（2-4週間のスプリント）

PoC開発は、2-4週間のスプリントで進める。

### Week 1: 環境構築・最小プロトタイプ

- APIキー取得、SDK導入
- 単純な分類エージェントを動かす
- ローカルでのテスト

**ゴール**: 「メール本文を入れたら分類結果が返ってくる」状態を達成。

### Week 2: ツール統合・現実データテスト

- MCPサーバーまたは直接Tool呼び出しの実装
- 実際の業務データ（匿名化）でのテスト
- プロンプト調整

**ゴール**: 30-50件の実データで、目標精度（例: 80%）を達成。

### Week 3: 運用要素の追加

- 認証・ログ・レート制限の実装
- フォールバック経路の設計
- 簡易UI（必要に応じて）

**ゴール**: 「**現場が触れる**」状態のプロトタイプを完成。

### Week 4: 内部UAT・精度測定

- 業務担当者数名による試用
- 精度・処理時間・コストの実測
- 改善項目の洗い出し

**ゴール**: 本番移行可否の判断材料を揃える。

## エンジニア・業務担当者の役割分担

PoC期間中の役割分担を明確にしておく。

| タスク | エンジニア | 業務担当者 | 共同 |
|--------|-----------|----------|------|
| API認証設定 | ◎ | | |
| MCPサーバー実装 | ◎ | | |
| プロンプト設計 | | | ◎ |
| Tool定義のdescription | | ◎ | |
| 業務ルールの定数化 | | | ◎ |
| エラーハンドリング設計 | ◎ | | |
| テストデータ作成 | | ◎ | |
| 精度評価 | | ◎ | |
| ログ設計 | ◎ | | |
| パフォーマンス最適化 | ◎ | | |

**プロンプト設計とTool定義のdescription**は、業務担当者の関与が必須。ここを丸投げすると、AIの精度が一気に落ちる。

## PoC開発完了の判断基準（チェックリスト）

```
□ 業務データ50件以上での精度測定が完了している
□ 目標精度（例: 80%）を達成している、または明確な改善計画がある
□ 認証・認可が実装されている
□ 監査ログが構造化形式で出力されている
□ レート制限・コスト上限が実装されている
□ フォールバック経路（人へのエスカレーション）が動作している
□ 主要メトリクスがダッシュボードまたは集計可能な形で取れている
□ コードがバージョン管理されている
□ 業務担当者が3名以上、実際に触って動作確認している
□ 本番運用に必要な追加コスト・期間が見積もられている
```

7-8項目以上で、次フェーズ（UAT・本番移行）に進む。

## まとめ

- AIエージェント開発は3層（業務知識/ツール/実行制御）で整理する
- Claude Agent SDK + MCPが業務効率化プロジェクトには最も適している
- プロジェクト推進者は「**コードを読める**」レベルの理解を持つ
- PoCから本番移行を見据え、5要素（認証/ログ/コスト/フォールバック/監視）を最初から組み込む
- スタイルガイドを守り、業務担当者が読めるコードを書く
- 2-4週間のスプリントでPoCを完成させる

## 次章への導線

第6章では、PoCを本番運用に移行するプロセスを扱う。

具体的には:
- PoC→本番のギャップを埋める運用設計
- インフラ構成（クラウド/オンプレ/ハイブリッド）の選定
- 監視・アラート・SLO設計
- リリース戦略（カナリア/段階展開）
- セキュリティレビューの進め方

「**PoCで動く**」と「**本番で動き続ける**」の間には大きな壁がある。その壁の越え方を学ぶ。

---

**関連書籍**

- 『Claude Codeマルチエージェント開発』(Zenn) — エージェント開発のさらに技術的な深掘り
- 『Claude Code × MCP サーバー開発入門』(Zenn) — MCPサーバー設計の専門書
- 全書籍一覧: https://zenn.dev/joinclass?tab=books

**AIコンサル無料診断**: https://joinclass.co.jp/#cta
