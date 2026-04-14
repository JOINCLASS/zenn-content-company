---
title: "セキュリティとチーム運用"
---

# セキュリティとチーム運用

CLAUDE.mdは便利ですが、AIに強力なツールアクセスを与えることには注意が必要です。この章では、安全にClaude Codeを運用するためのセキュリティ設計と、チームで効率的に使うための運用パターンを紹介します。

## セキュリティの基本原則

### 1. 最小権限の原則

Claude Codeに与える権限は、必要最小限にします。

```markdown
## 禁止事項

IMPORTANT: 以下の操作は絶対に実行しない

- 本番環境への直接デプロイ
- 本番データベースへのクエリ実行
- `.env`ファイルの内容をログや出力に含めない
- APIキーやパスワードをコードにハードコードしない
- `rm -rf`を実行しない
- `git push --force`を実行しない
```

### 2. 秘密情報の保護

CLAUDE.mdにAPIキーやパスワードを書いてはいけません。

```markdown
# やってはいけない
## 環境設定
API_KEY=sk-abc123...

# 正しい方法
## 環境設定
- APIキーは`.env`ファイルで管理する
- `.env`はGitにコミットしない
- 必要な環境変数の一覧は`.env.example`を参照
```

### 3. 破壊的操作の制限

データを削除したり、設定を変更する操作には、確認ステップを入れます。

```markdown
## データベース操作ルール

- SELECT: 自由に実行可能
- INSERT/UPDATE: 開発DBのみ可。本番は禁止
- DELETE: 論理削除のみ。物理削除は禁止
- DROP/TRUNCATE: 禁止。マイグレーションファイルで管理する
```

## Hooksによるセキュリティ強制

CLAUDE.mdのルールはAIが「忘れる」可能性があります。重要なセキュリティルールはHooksで強制します。

### 機密ファイルへのアクセス防止

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write",
        "command": "bash -c 'FILE=\"$TOOL_INPUT_FILE_PATH\"; if echo \"$FILE\" | grep -qE \"\\.(env|pem|key)$\"; then echo \"BLOCKED: 機密ファイルへのアクセスは禁止されています\" >&2; exit 1; fi'"
      }
    ]
  }
}
```

### 危険なコマンドの防止

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "bash -c 'CMD=\"$TOOL_INPUT\"; for PATTERN in \"rm -rf\" \"DROP TABLE\" \"TRUNCATE\" \"--force\" \"--no-verify\"; do if echo \"$CMD\" | grep -qi \"$PATTERN\"; then echo \"BLOCKED: 危険なコマンドが検出されました: $PATTERN\" >&2; exit 1; fi; done'"
      }
    ]
  }
}
```

## チーム運用パターン

### パターン1: 共有CLAUDE.md + 個人設定

チームで統一するルールはプロジェクトのCLAUDE.mdに、個人の好みは`~/.claude/CLAUDE.md`に書きます。

```
プロジェクトCLAUDE.md（Git管理）:
├── 技術スタック
├── コーディング規約
├── コマンド
└── 禁止事項

個人CLAUDE.md（各自管理）:
├── 言語設定（日本語/英語）
├── 出力スタイルの好み
└── エディタ連携設定
```

### パターン2: レビュー用CLAUDE.md

コードレビューの基準をCLAUDE.mdに書いておき、レビュー時にClaude Codeを活用します。

```markdown
## コードレビュー基準

PRをレビューする際は以下を確認:

### 必須チェック
- [ ] 型安全性: any, as, !（non-null assertion）の使用がないか
- [ ] エラーハンドリング: 外部API呼び出しにtry-catchがあるか
- [ ] テスト: 追加・変更した機能にテストがあるか
- [ ] セキュリティ: ユーザー入力のバリデーションがあるか

### 推奨チェック
- [ ] パフォーマンス: N+1クエリがないか
- [ ] 可読性: 関数が30行以内か
- [ ] 命名: 変数名・関数名が意図を表しているか
```

### パターン3: オンボーディング

新しいチームメンバーがClaude Codeをすぐ使えるように、セットアップガイドをCLAUDE.mdに含めます。

```markdown
## 開発環境セットアップ

新しい開発者は以下の手順で環境を構築:

1. リポジトリをクローン
2. `pnpm install`で依存関係をインストール
3. `.env.example`をコピーして`.env`を作成し、必要な値を設定
4. `pnpm prisma migrate dev`でDBをセットアップ
5. `pnpm dev`で開発サーバーを起動
6. `http://localhost:3000`にアクセスして動作確認
```

## 権限モデルの設計

チームでClaude Codeを使う場合、メンバーの役割に応じて異なるCLAUDE.mdを用意することもできます。

```markdown
## 権限レベル

### read-only（インターン・新メンバー）
- コードの閲覧・検索のみ
- ファイル変更は提案として出力（直接編集しない）
- テスト実行は可能

### developer（一般メンバー）
- コードの閲覧・編集が可能
- テスト・ビルドの実行が可能
- mainブランチへの直接コミットは禁止

### admin（リード）
- 全操作が可能
- デプロイスクリプトの実行が可能
- 設定ファイルの変更が可能
```

## CLAUDE.mdのメンテナンス

### 定期レビュー

月に1回、CLAUDE.mdの内容を見直します。

チェックリスト：
- 古くなった技術スタックの記述はないか
- 使わなくなったコマンドはないか
- 矛盾するルールはないか
- 新しく追加すべきルールはないか

### 変更履歴

CLAUDE.mdの変更は通常のコードレビューと同様にPRを通します。なぜなら、CLAUDE.mdの変更はチーム全員のAI出力に影響するからです。

```markdown
## CLAUDE.md変更のルール

- CLAUDE.mdの変更はPRを通す
- 2人以上のレビューを必須とする
- 変更理由をPRの説明に記載する
```

## トラブルシューティング

### AIがルールを無視する場合

1. ルールが曖昧でないか確認する（具体例を追加）
2. 矛盾するルールがないか確認する
3. 重要なルールに`IMPORTANT:`をつける
4. Hooksで強制する

### 出力が安定しない場合

1. 選択肢を排除する（「AまたはB」→「Aのみ」）
2. 具体例を追加する
3. 出力フォーマットを明示する

### コンテキストが溢れる場合

1. CLAUDE.mdを短くする（不要なルールを削除）
2. サブディレクトリCLAUDE.mdに分割する
3. サブエージェントを活用する

## まとめ

- 最小権限の原則で、必要な権限のみをAIに与える
- 秘密情報はCLAUDE.mdに書かない
- 重要なセキュリティルールはHooksで強制する
- チームでは共有CLAUDE.mdと個人設定を分離する
- 月次でCLAUDE.mdの内容を見直す
- CLAUDE.mdの変更もPRレビューを通す

---

## 著者の他の書籍

以下の書籍も合わせてご覧ください。

| 書籍 | 内容 |
|------|------|
| [月5万円で会社が回る](https://zenn.dev/joinclass/books/ai-agent-management-guide) | AIエージェント経営の始め方 |
| [Claude Codeで会社を動かす](https://zenn.dev/joinclass/books/claude-code-ai-ceo) | AIエージェント経営の実践記録 |
| [Claude Code 全自動化バイブル](https://zenn.dev/joinclass/books/claude-code-automation-bible) | Hooks・Skills・MCP・cronで24時間働くAIを作る |
| [企業のためのClaude Codeセキュリティガイド](https://zenn.dev/joinclass/books/claude-code-enterprise-security) | 安全な導入・運用・ガバナンスの実践 |
| [Claude Code × MCP サーバー開発入門](https://zenn.dev/joinclass/books/claude-code-mcp-development) | 外部ツール連携で生産性を10倍にする |
| [Claude Codeマルチエージェント開発](https://zenn.dev/joinclass/books/claude-code-multi-agent) | 設計・実装・運用の実践ガイド |
| [Next.js + Supabase SaaS開発入門](https://zenn.dev/joinclass/books/nextjs-supabase-saas) | 認証・DB・決済・リアルタイムを備えた本番SaaSを構築 |
| [中小企業AI業務自動化 実践ガイド](https://zenn.dev/joinclass/books/sme-ai-automation-guide) | 3ヶ月で成果を出すROI計算から導入ロードマップまで |

▶ [全書籍一覧はこちら](https://zenn.dev/joinclass?tab=books)

▶ [Amazon Kindle版はこちら](https://amzn.to/4mvzLAo)

---

## AI業務自動化コンサルティング

本書の内容を、あなたの事業に合わせてカスタマイズしたい方へ。

合同会社ジョインクラスでは、「AI業務自動化コンサルティング」を提供しています。

### 無料AI業務診断（30分）

あなたの事業の業務フローをヒアリングし、AIで自動化できる領域と期待される効果をレポートします。

**診断でわかること:**
- あなたの事業でAI自動化の効果が最も高い業務TOP3
- 導入に必要なコストと期間の見積もり
- CLAUDE.md設計のカスタマイズ方針

**対象:**
- 従業員1-30名の中小企業、スタートアップ
- 技術者が社内にいるが、AI活用が進んでいない企業
- ひとり社長で業務過多に悩んでいる方

▶ [無料診断のお申し込みはこちら](https://joinclass.co.jp/#cta)

診断はオンラインで実施します。所要時間は30分。事前の準備は不要です。まずはお気軽にご相談ください。
