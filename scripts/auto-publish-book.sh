#!/bin/bash
# Zenn書籍のスケジュール公開スクリプト
# launchd or cron で毎日8:00に実行
set -uo pipefail

export PATH="/Users/kyoagun/.nvm/versions/node/v22.17.0/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="/Users/kyoagun/workspace/zenn-content-company"
PRIORITY_FILE="$REPO_DIR/scripts/publish-book-priority.txt"
LOG_FILE="/Users/kyoagun/workspace/one-ceo/.company/scripts/logs/book-publish.log"
TODAY=$(date +%Y-%m-%d)

cd "$REPO_DIR"

if [ ! -f "$PRIORITY_FILE" ]; then
  exit 0
fi

while IFS=' ' read -r DATE SLUG; do
  # コメント・空行スキップ
  [ -z "$DATE" ] && continue
  [[ "$DATE" == \#* ]] && continue

  # 日付が今日以前か確認
  if [[ "$DATE" > "$TODAY" ]]; then
    continue
  fi

  CONFIG="$REPO_DIR/books/$SLUG/config.yaml"
  if [ ! -f "$CONFIG" ]; then
    echo "$(date): WARNING: $CONFIG not found" >> "$LOG_FILE"
    continue
  fi

  # 既に公開済みか確認
  if grep -q "published: true" "$CONFIG"; then
    continue
  fi

  # 公開
  echo "$(date): Publishing book: $SLUG" >> "$LOG_FILE"
  sed -i '' 's/published: false/published: true/' "$CONFIG"

  git add "$CONFIG"
  TITLE=$(grep "^title:" "$CONFIG" | sed 's/title: *"*//;s/"*$//')
  git commit -m "publish: $TITLE"
  git push origin main

  echo "$(date): Successfully published book: $SLUG ($TITLE)" >> "$LOG_FILE"

done < "$PRIORITY_FILE"
