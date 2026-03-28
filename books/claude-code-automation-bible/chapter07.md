---
title: "launchdとシェルスクリプトで定期実行する"
---

# launchdとシェルスクリプトで定期実行する

## この章で学ぶこと

- なぜcronではなくlaunchdを使うのか（macOSのフルディスクアクセス問題）
- launchdのplistファイル作成方法
- 実装例1: 毎朝9時のSlackダイジェスト通知
- 実装例2: 毎日8時のZenn/Qiita記事自動公開
- 実装例3: 毎夕19時の活動実績レポート
- シェルスクリプトの.env読み込み、エラーハンドリング、ログ管理
- `launchctl` でのテスト方法

## なぜcronではなくlaunchdか

macOSで定期実行と聞くとcronを思い浮かべるかもしれません。しかし、macOSでの自動化にはlaunchdを使うべきです。理由は2つあります。

### 理由1: フルディスクアクセス問題

macOS Catalina以降、cronはフルディスクアクセス権限を持っていません。ホームディレクトリ配下のファイルにアクセスしようとすると、権限エラーで失敗します。

```bash
# cronで実行すると失敗する例
* * * * * cat /Users/you/workspace/project/.env
# → Operation not permitted
```

launchdはmacOSネイティブのジョブスケジューラで、ユーザーエージェントとして動作するため、フルディスクアクセスの問題が発生しません。

### 理由2: スリープ復帰後の実行保証

MacBookをスリープしていて、指定時刻を過ぎた場合の挙動が異なります。

| スケジューラ | スリープ中に時刻が過ぎた場合 |
|------------|------------------------|
| cron | スキップされる（実行されない） |
| launchd | スリープ復帰後に実行される |

朝9時のダイジェスト通知をcronで設定していて、9時にMacBookがスリープだった場合、その日の通知は永久に来ません。launchdなら、蓋を開けた瞬間に実行されます。

筆者の環境では16個のlaunchdジョブが稼働しています。朝のダイジェスト、記事自動公開、SNS投稿、ダッシュボード起動など、すべてlaunchdで管理しています。

## launchdのplist作成方法

### plistファイルの配置場所

```
~/Library/LaunchAgents/   ← ユーザーエージェント（ここに置く）
/Library/LaunchDaemons/   ← システムデーモン（root権限が必要。通常使わない）
```

ユーザーの定期実行ジョブは、すべて `~/Library/LaunchAgents/` に配置します。

### 基本構造

plistはXML形式です。最初は面倒に見えますが、構造はシンプルです。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- ジョブの識別名（ユニークであること） -->
  <key>Label</key>
  <string>com.yourcompany.job-name</string>

  <!-- 実行するコマンド -->
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/path/to/your/script.sh</string>
  </array>

  <!-- 環境変数（PATHとHOMEは必須） -->
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/you</string>
  </dict>

  <!-- 作業ディレクトリ -->
  <key>WorkingDirectory</key>
  <string>/Users/you/workspace/project</string>

  <!-- ログ出力先 -->
  <key>StandardOutPath</key>
  <string>/path/to/logs/job-name.log</string>
  <key>StandardErrorPath</key>
  <string>/path/to/logs/job-name-error.log</string>

  <!-- 実行スケジュール（毎日9:00） -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
</dict>
</plist>
```

### 重要: PATH環境変数

launchdの実行環境はユーザーのシェル環境とは異なります。`.bashrc` や `.zshrc` の設定は読み込まれません。特に、以下のパスを明示的に指定しないとコマンドが見つかりません。

```xml
<key>PATH</key>
<!-- nodeのパス（nvm使用時は特に注意）とHomebrewのパスを含める -->
<string>/Users/you/.nvm/versions/node/v22.17.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
```

nvmを使っている場合、`node` のパスはバージョンごとに異なります。`which node` で確認してから設定してください。

### スケジュール設定のバリエーション

```xml
<!-- 毎日9:00 -->
<key>StartCalendarInterval</key>
<dict>
  <key>Hour</key>
  <integer>9</integer>
  <key>Minute</key>
  <integer>0</integer>
</dict>

<!-- 平日のみ（月-金）の9:00 -->
<!-- Weekday: 0=日, 1=月, ..., 6=土 -->
<key>StartCalendarInterval</key>
<array>
  <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
</array>

<!-- 30分間隔で繰り返し -->
<key>StartInterval</key>
<integer>1800</integer>
```

## シェルスクリプトの共通パターン

launchdから呼び出すシェルスクリプトには、共通のパターンがあります。筆者の環境では `common.sh` に共通関数をまとめ、全スクリプトからsourceしています。

### common.sh — 共通ヘルパー

```bash
#!/bin/bash
# 全自動化スクリプトがsourceして使う共通関数群
set -euo pipefail

# PATHを明示的に設定（launchdから起動時に必要）
export PATH="/Users/you/.nvm/versions/node/v22.17.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export HOME="/Users/you"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/.company/scripts/logs"

mkdir -p "$LOG_DIR"

# .env 読み込み（APIキーなどの秘密情報を環境変数として設定）
load_env() {
  local env_file="$PROJECT_ROOT/.env"
  if [ -f "$env_file" ]; then
    set -a          # exportを自動で付与
    source "$env_file"
    set +a
  fi
}

# ログ出力（タイムスタンプ付き）
log_info() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# エラー時にSlack通知するトラップ
# スクリプトが異常終了した場合、自動的にSlackにアラートを送る
on_error_notify() {
  local exit_code=$?
  local line_no=${1:-unknown}
  log_error "スクリプト失敗 (行:$line_no, コード:$exit_code)"
  if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
    curl -sf -X POST \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg text "[自動化] スクリプト失敗 (行:$line_no)" '{text: $text}')" \
      "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi
}
trap 'on_error_notify $LINENO' ERR

# Slack通知
notify_slack() {
  local message="$1"
  if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    log_error "SLACK_WEBHOOK_URL not set"
    return 1
  fi
  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$message" '{text: $text}')" \
    "$SLACK_WEBHOOK_URL" >/dev/null
}

# リトライ実行（最大3回、失敗時は2秒待機）
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
  log_error "3回失敗: $cmd"
  return 1
}

# コスト追跡（API呼び出しの月間コストを記録し、上限で自動停止）
track_cost() {
  local api_name="$1"
  local cost_usd="${2:-0.01}"
  local tracker="$PROJECT_ROOT/.company/scripts/cost-tracker.json"
  # 月間 $200 を超えたら自動停止
  # （実装の詳細は省略。JSON管理で月別集計）
}

# 初期化（sourceされた時点で.envを読み込む）
load_env
```

### なぜcommon.shを作るのか

16個のスクリプトがそれぞれ `.env` 読み込み、ログ出力、エラーハンドリング、Slack通知を個別に実装していたら、修正が必要になった時に16ファイルを編集する羽目になります。

common.shに共通化することで、たとえばSlack通知の仕組みを変えたい場合でも1ファイルの修正で済みます。

## 実装例1: 毎朝9時のSlackダイジェスト通知

朝起きてSlackを開くと、AIが生成した経営ダイジェストが届いている。これが筆者の日常です。

### シェルスクリプト

```bash
#!/bin/bash
# 朝AIダイジェスト生成スクリプト
# 全部門STATEを集約し、Slack送信
source "$(dirname "$0")/common.sh"

LOG_FILE="$LOG_DIR/auto-morning.log"

main() {
  log_info "=== 朝ダイジェスト生成開始 ===" | tee -a "$LOG_FILE"

  # コスト上限チェック（月間$200超ならスキップ）
  check_cost_limit || exit 0

  # ダッシュボードAPI経由でダイジェスト生成
  local result
  result=$(api_post "morning-digest" '{}')

  if [ $? -ne 0 ] || [ -z "$result" ]; then
    log_error "API呼び出し失敗" | tee -a "$LOG_FILE"
    exit 1
  fi

  local success
  success=$(echo "$result" | jq -r '.success')

  if [ "$success" = "true" ]; then
    log_info "朝ダイジェスト送信完了" | tee -a "$LOG_FILE"
    track_cost "morning-digest" "0.02" || true
  else
    local error
    error=$(echo "$result" | jq -r '.error // "不明なエラー"')
    log_error "朝ダイジェスト失敗: $error" | tee -a "$LOG_FILE"
  fi

  log_info "=== 朝ダイジェスト生成完了 ===" | tee -a "$LOG_FILE"
}

main "$@"
```

### plistファイル

`~/Library/LaunchAgents/com.yourcompany.auto-morning.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.yourcompany.auto-morning</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/you/workspace/project/.company/scripts/auto-morning.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/Users/you/.nvm/versions/node/v22.17.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/you</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>/Users/you/workspace/project</string>
  <key>StandardOutPath</key>
  <string>/Users/you/workspace/project/.company/scripts/logs/auto-morning.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/you/workspace/project/.company/scripts/logs/auto-morning-error.log</string>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
</dict>
</plist>
```

## 実装例2: 毎日8時のZenn/Qiita記事自動公開

記事のストック管理と自動公開の仕組みです。事前に `published: false` で書き溜めた記事を、毎朝1本ずつ自動公開します。

### 仕組みの全体像

```
[事前準備]
/write-zenn で記事を生成（published: false）
  ↓ ストックが5-10本溜まる
[毎朝8:00]
auto-publish.sh が起動
  → 最も古い未公開記事のフロントマターを published: true に変更
  → git commit & push
  → ZennのGitHub連携が自動で記事を公開
  → Slackに公開通知
```

### 自動公開スクリプト

```bash
#!/bin/bash
# Zenn記事自動公開スクリプト
# 未公開記事の中から最も古い1本を公開する
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTICLES_DIR="$SCRIPT_DIR/../articles"

# .env読み込み
if [ -f "$SCRIPT_DIR/../../.env" ]; then
  set -a; source "$SCRIPT_DIR/../../.env"; set +a
fi

# 未公開記事を取得（作成日が古い順）
UNPUBLISHED=$(grep -rl "^published: false" "$ARTICLES_DIR/"*.md 2>/dev/null | head -1)

if [ -z "$UNPUBLISHED" ]; then
  echo "$(date): No unpublished articles found"
  exit 0
fi

FILENAME=$(basename "$UNPUBLISHED")
echo "$(date): Publishing $FILENAME"

# published: false → published: true に変更
sed -i '' 's/^published: false/published: true/' "$UNPUBLISHED"

# git commit & push（ZennのGitHub連携が自動公開する）
cd "$SCRIPT_DIR/.."
git add "articles/$FILENAME"
git commit -m "publish: $FILENAME" --no-gpg-sign
git push origin main

echo "$(date): Successfully published $FILENAME"

# Slack通知
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  # 記事タイトルを取得
  TITLE=$(grep "^title:" "$UNPUBLISHED" | sed 's/^title: *"*//;s/"*$//')
  REMAINING=$(grep -rl "^published: false" "$ARTICLES_DIR/"*.md 2>/dev/null | wc -l | tr -d ' ')

  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg text "[Zenn] 記事公開: $TITLE (残りストック: ${REMAINING}本)" \
      '{text: $text}')" \
    "$SLACK_WEBHOOK_URL" >/dev/null 2>&1
fi
```

### plistファイル

`~/Library/LaunchAgents/com.yourcompany.zenn-publish.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.yourcompany.zenn-publish</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/you/workspace/zenn-content/scripts/auto-publish.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/Users/you/.nvm/versions/node/v22.17.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/you</string>
  </dict>
  <key>StandardOutPath</key>
  <string>/Users/you/workspace/project/.company/scripts/logs/zenn-publish.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/you/workspace/project/.company/scripts/logs/zenn-publish-error.log</string>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>8</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
</dict>
</plist>
```

筆者の環境では、Zenn・Qiitaそれぞれに同様のスクリプトとplistが設定されています。ストック残数が3本を切ったらSlackで警告が飛ぶようにしており、補充のタイミングを見逃しません。

## 実装例3: 毎夕19時の活動実績レポート

1日の自動化結果をまとめてSlackに通知するスクリプトです。「今日AIが何をしたか」を一目で把握できます。

### スクリプト

```bash
#!/bin/bash
# 夕方19:00 — 今日の活動実績をSlack通知
set -euo pipefail

export PATH="/Users/you/.nvm/versions/node/v22.17.0/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
fi

TODAY=$(date "+%Y-%m-%d")

# Zenn: 今日公開された記事をログから検出
ZENN_LOG="$PROJECT_ROOT/../zenn-content/scripts/publish.log"
if [ -f "$ZENN_LOG" ] && grep -q "$TODAY" "$ZENN_LOG" 2>/dev/null; then
  ZENN_RESULT="Zenn: 記事公開済み"
else
  ZENN_RESULT="Zenn: 今日は公開なし"
fi

# Qiita: 同様にチェック
QIITA_LOG="$PROJECT_ROOT/../qiita-content/scripts/publish.log"
if [ -f "$QIITA_LOG" ] && grep -q "$TODAY" "$QIITA_LOG" 2>/dev/null; then
  QIITA_RESULT="Qiita: 記事公開済み"
else
  QIITA_RESULT="Qiita: 今日は公開なし"
fi

# ストック残数（補充計画の判断材料）
ZENN_STOCK=$(grep -rl "^published: false" \
  "$PROJECT_ROOT/../zenn-content/articles/"*.md 2>/dev/null | wc -l | tr -d ' ')
QIITA_STOCK=$(grep -rl "^ignorePublish: true" \
  "$PROJECT_ROOT/../qiita-content/public/"*.md 2>/dev/null | wc -l | tr -d ' ')

# ストック警告
STOCK_WARNING=""
if [ "$ZENN_STOCK" -le 3 ] || [ "$QIITA_STOCK" -le 3 ]; then
  STOCK_WARNING="
[警告] ストック残数が少なくなっています。補充が必要です。"
fi

# Slack送信
MESSAGE="今日の活動実績 — ${TODAY}

記事配信:
- ${ZENN_RESULT}
- ${QIITA_RESULT}

ストック残数:
- Zenn: ${ZENN_STOCK}本
- Qiita: ${QIITA_STOCK}本${STOCK_WARNING}"

if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$MESSAGE" '{text: $text}')" \
    "$SLACK_WEBHOOK_URL" >/dev/null 2>&1
fi
```

## launchctlでのテスト方法

### ジョブの登録

```bash
# plistファイルを配置後、ジョブを登録
launchctl load ~/Library/LaunchAgents/com.yourcompany.auto-morning.plist
```

### 即時テスト実行

スケジュールを待たずに即座に実行するには:

```bash
# kickstartで即時起動（最も確実な方法）
launchctl kickstart gui/$(id -u)/com.yourcompany.auto-morning
```

`launchctl start` でも起動できますが、`kickstart` の方がデバッグ情報が多く、トラブルシューティングに便利です。

### ジョブの状態確認

```bash
# 登録済みジョブ一覧
launchctl list | grep yourcompany

# 特定ジョブの詳細（直近の終了コードを確認）
launchctl list com.yourcompany.auto-morning
# → PID, Status (0=正常), Label が表示される
```

Statusが `0` 以外なら異常終了です。エラーログを確認しましょう。

### ジョブの停止と削除

```bash
# ジョブを無効化（次回のスケジュール実行をスキップ）
launchctl unload ~/Library/LaunchAgents/com.yourcompany.auto-morning.plist

# plistを編集した後は、unload → load で再読み込み
launchctl unload ~/Library/LaunchAgents/com.yourcompany.auto-morning.plist
launchctl load ~/Library/LaunchAgents/com.yourcompany.auto-morning.plist
```

### よくあるトラブルと対処法

| 症状 | 原因 | 対処 |
|------|------|------|
| `node: command not found` | PATHにnodeのパスが含まれていない | plistのEnvironmentVariablesでPATHを設定 |
| `Permission denied` | スクリプトに実行権限がない | `chmod +x script.sh` |
| ジョブが実行されない | plistにXML構文エラー | `plutil -lint file.plist` で検証 |
| Status 1で終了 | スクリプト内のコマンドが失敗 | StandardErrorPathのログを確認 |
| .envが読み込まれない | パスが間違っている | スクリプト内で絶対パスを使う |

plistの構文チェックは `plutil` コマンドで行えます。

```bash
# XML構文の検証
plutil -lint ~/Library/LaunchAgents/com.yourcompany.auto-morning.plist
# → OK と表示されれば問題なし
```

## まとめ

- **macOSではcronではなくlaunchdを使う**。フルディスクアクセス問題とスリープ復帰後の実行保証が理由
- plistは `~/Library/LaunchAgents/` に配置。**PATH環境変数の明示的設定**が最も重要なポイント
- **common.sh**で.env読み込み、ログ出力、エラーハンドリング、Slack通知を共通化し、個別スクリプトの保守コストを下げる
- **ストック管理**の仕組み（残数監視+自動公開）により、コンテンツ配信を完全自動化できる
- **launchctl kickstart**で即時テスト。`plutil -lint`でplistの構文検証
- 筆者の環境では16個のlaunchdジョブが稼働し、朝のダイジェストから夕方の実績レポートまで、1日の自動化サイクルを回している
- 次章では、API非対応のサービスを自動化するための最終手段——Playwrightによるブラウザ操作について解説する
