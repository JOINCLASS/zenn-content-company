#!/bin/bash
# Zenn書籍を1冊公開するスクリプト
# 手動実行 or launchdで特定日に実行
# 使い方: ./publish-book.sh <book-slug>
set -euo pipefail

export PATH="/Users/kyoagun/.nvm/versions/node/v22.17.0/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="/Users/kyoagun/workspace/zenn-content-company"
cd "$REPO_DIR"

BOOK_SLUG="${1:-}"
if [ -z "$BOOK_SLUG" ]; then
  echo "Usage: ./publish-book.sh <book-slug>"
  exit 1
fi

CONFIG="books/$BOOK_SLUG/config.yaml"
if [ ! -f "$CONFIG" ]; then
  echo "Error: $CONFIG not found"
  exit 1
fi

# 今日他のコンテンツが公開されていないか確認
LOCK_FILE="/tmp/zenn-publish-$(date +%Y%m%d).lock"
if [ -f "$LOCK_FILE" ]; then
  echo "$(date): Today already published something. Skipping book."
  exit 0
fi

echo "$(date): Publishing book: $BOOK_SLUG"
sed -i '' 's/^published: false/published: true/' "$CONFIG"

git add "$CONFIG"
git commit -m "publish: 書籍「$(grep '^title:' "$CONFIG" | sed 's/title: *"*//;s/"*$//')」を公開"
git push

# ロックファイル作成（今日はこれ以上公開しない）
touch "$LOCK_FILE"

echo "$(date): Book published successfully: $BOOK_SLUG"
