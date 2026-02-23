---
title: "デプロイと運用 -- Vercel + Supabase本番環境の構築"
free: false
---

# デプロイと運用 -- Vercel + Supabase本番環境の構築

## はじめに

開発が完了し、本番環境にデプロイする段階に来た。SaaSアプリケーションのデプロイは、単にコードをサーバーにアップロードすることではない。セキュリティ、パフォーマンス、監視、バックアップ、CI/CDの全てを考慮した運用体制を構築する必要がある。

本章では以下を構築する。

1. Vercelへの本番デプロイ設定
2. Supabaseの本番環境設定
3. カスタムドメインとSSL
4. CI/CDパイプライン（GitHub Actions）
5. データベースマイグレーションの自動化
6. 監視とアラート
7. バックアップとリカバリ
8. 環境分離（Staging / Production）


## Vercelへの本番デプロイ

### プロジェクト設定

Vercelダッシュボードで以下を設定する。

| 設定 | 値 |
|------|-----|
| Framework Preset | Next.js |
| Build Command | `pnpm build` |
| Output Directory | `.next` |
| Install Command | `pnpm install` |
| Node.js Version | 22.x |

### 環境変数の設定

Vercelダッシュボードの「Settings」>「Environment Variables」で、環境ごとに変数を設定する。

```
# Production環境
NEXT_PUBLIC_SUPABASE_URL=https://xxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGci...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...

NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

STRIPE_PRO_MONTHLY_PRICE_ID=price_...
STRIPE_PRO_YEARLY_PRICE_ID=price_...
STRIPE_BUSINESS_MONTHLY_PRICE_ID=price_...
STRIPE_BUSINESS_YEARLY_PRICE_ID=price_...

NEXT_PUBLIC_APP_URL=https://taskflow.example.com
```

**重要:** `SUPABASE_SERVICE_ROLE_KEY` と `STRIPE_SECRET_KEY` は `NEXT_PUBLIC_` プレフィックスを付けない。クライアントに公開してはならない。

### カスタムドメインの設定

1. Vercelダッシュボードの「Settings」>「Domains」
2. カスタムドメイン（例: `taskflow.example.com`）を追加
3. DNSレコードを設定:

```
# CNAMEレコード
taskflow.example.com.  CNAME  cname.vercel-dns.com.

# もしくはAレコード（ルートドメインの場合）
example.com.  A  76.76.21.21
```

Vercelが自動的にSSL証明書を発行・更新する。


## Supabaseの本番環境設定

### 認証設定

Supabaseダッシュボードの「Authentication」で以下を設定する。

```
# URL Configuration
Site URL: https://taskflow.example.com
Redirect URLs:
  - https://taskflow.example.com/auth/callback
  - https://*.vercel.app/auth/callback (Preview用)

# Email Templates
カスタムメールテンプレートを設定（招待、確認、パスワードリセット）

# Providers
Google OAuth: 有効
  - Client ID: (Google Cloud Consoleから)
  - Client Secret: (Google Cloud Consoleから)
GitHub OAuth: 有効
  - Client ID: (GitHub Developer Settingsから)
  - Client Secret: (GitHub Developer Settingsから)
```

### メール送信の設定

本番環境では、Supabaseのデフォルトメールサーバーではなく、カスタムSMTPを設定することを推奨する。

```
# Supabase Dashboard > Project Settings > Auth > SMTP Settings
SMTP Host: smtp.resend.com
SMTP Port: 465
SMTP User: resend
SMTP Password: re_xxxxx
Sender Email: noreply@taskflow.example.com
Sender Name: TaskFlow
```

推奨のメール送信サービス:
- **Resend**: 開発者向け、モダンなAPI、月3,000通無料
- **SendGrid**: 大手、月100通無料
- **Amazon SES**: 大量送信向け、低コスト

### データベースの接続プーリング

Supabaseは、外部からの接続に**PgBouncer**（接続プーラー）を提供する。サーバーレス環境（Vercel）では、接続プーリングモードを使用する。

```
# 直接接続（マイグレーション用）
postgresql://postgres:[password]@db.xxxxx.supabase.co:5432/postgres

# プール接続（アプリケーション用）
postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres
```

Supabaseクライアントライブラリ（`@supabase/supabase-js`）を使う場合は、PostgREST経由でアクセスするため、接続プーリングの設定は不要だ。


## CI/CDパイプライン

### GitHub Actions の設定

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  NEXT_PUBLIC_SUPABASE_URL: ${{ secrets.NEXT_PUBLIC_SUPABASE_URL }}
  NEXT_PUBLIC_SUPABASE_ANON_KEY: ${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}

jobs:
  lint-and-type-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile

      - name: Type Check
        run: pnpm tsc --noEmit

      - name: Lint
        run: pnpm lint

      - name: Format Check
        run: pnpm format:check

  build:
    runs-on: ubuntu-latest
    needs: lint-and-type-check
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile

      - name: Build
        run: pnpm build
        env:
          NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: ${{ secrets.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY }}

  deploy-db:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: build
    steps:
      - uses: actions/checkout@v4

      - uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Link Supabase Project
        run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      - name: Push Database Migrations
        run: supabase db push
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

### 必要なGitHub Secrets

| Secret | 説明 |
|--------|------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | Stripe publishable key |
| `SUPABASE_PROJECT_REF` | Supabase Project Reference ID |
| `SUPABASE_ACCESS_TOKEN` | Supabase CLI access token |


## データベースマイグレーションの運用

### マイグレーションのワークフロー

```bash
# 1. ローカルで新しいマイグレーションを作成
supabase migration new add_custom_fields_to_tasks

# 2. マイグレーションファイルにSQLを記述
# supabase/migrations/20260223xxxxxx_add_custom_fields_to_tasks.sql

# 3. ローカルでテスト
supabase db reset

# 4. 型定義を再生成
pnpm db:types

# 5. コミット・プッシュ
git add .
git commit -m "feat: add custom fields to tasks"
git push

# 6. CI/CDが自動的に本番DBにマイグレーションを適用
```

### マイグレーションのベストプラクティス

```sql
-- 1. カラム追加は安全（ダウンタイムなし）
ALTER TABLE public.tasks ADD COLUMN labels TEXT[] DEFAULT '{}';

-- 2. NOT NULLカラムの追加はデフォルト値が必要
ALTER TABLE public.tasks ADD COLUMN priority_score INTEGER NOT NULL DEFAULT 0;

-- 3. カラム削除は段階的に行う
-- Step 1: アプリケーションコードからカラムの参照を削除
-- Step 2: カラムをNULLABLEにする（安全策）
-- Step 3: 次のリリースでカラムを削除

-- 4. インデックスはCONCURRENTLYで作成（ロック回避）
CREATE INDEX CONCURRENTLY idx_tasks_labels ON public.tasks USING gin(labels);
```


## 監視とアラート

### Vercelの監視

Vercelは以下の監視機能を提供する。

| 機能 | 説明 |
|------|------|
| Analytics | ページビュー、Web Vitals |
| Speed Insights | Core Web Vitals（LCP、FID、CLS） |
| Logs | サーバーサイドのログ |
| Functions | Serverless Functionの実行時間・エラー |

```typescript
// next.config.ts でAnalyticsを有効化
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  experimental: {
    // Vercel Speed Insights
  },
}

export default nextConfig
```

```tsx
// src/app/layout.tsx にAnalyticsを追加
import { Analytics } from '@vercel/analytics/react'
import { SpeedInsights } from '@vercel/speed-insights/next'

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="ja">
      <body>
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  )
}
```

```bash
# Vercel Analytics のインストール
pnpm add @vercel/analytics @vercel/speed-insights
```

### Supabaseの監視

Supabaseダッシュボードで確認できる項目:

| 項目 | 場所 |
|------|------|
| API リクエスト数 | Reports > API |
| データベースサイズ | Database > Usage |
| 認証イベント | Authentication > Logs |
| ストレージ使用量 | Storage > Usage |
| Realtime接続数 | Reports > Realtime |

### エラー追跡

本番環境のエラーを追跡するためにSentryを導入する。

```bash
pnpm add @sentry/nextjs
npx @sentry/wizard@latest -i nextjs
```

```typescript
// sentry.client.config.ts
import * as Sentry from '@sentry/nextjs'

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: 0.1, // 10%のトランザクションをサンプリング
  environment: process.env.NODE_ENV,
})
```


## バックアップとリカバリ

### Supabaseのバックアップ

| プラン | バックアップ頻度 | 保持期間 |
|--------|--------------|---------|
| Free | 日次 | 7日 |
| Pro | 日次 | 7日（PITR 7日） |
| Team | 日次 | 30日（PITR 30日） |

**PITR（Point-in-Time Recovery）**: Pro以上のプランでは、任意の時点にデータベースを復元できる。

### 手動バックアップ

```bash
# pg_dump でバックアップ（ローカルから本番DBへの接続）
pg_dump \
  --host=db.xxxxx.supabase.co \
  --port=5432 \
  --username=postgres \
  --dbname=postgres \
  --format=custom \
  --file=backup_$(date +%Y%m%d).dump

# リストア
pg_restore \
  --host=db.xxxxx.supabase.co \
  --port=5432 \
  --username=postgres \
  --dbname=postgres \
  --clean \
  backup_20260223.dump
```


## 環境分離

### Staging環境の構築

本番環境と同じ構成のStaging環境を用意する。

```
本番環境:
  - Vercel Production Deployment
  - Supabase Production Project
  - Stripe Live Mode
  - taskflow.example.com

Staging環境:
  - Vercel Preview Deployment (mainブランチ以外)
  - Supabase Staging Project (別プロジェクト)
  - Stripe Test Mode
  - staging.taskflow.example.com
```

### Vercelの環境変数分離

Vercelでは、環境ごと（Production / Preview / Development）に異なる環境変数を設定できる。

```
# Production
NEXT_PUBLIC_SUPABASE_URL=https://prod-xxxxx.supabase.co
STRIPE_SECRET_KEY=sk_live_...

# Preview (Staging)
NEXT_PUBLIC_SUPABASE_URL=https://staging-xxxxx.supabase.co
STRIPE_SECRET_KEY=sk_test_...
```

### Supabaseのブランチング

Supabase CLIのブランチング機能を使えば、GitブランチごとにSupabaseの環境を自動的に作成できる。

```bash
# ブランチングの有効化
supabase branches create feature/new-feature

# ブランチごとにマイグレーションを適用
supabase db push --branch feature/new-feature
```


## セキュリティチェックリスト

本番環境のデプロイ前に確認するセキュリティチェックリスト。

### 認証・認可

- [ ] RLSが全テーブルで有効
- [ ] `service_role` キーがクライアントに公開されていない
- [ ] OAuthのリダイレクトURLが本番ドメインのみに制限されている
- [ ] メール確認が有効（Supabase Auth設定）
- [ ] パスワードの最小長が8文字以上

### API

- [ ] Supabase anon keyの権限が最小限
- [ ] APIレート制限が設定されている
- [ ] CORSの設定が本番ドメインのみ許可

### データ

- [ ] バックアップが設定されている
- [ ] PITRが有効（Pro以上）
- [ ] データベースパスワードが十分に強力

### インフラ

- [ ] SSL/TLSが有効
- [ ] 環境変数にシークレットが含まれていない（`.env` がコミットされていない）
- [ ] Vercelの環境変数が正しく設定されている
- [ ] Stripe Webhookの署名検証が有効

### 監視

- [ ] エラー追跡（Sentry等）が設定されている
- [ ] Web Vitalsの監視が有効
- [ ] Supabaseの使用量アラートが設定されている


## パフォーマンスの最適化

### Next.jsの最適化

```typescript
// next.config.ts
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: '*.supabase.co',
        pathname: '/storage/v1/object/public/**',
      },
    ],
  },
  // 実験的機能
  experimental: {
    // PPR (Partial Prerendering) が安定版になった場合
    // ppr: true,
  },
}

export default nextConfig
```

### キャッシュ戦略

```typescript
// 静的データのキャッシュ（料金プラン等）
// Server Componentで revalidate を設定
export const revalidate = 3600 // 1時間キャッシュ

// 動的データはキャッシュしない
export const dynamic = 'force-dynamic'
```

### データベースクエリの最適化

```sql
-- 頻繁に使うクエリのインデックスを確認
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS times_used,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- 未使用のインデックスを特定
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
AND idx_scan = 0;
```


## まとめ

本章で構築した運用基盤を整理する。

| 項目 | 設定 |
|------|------|
| デプロイ | Vercel（GitHubプッシュで自動デプロイ） |
| DBマイグレーション | GitHub Actions + supabase db push |
| カスタムドメイン | Vercel Domains + SSL自動発行 |
| CI/CD | GitHub Actions（lint, type-check, build, deploy-db） |
| 監視 | Vercel Analytics, Sentry, Supabase Dashboard |
| バックアップ | Supabase自動バックアップ + PITR |
| 環境分離 | Production / Staging（別Supabaseプロジェクト） |
| セキュリティ | チェックリストで網羅的に確認 |

運用のポイントを整理する。

1. **自動化を徹底する**: デプロイ、マイグレーション、テストを全てCI/CDで自動化
2. **環境を分離する**: 本番とStagingで完全に別の環境を使う
3. **監視を怠らない**: エラー追跡とパフォーマンス監視を初日から設定
4. **バックアップを確認する**: 定期的にリストアテストを実施

次章（最終章）では、SaaSの成長戦略について解説する。PLG（Product-Led Growth）、料金設計、スケーリングの考え方を紹介する。
