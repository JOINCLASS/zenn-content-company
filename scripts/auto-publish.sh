#!/bin/bash
# Zenn記事を1日1本ずつ自動公開するスクリプト
# cron: 0 23 * * * (JST 8:00)
set -euo pipefail

export PATH="/Users/kyoagun/.nvm/versions/node/v22.17.0/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="/Users/kyoagun/workspace/zenn-content-company"
cd "$REPO_DIR"

# 未公開記事を1本見つける（ファイル名順で最初のもの）
TARGET=$(grep -rl "^published: false" articles/*.md 2>/dev/null | head -1)

if [ -z "$TARGET" ]; then
  echo "$(date): No unpublished articles found. Skipping."
  exit 0
fi

FILENAME=$(basename "$TARGET")
echo "$(date): Publishing $FILENAME"

# published: false → true に変更
sed -i '' 's/^published: false/published: true/' "$TARGET"

# git commit & push
git add "$TARGET"
git commit -m "publish: $(head -3 "$TARGET" | grep 'title:' | sed 's/title: *"*//;s/"*$//')"
git push

echo "$(date): Successfully published $FILENAME"
