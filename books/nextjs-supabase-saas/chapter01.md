---
title: "なぜNext.js + Supabaseなのか -- SaaS開発の技術選定"
free: true
---

# なぜNext.js + Supabaseなのか -- SaaS開発の技術選定

## はじめに -- 個人開発者がSaaSを作れる時代

2026年現在、SaaSビジネスの参入障壁は劇的に下がった。

かつてSaaSプロダクトを構築するには、フロントエンド、バックエンド、データベース、認証基盤、決済システム、インフラの全てを自前で構築する必要があった。数名のエンジニアチームで半年以上かかるのが当たり前だった。

しかし今、**Next.js + Supabase**という組み合わせを使えば、1人のエンジニアが数週間でMVP（Minimum Viable Product）をリリースできる。認証、データベース、ストレージ、リアルタイム機能がSupabaseに統合されており、Next.jsのApp Routerを使えばフルスタックアプリケーションをTypeScript一本で構築できる。

本書では、この技術スタックを使って「本番運用レベル」のSaaSアプリケーションを一から構築する方法を解説する。単なるチュートリアルではなく、マルチテナント設計、Stripe決済連携、Row Level Security（RLS）、Vercelデプロイ、そしてSaaSの成長戦略までを全12章でカバーする。

筆者自身、合同会社ジョインクラスでNext.js + Supabaseベースの複数のSaaSプロダクトを開発・運用しており、その実務経験をベースに解説を進める。


## SaaS開発に必要な要素を整理する

SaaSアプリケーションには、通常のWebアプリにはない固有の要件がある。まず、SaaS開発に必要な要素を整理しよう。

### 1. 認証・認可

SaaSの最も基本的な機能だ。ユーザー登録、ログイン、パスワードリセットはもちろん、OAuth（Google、GitHub等）対応、Magic Link認証、二要素認証（2FA）まで求められることが多い。

さらにSaaS特有の要件として、**組織（テナント）単位のアクセス管理**がある。同じユーザーが複数の組織に所属し、組織ごとに異なる権限を持つ、というシナリオを想定する必要がある。

### 2. マルチテナントデータベース

テナント（顧客企業）ごとにデータを完全に分離する仕組みが必要だ。テナントAのデータがテナントBに見えてしまうことは絶対に許されない。

マルチテナントの実装方式は大きく3つある。

| 方式 | 概要 | メリット | デメリット |
|------|------|---------|-----------|
| データベース分離 | テナントごとにDBを用意 | 完全な分離 | コスト高、管理が複雑 |
| スキーマ分離 | 同じDBで別スキーマ | バランス型 | マイグレーションが複雑 |
| 行レベル分離 | 同じテーブルでtenant_id列 | 低コスト、シンプル | RLSの設計が重要 |

本書では、**行レベル分離 + Row Level Security（RLS）** のアプローチを採用する。Supabase（PostgreSQL）のRLS機能を使えば、データベースレベルでテナント間のデータ分離を強制できる。

### 3. サブスクリプション決済

SaaSのビジネスモデルの根幹だ。月額・年額のサブスクリプション、無料プラン、トライアル期間、プランのアップグレード・ダウングレード、請求書発行、支払い失敗時の処理など、考慮すべき事項が多い。

本書ではStripeを使って実装する。Stripeは世界で最も広く使われている決済プラットフォームであり、サブスクリプション管理に必要な機能が全て揃っている。

### 4. リアルタイム機能

SaaSアプリでは、リアルタイムの通知やデータ同期がUX向上に大きく寄与する。例えば、他のユーザーの操作がリアルタイムに反映される、新しいコメントが即座に表示される、ステータス更新がリアルタイムに通知される、といった機能だ。

SupabaseのRealtime機能を使えば、WebSocketベースのリアルタイム同期を簡単に実装できる。

### 5. ファイルストレージ

ユーザーがアップロードするファイル（プロフィール画像、ドキュメント、添付ファイル等）を安全に管理するストレージが必要だ。アクセス制御、容量制限、CDN配信なども考慮する。

Supabase Storageは、S3互換のオブジェクトストレージを提供しており、RLSと組み合わせたアクセス制御が可能だ。

### 6. 管理画面・分析機能

SaaSの運用には、管理者向けのダッシュボードが不可欠だ。ユーザー管理、利用状況の分析、課金状態の確認、システム監視などの機能を備える必要がある。

### 7. インフラとデプロイ

本番環境のデプロイ、CI/CD、監視、スケーリングといった運用面の考慮も重要だ。


## Next.jsを選ぶ理由

SaaSのフロントエンド（+バックエンド）フレームワークとして、なぜNext.jsが最適なのか。

### App Router -- サーバーファーストのアーキテクチャ

Next.js 13で導入され、14で安定版となったApp Routerは、React Server Components（RSC）を基盤としたサーバーファーストのアーキテクチャだ。

```typescript
// app/dashboard/page.tsx -- Server Component（デフォルト）
// このコンポーネントはサーバーでのみ実行される
import { createClient } from '@/lib/supabase/server'

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: projects } = await supabase
    .from('projects')
    .select('*')
    .order('created_at', { ascending: false })

  return (
    <div>
      <h1>Dashboard</h1>
      <ProjectList projects={projects ?? []} />
    </div>
  )
}
```

Server Componentsの利点は以下の通りだ。

1. **データフェッチがサーバーで完結する** -- APIエンドポイントを別途作る必要がない
2. **クライアントバンドルが小さくなる** -- サーバーでのみ使うライブラリがバンドルに含まれない
3. **SEOに強い** -- サーバーでレンダリングされたHTMLが返される
4. **セキュリティが向上する** -- APIキーやデータベース接続情報がクライアントに露出しない

### Server Actions -- APIルートの削減

Next.js 14のServer Actionsを使えば、フォーム送信やデータ変更のためにAPIルートを書く必要がなくなる。

```typescript
// app/projects/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function createProject(formData: FormData) {
  const supabase = await createClient()
  const name = formData.get('name') as string
  const description = formData.get('description') as string

  const { error } = await supabase
    .from('projects')
    .insert({ name, description })

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/dashboard')
  return { success: true }
}
```

```tsx
// app/projects/new/page.tsx
import { createProject } from '../actions'

export default function NewProjectPage() {
  return (
    <form action={createProject}>
      <input name="name" placeholder="プロジェクト名" required />
      <textarea name="description" placeholder="説明" />
      <button type="submit">作成</button>
    </form>
  )
}
```

APIルートの管理から解放されることで、SaaS開発の生産性が大幅に向上する。

### Middleware -- 認証チェックの一元化

Next.jsのMiddleware機能を使えば、認証状態のチェックやリダイレクトをルーティングレベルで一元管理できる。

```typescript
// middleware.ts
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value)
          })
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) => {
            supabaseResponse.cookies.set(name, value, options)
          })
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()

  // 未認証ユーザーをログインページにリダイレクト
  if (!user && request.nextUrl.pathname.startsWith('/dashboard')) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    return NextResponse.redirect(url)
  }

  return supabaseResponse
}

export const config = {
  matcher: ['/dashboard/:path*', '/settings/:path*'],
}
```

### その他の利点

- **TypeScript完全対応**: 型安全なフルスタック開発
- **画像最適化**: `next/image`による自動最適化
- **フォント最適化**: `next/font`によるCLS改善
- **並列ルート・インターセプトルート**: モーダルやレイアウトの複雑なUI
- **Vercelとの親和性**: ゼロコンフィグでのデプロイ


## Supabaseを選ぶ理由

バックエンド基盤として、なぜSupabaseが最適なのか。

### Firebaseの代替ではなく「PostgreSQLの拡張」

Supabaseはしばしば「オープンソースのFirebase代替」と紹介される。しかしこの説明は本質を見誤っている。Supabaseは**PostgreSQLを中心に据えたバックエンドプラットフォーム**であり、SQLの全機能を使える点がFirebase（NoSQL）との根本的な違いだ。

SaaS開発においてリレーショナルデータベースが有利な理由は明確だ。

1. **トランザクション**: 決済処理など、一連の操作のアトミック性が保証される
2. **JOIN**: 複数テーブルの結合クエリが自然に書ける
3. **制約**: 外部キー、一意制約、チェック制約でデータ整合性を担保
4. **RLS**: PostgreSQLのネイティブ機能として行レベルセキュリティが使える
5. **マイグレーション**: スキーマの変更を管理・追跡できる

### Supabaseの統合機能

Supabaseは以下の機能を一つのプラットフォームで提供する。

```
┌─────────────────────────────────────────────────┐
│                  Supabase                        │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │   Auth   │  │ Database │  │ Storage  │      │
│  │ (GoTrue) │  │(Postgres)│  │  (S3互換) │      │
│  └──────────┘  └──────────┘  └──────────┘      │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ Realtime │  │Edge Func │  │  Vector  │      │
│  │(WebSocket)│  │  (Deno)  │  │(pgvector)│      │
│  └──────────┘  └──────────┘  └──────────┘      │
│                                                  │
│  ┌──────────────────────────────────────────┐   │
│  │         PostgREST (自動REST API)         │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

| 機能 | 説明 | SaaSでの用途 |
|------|------|-------------|
| Auth | 認証・認可 | ユーザー登録、ログイン、OAuth |
| Database | PostgreSQL | テナントデータ、メタデータ |
| Storage | S3互換ストレージ | ファイルアップロード |
| Realtime | WebSocketベースのリアルタイム | 通知、データ同期 |
| Edge Functions | サーバーレスファンクション | Webhook処理、外部API連携 |
| Vector | pgvectorベースのベクトルDB | AI/検索機能 |

これらが全て**1つのダッシュボード**から管理でき、**1つのクライアントライブラリ**でアクセスできる。

### RLS -- SaaSのためのセキュリティ機能

Supabase（PostgreSQL）のRow Level Security（RLS）は、SaaSのマルチテナント設計における決定的な利点だ。

```sql
-- テナントのメンバーのみがテナントのデータにアクセスできるポリシー
CREATE POLICY "tenant_isolation" ON projects
  FOR ALL
  USING (
    tenant_id IN (
      SELECT tenant_id FROM tenant_members
      WHERE user_id = auth.uid()
    )
  );
```

このポリシーをデータベースレベルで設定すれば、アプリケーションコードでフィルタリングを忘れても、他テナントのデータが漏洩することはない。**セキュリティがインフラ層で保証される**のだ。

### 料金体系 -- スタートアップに優しい

Supabaseの料金体系はSaaS開発者に優しい。

| プラン | 月額 | 含まれるリソース |
|--------|------|----------------|
| Free | $0 | DB 500MB, Storage 1GB, 5万MAU |
| Pro | $25 | DB 8GB, Storage 100GB, 10万MAU |
| Team | $599 | 拡張リソース、優先サポート |

Freeプランでも十分にMVPを構築・検証でき、ユーザーが増えたらProプランに移行すれば良い。従量課金が始まるのはProプランの含有リソースを超えた場合のみだ。


## 競合技術との比較

「なぜこの組み合わせか」をさらに明確にするため、代替の技術スタックと比較する。

### Next.js + Supabase vs Next.js + Firebase

| 観点 | Supabase | Firebase |
|------|----------|---------|
| データベース | PostgreSQL（RDB） | Firestore（NoSQL） |
| クエリ | SQLの全機能 | 制限付きクエリ |
| RLS | PostgreSQLネイティブ | Firestore Security Rules |
| マイグレーション | SQL標準のマイグレーション | スキーマレス |
| ロックイン | オープンソース、移行可能 | Google依存 |
| ローカル開発 | supabase CLIで完全再現 | Firebase Emulatorで部分的 |

SaaS開発では、**データの整合性と複雑なクエリ**が求められる場面が多い。ユーザーの課金状態、テナントのメンバーシップ、権限の階層構造など、リレーショナルに表現するのが自然なデータが多いため、PostgreSQLベースのSupabaseに軍配が上がる。

### Next.js + Supabase vs Ruby on Rails

| 観点 | Next.js + Supabase | Ruby on Rails |
|------|-------------------|---------------|
| 言語 | TypeScript統一 | Ruby + JavaScript |
| フロントエンド | React（リッチUI） | Hotwire/Turbo（限定的） |
| リアルタイム | Supabase Realtime | Action Cable |
| 認証 | Supabase Auth（設定のみ） | Devise（コード必要） |
| デプロイ | Vercel + Supabase | Heroku / AWS |
| スケーリング | サーバーレスで自動 | サーバー管理が必要 |

Railsは「一人でフルスタック開発」の先駆者だが、モダンなSaaS開発では**フロントエンドの表現力**がビジネス上の差別化要因になることが多い。Next.js + Reactの組み合わせは、リッチなUIを構築する上で圧倒的に有利だ。

### Next.js + Supabase vs Next.js + Prisma + 自前Auth

| 観点 | Supabase | 自前構築 |
|------|----------|---------|
| 認証 | 組み込み（設定のみ） | 自前実装 or NextAuth |
| DB管理 | ダッシュボード + CLI | Prisma Studio + CLI |
| ストレージ | 組み込み | S3 + 別途管理 |
| リアルタイム | 組み込み | Socket.io等を別途実装 |
| 初期構築の速度 | 速い | 遅い |
| カスタマイズ性 | 中程度 | 高い |

自前構築のカスタマイズ性は高いが、SaaSのMVP段階では「速く市場に出して検証する」ことが最優先だ。Supabaseを使えば、認証・DB・ストレージ・リアルタイムの基盤を**数時間で構築**できる。


## 本書で構築するSaaSアプリケーション

本書を通じて、架空のSaaSアプリケーション「TaskFlow」を構築する。TaskFlowは、チーム向けのプロジェクト管理・タスク管理SaaSだ。

### 機能一覧

| 機能 | 実装する章 |
|------|-----------|
| ユーザー認証（メール/パスワード、Google OAuth、Magic Link） | 第4章 |
| 組織（テナント）の作成・管理 | 第5章 |
| プロジェクトのCRUD | 第6章 |
| タスクのリアルタイム同期 | 第6章 |
| ファイル添付 | 第7章 |
| サブスクリプション決済（Free / Pro / Business） | 第8章 |
| 管理者ダッシュボード | 第9章 |
| テナント間データ分離（RLS） | 第10章 |
| 本番デプロイ | 第11章 |

### 料金プラン

| プラン | 月額 | 機能制限 |
|--------|------|---------|
| Free | 無料 | 1プロジェクト、3メンバー、100MB Storage |
| Pro | 月額 ¥980 | 10プロジェクト、20メンバー、10GB Storage |
| Business | 月額 ¥2,980 | 無制限プロジェクト、無制限メンバー、100GB Storage |

### 技術スタック

```
フロントエンド:
  - Next.js 14+ (App Router)
  - TypeScript
  - Tailwind CSS
  - shadcn/ui

バックエンド:
  - Supabase (PostgreSQL, Auth, Storage, Realtime)
  - Stripe (決済)

インフラ:
  - Vercel (フロントエンド)
  - Supabase Cloud (バックエンド)

開発ツール:
  - Supabase CLI
  - pnpm
  - ESLint + Prettier
```


## 本書の読み方

### 対象読者

- Next.jsの基本（ページの作成、コンポーネント、ルーティング）がわかるエンジニア
- TypeScriptの基本的な構文がわかるエンジニア
- SaaSプロダクトを作りたい個人開発者・スタートアップエンジニア

### 前提知識

以下の知識があるとスムーズに読み進められる。

- HTML/CSS/JavaScriptの基礎
- Reactの基本概念（コンポーネント、State、Props）
- SQLの基礎（SELECT、INSERT、UPDATE、DELETE）
- Gitの基本操作
- ターミナル操作

### 各章の位置付け

```
基礎編（第1-3章）   -- 技術選定、環境構築、Supabaseの基本
実装編（第4-7章）   -- 認証、DB設計、CRUD、ストレージ
ビジネス編（第8-9章）-- 決済、管理画面
セキュリティ編（第10章） -- RLS
運用編（第11章）    -- デプロイ、監視
成長編（第12章）    -- PLG、料金設計、スケーリング
```

第1章から順に読み進めることで、SaaSアプリが段階的に完成していく構成になっている。ただし、特定の機能だけを実装したい場合は、該当する章から読むことも可能だ。

### コードの入手

本書のサンプルコードは、各章の冒頭で示すリポジトリからクローンできる。章ごとにブランチが用意されており、各章の完成状態のコードを確認できる。


## まとめ

本章では、SaaS開発の全体像と、Next.js + Supabaseという技術選定の理由を説明した。

要点を整理する。

1. **SaaS開発には認証、マルチテナントDB、決済、リアルタイム機能が必要** -- これらを全て自前で構築するのは現実的でない
2. **Next.js App Routerはサーバーファーストのアーキテクチャ** -- Server Components、Server Actions、MiddlewareでSaaS開発の生産性が高い
3. **SupabaseはPostgreSQLベースの統合プラットフォーム** -- Auth、Database、Storage、Realtimeが一つにまとまっている
4. **RLSがマルチテナント設計の決め手** -- データベースレベルでテナント間分離を保証できる
5. **スタートアップに優しい料金体系** -- Freeプランで始めてスケールに応じて拡張

次章では、開発環境のセットアップから始める。Next.jsプロジェクトの作成、Supabaseプロジェクトの作成、ローカル開発環境の構築、そして最初のデプロイまでを一気に進める。
