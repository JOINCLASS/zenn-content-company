---
title: "第6章 Hooksによるセキュリティ強制 -- 危険操作のブロック・監査ログ"
free: false
---

# 第6章 Hooksによるセキュリティ強制 -- 危険操作のブロック・監査ログ

## この章で学ぶこと

- Claude Code Hooksの仕組みと動作タイミング
- セキュリティ用途でのHooks設計パターン
- 機密情報の送信防止フィルタ
- 監査ログの自動記録
- Hooksのテストとデバッグ方法

---

## 前章の振り返りと本章の位置づけ

前章まで、Permissions（第4章）とCLAUDE.md（第5章）によるセキュリティ制御を解説した。

- **Permissions**: ツール（操作）の許可・拒否を静的に設定
- **CLAUDE.md**: 行動規範を指示として定義

しかし、これらでは対応できないケースがある。「コマンドの引数に特定の文字列が含まれていたらブロック」「実行されたコマンドをログに記録」「ファイルの内容に機密情報が含まれていたらAPIへの送信を中止」といった**動的な制御**だ。

これを実現するのが**Hooks**だ。


## Hooksとは何か

Hooksは、Claude Codeのライフサイクルの特定のタイミングで実行されるスクリプトだ。以下の4つのタイミングでフックを設定できる。

| Hook | タイミング | 用途 |
|------|----------|------|
| PreToolUse | ツール実行前 | 実行の許可/拒否を判定 |
| PostToolUse | ツール実行後 | 実行結果のログ記録・検証 |
| Notification | 通知発生時 | 通知のカスタマイズ |
| Stop | セッション終了時 | セッションの要約・ログ保存 |

セキュリティ用途で最も重要なのは**PreToolUse**と**PostToolUse**だ。

### Hooksの設定場所

Hooksは`.claude/settings.json`のhooksセクションに定義する。

> Hooks APIはClaude Codeの比較的新しい機能です。設定構文は `claude --help` または公式ドキュメント（https://docs.anthropic.com/en/docs/claude-code）で最新版を確認してください。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/security-check.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/audit-log.sh"
          }
        ]
      }
    ]
  }
}
```

### Hookスクリプトへの入力

Hookスクリプトには、**stdin経由でJSON**が渡される。環境変数ではない点に注意が必要だ。

渡されるJSONフィールド:

| フィールド | 説明 |
|-----------|------|
| `session_id` | セッションID |
| `transcript_path` | トランスクリプトファイルのパス |
| `cwd` | カレントディレクトリ |
| `hook_event_name` | Hookイベント名（PreToolUse, PostToolUse等） |
| `tool_name` | ツール名（Bash, Read, Edit等） |
| `tool_input` | ツールへの入力（オブジェクト） |
| `tool_use_id` | ツール使用ID |
| `tool_response` | ツールの実行結果（PostToolUseのみ） |

唯一の環境変数は `CLAUDE_PROJECT_DIR`（プロジェクトディレクトリのパス）だ。`$TOOL_INPUT`、`$TOOL_NAME` といった環境変数は存在しない。

stdinからJSONを読み取る基本パターン:

```bash
#!/bin/bash
# stdin から JSON を読み取る
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
```

### Hookスクリプトの戻り値

Hookスクリプトは、終了コードによってClaude Codeの動作を制御する。

- **終了コード 0**: 成功（許可）。stdoutにJSONがあれば解析される
- **終了コード 2**: ブロック。stderrの内容がClaudeに渡される
- **その他の終了コード**: 非ブロックエラー。stderrは詳細ログに表示されるが、実行は継続される

PreToolUseでは、exit 0でJSONを返すことでも操作を拒否できる:

```bash
# JSON出力で deny を返す方法（exit 0 + JSON出力）
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by security hook"}}'
exit 0
```

> **重要**: 終了コード1は「非ブロックエラー」として扱われ、ツール実行はブロックされない。操作をブロックしたい場合は、必ず**終了コード2**を使うか、JSON出力で`permissionDecision: "deny"`を返すこと。


## セキュリティHook設計パターン

### パターン1: 機密情報を含むコマンドのブロック

Bashコマンドの引数に機密情報のパターンが含まれていたらブロックする。

```bash
#!/bin/bash
# /scripts/claude-hooks/block-secrets-in-commands.sh
# PreToolUse hook for Bash
# stdin から JSON を読み取り、コマンド内容を検査する

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# コマンドが空なら許可
if [ -z "$COMMAND" ]; then
  exit 0
fi

# 機密情報のパターンを定義
PATTERNS=(
  'password='
  'PASSWORD='
  'secret='
  'SECRET='
  'api_key='
  'API_KEY='
  'token='
  'TOKEN='
  'BEGIN RSA PRIVATE KEY'
  'BEGIN OPENSSH PRIVATE KEY'
  'AKIA[0-9A-Z]{16}'  # AWS Access Key
  'sk-[a-zA-Z0-9]{48}'  # OpenAI/Anthropic API Key
)

for pattern in "${PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    echo "BLOCKED: Command contains potential secret pattern: $pattern" >&2
    echo "Do not include secrets in commands. Use environment variables instead." >&2
    exit 2
  fi
done

exit 0
```

### パターン2: 監査ログの自動記録

全てのツール実行を監査ログに記録する。

```bash
#!/bin/bash
# /scripts/claude-hooks/audit-log.sh
# PostToolUse hook for all tools
# stdin から JSON を読み取り、実行内容をログに記録する

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty' | head -c 500)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
USER=$(whoami)
PROJECT=$(basename "${CLAUDE_PROJECT_DIR:-$(pwd)}")
LOG_DIR="${HOME}/.claude/audit-logs"
LOG_FILE="${LOG_DIR}/${PROJECT}-$(date +%Y-%m-%d).jsonl"

mkdir -p "$LOG_DIR"

# 機密情報をマスキング
MASKED_INPUT=$(echo "$TOOL_INPUT" | sed -E \
  -e 's/(password|secret|token|api_key)=[^ ]*/\1=***MASKED***/gi' \
  -e 's/(sk-)[a-zA-Z0-9]+/\1***MASKED***/g' \
  -e 's/(AKIA)[A-Z0-9]+/\1***MASKED***/g'
)

# JSONL形式でログを記録
echo "{\"timestamp\":\"${TIMESTAMP}\",\"user\":\"${USER}\",\"session\":\"${SESSION_ID}\",\"project\":\"${PROJECT}\",\"tool\":\"${TOOL_NAME}\",\"input\":${MASKED_INPUT}}" >> "$LOG_FILE"

exit 0
```

監査ログの出力例:

```jsonl
{"timestamp":"2026-04-04T03:15:00Z","user":"engineer1","project":"customer-api","tool":"Bash","input":"npm run test"}
{"timestamp":"2026-04-04T03:15:30Z","user":"engineer1","project":"customer-api","tool":"Edit","input":"src/auth/login.ts"}
{"timestamp":"2026-04-04T03:16:00Z","user":"engineer1","project":"customer-api","tool":"Bash","input":"git add src/auth/login.ts"}
{"timestamp":"2026-04-04T03:16:15Z","user":"engineer1","project":"customer-api","tool":"Bash","input":"git commit -m \"fix: improve login validation\""}
```

### パターン3: 危険なファイル変更の検知

本番設定ファイルやセキュリティ関連ファイルの変更を検知し、アラートを送信する。

```bash
#!/bin/bash
# /scripts/claude-hooks/detect-sensitive-file-changes.sh
# PostToolUse hook for Edit and Write
# stdin から JSON を読み取り、センシティブファイルの変更を検知する

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# ファイルパスが空なら終了
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# センシティブなファイルパターン
SENSITIVE_PATTERNS=(
  "Dockerfile"
  "docker-compose"
  ".github/workflows"
  "nginx.conf"
  "security"
  "auth"
  "permission"
  "cors"
  "firewall"
  ".claude/settings.json"
  "CLAUDE.md"
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  if echo "$FILE_PATH" | grep -qi "$pattern"; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    ALERT_FILE="${HOME}/.claude/security-alerts.log"

    echo "[${TIMESTAMP}] SENSITIVE FILE MODIFIED: tool=${TOOL_NAME} file=${FILE_PATH}" >> "$ALERT_FILE"

    # Slack通知（オプション）
    # curl -s -X POST "$SLACK_WEBHOOK_URL" \
    #   -H 'Content-Type: application/json' \
    #   -d "{\"text\":\"[Security Alert] Sensitive file modified by Claude Code: ${FILE_PATH}\"}" &

    break
  fi
done

exit 0
```

### パターン4: 外部通信の制御

curlやwget等の外部通信コマンドが許可されたドメインのみにアクセスすることを強制する。

```bash
#!/bin/bash
# /scripts/claude-hooks/restrict-external-access.sh
# PreToolUse hook for Bash
# stdin から JSON を読み取り、外部通信先を検査する

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# コマンドが空なら許可
if [ -z "$COMMAND" ]; then
  exit 0
fi

# 外部通信コマンドの検出
if echo "$COMMAND" | grep -qE "(curl|wget|http|fetch) "; then

  # 許可されたドメインのリスト
  ALLOWED_DOMAINS=(
    "registry.npmjs.org"
    "api.github.com"
    "raw.githubusercontent.com"
    "pypi.org"
  )

  DOMAIN_FOUND=false
  for domain in "${ALLOWED_DOMAINS[@]}"; do
    if echo "$COMMAND" | grep -q "$domain"; then
      DOMAIN_FOUND=true
      break
    fi
  done

  if [ "$DOMAIN_FOUND" = false ]; then
    echo "BLOCKED: External access to unauthorized domain." >&2
    echo "Allowed domains: ${ALLOWED_DOMAINS[*]}" >&2
    exit 2
  fi
fi

exit 0
```

### パターン5: .envファイルの内容がコンテキストに含まれることを防止

Claude Codeが.envファイルの読み取りを試みた場合に、内容の代わりに警告メッセージを返す。

```bash
#!/bin/bash
# /scripts/claude-hooks/block-env-read.sh
# PreToolUse hook for Read
# stdin から JSON を読み取り、.envファイルの読み取りをブロックする

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# ファイルパスが空なら許可
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# .envファイルパターンの検出
if echo "$FILE_PATH" | grep -qE '\.(env|env\..+)$'; then
  echo "BLOCKED: Reading .env files is not allowed." >&2
  echo "Use application code to read environment variables at runtime." >&2
  echo "For configuration, see config/README.md for non-sensitive defaults." >&2
  exit 2
fi

exit 0
```


## Hooksの設定ファイル完全版

上記の全パターンを組み合わせた設定ファイルの完全版を示す。

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Edit",
      "Write",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(git status)",
      "Bash(git diff*)",
      "Bash(git log*)",
      "Bash(git add*)",
      "Bash(git commit*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(rm -rf*)",
      "Bash(sudo*)",
      "Read(*.pem)",
      "Read(*.key)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/scripts/claude-hooks/block-secrets-in-commands.sh"
          },
          {
            "type": "command",
            "command": "/scripts/claude-hooks/restrict-external-access.sh"
          }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "/scripts/claude-hooks/block-env-read.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/scripts/claude-hooks/audit-log.sh"
          }
        ]
      },
      {
        "matcher": "(Edit|Write)",
        "hooks": [
          {
            "type": "command",
            "command": "/scripts/claude-hooks/detect-sensitive-file-changes.sh"
          }
        ]
      }
    ]
  }
}
```


## 監査ログの活用

### ログの集約と分析

複数の開発者の監査ログを集約し、定期的に分析する。

```bash
#!/bin/bash
# /scripts/claude-hooks/aggregate-audit-logs.sh
# 全開発者の監査ログを集約するスクリプト（IT管理者が定期実行）

AGGREGATE_DIR="/var/log/claude-code-audit"
mkdir -p "$AGGREGATE_DIR"

# 全ユーザーのログを集約（NFS共有またはrsync）
for user_home in /home/*/; do
  username=$(basename "$user_home")
  log_dir="${user_home}.claude/audit-logs"

  if [ -d "$log_dir" ]; then
    cp "$log_dir"/*.jsonl "$AGGREGATE_DIR/${username}/" 2>/dev/null
  fi
done

# 本日のサマリーを生成
TODAY=$(date +%Y-%m-%d)
echo "=== Claude Code Audit Summary: ${TODAY} ===" > "$AGGREGATE_DIR/summary-${TODAY}.txt"

# ツール使用頻度の集計
echo "" >> "$AGGREGATE_DIR/summary-${TODAY}.txt"
echo "## Tool Usage Counts" >> "$AGGREGATE_DIR/summary-${TODAY}.txt"
cat "$AGGREGATE_DIR"/*/"*-${TODAY}.jsonl" 2>/dev/null | \
  jq -r '.tool' | sort | uniq -c | sort -rn >> "$AGGREGATE_DIR/summary-${TODAY}.txt"

# ブロックされた操作の一覧
echo "" >> "$AGGREGATE_DIR/summary-${TODAY}.txt"
echo "## Blocked Operations" >> "$AGGREGATE_DIR/summary-${TODAY}.txt"
grep "BLOCKED" "$AGGREGATE_DIR"/*/"*-${TODAY}.jsonl" 2>/dev/null >> "$AGGREGATE_DIR/summary-${TODAY}.txt"
```

### セキュリティダッシュボード

監査ログをElasticSearch/Kibana等に送信し、ダッシュボードで可視化することも有効だ。

監視すべきメトリクス:

- 1日あたりのClaude Code操作数（ユーザー別）
- ブロックされた操作の頻度とパターン
- センシティブファイルの変更頻度
- 外部通信の試行回数
- 新しいnpm/pipパッケージの追加頻度


## Hooksのテストとデバッグ

Hookスクリプトは本番環境に適用する前にテストすべきだ。

### ユニットテスト

```bash
#!/bin/bash
# /scripts/claude-hooks/test-hooks.sh
# Hookスクリプトのテスト。実際のHookと同様にstdin経由でJSONを渡す。

echo "=== Testing block-secrets-in-commands.sh ==="

# テスト1: 通常のコマンドは許可
echo "Test 1: Normal command should pass"
echo '{"tool_name":"Bash","tool_input":{"command":"npm run test"}}' | /scripts/claude-hooks/block-secrets-in-commands.sh
if [ $? -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi

# テスト2: パスワードを含むコマンドはブロック（exit 2）
echo "Test 2: Command with password should be blocked"
echo '{"tool_name":"Bash","tool_input":{"command":"curl -d password=secret123 https://api.example.com"}}' | /scripts/claude-hooks/block-secrets-in-commands.sh 2>/dev/null
if [ $? -eq 2 ]; then echo "PASS"; else echo "FAIL"; fi

# テスト3: AWS Access Keyパターンはブロック（exit 2）
echo "Test 3: AWS access key pattern should be blocked"
echo '{"tool_name":"Bash","tool_input":{"command":"export AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE"}}' | /scripts/claude-hooks/block-secrets-in-commands.sh 2>/dev/null
if [ $? -eq 2 ]; then echo "PASS"; else echo "FAIL"; fi

# テスト4: .envファイルの読み取りはブロック
echo ""
echo "=== Testing block-env-read.sh ==="
echo "Test 4: .env file read should be blocked"
echo '{"tool_name":"Read","tool_input":{"file_path":".env"}}' | /scripts/claude-hooks/block-env-read.sh 2>/dev/null
if [ $? -eq 2 ]; then echo "PASS"; else echo "FAIL"; fi

# テスト5: .env.localファイルの読み取りもブロック
echo "Test 5: .env.local file read should be blocked"
echo '{"tool_name":"Read","tool_input":{"file_path":".env.local"}}' | /scripts/claude-hooks/block-env-read.sh 2>/dev/null
if [ $? -eq 2 ]; then echo "PASS"; else echo "FAIL"; fi

# テスト6: 通常のファイル読み取りは許可
echo "Test 6: Normal file read should pass"
echo '{"tool_name":"Read","tool_input":{"file_path":"src/index.ts"}}' | /scripts/claude-hooks/block-env-read.sh 2>/dev/null
if [ $? -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi
```

### デバッグ方法

Hookスクリプトがうまく動作しない場合のデバッグ方法を示す。

```bash
# 1. スクリプトに実行権限があるか確認
ls -la /scripts/claude-hooks/*.sh
# → -rwxr-xr-x であること

# 2. スクリプトを手動で実行してテスト（stdin経由でJSONを渡す）
echo '{"tool_name":"Bash","tool_input":{"command":"curl -d password=test http://example.com"}}' \
  | /scripts/claude-hooks/block-secrets-in-commands.sh
echo "Exit code: $?"
# → Exit code: 2（ブロック）になるはず

# 3. jq がインストールされているか確認（Hookスクリプトに必須）
which jq && jq --version

# 4. ログファイルでHookの実行履歴を確認
tail -f ~/.claude/audit-logs/*.jsonl

# 5. Claude Codeのデバッグモードで確認
# Claude Code実行時に --verbose フラグを使用
```


## Hooksのパフォーマンス考慮

Hookスクリプトは全てのツール実行のたびに呼び出されるため、パフォーマンスへの影響を最小限にする必要がある。

**推奨**:
- スクリプトの実行時間は100ms以内に抑える
- 外部API呼び出し（Slack通知等）はバックグラウンドで実行する
- grepのパターンマッチングは効率的に行う
- 大量のログ書き込みはバッファリングする

**非推奨**:
- Hookスクリプト内でnpmやpip等のパッケージマネージャを実行する
- 外部APIのレスポンスを待つ（同期的な通知）
- 大きなファイルの全文検索

次の第7章では、Permissions、CLAUDE.md、Hooksの3層防御を補完する「シークレット管理」について解説する。APIキー、認証情報、暗号化キーを安全に扱うための具体的な方法を示す。

---

## まとめ

- HooksはClaude Codeのツール実行前後にカスタムスクリプトを実行する仕組み
- PreToolUseで危険な操作をブロック、PostToolUseで監査ログを記録
- 機密情報パターンの検出、外部通信の制限、センシティブファイル変更の検知が可能
- 監査ログはJSONL形式で記録し、集約・分析の基盤として活用
- Hookスクリプトは本番適用前にユニットテストを実施する
- パフォーマンスを考慮し、スクリプトの実行時間は100ms以内に抑える

:::message
**本章の情報はClaude Code 2.x系（v2.1.90）（2026年4月時点）に基づいています。** Claude Codeのメジャーアップデート時に改訂予定です。最新情報は[Anthropic公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)をご確認ください。
:::

> Claude Codeの高度な活用パターンを知りたい方は「[Claude Code x MCPサーバー開発入門](https://zenn.dev/joinclass/books/claude-code-mcp-development)」をご覧ください。MCP連携時のセキュリティ設計も参考になります。
