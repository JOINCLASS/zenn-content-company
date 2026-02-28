---
title: "プロジェクト規模別テンプレート"
---

# プロジェクト規模別テンプレート

CLAUDE.mdの内容は、プロジェクトの規模によって大きく変わります。個人の小さなスクリプトと、チームで開発する大規模アプリケーションでは、必要な情報が異なります。

この章では、3つの規模別にすぐ使えるテンプレートを紹介します。

## Small: 個人プロジェクト・スクリプト

1人で開発する小規模プロジェクト向けです。10-20行で十分です。

```markdown
# プロジェクト名

一言でプロジェクトの説明。

## スタック

- 言語: Python 3.12
- 主要ライブラリ: requests, click
- テスト: pytest

## ルール

- 型ヒントを必ずつける
- 関数にはdocstringを書く
- テストは`tests/`に配置する

## コマンド

- 実行: `python main.py`
- テスト: `pytest`
- リント: `ruff check .`
```

このレベルでは、コーディング規約を細かく書く必要はありません。技術スタックとコマンドを明示するだけで、Claude Codeは適切に動きます。

### CLIツールの例

```markdown
# mycli - ファイル変換CLIツール

CSV/JSON/YAMLの相互変換を行うCLIツール。

## スタック

- Node.js 22 + TypeScript
- CLI: Commander.js
- テスト: Vitest

## ルール

- ESM形式で書く（import/export）
- エラーは`process.exit(1)`で終了。例外はスローしない
- CLIオプションの説明は英語。ユーザー向けメッセージも英語

## コマンド

- ビルド: `pnpm build`
- テスト: `pnpm test`
- ローカル実行: `pnpm start -- --input file.csv --output file.json`
```

## Medium: チーム開発Webアプリ

3-10人のチームで開発するWebアプリケーション向けです。30-60行が目安です。

```markdown
# TaskBoard - チームタスク管理アプリ

Webベースのカンバン式タスク管理ツール。
チームメンバーのタスク割り当て、進捗管理、期限通知を提供。

## 技術スタック

- フレームワーク: Next.js 15 (App Router)
- 言語: TypeScript 5.x (strict mode)
- DB: PostgreSQL 16 + Prisma ORM
- 認証: NextAuth.js v5
- UI: Tailwind CSS v4 + Radix UI
- テスト: Vitest + Playwright (E2E)
- パッケージマネージャ: pnpm
- CI: GitHub Actions

## ディレクトリ構成

- `app/` — Next.js App Routerのルート
- `components/` — 共有UIコンポーネント
- `lib/` — ビジネスロジックとユーティリティ
- `prisma/` — スキーマとマイグレーション
- `tests/` — Vitestユニットテスト
- `e2e/` — Playwrightテスト

## コーディング規約

- Server Componentsをデフォルトにする。"use client"は必要最小限
- データ取得はServer Componentsで行う。Client Componentからfetchしない
- Prismaのクエリは`lib/db/`に集約する
- コンポーネントのpropsは`type`で定義する（`interface`ではなく）
- CSSクラスはTailwindで書く。カスタムCSSは使わない
- 日本語のコメントは許可するが、変数名・関数名は英語

## コマンド

- 開発: `pnpm dev`
- ビルド: `pnpm build`
- テスト: `pnpm test`
- E2Eテスト: `pnpm test:e2e`
- リント: `pnpm lint`
- 型チェック: `pnpm typecheck`
- DBマイグレーション: `pnpm prisma migrate dev --name <name>`
- DBシード: `pnpm prisma db seed`

## 禁止事項

- mainブランチに直接push禁止
- `.env.local`をGitに含めない
- Prismaマイグレーションファイルを手動編集しない
- `any`型を使わない。不明な型は`unknown`を使う
- `console.log`はデバッグ用のみ。本番コードに残さない

## PR規約

- PRタイトル: `feat:`, `fix:`, `refactor:`, `docs:`, `test:` のプレフィックス
- PRには変更の理由と影響範囲を記述する
- マージ前にCIが全てパスしていること
```

### ディレクトリ構成セクションの効果

ディレクトリ構成を明示すると、Claude Codeは新しいファイルを作る際に正しい場所に配置してくれます。「コンポーネントはどこに置けばいい？」と聞く必要がなくなります。

## Large: モノレポ・マイクロサービス

大規模プロジェクトでは、ルートのCLAUDE.mdに共通ルールを書き、各パッケージのCLAUDE.mdに個別ルールを書きます。

### ルートのCLAUDE.md

```markdown
# SaaSプラットフォーム

マルチテナントSaaSプラットフォーム。pnpm workspacesによるモノレポ構成。

## 構成

- `packages/web/` — Next.jsフロントエンド
- `packages/api/` — Hono APIサーバー
- `packages/shared/` — 共有型定義とユーティリティ
- `packages/db/` — Drizzle ORMスキーマとマイグレーション
- `infra/` — Terraformインフラ定義

## 全パッケージ共通ルール

- TypeScript strict mode
- ESLint + Prettierを適用（各パッケージで`pnpm lint`）
- テストは各パッケージの`__tests__/`に配置
- パッケージ間の依存はworkspace protocolを使う
- 環境変数は`packages/shared/env.ts`のzodスキーマで検証する

## 禁止事項

- パッケージ間で直接ファイルをimportしない（必ずpackage.jsonのexportsを経由）
- `shared`パッケージからは外部APIを呼ばない（純粋な型とロジックのみ）
- infrastructure as codeの変更は必ずPRレビューを通す
```

### packages/web/CLAUDE.md

```markdown
# Web フロントエンド

## スタック

- Next.js 15 (App Router)
- Tailwind CSS v4
- React Hook Form + Zod（フォームバリデーション）

## ルール

- ページコンポーネントは`app/`直下にのみ配置
- 共有コンポーネントは`components/ui/`に配置
- API呼び出しは`lib/api-client.ts`の関数を使う
- 画像は`public/`ではなくCDNのURLを使う

## コマンド

- 開発: `pnpm dev`（ポート3000）
- ビルド: `pnpm build`
- テスト: `pnpm test`
```

### packages/api/CLAUDE.md

```markdown
# API サーバー

## スタック

- Hono (Node.jsランタイム)
- Drizzle ORM
- Zod（リクエスト/レスポンス検証）

## ルール

- ルートは`routes/`にリソース単位で配置（例: `routes/users.ts`）
- ミドルウェアは`middleware/`に配置
- ビジネスロジックは`services/`に配置。ルートハンドラに直接書かない
- レスポンスは必ず`{ data, error, meta }`の形式で返す
- 認証が必要なルートには`authMiddleware`を適用する

## コマンド

- 開発: `pnpm dev`（ポート8080）
- テスト: `pnpm test`
```

## テンプレートの適用方法

1. 自分のプロジェクト規模に合ったテンプレートをコピーする
2. プロジェクト名、技術スタック、コマンドを置き換える
3. プロジェクト固有のルールを追加する
4. 不要なセクションを削除する

最初は少なめに書いて、Claude Codeの出力を見ながらルールを追加していくのが効率的です。「ここはこうしてほしかったのに」と思ったら、それをCLAUDE.mdに書き加えます。

## まとめ

- Small（10-20行）: スタックとコマンドだけでOK
- Medium（30-60行）: ディレクトリ構成と規約を追加
- Large（ルート20行 + 各パッケージ20行）: 共通ルールと個別ルールを分離
- テンプレートをベースに、プロジェクト固有のルールを足す
