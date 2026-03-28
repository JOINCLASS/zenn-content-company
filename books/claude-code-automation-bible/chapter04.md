---
title: "Hooksで「トリガー型」自動化を作る"
---

# Hooksで「トリガー型」自動化を作る

:::message
**この章で学ぶこと**
- Hooksの仕組み（PreToolUse / PostToolUse / Notification）
- 実装例1: コミット時に自動テスト実行
- 実装例2: ファイル保存時にlint実行
- 実装例3: エラー発生時にSlack通知
- Hooksの設定方法と設定ファイルの構造
- デバッグとトラブルシューティング
:::

## Hooksとは何か

Hooksは、Claude Codeの内部で「何かが起きたとき」に自動でスクリプトを実行する仕組みだ。gitのpre-commitフックやWebpackのプラグインと同じ発想である。

例えば、「Claude CodeがBashコマンドを実行しようとしたとき」「Claude Codeがファイルを書き込んだ直後」「Claude Codeがエラーを検出したとき」に、指定したスクリプトが自動で走る。

```
Claude Code の操作フロー（Hooks付き）

ユーザー: 「このバグを直して」
    │
    ▼
Claude Code: ファイルを分析
    │
    ▼
Claude Code: Writeツールでファイルを書き換えようとする
    │
    ├──▶ [PreToolUse Hook] 書き込み前チェック ← ここで介入できる
    │
    ▼
Claude Code: ファイルを書き換える
    │
    ├──▶ [PostToolUse Hook] 書き込み後にlint実行 ← ここでも介入できる
    │
    ▼
Claude Code: Bashツールでgit commitを実行しようとする
    │
    ├──▶ [PreToolUse Hook] コミット前テスト実行 ← ここでも
    │
    ▼
完了
```

Hooksがなければ、これらのチェックは全て手動で依頼する必要がある。「lint通してから変更して」「テスト走らせてからコミットして」と毎回言わなければならない。Hooksがあれば、**言わなくても自動で走る**。

## Hooksの3つのタイプ

Claude Code のHooksには3つのタイプがある。

### PreToolUse — ツール実行「前」に走る

Claude Codeがツール（Bash、Write、Edit等）を使おうとした**直前**に実行される。戻り値でツール実行を**ブロック**できるのが最大の特徴だ。

```
用途: ガードレール、安全性チェック、入力バリデーション
```

### PostToolUse — ツール実行「後」に走る

Claude Codeがツールを使った**直後**に実行される。ツール実行の結果を受けて、後処理を行う。

```
用途: lint、テスト、ログ記録、通知
```

### Notification — 通知イベント時に走る

Claude Codeが何かをユーザーに通知するタイミングで実行される。エラーや警告の検出に使う。

```
用途: エラー通知、進捗報告、アラート
```

## 設定ファイルの構造

Hooksは `.claude/settings.local.json` に定義する。

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        // matcher: どのツールの実行時にフックを発動するか
        // "Bash" なら Bash ツール実行時のみ発動
        "matcher": "Bash",

        // hook: 実行するコマンド
        // 標準入力にツールの入力パラメータがJSON形式で渡される
        "hook": "bash .claude/hooks/pre-bash-safety.sh"
      }
    ],
    "PostToolUse": [
      {
        // matcher は正規表現も使える
        // "Write|Edit" なら Write または Edit ツール実行後に発動
        "matcher": "Write|Edit",
        "hook": "bash .claude/hooks/post-write-lint.sh"
      }
    ],
    "Notification": [
      {
        // Notification には matcher が不要
        // 全ての通知イベントで発動する
        "hook": "bash .claude/hooks/on-notification.sh"
      }
    ]
  }
}
```

### matcher の指定方法

| パターン | 意味 | 例 |
|---------|------|-----|
| `"Bash"` | Bashツールのみ | シェルコマンド実行時 |
| `"Write"` | Writeツールのみ | ファイル書き込み時 |
| `"Write\|Edit"` | WriteまたはEdit | ファイル変更時 |
| `".*"` | 全ツール | あらゆるツール使用時 |

### Hookスクリプトへの入力

Hookスクリプトには、**標準入力（stdin）** でJSON形式のデータが渡される。

```jsonc
// PreToolUse の場合: ツールに渡そうとしているパラメータ
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /important-data"
  }
}

// PostToolUse の場合: ツールの実行結果も含まれる
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/path/to/file.ts",
    "content": "..."
  },
  "tool_result": "File written successfully"
}
```

### Hookスクリプトの戻り値

PreToolUseフックは、**終了コード**でツール実行の可否を制御できる。

| 終了コード | 動作 |
|-----------|------|
| `0` | ツール実行を**許可** |
| `非0` (1, 2, ...) | ツール実行を**ブロック** |

PostToolUseとNotificationフックでは、終了コードは無視される（ツールは既に実行済みのため）。

**標準出力（stdout）** に書いた内容は、Claude Codeのコンテキストにフィードバックされる。つまり、Hookの出力をAIが読んで次のアクションに活かすことができる。

## 実装例1: Bash実行前の安全性チェック

最も重要なHookから始めよう。Claude CodeがBashコマンドを実行する前に、危険なコマンドをブロックするガードレールだ。

### なぜ必要か

Claude Codeは強力だ。Bashツールを使えば、`rm -rf /` だって実行できてしまう。人間が毎回コマンドを確認するのは現実的ではない（特に自動化している場合）。Hookで機械的にチェックするのが安全だ。

### 実装

```bash
#!/bin/bash
# .claude/hooks/pre-bash-safety.sh
# Bashツール実行前に危険なコマンドをブロックする

# 標準入力からJSON読み取り
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# コマンドが空なら何もしない（許可）
if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- 危険パターンの定義 ---
# 本番環境への直接操作をブロック
DANGEROUS_PATTERNS=(
  "rm -rf /"          # ルート削除
  "rm -rf ~"          # ホームディレクトリ削除
  "rm -rf \."         # カレントディレクトリ削除
  "DROP TABLE"        # テーブル削除
  "DROP DATABASE"     # データベース削除
  "truncate"          # テーブル全削除
  "> /dev/sda"        # ディスク直接書き込み
  "mkfs"              # フォーマット
  ":(){ :|:& };:"     # Fork bomb
  "dd if=/dev"        # ディスクコピー
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qi "$pattern"; then
    # 標準出力にブロック理由を書く（AIにフィードバックされる）
    echo "BLOCKED: 危険なコマンドを検出しました: $pattern"
    echo "このコマンドは安全性のため実行できません。"
    echo "別のアプローチを検討してください。"
    # 終了コード1でブロック
    exit 1
  fi
done

# --- 本番環境への操作チェック ---
# production, prod, mainブランチへの直接pushをブロック
if echo "$COMMAND" | grep -qE "git push.*(origin|upstream).*(main|master|production)"; then
  echo "BLOCKED: mainブランチへの直接pushは禁止されています。"
  echo "PRを作成してレビューを通してください。"
  exit 1
fi

# 全チェック通過 → 実行許可
exit 0
```

### 動作確認

このHookが正しく動いているか確認するには、Claude Codeで意図的に危険なコマンドを実行させてみる。

```
ユーザー: 「rm -rf / を実行して」

Claude Code: Bashツールで rm -rf / を実行しようとします
  ↓
[PreToolUse Hook] pre-bash-safety.sh が発動
  ↓
Hook出力: "BLOCKED: 危険なコマンドを検出しました: rm -rf /"
  ↓
Claude Code: 「安全性チェックによりブロックされました。
              別のアプローチを提案します...」
```

## 実装例2: ファイル変更後の自動lint

### なぜ必要か

Claude Codeがファイルを書き換えた後、lint（構文チェック）を自動で走らせたい。手動で「lintも通して」と毎回頼むのは面倒だし、忘れることもある。

### 実装

```bash
#!/bin/bash
# .claude/hooks/post-write-lint.sh
# Write/Edit後に対象ファイルのlintを自動実行する

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# ファイルパスが取れなければ終了
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- ファイル拡張子に応じたlintを実行 ---
EXTENSION="${FILE_PATH##*.}"

case "$EXTENSION" in
  ts|tsx)
    # TypeScriptファイル: ESLintで構文チェック
    if command -v npx &>/dev/null && [ -f "$(dirname "$FILE_PATH")/node_modules/.bin/eslint" ] 2>/dev/null || [ -f "package.json" ]; then
      RESULT=$(npx eslint "$FILE_PATH" --format compact 2>&1) || true
      if [ -n "$RESULT" ]; then
        echo "ESLint結果 ($FILE_PATH):"
        echo "$RESULT"
        echo ""
        echo "上記のlintエラーを修正してください。"
      fi
    fi
    ;;

  js|jsx)
    # JavaScriptファイル: ESLintで構文チェック
    if command -v npx &>/dev/null; then
      RESULT=$(npx eslint "$FILE_PATH" --format compact 2>&1) || true
      if [ -n "$RESULT" ]; then
        echo "ESLint結果 ($FILE_PATH):"
        echo "$RESULT"
      fi
    fi
    ;;

  py)
    # Pythonファイル: ruffで構文チェック（高速）
    if command -v ruff &>/dev/null; then
      RESULT=$(ruff check "$FILE_PATH" 2>&1) || true
      if [ -n "$RESULT" ]; then
        echo "Ruff結果 ($FILE_PATH):"
        echo "$RESULT"
      fi
    fi
    ;;

  md)
    # Markdownファイル: 文字数カウント（品質基準チェック）
    CHARS=$(wc -m < "$FILE_PATH" | tr -d ' ')
    echo "文字数: ${CHARS}文字 ($FILE_PATH)"
    if [ "$CHARS" -lt 1000 ]; then
      echo "警告: 1,000文字未満です。内容が薄い可能性があります。"
    fi
    ;;
esac

# PostToolUseなので終了コードは無視される（常に0で良い）
exit 0
```

### ポイント: AIへのフィードバック

このHookの出力（stdout）はClaude Codeにフィードバックされる。つまり、lintエラーがあれば、Claude Codeは**自動的にそのエラーを認識して修正に取りかかる**。

```
Claude Code: Writeツールで app.tsx を書き込む
  ↓
[PostToolUse Hook] post-write-lint.sh が発動
  ↓
Hook出力:
  ESLint結果 (app.tsx):
  app.tsx:15:10 - 'unused' is defined but never used
  上記のlintエラーを修正してください。
  ↓
Claude Code: 「lintエラーが検出されました。修正します...」
  ↓
Claude Code: Editツールで app.tsx の15行目を修正
  ↓
[PostToolUse Hook] 再度発動 → 今度はエラーなし
  ↓
Claude Code: 「修正完了。lintエラーは解消されました。」
```

人間が何も言わなくても、lint → 修正 → 再lint のサイクルが自動で回る。これがHooksの威力だ。

## 実装例3: エラー発生時のSlack通知

### なぜ必要か

自動化が進むと、Claude Codeがバックグラウンドで動いている時間が増える。エラーが起きても気づかない。Slack通知があれば、すぐに対応できる。

### 実装

```bash
#!/bin/bash
# .claude/hooks/on-notification.sh
# Claude Codeの通知イベント時にSlack送信する

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')

# 通知メッセージが空なら何もしない
if [ -z "$MESSAGE" ]; then
  exit 0
fi

# --- エラーキーワードの検出 ---
# "error", "failed", "exception" を含む場合のみSlack通知
if echo "$MESSAGE" | grep -qiE "(error|failed|exception|fatal|panic)"; then

  # Slack Webhook URLが設定されていなければスキップ
  WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
  if [ -z "$WEBHOOK_URL" ]; then
    exit 0
  fi

  # Slack通知を送信
  PAYLOAD=$(jq -n \
    --arg text ":rotating_light: [Claude Code] エラー検出\n\`\`\`\n${MESSAGE}\n\`\`\`" \
    '{text: $text}')

  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$WEBHOOK_URL" >/dev/null 2>&1

  # ログにも記録
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR通知送信: $MESSAGE" \
    >> "${HOME}/.claude/hooks/notification.log"
fi

exit 0
```

### Slack Webhookの設定

Slack通知を使うには、Slack Incoming Webhookを設定して環境変数にURLをセットする。

```bash
# .env に追記（gitにはコミットしないこと）
SLACK_WEBHOOK_URL=your-slack-webhook-url-here
```

筆者の環境では、`.company/scripts/common.sh` がこの環境変数を読み込み、全スクリプトで共通して使える形にしている。

```bash
# common.sh の抜粋: .env読み込み処理
load_env() {
  local env_file="$PROJECT_ROOT/.env"
  if [ -f "$env_file" ]; then
    set -a
    source "$env_file"
    set +a
  fi
}
```

## Hooksのディレクトリ構成

Hooksが増えてきたら、ディレクトリで整理する。

```
.claude/
├── hooks/
│   ├── pre-bash-safety.sh       # Bash実行前: 安全性チェック
│   ├── post-write-lint.sh       # Write/Edit後: lint実行
│   ├── on-notification.sh       # 通知: Slack送信
│   ├── post-bash-cost-track.sh  # Bash後: コスト追跡
│   └── notification.log         # 通知ログ（自動生成）
└── settings.local.json          # Hooks設定（上記スクリプトを登録）
```

## デバッグとトラブルシューティング

### よくある問題1: Hookが発動しない

```bash
# 確認手順

# 1. settings.local.json のパスが正しいか確認
cat .claude/settings.local.json | jq '.hooks'

# 2. Hookスクリプトに実行権限があるか確認
ls -la .claude/hooks/
# → -rwxr-xr-x なら OK。-rw-r--r-- なら chmod +x が必要

# 3. 実行権限を付与
chmod +x .claude/hooks/*.sh
```

### よくある問題2: Hookがエラーで落ちる

```bash
# Hookスクリプトを直接実行してデバッグする

# テスト用の入力JSONを作成
echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
  | bash .claude/hooks/pre-bash-safety.sh

# 終了コードを確認
echo $?
# → 0 なら許可、1 ならブロック
```

### よくある問題3: jqが入っていない

Hookスクリプトは `jq` コマンドでJSONを解析している。インストールされていないとエラーになる。

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# jq なしで代替する場合（非推奨だが緊急時に）
# Python のワンライナーで代用
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
")
```

### よくある問題4: Hookが遅くてClaude Codeがブロックされる

Hookスクリプトの実行時間が長いと、Claude Codeの応答が遅くなる。特にPostToolUseでESLintを走らせると、プロジェクトの規模によっては数秒かかる。

```bash
# 対策1: 対象ファイルだけlintする（プロジェクト全体をlintしない）
npx eslint "$FILE_PATH"           # OK: 1ファイルだけ
npx eslint .                       # NG: プロジェクト全体

# 対策2: タイムアウトを設定する
timeout 5 npx eslint "$FILE_PATH"  # 5秒でタイムアウト

# 対策3: バックグラウンドで実行する（結果を待たない）
npx eslint "$FILE_PATH" >> /tmp/lint-results.log 2>&1 &
# ※ ただしAIへのフィードバックが得られない
```

筆者の環境では、対策1を基本とし、5秒以上かかるlintは対策2でタイムアウトさせている。

## Hooksの設計原則

最後に、Hooksを設計する際の原則をまとめておく。

### 原則1: Hookは軽く保つ

Hookは**毎回のツール使用で発動する**。重い処理を入れると、Claude Code全体が遅くなる。1つのHookは3秒以内に完了するのが目安だ。

### 原則2: PreToolUseは慎重に

PreToolUseでツール実行をブロックすると、Claude Codeのワークフローが止まる。**本当に危険な操作だけ**をブロックし、それ以外は通す。過剰なガードレールはAIの生産性を下げる。

### 原則3: PostToolUseの出力はAIへの指示として書く

PostToolUseのstdoutはClaude Codeにフィードバックされる。つまり、出力は「AIに対する指示」として書くのが効果的だ。

```bash
# NG: 人間向けのメッセージ
echo "ESLint found 3 errors in app.tsx"

# OK: AIへの指示として書く
echo "ESLint結果: app.tsx に3件のエラーがあります。"
echo "上記のエラーを修正してください。"
echo "修正後、再度lintが自動実行されます。"
```

### 原則4: 冪等性を保つ

Hookは何度実行されても同じ結果になるように書く。特にログ記録やコスト追跡では、二重カウントしないよう注意する。

```bash
# NG: 毎回追記するだけ（重複チェックなし）
echo "$COMMAND" >> command-log.txt

# OK: タイムスタンプ付きで記録（後から追跡可能）
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $COMMAND" >> command-log.txt
```

:::message
**まとめ**
- Hooksは Claude Code のツール使用イベントに応じて自動実行されるスクリプト
- 3つのタイプ: PreToolUse（実行前）、PostToolUse（実行後）、Notification（通知時）
- PreToolUseは終了コードでツール実行をブロックできる（ガードレール）
- PostToolUseの出力はAIにフィードバックされ、自動修正のトリガーになる
- 設定は `.claude/settings.local.json` の `hooks` セクションに記述
- Hookは軽く（3秒以内）、PreToolUseは慎重に（過剰ブロック禁止）
- jqでJSON解析、stdoutでAIにフィードバック、終了コードで制御
:::
