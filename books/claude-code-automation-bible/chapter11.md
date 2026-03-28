---
title: "全自動化パイプラインの統合と監視"
---

## この章で学ぶこと

- 全自動化システムの統合アーキテクチャ
- Slackベースの監視体系（朝9:00の予定通知 / 夕19:00の実績レポート）
- Next.jsダッシュボード（localhost:4000）の構成とlaunchd常時起動
- エラーハンドリングとリカバリの設計
- 月$100-200のAI予算内でのコスト管理
- STATE.mdの自動更新によるKPI追跡

---

## 11.1 全システムの統合アーキテクチャ

ここまでの章で構築してきた個別のパイプラインを、1つの図にまとめる。

```
┌─────────────────────────────────────────────────────┐
│                   launchd (macOS)                     │
│  スケジューラ：全自動化の起点                          │
├──────────┬──────────┬──────────┬──────────┬───────────┤
│ 08:00    │ 08:30    │ 08:43    │ 09:00    │ 09:30     │
│ Zenn公開 │ Qiita公開│ note投稿 │ 朝digest │ 自動承認  │
└────┬─────┴────┬─────┴────┬─────┴────┬─────┴─────┬─────┘
     │          │          │          │           │
     ▼          ▼          ▼          ▼           ▼
┌─────────┐┌─────────┐┌────────┐┌──────────┐┌──────────┐
│git push ││git push ││Playwright││Dashboard ││Dashboard │
│→ Zenn   ││→ Qiita  ││→ note   ││API       ││API       │
└─────────┘└─────────┘└────────┘└────┬─────┘└────┬─────┘
                                     │           │
                              ┌──────▼───────────▼──────┐
                              │  Next.js Dashboard       │
                              │  localhost:4000           │
                              │  (launchd常時起動)        │
                              ├───────────────────────────┤
                              │ - 部門STATE集約           │
                              │ - 承認キュー管理          │
                              │ - KPIダッシュボード       │
                              │ - Gemini AIチャット       │
                              │ - タスク管理              │
                              └──────────┬────────────────┘
                                         │
                              ┌──────────▼────────────────┐
                              │  Slack Webhook             │
                              │  通知・レポート送信         │
                              └──────────┬────────────────┘
                                         │
                              ┌──────────▼────────────────┐
                              │  CEO（スマホで確認）        │
                              │  承認操作 → 実行           │
                              └───────────────────────────┘

並行稼働:
┌───────────────────────────────────────────────────────┐
│ Autonomos (Sales Cruise)                               │
│ SNS投稿 461件スケジュール済み                           │
│ X / LinkedIn / Threads に30分間隔で自動配信             │
└───────────────────────────────────────────────────────┘
```

### launchdジョブの全一覧

筆者の環境で稼働している全launchdジョブを示す。

```
# ~/Library/LaunchAgents/ に配置されたplistファイル一覧

com.joinclass.ai-ceo-dashboard.plist   # Dashboard常時起動（RunAtLoad + KeepAlive）
com.joinclass.zenn-publish.plist       # Zenn記事公開（毎日 08:00）
com.joinclass.qiita-publish.plist      # Qiita記事公開（毎日 08:30）
com.joinclass.note-publish.plist       # note記事投稿（毎日 08:43）
com.joinclass.auto-morning.plist       # 朝ダイジェスト（毎日 09:00）
com.joinclass.auto-approve.plist       # 自動承認処理（毎日 09:30）
com.joinclass.auto-sns.plist           # SNS投稿実行（毎日 12:00）
com.joinclass.auto-tasks.plist         # タスク自動割り振り（毎日 09:15）
com.joinclass.auto-state-update.plist  # STATE.md自動更新（毎日 18:00）
com.joinclass.auto-sales-pipeline.plist # 営業パイプライン更新（毎日 10:00）
com.joinclass.daily-summary.plist      # 夕方サマリ（毎日 19:00）
com.joinclass.daily-schedule.plist     # 翌日スケジュール生成（毎日 21:00）
```

合計12個のジョブが、毎日決まった時刻に自動実行されている。すべてのジョブは `common.sh` を `source` しており、共通のエラーハンドリング、Slack通知、コスト追跡、git自動コミットの仕組みを使っている。

---

## 11.2 Slackベースの監視体系

全自動化システムの監視は、Slackに集約している。

### 朝9:00 — 予定通知

```
[AI-CEO] 朝ダイジェスト -- 2026-03-28

■ 承認待ち (2件)
  [AQ-021] マーケ: LinkedIn投稿ドラフト | medium
  [AQ-022] 営業: AI自動化コンサル提案書 | high

■ 今日の自動実行予定
  08:00 Zenn記事公開（ストック残: 6本）
  08:30 Qiita記事公開（ストック残: 5本）
  08:43 note記事投稿（ストック残: 4本）
  12:00 SNS投稿 x 12件

■ 部門状態
  開発: 正常 | マーケ: 正常 | 営業: 再編中 | 経理: 正常

■ おすすめアクション
  1. [AQ-022] 高優先度の提案書を確認してください
  2. Zennストックが6本。今週中に補充を推奨
```

### 夕19:00 — 実績レポート

```
[AI-CEO] 夕方サマリ -- 2026-03-28

■ 今日の実績
  Zenn記事公開: 1本（累計14本）
  Qiita記事公開: 1本（累計4本）
  note記事投稿: 1本
  SNS投稿: 12件（成功: 12 / 失敗: 0）
  承認処理: 2件（手動承認: 1 / 自動承認: 1）
  タスク完了: 3件

■ エラー (0件)
  なし

■ コスト
  今月累計: $0.15 / $200 (0.08%)
  ※ Claude Code Maxは固定$200。API追加利用分のみ計上

■ 明日の予定
  Zenn記事公開（ストック残: 5本）
  SNS投稿 x 14件
```

### Slack通知の設計原則

```bash
# common.sh のSlack通知関数
# 全スクリプトがこの関数を使うことで、通知フォーマットを統一する

notify_slack() {
  local message="$1"

  # SLACK_WEBHOOK_URLが未設定の場合はスキップ（開発環境対策）
  if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    log_error "SLACK_WEBHOOK_URL not set"
    return 1
  fi

  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$message" '{text: $text}')" \
    "$SLACK_WEBHOOK_URL" >/dev/null
}
```

通知は「受動的に確認できる」ことが重要だ。能動的に確認が必要な監視は長続きしない。Slackに流しておけば、手が空いたときに確認するだけで済む。

---

## 11.3 ダッシュボード（Next.js / localhost:4000）

CLIとSlackだけでは、全体像の把握が難しい。そこで、Next.jsで経営ダッシュボードを構築し、localhost:4000で常時稼働させている。

### launchdによる常時起動

```xml
<!-- com.joinclass.ai-ceo-dashboard.plist -->
<dict>
  <key>Label</key>
  <string>com.joinclass.ai-ceo-dashboard</string>
  <key>WorkingDirectory</key>
  <string>/Users/kyoagun/workspace/one-ceo/dashboard</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/kyoagun/.nvm/versions/node/v22.17.0/bin/node</string>
    <string>/Users/kyoagun/.nvm/versions/node/v22.17.0/bin/npx</string>
    <string>next</string>
    <string>dev</string>
    <string>--port</string>
    <string>4000</string>
  </array>

  <!-- macOS起動時に自動起動 -->
  <key>RunAtLoad</key>
  <true/>

  <!-- クラッシュしても自動再起動 -->
  <key>KeepAlive</key>
  <true/>
</dict>
```

`RunAtLoad: true` でMac起動時に自動的にダッシュボードが立ち上がる。`KeepAlive: true` でプロセスが落ちても自動復旧する。つまり、Macの電源を入れるだけで全システムが稼働する。

### ダッシュボードの主要機能

```
localhost:4000/
├── /                    # トップ：全社KPIサマリ
├── /departments         # 部門別STATE一覧
├── /approvals           # 承認キュー管理UI
├── /tasks               # タスク管理（部門別）
├── /marketing           # SNS投稿スケジュール・実績
├── /finance             # コスト追跡・月次レポート
├── /chat                # Gemini AIチャット（質問応答）
└── /api/
    ├── /health          # ヘルスチェック
    ├── /morning-digest  # 朝ダイジェスト生成
    ├── /approvals/*     # 承認操作API
    ├── /marketing/*     # SNS投稿API
    ├── /state/*         # STATE更新API
    └── /tasks/*         # タスク管理API
```

### ダッシュボードAPIと自動化スクリプトの連携

すべての自動化スクリプトは、ダッシュボードのAPIを経由して動作する。直接ファイルを操作するのではなく、APIを介することで以下のメリットがある。

```bash
# common.sh から — ダッシュボード起動確認
# 自動化スクリプトは実行前に必ずダッシュボードの起動を確認する
ensure_dashboard() {
  local max_wait=90
  local waited=0

  # 既に起動中なら即リターン
  if curl -sf "$DASHBOARD_URL/api/health" >/dev/null 2>&1; then
    return 0
  fi

  log_info "ダッシュボード起動中..."

  # ビルド済みか確認、なければビルド
  if [ ! -d "$PROJECT_ROOT/dashboard/.next" ]; then
    log_info "ビルド実行中..."
    cd "$PROJECT_ROOT/dashboard" && npm run build &>/dev/null
  fi

  # バックグラウンドで起動し、ヘルスチェックを90秒間ポーリング
  cd "$PROJECT_ROOT/dashboard" && npm run start &>/dev/null &

  while [ $waited -lt $max_wait ]; do
    if curl -sf "$DASHBOARD_URL/api/health" >/dev/null 2>&1; then
      log_info "ダッシュボード起動完了"
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done

  log_error "ダッシュボードが起動できませんでした"
  return 1
}
```

ダッシュボードが落ちていた場合でも、スクリプトが自動的に起動を試みる。最大90秒待機し、それでもダメならエラーとして処理される。

---

## 11.4 エラーハンドリングとリカバリ

全自動化システムで最も重要なのは、**エラーが起きたときに自動的にリカバリし、人間に通知する**仕組みだ。

### 3段階のエラーハンドリング

```bash
# common.sh のエラートラップ
# 全スクリプトがこの仕組みを継承する

# Level 1: エラー時の自動通知
on_error_notify() {
  local exit_code=$?
  local line_no=${1:-unknown}
  log_error "スクリプト失敗: $SCRIPT_NAME (行:$line_no, 終了コード:$exit_code)"

  # Slack通知で即座にCEOに知らせる
  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -sf -X POST \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg text ":x: [AI-CEO] $SCRIPT_NAME 失敗 (行:$line_no, コード:$exit_code)" \
        '{text: $text}')" \
      "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi
}
trap 'on_error_notify $LINENO' ERR

# Level 2: リトライ（最大3回）
retry() {
  local max_attempts=3
  local attempt=1
  local cmd="$@"

  while [ $attempt -le $max_attempts ]; do
    if eval "$cmd"; then
      return 0
    fi
    log_info "リトライ $attempt/$max_attempts: $cmd"
    attempt=$((attempt + 1))
    sleep 2
  done

  # Level 3: 3回失敗 → エスカレーション
  log_error "3回失敗: $cmd"
  return 1
}
```

### エスカレーションの仕組み

3回リトライしても失敗した場合は、`approval-queue.md` にエスカレーションとして追加される。

```yaml
# エスカレーションルール
escalation:
  # 自動実行タスクが3回連続失敗 → CEO通知
  consecutive_failures: 3

  # 予算の80%に到達 → CEO通知
  budget_warning: 80%

  # セキュリティインシデントの疑い → 即座にCEO通知
  security_incident: immediate

  # ユーザーからのクレーム → 即座にCEO通知
  customer_complaint: immediate
```

### 実際のエラー事例と対処

運用3ヶ月間で発生した主要エラーとその対処を示す。

| エラー | 原因 | 検知方法 | 対処 |
|---|---|---|---|
| Zenn公開スクリプト失敗 | git pushのコンフリクト | Slack通知 | `git pull --rebase` を追加 |
| ダッシュボード停止 | Node.jsメモリ不足 | KeepAliveで自動復旧 | `--max-old-space-size=512` を追加 |
| note投稿失敗 | Cookie期限切れ | Slack通知 | 手動ログインでCookie更新 |
| Autonomos API タイムアウト | 一時的なネットワーク障害 | Autonomos側で自動リトライ | 対処不要 |

最も頻度が高かったのは「git pushのコンフリクト」だ。手動でファイルを編集している最中に自動スクリプトがpushしようとして衝突する。対策として、スクリプトに `git pull --rebase` を先に実行するロジックを追加した。

---

## 11.5 コスト管理（月$100-200のAI予算内に収める）

AI運用の最大コストは**Claude Code Maxプラン（月額$200固定）**だ。これ以外のAPI利用を最小化することで、予算内に収めている。

### コスト構造

```
月間コスト内訳（実績）:
  Claude Code Max:      $200（固定）  ← 全AI処理のメイン
  Gemini API:           $0.04         ← ダッシュボードAIチャットのみ
  Firebase:             $0            ← 無料枠内
  GitHub Actions:       $0            ← 無料枠内
  ──────────────────────────────
  AI関連合計:           $200.04/月
```

### 自動コスト追跡

```bash
# common.sh のコスト追跡関数
# 各スクリプトが実行後にAPIコストを記録する

track_cost() {
  local api_name="$1"
  local cost_usd="${2:-0.01}"
  local tracker="$COMPANY_DIR/scripts/cost-tracker.json"

  # 月が変わったらリセット
  local current_month=$(date '+%Y-%m')
  local stored_month=$(jq -r '.month' "$tracker")
  if [ "$current_month" != "$stored_month" ]; then
    echo '{"month":"'"$current_month"'","total_usd":0,"calls":{}}' > "$tracker"
  fi

  # コスト加算
  local new_total=$(jq --arg cost "$cost_usd" \
    '.total_usd += ($cost | tonumber)' "$tracker")
  echo "$new_total" | jq . > "$tracker"

  # 閾値チェック（$200超過で自動停止）
  local total=$(echo "$new_total" | jq '.total_usd')
  if (( $(echo "$total >= 200" | bc -l) )); then
    notify_slack ":rotating_light: 月間コスト上限到達: \$${total}。自動実行を停止します。"
    return 1  # これにより後続のスクリプトも実行されない
  elif (( $(echo "$total >= 160" | bc -l) )); then
    notify_slack ":warning: 月間コスト警告: \$${total} / \$200"
  fi
}
```

### 予算超過防止の多重防御

```
防御レイヤー:
  Layer 1: Claude Code Maxの固定料金（$200以上かからない構造）
  Layer 2: 追加API利用のtrack_cost()による積算管理
  Layer 3: check_cost_limit()による実行前チェック
  Layer 4: $160到達でSlack警告
  Layer 5: $200到達で全自動実行を停止 + 即時CEO通知
```

実際の運用では、Layer 1（固定料金）のおかげで予算超過は一度も起きていない。追加APIコストは月$1未満に収まっている。「$200を超えない構造にする」ことが、最も効果的なコスト管理だ。

---

## 11.6 KPIの自動追跡（STATE.mdの自動更新）

全自動化の最後のピースは、**結果の自動追跡**だ。手動でKPIを集計するのは非効率なので、STATE.mdを自動更新する仕組みを構築している。

### STATE自動更新の仕組み

```bash
#!/bin/bash
# auto-state-update.sh
# タスク集計・パイプライン状態からSTATE.mdを自動更新
# launchd: 毎日 18:00 JST

source "$(dirname "$0")/common.sh"

main() {
  log_info "=== STATE自動更新開始 ==="

  # ダッシュボードAPIで状態を集約・更新
  # 内部処理:
  # 1. 各部門のタスク完了数・進行中数を集計
  # 2. 承認キューの件数を取得
  # 3. Zenn/Qiitaのストック残数を確認
  # 4. SNS投稿の成功/失敗数を集計
  # 5. コスト実績を反映
  # 6. STATE.mdを更新
  local result
  result=$(api_post "state/auto-update" '{}')

  local success
  success=$(echo "$result" | jq -r '.success')

  if [ "$success" = "true" ]; then
    local updated
    updated=$(echo "$result" | jq -r \
      '.updated | "完了:\(.completedTasks) 進行中:\(.inProgressTasks) 承認待ち:\(.approvalCount)"')
    log_info "STATE更新完了: $updated"
  fi

  # 変更をgitにコミット
  git_auto_commit "auto: STATE.md 自動更新"
}

main "$@"
```

### 追跡しているKPI

```yaml
# STATE.mdで自動追跡されるKPI一覧
auto_tracked_kpis:
  # 書籍・記事
  zenn_books_published: 7        # 公開済み書籍数
  zenn_books_sold: 11            # 累計販売部数
  zenn_articles_published: 14    # 公開済み記事数
  qiita_articles_published: 4   # Qiita記事数
  article_stock_remaining: 7    # ストック残数

  # SNS
  sns_scheduled_total: 461       # スケジュール済み投稿数
  sns_posted_today: 12           # 今日の投稿数
  sns_success_rate: 100%         # 投稿成功率

  # 営業
  pipeline_deals: 0              # パイプライン案件数
  consulting_inquiries: 0        # 問い合わせ数

  # コスト
  monthly_ai_cost: "$200"        # 月間AIコスト
  monthly_total_cost: "¥32,280"  # 月間総コスト
```

### gitコミットログによるKPI履歴

STATE.mdの自動更新は毎日gitにコミットされる。つまり、`git log` でKPIの変遷を追跡できる。

```bash
# STATE.mdの変更履歴を表示
git log --oneline --follow .company/STATE.md

# 出力例:
# abc1234 auto: STATE.md 自動更新 (完了:3 進行中:5 承認待ち:1)
# def5678 auto: STATE.md 自動更新 (完了:2 進行中:4 承認待ち:3)
# ghi9012 auto: STATE.md 自動更新 (完了:5 進行中:3 承認待ち:0)
```

専用のBI（ビジネスインテリジェンス）ツールは不要だ。git + Markdown + Slackの組み合わせで、一人経営に必要十分な監視・追跡が実現できる。

---

## まとめ

- 12個のlaunchdジョブが毎日自動実行され、Mac起動時にすべて自動復旧する
- 監視はSlackに集約。朝9:00に予定、夕19:00に実績を自動通知
- Next.jsダッシュボード（localhost:4000）はlaunchdでKeepAlive常時起動。全APIの中枢
- エラーハンドリングは3段階：自動通知 → リトライ3回 → CEOエスカレーション
- コスト管理の核心は「$200を超えない構造にする」こと。Claude Code Max固定料金が鍵
- STATE.mdの毎日自動更新により、KPIがgitの履歴として自動蓄積される
