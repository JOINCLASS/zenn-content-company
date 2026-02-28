---
title: "Skills とカスタムコマンド"
---

# Skills とカスタムコマンド

Claude Code Skillsは、繰り返し使うプロンプトを「スラッシュコマンド」として登録する機能です。CLAUDE.mdが「常にこうしてほしい」という設定なら、Skillsは「今からこれをやって」という指示のテンプレートです。

## Skillsとは

Skillsは、`.claude/skills/`ディレクトリに配置するMarkdownファイルです。各ファイルがスラッシュコマンドとして使えるようになります。

```
.claude/
└── skills/
    ├── commit.md        → /commit で呼び出し
    ├── review-pr.md     → /review-pr で呼び出し
    └── new-component.md → /new-component で呼び出し
```

## 基本的なSkillの作り方

Skillファイルはシンプルなマークダウンで、以下の構成で書きます。

### 例: コミットSkill

`.claude/skills/commit.md`:

```markdown
変更内容を確認し、適切なコミットメッセージを生成してコミットしてください。

手順:
1. `git diff --staged`で変更内容を確認
2. 変更がステージングされていない場合は`git diff`で確認し、関連ファイルをステージング
3. 変更内容を分析し、Conventional Commits形式のメッセージを生成
4. `git commit`を実行

コミットメッセージのルール:
- プレフィックス: feat, fix, refactor, docs, test, chore
- 日本語で記述
- 1行目は50文字以内
- 必要に応じて本文に詳細を記載
```

使い方: チャットで `/commit` と入力するだけ。

### 例: PRレビューSkill

`.claude/skills/review-pr.md`:

```markdown
指定されたPRをレビューしてください。

手順:
1. `gh pr diff`で変更差分を取得
2. 以下の観点でレビュー:
   - バグがないか
   - セキュリティ上の問題がないか
   - パフォーマンスの問題がないか
   - テストが十分か
   - コーディング規約に従っているか
3. 問題があればコメント案を作成
4. 問題がなければ「LGTM」の旨を報告

レビュー結果のフォーマット:
## レビュー結果

### 問題点
- [ ] ファイル名:行番号 — 説明

### 改善提案
- ファイル名:行番号 — 提案内容

### 良い点
- 具体的に良い点を挙げる
```

使い方: `/review-pr 123` でPR #123をレビュー。

## 実用的なSkillパターン

### コンポーネント生成Skill

`.claude/skills/new-component.md`:

```markdown
新しいReactコンポーネントを作成してください。

引数としてコンポーネント名を受け取ります。

手順:
1. `components/ui/{ComponentName}.tsx`にコンポーネントを作成
2. Props型を定義
3. Tailwind CSSでスタイリング
4. `components/ui/index.ts`にexportを追加
5. `__tests__/components/{ComponentName}.test.tsx`にテストを作成
6. テストを実行して通ることを確認

コンポーネントのテンプレート:
- export namedのみ（default exportは使わない）
- forwardRefが必要な場合はRefを受け取る
- classNameのマージにはcnユーティリティを使う
```

### DBマイグレーションSkill

`.claude/skills/migrate.md`:

```markdown
データベースマイグレーションを作成してください。

引数としてマイグレーションの説明を受け取ります。

手順:
1. `prisma/schema.prisma`に必要な変更を加える
2. `pnpm prisma migrate dev --name {説明をkebab-caseに変換}`でマイグレーション生成
3. 生成されたSQLファイルの内容を表示して確認
4. 影響を受ける`lib/db/`のクエリ関数を更新
5. テストを更新
6. `pnpm test`で全テストがパスすることを確認
```

### APIエンドポイント生成Skill

`.claude/skills/new-api.md`:

```markdown
新しいAPIエンドポイントを作成してください。

引数としてリソース名とHTTPメソッドを受け取ります（例: "users GET,POST"）。

手順:
1. `schemas/{resource}.ts`にZodスキーマを作成
2. `services/{resource}.ts`にビジネスロジックを作成
3. `app/api/{resource}/route.ts`にルートハンドラを作成
4. テストを`__tests__/api/{resource}.test.ts`に作成
5. `pnpm test`でテストがパスすることを確認
6. `pnpm typecheck`で型エラーがないことを確認

APIレスポンス形式:
- 成功: `{ data: T }`
- リスト: `{ data: T[], meta: { total, page, limit } }`
- エラー: `{ error: { code, message } }`
```

### リリースノート生成Skill

`.claude/skills/release-notes.md`:

```markdown
最新のリリースノートを生成してください。

手順:
1. `git log`で前回のタグから現在までのコミットを取得
2. コミットをカテゴリ別に分類:
   - feat: 新機能
   - fix: バグ修正
   - refactor: リファクタリング
   - その他
3. 以下のフォーマットで出力:

## v{バージョン} リリースノート

### 新機能
- 説明

### バグ修正
- 説明

### その他の変更
- 説明
```

## ユーザースコープのSkills

`~/.claude/skills/`に配置すると、全プロジェクトで使えるグローバルSkillになります。

```
~/.claude/
└── skills/
    ├── explain.md       → /explain（コードの解説）
    ├── optimize.md      → /optimize（パフォーマンス改善）
    └── security-check.md → /security-check（セキュリティチェック）
```

個人的によく使うワークフローはここに配置します。

## Skillsの設計ガイドライン

### 1. 1つのSkillに1つの目的

「コンポーネント作成 + テスト + ストーリー」を1つのSkillにまとめるのは良いですが、「コンポーネント作成 + PRレビュー」のように無関係なものを混ぜるのは避けましょう。

### 2. 手順は番号付きリストで

Claude Codeは番号付きリストを順番に実行します。手順の順序が重要な場合は必ず番号をつけます。

### 3. 出力フォーマットを明示

結果をどの形式で出力してほしいかを明示すると、一貫した出力が得られます。

### 4. エラーハンドリングを含める

「テストが失敗した場合は修正してから再実行」のように、エラー時の対処もSkillに含めておくと、Claude Codeが自律的にリカバリーしてくれます。

## CLAUDE.mdとSkillsの使い分け

| 用途 | CLAUDE.md | Skills |
|------|-----------|--------|
| 常に適用するルール | 向いている | 向いていない |
| オンデマンドの作業 | 向いていない | 向いている |
| テンプレート化された手順 | 記載は可能 | 最適 |
| 個人の好み | ユーザーCLAUDE.md | ユーザーSkills |
| チーム共有 | プロジェクトCLAUDE.md | プロジェクトSkills |

## まとめ

- Skillsは`.claude/skills/`にMarkdownで配置するスラッシュコマンド
- 繰り返すワークフローをテンプレート化する
- 1 Skill = 1目的で設計する
- 手順は番号付きリスト、出力フォーマットを明示
- プロジェクトスコープとユーザースコープを使い分ける
