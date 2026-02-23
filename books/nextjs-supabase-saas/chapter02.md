---
title: "開発環境のセットアップ -- プロジェクト作成からデプロイまで"
free: true
---

# 開発環境のセットアップ -- プロジェクト作成からデプロイまで

## はじめに

本章では、SaaSアプリケーション「TaskFlow」の開発環境を一から構築する。Next.jsプロジェクトの作成、Supabaseプロジェクトの作成、ローカル開発環境の構築、UIライブラリの導入、そしてVercelへの最初のデプロイまでを一気に進める。

本章を終える頃には、ローカルで動作するNext.js + Supabaseアプリケーションが手元にあり、それがVercel上でも公開されている状態になる。


## 必要なツールのインストール

開発を始める前に、以下のツールがインストールされていることを確認する。

### Node.js

Node.js 18.17以降が必要だ。推奨はLTS版（2026年2月時点ではNode.js 22 LTS）。

```bash
# バージョン確認
node --version
# v22.x.x

# nodenvやvoltaでバージョン管理することを推奨
```

### pnpm

本書ではパッケージマネージャとしてpnpmを使用する。npmやyarnでも構わないが、本書のコマンドはpnpmで統一する。

```bash
# pnpmのインストール
npm install -g pnpm

# バージョン確認
pnpm --version
```

### Supabase CLI

ローカル開発環境でSupabaseを動かすために、Supabase CLIが必要だ。

```bash
# macOS（Homebrew）
brew install supabase/tap/supabase

# npm経由（全OS対応）
pnpm add -g supabase

# バージョン確認
supabase --version
```

### Docker

Supabase CLIのローカル開発にはDockerが必要だ。Docker Desktopをインストールしておく。

```bash
# Dockerが動作していることを確認
docker --version
```


## Next.jsプロジェクトの作成

TaskFlowのNext.jsプロジェクトを作成する。

```bash
# プロジェクト作成
pnpm create next-app@latest taskflow \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --src-dir \
  --import-alias "@/*"

# ディレクトリに移動
cd taskflow
```

`create-next-app` のプロンプトで以下を選択する。

| 項目 | 選択 |
|------|------|
| TypeScript | Yes |
| ESLint | Yes |
| Tailwind CSS | Yes |
| src/ directory | Yes |
| App Router | Yes |
| import alias | @/* |

### ディレクトリ構成の確認

作成されたプロジェクトの構成を確認する。

```
taskflow/
├── src/
│   └── app/
│       ├── layout.tsx       # ルートレイアウト
│       ├── page.tsx         # トップページ
│       └── globals.css      # グローバルスタイル
├── public/                  # 静的ファイル
├── next.config.ts           # Next.js設定
├── tailwind.config.ts       # Tailwind CSS設定
├── tsconfig.json            # TypeScript設定
├── package.json
└── pnpm-lock.yaml
```

### 動作確認

```bash
# 開発サーバーの起動
pnpm dev

# ブラウザで http://localhost:3000 を開く
```

Next.jsのデフォルトページが表示されれば成功だ。


## Supabaseプロジェクトの作成

### Supabase Cloudでのプロジェクト作成

1. [supabase.com](https://supabase.com) にアクセスし、アカウントを作成する
2. 「New Project」をクリック
3. 以下の情報を入力する

| 項目 | 値 |
|------|-----|
| Organization | 自分の組織を選択（なければ作成） |
| Project name | taskflow |
| Database Password | 強力なパスワードを設定（後で使うので控えておく） |
| Region | Northeast Asia (Tokyo) |
| Pricing Plan | Free |

4. 「Create new project」をクリック

プロジェクトの作成には数分かかる。作成が完了したら、ダッシュボードの「Project Settings」>「API」から以下の値を控えておく。

- **Project URL**: `https://xxxxx.supabase.co`
- **anon key**: `eyJhbGci...`（公開可能なキー）
- **service_role key**: `eyJhbGci...`（サーバーサイド専用、公開禁止）

### ローカル開発環境の初期化

プロジェクトディレクトリでSupabase CLIを初期化する。

```bash
# Supabase CLIの初期化
supabase init
```

以下のファイルとディレクトリが生成される。

```
taskflow/
├── supabase/
│   ├── config.toml          # Supabase ローカル設定
│   ├── migrations/          # データベースマイグレーション
│   └── seed.sql             # 初期データ
└── ...
```

### ローカルSupabaseの起動

```bash
# ローカルSupabaseの起動（初回はDockerイメージのダウンロードがあるため数分かかる）
supabase start
```

起動すると、ローカルのSupabaseサービス群のURLが表示される。

```
Started supabase local development setup.

         API URL: http://127.0.0.1:54321
     GraphQL URL: http://127.0.0.1:54321/graphql/v1
  S3 Storage URL: http://127.0.0.1:54321/storage/v1/s3
          DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
      Studio URL: http://127.0.0.1:54323
    Inbucket URL: http://127.0.0.1:54324
      JWT secret: super-secret-jwt-token-with-at-least-32-characters
        anon key: eyJhbGci...
service_role key: eyJhbGci...
   S3 Access Key: ...
   S3 Secret Key: ...
```

- **Studio URL** (`http://127.0.0.1:54323`): ローカルのSupabaseダッシュボード
- **API URL** (`http://127.0.0.1:54321`): ローカルのSupabase API
- **Inbucket URL** (`http://127.0.0.1:54324`): メール送信のテスト用（Magic Link等の確認）


## Supabaseクライアントライブラリの導入

Next.jsからSupabaseに接続するためのクライアントライブラリをインストールする。

```bash
# Supabaseクライアントライブラリ
pnpm add @supabase/supabase-js @supabase/ssr
```

### 環境変数の設定

プロジェクトルートに `.env.local` ファイルを作成する。

```bash
# .env.local

# ローカル開発環境の値（supabase start で表示されたもの）
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# サーバーサイドでのみ使用（NEXT_PUBLIC_ プレフィックスなし）
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**重要:** `.env.local` は `.gitignore` に含まれていることを確認する（`create-next-app` のデフォルトで含まれている）。`SUPABASE_SERVICE_ROLE_KEY` は決してクライアントに公開してはならない。

### Supabaseクライアントの作成

サーバーサイドとクライアントサイドでSupabaseクライアントの作成方法が異なる。それぞれのユーティリティ関数を作成する。

```typescript
// src/lib/supabase/server.ts
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // Server Componentから呼ばれた場合、
            // cookieの設定はできないが、エラーにしない
          }
        },
      },
    }
  )
}
```

```typescript
// src/lib/supabase/client.ts
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
```

```typescript
// src/lib/supabase/admin.ts
// サーバーサイド専用: RLSをバイパスする管理者クライアント
import { createClient } from '@supabase/supabase-js'

export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  )
}
```

**使い分けの指針:**

| クライアント | 使用場所 | RLS | 用途 |
|-------------|---------|-----|------|
| `server.ts` | Server Component, Server Action, Route Handler | 有効 | 通常のデータアクセス |
| `client.ts` | Client Component | 有効 | ブラウザからのデータアクセス |
| `admin.ts` | Server Action, Route Handler, Webhook | 無効 | 管理操作（ユーザー管理等） |


## Middlewareの設定

認証状態の管理とセッション更新のために、Next.jsのMiddlewareを設定する。

```typescript
// src/middleware.ts
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({
    request,
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({
            request,
          })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // セッションの更新（重要: これによりセッションの有効期限が延長される）
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // 未認証ユーザーのダッシュボードアクセスをリダイレクト
  if (
    !user &&
    !request.nextUrl.pathname.startsWith('/login') &&
    !request.nextUrl.pathname.startsWith('/signup') &&
    !request.nextUrl.pathname.startsWith('/auth') &&
    request.nextUrl.pathname.startsWith('/dashboard')
  ) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.searchParams.set('redirect', request.nextUrl.pathname)
    return NextResponse.redirect(url)
  }

  // 認証済みユーザーのログインページアクセスをリダイレクト
  if (
    user &&
    (request.nextUrl.pathname === '/login' ||
      request.nextUrl.pathname === '/signup')
  ) {
    const url = request.nextUrl.clone()
    url.pathname = '/dashboard'
    return NextResponse.redirect(url)
  }

  return supabaseResponse
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
```


## UIライブラリの導入

UIコンポーネントには**shadcn/ui**を使用する。Tailwind CSSベースで、コピー&ペーストでプロジェクトに取り込むスタイルのライブラリだ。

### shadcn/uiの初期化

```bash
# shadcn/uiの初期化
pnpm dlx shadcn@latest init
```

プロンプトで以下を選択する。

| 項目 | 選択 |
|------|------|
| Style | New York |
| Base color | Neutral |
| CSS variables | Yes |

### 基本コンポーネントのインストール

SaaSアプリで頻繁に使うコンポーネントをインストールする。

```bash
# 基本コンポーネント
pnpm dlx shadcn@latest add button card input label \
  form dialog dropdown-menu avatar badge separator \
  table tabs toast sheet command
```

### Lucide Iconsの確認

shadcn/uiはアイコンにLucide Reactを使用する。shadcn/uiの初期化時に自動的にインストールされる。

```bash
# 確認
pnpm list lucide-react
```


## プロジェクト構成の整理

SaaSアプリケーションに適したディレクトリ構成を整える。

```
src/
├── app/
│   ├── (auth)/              # 認証関連ページ（レイアウト共有）
│   │   ├── login/
│   │   │   └── page.tsx
│   │   ├── signup/
│   │   │   └── page.tsx
│   │   └── layout.tsx
│   ├── (marketing)/         # マーケティングページ
│   │   ├── page.tsx         # トップページ（LP）
│   │   ├── pricing/
│   │   │   └── page.tsx
│   │   └── layout.tsx
│   ├── dashboard/           # 認証必須エリア
│   │   ├── page.tsx
│   │   ├── projects/
│   │   ├── settings/
│   │   └── layout.tsx
│   ├── auth/
│   │   └── callback/
│   │       └── route.ts     # OAuth コールバック
│   ├── api/
│   │   └── webhooks/
│   │       └── stripe/
│   │           └── route.ts # Stripe Webhook
│   ├── layout.tsx           # ルートレイアウト
│   └── globals.css
├── components/
│   ├── ui/                  # shadcn/ui コンポーネント
│   ├── auth/                # 認証関連コンポーネント
│   ├── dashboard/           # ダッシュボード関連
│   └── marketing/           # マーケティング関連
├── lib/
│   ├── supabase/            # Supabaseクライアント
│   │   ├── server.ts
│   │   ├── client.ts
│   │   └── admin.ts
│   ├── stripe/              # Stripe関連
│   └── utils.ts             # ユーティリティ
├── types/
│   ├── database.ts          # Supabase型定義（自動生成）
│   └── index.ts             # 共通型定義
└── middleware.ts
```

ディレクトリを作成する。

```bash
# ディレクトリ作成
mkdir -p src/app/\(auth\)/login
mkdir -p src/app/\(auth\)/signup
mkdir -p src/app/\(marketing\)/pricing
mkdir -p src/app/dashboard/projects
mkdir -p src/app/dashboard/settings
mkdir -p src/app/auth/callback
mkdir -p src/app/api/webhooks/stripe
mkdir -p src/components/auth
mkdir -p src/components/dashboard
mkdir -p src/components/marketing
mkdir -p src/lib/supabase
mkdir -p src/lib/stripe
mkdir -p src/types
```

### Route Groupsの説明

`(auth)` や `(marketing)` のカッコ付きディレクトリは、Next.jsの**Route Groups**だ。URLパスに影響を与えずに、レイアウトを共有するためのグルーピング機能だ。

- `(auth)/login/page.tsx` は `/login` でアクセスできる（URLに `auth` は含まれない）
- `(marketing)/page.tsx` は `/` でアクセスできる

これにより、認証ページとマーケティングページで異なるレイアウトを適用できる。


## TypeScript設定の強化

`tsconfig.json` にSaaS開発で有用な設定を追加する。

```json
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [
      {
        "name": "next"
      }
    ],
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

`strict: true` がデフォルトで有効になっている。SaaS開発では型安全性が特に重要なので、この設定は変更しない。


## Supabaseの型定義を自動生成する

Supabaseのテーブル構造からTypeScriptの型定義を自動生成する機能がある。現時点ではテーブルを作成していないが、生成コマンドと設定を準備しておく。

```bash
# Supabaseにログイン
supabase login

# 型定義の生成（リモートDBから）
supabase gen types typescript --project-id YOUR_PROJECT_ID > src/types/database.ts

# ローカルDBから生成する場合
supabase gen types typescript --local > src/types/database.ts
```

生成される型定義は以下のような形になる（テーブル作成後）。

```typescript
// src/types/database.ts（自動生成の例）
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      projects: {
        Row: {
          id: string
          name: string
          description: string | null
          tenant_id: string
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          description?: string | null
          tenant_id: string
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          description?: string | null
          tenant_id?: string
          created_at?: string
          updated_at?: string
        }
      }
      // ... 他のテーブル
    }
  }
}
```

この型定義をSupabaseクライアントに渡すことで、クエリの結果が型安全になる。

```typescript
// 型安全なSupabaseクライアント
import { createClient } from '@supabase/supabase-js'
import { Database } from '@/types/database'

const supabase = createClient<Database>(url, key)

// 自動補完が効く
const { data } = await supabase
  .from('projects')  // テーブル名が補完される
  .select('*')
// data の型は Database['public']['Tables']['projects']['Row'][] | null
```


## トップページの作成

簡単なランディングページを作成して、プロジェクトの動作を確認する。

```tsx
// src/app/(marketing)/layout.tsx
export default function MarketingLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <a href="/" className="text-xl font-bold">
            TaskFlow
          </a>
          <nav className="flex items-center gap-4">
            <a href="/pricing" className="text-sm text-muted-foreground hover:text-foreground">
              料金
            </a>
            <a
              href="/login"
              className="text-sm bg-primary text-primary-foreground px-4 py-2 rounded-md hover:bg-primary/90"
            >
              ログイン
            </a>
          </nav>
        </div>
      </header>
      <main className="flex-1">{children}</main>
      <footer className="border-t py-8">
        <div className="container mx-auto px-4 text-center text-sm text-muted-foreground">
          &copy; 2026 TaskFlow. All rights reserved.
        </div>
      </footer>
    </div>
  )
}
```

```tsx
// src/app/(marketing)/page.tsx
export default function HomePage() {
  return (
    <div className="container mx-auto px-4 py-24">
      <div className="max-w-3xl mx-auto text-center">
        <h1 className="text-5xl font-bold tracking-tight mb-6">
          チームのタスク管理を
          <br />
          シンプルに、パワフルに
        </h1>
        <p className="text-xl text-muted-foreground mb-8">
          TaskFlowは、プロジェクト管理をリアルタイムで共有できる
          チーム向けSaaSツールです。無料で始められます。
        </p>
        <div className="flex gap-4 justify-center">
          <a
            href="/signup"
            className="bg-primary text-primary-foreground px-8 py-3 rounded-md text-lg font-medium hover:bg-primary/90"
          >
            無料で始める
          </a>
          <a
            href="/pricing"
            className="border px-8 py-3 rounded-md text-lg font-medium hover:bg-accent"
          >
            料金を見る
          </a>
        </div>
      </div>
    </div>
  )
}
```


## ESLint と Prettier の設定

コード品質を保つために、ESLintとPrettierを整備する。

```bash
# Prettier のインストール
pnpm add -D prettier prettier-plugin-tailwindcss

# ESLint の追加プラグイン
pnpm add -D @typescript-eslint/eslint-plugin
```

```json
// .prettierrc
{
  "semi": false,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5",
  "plugins": ["prettier-plugin-tailwindcss"]
}
```

```json
// .prettierignore
node_modules
.next
dist
pnpm-lock.yaml
```

### package.json にスクリプトを追加

```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "db:start": "supabase start",
    "db:stop": "supabase stop",
    "db:reset": "supabase db reset",
    "db:migration": "supabase migration new",
    "db:types": "supabase gen types typescript --local > src/types/database.ts"
  }
}
```


## Vercelへのデプロイ

最初のデプロイを行い、本番環境の動作を確認する。

### 1. GitHubリポジトリの作成

```bash
# Gitリポジトリの初期化（create-next-appで初期化済みの場合は不要）
git init

# 全ファイルをコミット
git add .
git commit -m "Initial setup: Next.js + Supabase + shadcn/ui"

# GitHubリポジトリを作成してプッシュ
gh repo create taskflow --private --push --source .
```

### 2. Vercelプロジェクトの作成

1. [vercel.com](https://vercel.com) にアクセスし、GitHubアカウントでログイン
2. 「Add New...」>「Project」をクリック
3. GitHubからtaskflowリポジトリをインポート
4. 環境変数を設定:

| 変数名 | 値 |
|--------|-----|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase CloudのProject URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase Cloudのanon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Cloudのservice_role key |

5. 「Deploy」をクリック

### 3. Supabase Cloudの認証設定

VercelにデプロイしたアプリのURLを、Supabaseの認証設定に追加する。

1. Supabaseダッシュボードで「Authentication」>「URL Configuration」を開く
2. 以下を設定:

| 項目 | 値 |
|------|-----|
| Site URL | `https://taskflow-xxx.vercel.app` |
| Redirect URLs | `https://taskflow-xxx.vercel.app/auth/callback` |

### 4. デプロイの確認

Vercelから提供されるURLにアクセスし、トップページが表示されることを確認する。

```
https://taskflow-xxx.vercel.app
```


## 開発ワークフローの確認

開発からデプロイまでの基本的なワークフローを確認する。

### ローカル開発

```bash
# 1. Supabaseのローカルサーバーを起動
pnpm db:start

# 2. Next.jsの開発サーバーを起動
pnpm dev

# 3. ブラウザで http://localhost:3000 を開いて開発
```

### データベースの変更

```bash
# 1. マイグレーションファイルを作成
pnpm db:migration create_projects_table

# 2. supabase/migrations/ 以下に生成されたファイルにSQLを記述

# 3. マイグレーションを適用
supabase db reset

# 4. 型定義を再生成
pnpm db:types
```

### デプロイ

```bash
# 1. コードをコミット
git add .
git commit -m "feat: add projects table"

# 2. GitHubにプッシュ（VercelがGitHubと連携している場合、自動デプロイ）
git push

# 3. Supabase Cloudのマイグレーション（supabase CLIでリモートに適用）
supabase db push
```

### 環境の対応関係

| ローカル | 本番 |
|---------|------|
| `http://localhost:3000` | `https://taskflow-xxx.vercel.app` |
| `http://127.0.0.1:54321` (Supabase API) | `https://xxx.supabase.co` |
| `http://127.0.0.1:54323` (Studio) | Supabaseダッシュボード |
| `http://127.0.0.1:54324` (Inbucket) | 実際のメール送信 |
| `.env.local` | Vercel環境変数 |


## トラブルシューティング

### Supabase CLIが起動しない

```bash
# Dockerが動作しているか確認
docker info

# Supabaseのコンテナを停止してリセット
supabase stop --no-backup
supabase start
```

### 型定義の生成でエラーが出る

```bash
# ローカルSupabaseが起動していることを確認
supabase status

# 起動していなければ起動
supabase start

# 再度型生成
pnpm db:types
```

### VercelデプロイでSupabase接続エラー

環境変数が正しく設定されているか確認する。Vercelダッシュボードの「Settings」>「Environment Variables」で値を確認し、`NEXT_PUBLIC_` プレフィックスが正しく付いているか確認する。


## まとめ

本章で構築した環境を整理する。

| 項目 | 状態 |
|------|------|
| Next.js 14+ プロジェクト | 作成済み（App Router, TypeScript） |
| Supabase Cloud プロジェクト | 作成済み |
| Supabase CLI ローカル環境 | 初期化済み |
| Supabaseクライアント | サーバー用、クライアント用、管理者用の3種を作成 |
| Middleware | 認証チェックを設定 |
| shadcn/ui | 基本コンポーネントをインストール |
| ディレクトリ構成 | SaaS向けに整理 |
| Vercelデプロイ | 初回デプロイ完了 |

これで開発の基盤が整った。次章では、Supabaseの基本機能（認証、データベース、ストレージ）をハンズオン形式で学んでいく。
