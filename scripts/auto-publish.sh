#!/bin/bash
# Zenn記事を1日1本ずつ自動公開するスクリプト
# launchd: com.joinclass.zenn-publish（毎日8:00 JST）
# ルール: 1日1コンテンツのみ + 実体験検証チェック合格のみ公開
set -uo pipefail

export PATH="/Users/kyoagun/.nvm/versions/node/v22.17.0/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR="/Users/kyoagun/workspace/zenn-content-company"
VERIFY_SCRIPT="/Users/kyoagun/workspace/one-ceo/.company/scripts/verify-article-authenticity.sh"
cd "$REPO_DIR"

# 今日他のコンテンツが公開されていないか確認
LOCK_FILE="/tmp/zenn-publish-$(date +%Y%m%d).lock"
if [ -f "$LOCK_FILE" ]; then
  echo "$(date): Today already published something (book or article). Skipping."
  exit 0
fi

# 優先公開リスト（上から順に優先。ファイルが存在しpublished: falseなら最優先で公開）
PRIORITY_FILE="$REPO_DIR/scripts/publish-priority.txt"
PRIORITY_LIST=""
if [ -f "$PRIORITY_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    CANDIDATE="$REPO_DIR/articles/$line"
    if [ -f "$CANDIDATE" ] && grep -q "^published: false" "$CANDIDATE"; then
      PRIORITY_LIST="$CANDIDATE $PRIORITY_LIST"
    fi
  done < "$PRIORITY_FILE"
fi

# 優先リスト + 残りの未公開記事をマージ
ALL_TARGETS="$PRIORITY_LIST $(grep -rl "^published: false" articles/*.md 2>/dev/null | tr '\n' ' ')"

# 重複除去して順番に処理
SEEN=""
for TARGET in $ALL_TARGETS; do
  # 重複スキップ
  case "$SEEN" in *"$TARGET"*) continue ;; esac
  SEEN="$SEEN $TARGET"

  FILENAME=$(basename "$TARGET")

  # 実体験検証チェック（Zenn AIガイドライン対応）
  if [ -f "$VERIFY_SCRIPT" ]; then
    VERIFY_RESULT=$("$VERIFY_SCRIPT" "$TARGET" 2>/dev/null | head -1)
    if echo "$VERIFY_RESULT" | grep -q "❌ 不合格"; then
      echo "$(date): SKIP $FILENAME — 実体験検証不合格（Zenn AIガイドライン）"
      continue
    fi
  fi

  echo "$(date): Publishing $FILENAME (verification passed)"

  # published: false → true に変更
  sed -i '' 's/^published: false/published: true/' "$TARGET"

  # git commit & push
  git add "$TARGET"
  git commit -m "publish: $(head -3 "$TARGET" | grep 'title:' | sed 's/title: *"*//;s/"*$//')"
  git push

  # ロックファイル作成
  touch "$LOCK_FILE"

  echo "$(date): Successfully published $FILENAME"
  exit 0
done

echo "$(date): No verified unpublished articles found. Skipping."
