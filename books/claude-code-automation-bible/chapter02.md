---
title: "Claude Code自動化の4つの柱 — Hooks・Skills・MCP・外部スクリプト"
free: true
---

# Claude Code自動化の4つの柱 — Hooks・Skills・MCP・外部スクリプト

:::message
**この章で学ぶこと**
- Claude Codeの自動化を構成する4つの仕組みの役割と違い
- 各仕組みが得意なユースケース
- 4つをどう組み合わせるかの判断フローチャート
- 実際の運用で使い分けている著者の事例
:::

## 自動化は1つの技術では完成しない

前章で「手動Claude Codeの限界」を見た。では、自動化するにはどうすればいいのか。

結論から言うと、**Claude Codeの自動化には4つの仕組みが必要**で、それぞれ得意領域が異なる。1つだけでは全体をカバーできない。

```
┌────────────────────────────────────────────────┐
│          Claude Code 自動化の4つの柱             │
├────────────┬────────────┬──────────┬───────────┤
│   Hooks    │   Skills   │   MCP    │ 外部       │
│            │            │          │ スクリプト  │
│ イベント    │ ワークフロー │ ツール    │ OS レベル  │
│ 駆動       │ 定義       │ 連携     │ スケジュール │
└────────────┴────────────┴──────────┴───────────┘
  Claude Code の「内側」             「外側」
```

左の3つ（Hooks、Skills、MCP）はClaude Codeの**内側**の仕組みだ。Claude Codeが起動している間に動く。

右の1つ（外部スクリプト）はClaude Codeの**外側**の仕組みだ。Claude Codeが起動していなくても、OSレベルで定時実行される。

この「内側と外側」の組み合わせが、24時間止まらないAI自動化の核心だ。

## 第1の柱: Hooks — イベント駆動の自動実行

### Hooksとは

Hooksは、Claude Codeの内部イベントに応じて自動的にスクリプトを実行する仕組みだ。「何かが起きたとき、自動的にこれをやれ」というトリガー型の自動化である。

```jsonc
// .claude/settings.local.json の hooks セクション
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        // Bashツール実行前に安全性チェックを行う
        "hook": "bash .claude/hooks/pre-bash-check.sh"
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        // ファイル書き込み後に自動でlintを実行する
        "hook": "bash .claude/hooks/post-write-lint.sh"
      }
    ]
  }
}
```

### Hooksが得意なこと

- **ガードレール** — 危険なコマンドの実行前に安全性チェック
- **自動検証** — ファイル変更後にlint、テスト、型チェックを自動実行
- **通知** — エラー発生時にSlackやメールで自動通知
- **ログ記録** — 全操作の自動記録

### Hooksの特徴

| 項目 | 内容 |
|------|------|
| トリガー | Claude Code内のツール使用イベント |
| 実行タイミング | ツール使用の前（Pre）または後（Post） |
| 実行環境 | ローカルのシェル |
| 設定場所 | `.claude/settings.local.json` |
| ユースケース | ガードレール、自動検証、通知 |

Hooksは「受動的」な自動化だ。何かが起きるのを待って反応する。自分からは動かない。

## 第2の柱: Skills — 再利用可能なワークフロー定義

### Skillsとは

Skillsは、Claude Codeに「こういうタスクはこの手順でやれ」と教える仕組みだ。Markdownファイルでワークフローを定義し、スラッシュコマンドで呼び出す。

```markdown
<!-- .claude/skills/write-zenn.md -->
---
name: write-zenn
description: Zenn記事の執筆ワークフロー
---

# Zenn記事執筆スキル

## 手順

1. トピックと対象読者を確認する
2. `.company/steering/brand.md` のトーン規約を読む
3. 記事構成（H2 x 3-5個）をまず作成する
4. 各セクションを執筆する
5. コードブロックには必ず「なぜ」のコメントを入れる
6. フロントマターを設定する（topics, published, etc）
7. 文字数を確認する（3,000-8,000字）
```

### Skillsが得意なこと

- **定型ワークフローの標準化** — 記事執筆、提案書作成、コードレビューなどの手順を統一
- **品質基準の埋め込み** — 「毎回このチェックリストを通す」をスキル定義に含める
- **チーム共有** — `.claude/skills/` ディレクトリをgitで管理し、全メンバーが同じワークフローを使う

### Skillsの特徴

| 項目 | 内容 |
|------|------|
| トリガー | ユーザーのスラッシュコマンド、またはエージェントからの呼び出し |
| 実行タイミング | 明示的に呼び出されたとき |
| 実行環境 | Claude Codeのコンテキスト内 |
| 設定場所 | `.claude/skills/*.md` |
| ユースケース | 定型ワークフロー、品質基準の強制 |

筆者の環境では、以下の5つのスキルが日常的に稼働している。

```
.claude/skills/
├── write-zenn.md          # Zenn記事執筆
├── write-qiita.md         # Qiita記事執筆
├── write-note.md          # note記事執筆
├── publish-zenn-book.md   # Zenn書籍出版
└── publish-kindle.md      # Kindle出版
```

Skillsは「能動的だが、呼び出しが必要」な自動化だ。定義しておけば、いつでも同じ品質で実行できる。

## 第3の柱: MCP — 外部ツール連携の標準プロトコル

### MCPとは

MCP（Model Context Protocol）は、Claude Codeが外部ツールやサービスと連携するための標準プロトコルだ。Slack、GitHub、データベース、APIなど、あらゆる外部サービスをClaude Codeから操作できるようにする。

```jsonc
// .claude/settings.local.json の mcpServers セクション
{
  "mcpServers": {
    "slack": {
      // Slack MCPサーバー: チャンネルへの投稿・読み取りが可能
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-..."
      }
    },
    "github": {
      // GitHub MCPサーバー: Issue・PR操作が可能
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-github"],
      "env": {
        "GITHUB_TOKEN": "your-github-token"
      }
    }
  }
}
```

### MCPが得意なこと

- **外部サービスとの双方向連携** — Slackにメッセージを送る、GitHubにIssueを作る
- **データの取得** — 外部APIからデータを引っ張ってきて分析する
- **ツールチェーン** — 複数のサービスを組み合わせた複雑なワークフロー

### MCPの特徴

| 項目 | 内容 |
|------|------|
| トリガー | Claude Codeからのツール呼び出し |
| 実行タイミング | Claude Codeがツールを使用するとき |
| 実行環境 | MCPサーバープロセス（ローカルまたはリモート） |
| 設定場所 | `.claude/settings.local.json` の `mcpServers` |
| ユースケース | 外部サービス連携、データ取得、通知 |

MCPは「Claude Codeの手足を増やす」仕組みだ。素のClaude Codeはローカルファイルの読み書きとシェルコマンドしかできないが、MCPを通じてSlack、GitHub、データベース、Web APIなど、あらゆる外部サービスを操作できるようになる。

## 第4の柱: 外部スクリプト — Claude Codeの外側の自動化

### 外部スクリプトとは

ここまでの3つ（Hooks、Skills、MCP）は、すべてClaude Codeが起動している間に動く仕組みだった。だが、24時間365日の自動化を実現するには、**Claude Codeが起動していなくても動く仕組み**が必要だ。

それが外部スクリプトだ。bash、launchd（macOS）、cron（Linux）、Playwrightなどを使って、OSレベルでスケジュール実行する。

```bash
#!/bin/bash
# auto-morning.sh — 毎朝9:00に自動実行される朝ダイジェスト
# launchdから起動され、ダッシュボードAPIを叩いて結果をSlack送信

source "$(dirname "$0")/common.sh"

main() {
  log_info "=== 朝ダイジェスト生成開始 ==="

  # 月間コスト上限をチェック（$200超えなら実行しない）
  check_cost_limit || exit 0

  # ダッシュボードが起動しているか確認（最大90秒待機）
  ensure_dashboard || exit 1

  # APIを叩いてダイジェスト生成
  local result
  result=$(api_post "morning-digest" '{}')

  if [ $? -ne 0 ] || [ -z "$result" ]; then
    log_error "API呼び出し失敗"
    exit 1
  fi

  # .company/の変更があればgit自動コミット
  git_auto_commit "auto: 朝ダイジェスト実行に伴う自動更新"

  log_info "=== 朝ダイジェスト生成完了 ==="
}

main "$@"
```

### macOSでの定時実行: launchd

macOSでは、cronの代わりにlaunchdを使うのが標準だ。plistファイルを `~/Library/LaunchAgents/` に配置する。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- com.joinclass.ai-ceo-dashboard.plist -->
<!-- ダッシュボードをOS起動時に自動起動し、常時稼働させる -->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.joinclass.ai-ceo-dashboard</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/node</string>
    <string>npx</string>
    <string>next</string>
    <string>dev</string>
    <string>--port</string>
    <string>4000</string>
  </array>
  <key>RunAtLoad</key>  <!-- OS起動時に自動実行 -->
  <true/>
  <key>KeepAlive</key>  <!-- クラッシュしても自動再起動 -->
  <true/>
</dict>
</plist>
```

### 外部スクリプトが得意なこと

- **定時実行** — 毎朝9時のダイジェスト、毎時のSNS投稿、毎日の記事公開
- **常時稼働** — ダッシュボードやAPIサーバーの永続実行
- **ブラウザ操作** — Playwrightを使ったWebサイトの自動操作（SNS投稿のUI操作など）
- **Claude Code非依存** — Claude Codeのセッションが切れても動き続ける

### 外部スクリプトの特徴

| 項目 | 内容 |
|------|------|
| トリガー | OS のスケジューラ（launchd / cron） |
| 実行タイミング | 設定したスケジュール通り |
| 実行環境 | OS のシェル |
| 設定場所 | `~/Library/LaunchAgents/*.plist` または crontab |
| ユースケース | 定時実行、常時稼働、ブラウザ操作 |

## 4つの柱の比較表

| 特性 | Hooks | Skills | MCP | 外部スクリプト |
|------|-------|--------|-----|-------------|
| **実行トリガー** | ツール使用イベント | スラッシュコマンド | ツール呼び出し | OS スケジューラ |
| **Claude Code必要** | はい | はい | はい | いいえ |
| **設定の複雑さ** | 低 | 低 | 中 | 中〜高 |
| **外部サービス連携** | 間接的 | 間接的 | ネイティブ | 直接 |
| **定時実行** | 不可 | 不可 | 不可 | 可能 |
| **典型的なユースケース** | ガードレール | ワークフロー | ツール連携 | 定時バッチ |

## 使い分けフローチャート

「この自動化にはどの仕組みを使えばいいのか?」を判断するフローチャートを示す。

```
自動化したいことは何か？
│
├─ Q1: Claude Code操作中に自動で発動してほしい？
│   ├─ Yes → Q2: ツール使用の前後に実行したい？
│   │          ├─ Yes → 【Hooks】を使う
│   │          │        例: コミット前のテスト、ファイル保存時のlint
│   │          └─ No  → Q3: 手順を標準化して呼び出したい？
│   │                     ├─ Yes → 【Skills】を使う
│   │                     │        例: 記事執筆、コードレビュー
│   │                     └─ No  → Q4: 外部サービスと連携する？
│   │                                ├─ Yes → 【MCP】を使う
│   │                                │        例: Slack通知、GitHub操作
│   │                                └─ No  → 【CLAUDE.md】に指示を書く
│   │
│   └─ No → Q5: 定時実行が必要？
│            ├─ Yes → 【外部スクリプト + launchd/cron】を使う
│            │        例: 朝ダイジェスト、SNS定時投稿
│            └─ No  → Q6: ブラウザ操作が必要？
│                      ├─ Yes → 【外部スクリプト + Playwright】を使う
│                      │        例: SNSのUI操作、Webスクレイピング
│                      └─ No  → 【bashスクリプト + Claude CLI】を使う
│                               例: バッチ処理、データ変換
```

## 実例: 著者の環境での使い分け

筆者の環境で、4つの柱がどう使い分けられているかを具体的に示す。

### Hooks（3つ稼働中）

```
用途                    トリガー         処理内容
──────────────────────────────────────────────────
Bash実行前チェック      PreToolUse       危険なコマンド(rm -rf等)をブロック
ファイル書き込み後lint  PostToolUse      Write後に自動でESLint実行
コスト追跡             PostToolUse      API呼び出し後にコスト記録
```

### Skills（5つ定義済み）

```
スキル名            呼び出し方               用途
──────────────────────────────────────────────────
write-zenn         /write-zenn              Zenn記事執筆
write-qiita        /write-qiita             Qiita記事執筆
write-note         /write-note              note記事執筆
publish-zenn-book  /publish-zenn-book       Zenn書籍出版
publish-kindle     /publish-kindle          Kindle出版
```

### MCP（外部サービス連携）

```
MCPサーバー         連携先              用途
──────────────────────────────────────────────────
Figma MCP          Figma               デザインからのコード生成
GitHub MCP         GitHub              Issue・PR操作
```

### 外部スクリプト（6つ稼働中）

```
スクリプト              スケジュール     用途
──────────────────────────────────────────────────
auto-morning.sh        毎朝 9:00       朝ダイジェスト → Slack送信
auto-sns.sh            毎日 12:00      SNS投稿の自動配信
auto-tasks.sh          毎朝 9:30       従業員タスク通知
auto-state-update.sh   毎日 23:00      STATE.md自動更新
auto-approve.sh        毎時            自動承認可能なアイテムの処理
daily-report.sh        毎日 18:00      日次レポート生成
```

## 4つの柱の組み合わせパターン

実際の業務では、4つの柱を組み合わせて使うことが多い。代表的なパターンを紹介する。

### パターン1: 記事の自動公開パイプライン

```
[Skill] 記事執筆   →  [Hook] 品質チェック  →  [外部] 定時公開
                                                  ↓
                                           [MCP] Slack通知
```

1. Skillで記事を執筆（品質基準に沿って）
2. Hookでlintと文字数チェックを自動実行
3. 外部スクリプトが毎朝8:00にZenn APIを叩いて公開
4. MCPでSlackに公開完了を通知

### パターン2: 朝ダイジェストパイプライン

```
[外部] launchd 9:00起動  →  [API] ダッシュボード  →  [MCP] Slack送信
                                  ↓
                            [内部] 全部門STATE読み取り
```

1. launchdが毎朝9:00にbashスクリプトを起動
2. スクリプトがダッシュボードAPIを呼び出し
3. APIが全部門のSTATE.mdを集約してダイジェスト生成
4. 結果をSlack Webhookで送信

### パターン3: 安全なコード変更パイプライン

```
[CLAUDE.md] 権限定義  →  [Hook] 実行前チェック  →  [Hook] 実行後テスト
                                                       ↓
                                               [外部] git auto-commit
```

1. CLAUDE.mdで「本番デプロイはdraftモード」と権限を定義
2. Hookでコマンド実行前に安全性チェック
3. Hookで変更後に自動テスト実行
4. テスト通過後、外部スクリプトでgit自動コミット

## 次の章から、1つずつ構築していく

本章では4つの柱の全体像を示した。次章からは、各柱を1つずつ詳しく解説し、実際に動くコードを書いていく。

まずは第3章で、全ての自動化の**基盤**となるCLAUDE.mdの設計から始める。CLAUDE.mdの品質が自動化全体の品質を決める。ここを雑に書くと、あとで全てが崩れる。

:::message
**まとめ**
- Claude Code自動化は「Hooks」「Skills」「MCP」「外部スクリプト」の4つの柱で構成される
- Hooks = イベント駆動（ツール使用の前後に自動実行）
- Skills = ワークフロー定義（再利用可能な手順書）
- MCP = 外部ツール連携（Slack、GitHub等の操作）
- 外部スクリプト = OS レベルの定時実行（launchd / cron）
- 実際の業務では4つを組み合わせてパイプラインを構築する
- 判断に迷ったら、本章のフローチャートに従う
:::
