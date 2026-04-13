---
title: "Stripe連携 -- サブスクリプション決済の実装"
free: false
---

# Stripe連携 -- サブスクリプション決済の実装

## はじめに

SaaSビジネスの収益エンジンであるサブスクリプション決済を実装する。本章では、Stripeを使ってTaskFlowの3つの料金プラン（Free / Pro / Business）の課金システムを構築する。

実装する機能は以下の通りだ。

1. Stripeアカウントのセットアップとプロダクト・料金の作成
2. Checkout Sessionによる決済フロー
3. Customer Portalによる請求管理
4. Webhookによる決済イベントの処理
5. プランのアップグレード・ダウングレード
6. テナントの課金状態管理


## Stripeのセットアップ

### アカウント作成とAPIキー

1. [stripe.com](https://stripe.com) でアカウントを作成
2. ダッシュボードの「Developers」>「API keys」からキーを取得

| キー | 用途 | 環境変数名 |
|------|------|-----------|
| Publishable key | クライアントサイド | `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` |
| Secret key | サーバーサイド | `STRIPE_SECRET_KEY` |
| Webhook signing secret | Webhook検証 | `STRIPE_WEBHOOK_SECRET` |

```bash
# .env.local に追加
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### Stripeライブラリのインストール

```bash
pnpm add stripe @stripe/stripe-js
```

### Stripeクライアントの初期化

```typescript
// src/lib/stripe/server.ts
import Stripe from 'stripe'

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-12-18.acacia',
  typescript: true,
})
```

> このAPIバージョンは執筆時点の最新版である。Stripeは定期的にAPIバージョンを更新するため、実装時には[公式ドキュメント](https://docs.stripe.com/api/versioning)で最新バージョンを確認されたい。

```typescript
// src/lib/stripe/client.ts
import { loadStripe } from '@stripe/stripe-js'

let stripePromise: ReturnType<typeof loadStripe> | null = null

export function getStripe() {
  if (!stripePromise) {
    stripePromise = loadStripe(process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY!)
  }
  return stripePromise
}
```


## プロダクトと料金の作成

StripeダッシュボードまたはAPIでプロダクトと料金を作成する。本書ではスクリプトで作成する。

```typescript
// scripts/setup-stripe.ts
// 実行: npx tsx scripts/setup-stripe.ts

import Stripe from 'stripe'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

async function setup() {
  // プロダクトの作成
  const product = await stripe.products.create({
    name: 'TaskFlow',
    description: 'チーム向けプロジェクト管理SaaS',
  })

  console.log('Product:', product.id)

  // Pro プランの料金
  const proMonthly = await stripe.prices.create({
    product: product.id,
    unit_amount: 980, // ¥980
    currency: 'jpy',
    recurring: {
      interval: 'month',
    },
    metadata: {
      plan: 'pro',
    },
  })

  const proYearly = await stripe.prices.create({
    product: product.id,
    unit_amount: 9800, // ¥9,800（年額、2ヶ月分お得）
    currency: 'jpy',
    recurring: {
      interval: 'year',
    },
    metadata: {
      plan: 'pro',
    },
  })

  // Business プランの料金
  const businessMonthly = await stripe.prices.create({
    product: product.id,
    unit_amount: 2980, // ¥2,980
    currency: 'jpy',
    recurring: {
      interval: 'month',
    },
    metadata: {
      plan: 'business',
    },
  })

  const businessYearly = await stripe.prices.create({
    product: product.id,
    unit_amount: 29800, // ¥29,800（年額、約2ヶ月分お得）
    currency: 'jpy',
    recurring: {
      interval: 'year',
    },
    metadata: {
      plan: 'business',
    },
  })

  console.log('Prices:')
  console.log(`  Pro Monthly: ${proMonthly.id}`)
  console.log(`  Pro Yearly: ${proYearly.id}`)
  console.log(`  Business Monthly: ${businessMonthly.id}`)
  console.log(`  Business Yearly: ${businessYearly.id}`)

  console.log('\nAdd these to your .env.local:')
  console.log(`STRIPE_PRO_MONTHLY_PRICE_ID=${proMonthly.id}`)
  console.log(`STRIPE_PRO_YEARLY_PRICE_ID=${proYearly.id}`)
  console.log(`STRIPE_BUSINESS_MONTHLY_PRICE_ID=${businessMonthly.id}`)
  console.log(`STRIPE_BUSINESS_YEARLY_PRICE_ID=${businessYearly.id}`)
}

setup().catch(console.error)
```

### 料金設定の管理

```typescript
// src/lib/stripe/plans.ts

export type BillingInterval = 'month' | 'year'

export const STRIPE_PLANS = {
  pro: {
    name: 'Pro',
    description: '10プロジェクト、20メンバー、10GB Storage',
    prices: {
      month: {
        amount: 980,
        priceId: process.env.STRIPE_PRO_MONTHLY_PRICE_ID!,
      },
      year: {
        amount: 9800,
        priceId: process.env.STRIPE_PRO_YEARLY_PRICE_ID!,
      },
    },
  },
  business: {
    name: 'Business',
    description: '無制限プロジェクト、無制限メンバー、100GB Storage',
    prices: {
      month: {
        amount: 2980,
        priceId: process.env.STRIPE_BUSINESS_MONTHLY_PRICE_ID!,
      },
      year: {
        amount: 29800,
        priceId: process.env.STRIPE_BUSINESS_YEARLY_PRICE_ID!,
      },
    },
  },
} as const
```


## Checkout Session -- 決済フロー

### サブスクリプション作成のServer Action

```typescript
// src/app/dashboard/t/[slug]/settings/billing/actions.ts
'use server'

import { stripe } from '@/lib/stripe/server'
import { STRIPE_PLANS, type BillingInterval } from '@/lib/stripe/plans'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import type { Plan } from '@/lib/plans'

export async function createCheckoutSession(
  tenantId: string,
  tenantSlug: string,
  plan: 'pro' | 'business',
  interval: BillingInterval
) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return { error: '認証が必要です' }

  // テナント情報を取得
  const { data: tenant } = await supabase
    .from('tenants')
    .select('id, name, stripe_customer_id')
    .eq('id', tenantId)
    .single()

  if (!tenant) return { error: 'テナントが見つかりません' }

  // Stripeカスタマーの取得または作成
  let customerId = tenant.stripe_customer_id

  if (!customerId) {
    const customer = await stripe.customers.create({
      email: user.email!,
      name: tenant.name,
      metadata: {
        tenant_id: tenantId,
        supabase_user_id: user.id,
      },
    })
    customerId = customer.id

    // テナントにcustomer_idを保存
    await supabase
      .from('tenants')
      .update({ stripe_customer_id: customerId })
      .eq('id', tenantId)
  }

  // Checkout Sessionの作成
  const priceId = STRIPE_PLANS[plan].prices[interval].priceId
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'

  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [
      {
        price: priceId,
        quantity: 1,
      },
    ],
    success_url: `${baseUrl}/dashboard/t/${tenantSlug}/settings/billing?success=true`,
    cancel_url: `${baseUrl}/dashboard/t/${tenantSlug}/settings/billing?canceled=true`,
    subscription_data: {
      metadata: {
        tenant_id: tenantId,
        plan,
      },
    },
    allow_promotion_codes: true,
    billing_address_collection: 'required',
    tax_id_collection: {
      enabled: true,
    },
  })

  if (session.url) {
    redirect(session.url)
  }

  return { error: 'Checkout Sessionの作成に失敗しました' }
}

// Customer Portalへのリダイレクト
export async function createBillingPortalSession(
  tenantId: string,
  tenantSlug: string
) {
  const supabase = await createClient()

  const { data: tenant } = await supabase
    .from('tenants')
    .select('stripe_customer_id')
    .eq('id', tenantId)
    .single()

  if (!tenant?.stripe_customer_id) {
    return { error: '課金情報がありません' }
  }

  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'

  const session = await stripe.billingPortal.sessions.create({
    customer: tenant.stripe_customer_id,
    return_url: `${baseUrl}/dashboard/t/${tenantSlug}/settings/billing`,
  })

  redirect(session.url)
}
```


## Webhook -- 決済イベントの処理

Stripeからの通知を受け取るWebhookエンドポイントを実装する。これがサブスクリプション管理の心臓部だ。

```typescript
// src/app/api/webhooks/stripe/route.ts
import { headers } from 'next/headers'
import { NextResponse } from 'next/server'
import { stripe } from '@/lib/stripe/server'
import { createAdminClient } from '@/lib/supabase/admin'
import type Stripe from 'stripe'

export async function POST(request: Request) {
  const body = await request.text()
  const headersList = await headers()
  const signature = headersList.get('stripe-signature')

  if (!signature) {
    return NextResponse.json(
      { error: 'Missing stripe-signature header' },
      { status: 400 }
    )
  }

  let event: Stripe.Event

  try {
    event = stripe.webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    console.error(`Webhook signature verification failed: ${message}`)
    return NextResponse.json(
      { error: `Webhook Error: ${message}` },
      { status: 400 }
    )
  }

  const supabase = createAdminClient()

  try {
    switch (event.type) {
      // サブスクリプションが作成・更新された
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const subscription = event.data.object as Stripe.Subscription
        const tenantId = subscription.metadata.tenant_id
        const plan = subscription.metadata.plan as string

        if (!tenantId) {
          console.error('No tenant_id in subscription metadata')
          break
        }

        const status = subscription.status
        const isActive = status === 'active' || status === 'trialing'

        await supabase
          .from('tenants')
          .update({
            stripe_subscription_id: subscription.id,
            plan: isActive ? plan : 'free',
          })
          .eq('id', tenantId)

        console.log(`Subscription ${subscription.id} ${event.type}: plan=${plan}, status=${status}`)
        break
      }

      // サブスクリプションが削除された（キャンセル完了）
      case 'customer.subscription.deleted': {
        const subscription = event.data.object as Stripe.Subscription
        const tenantId = subscription.metadata.tenant_id

        if (!tenantId) break

        await supabase
          .from('tenants')
          .update({
            stripe_subscription_id: null,
            plan: 'free',
          })
          .eq('id', tenantId)

        console.log(`Subscription ${subscription.id} deleted: reverted to free`)
        break
      }

      // 請求書の支払い成功
      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice
        console.log(`Invoice ${invoice.id} paid: ${invoice.amount_paid}`)
        break
      }

      // 請求書の支払い失敗
      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const customerId = invoice.customer as string

        // テナントを取得して通知を送る等の処理
        const { data: tenant } = await supabase
          .from('tenants')
          .select('id, name')
          .eq('stripe_customer_id', customerId)
          .single()

        if (tenant) {
          console.error(`Payment failed for tenant ${tenant.name} (${tenant.id})`)
          // ここでメール通知やアプリ内通知を送信
        }
        break
      }

      default:
        console.log(`Unhandled event type: ${event.type}`)
    }
  } catch (error) {
    console.error(`Error processing webhook event ${event.type}:`, error)
    return NextResponse.json(
      { error: 'Webhook handler failed' },
      { status: 500 }
    )
  }

  return NextResponse.json({ received: true })
}
```

**重要:** WebhookのRoute Handlerでは `request.text()` で生のbodyを取得する。`request.json()` を使うとStripeの署名検証に失敗するため注意が必要だ。


## 料金プランページ

```tsx
// src/app/(marketing)/pricing/page.tsx
import { PricingTable } from '@/components/marketing/pricing-table'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: '料金プラン | TaskFlow',
  description: 'TaskFlowの料金プラン。無料で始められ、チームの成長に合わせてスケールアップ。',
}

export default function PricingPage() {
  return (
    <div className="container mx-auto px-4 py-24">
      <div className="text-center mb-16">
        <h1 className="text-4xl font-bold mb-4">
          シンプルで透明な料金体系
        </h1>
        <p className="text-xl text-muted-foreground">
          無料で始めて、チームの成長に合わせてアップグレード
        </p>
      </div>
      <PricingTable />
    </div>
  )
}
```

```tsx
// src/components/marketing/pricing-table.tsx
'use client'

import { useState } from 'react'

type BillingInterval = 'month' | 'year'

const plans = [
  {
    name: 'Free',
    slug: 'free',
    description: '個人やお試しに',
    prices: { month: 0, year: 0 },
    features: [
      '1プロジェクト',
      '3メンバーまで',
      '100MBストレージ',
      '基本的なタスク管理',
    ],
    cta: '無料で始める',
    popular: false,
  },
  {
    name: 'Pro',
    slug: 'pro',
    description: '成長中のチームに',
    prices: { month: 980, year: 9800 },
    features: [
      '10プロジェクト',
      '20メンバーまで',
      '10GBストレージ',
      'リアルタイム同期',
      '分析ダッシュボード',
      '優先サポート',
    ],
    cta: 'Proを始める',
    popular: true,
  },
  {
    name: 'Business',
    slug: 'business',
    description: '大規模チーム向け',
    prices: { month: 2980, year: 29800 },
    features: [
      '無制限プロジェクト',
      '無制限メンバー',
      '100GBストレージ',
      '全Pro機能',
      'カスタムフィールド',
      '専用サポート',
      'SLA保証',
    ],
    cta: 'Businessを始める',
    popular: false,
  },
]

export function PricingTable() {
  const [interval, setInterval] = useState<BillingInterval>('month')

  return (
    <div>
      {/* 月額/年額トグル */}
      <div className="flex justify-center mb-12">
        <div className="flex items-center gap-3 bg-gray-100 p-1 rounded-full">
          <button
            onClick={() => setInterval('month')}
            className={`px-4 py-2 rounded-full text-sm transition-colors ${
              interval === 'month'
                ? 'bg-white shadow-sm font-medium'
                : 'text-muted-foreground'
            }`}
          >
            月払い
          </button>
          <button
            onClick={() => setInterval('year')}
            className={`px-4 py-2 rounded-full text-sm transition-colors ${
              interval === 'year'
                ? 'bg-white shadow-sm font-medium'
                : 'text-muted-foreground'
            }`}
          >
            年払い
            <span className="ml-1 text-xs text-green-600 font-medium">2ヶ月分お得</span>
          </button>
        </div>
      </div>

      {/* プランカード */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-5xl mx-auto">
        {plans.map((plan) => (
          <div
            key={plan.slug}
            className={`relative rounded-2xl border p-8 ${
              plan.popular ? 'border-primary shadow-lg scale-105' : ''
            }`}
          >
            {plan.popular && (
              <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-primary text-primary-foreground text-xs font-medium px-3 py-1 rounded-full">
                人気
              </div>
            )}

            <h3 className="text-lg font-semibold">{plan.name}</h3>
            <p className="text-sm text-muted-foreground mt-1">{plan.description}</p>

            <div className="mt-6 mb-8">
              <span className="text-4xl font-bold">
                {plan.prices[interval] === 0 ? '無料' : `¥${plan.prices[interval].toLocaleString()}`}
              </span>
              {plan.prices[interval] > 0 && (
                <span className="text-muted-foreground text-sm">
                  /{interval === 'month' ? '月' : '年'}
                </span>
              )}
            </div>

            <a
              href={plan.slug === 'free' ? '/signup' : `/signup?plan=${plan.slug}&interval=${interval}`}
              className={`block text-center py-2.5 rounded-md text-sm font-medium transition-colors ${
                plan.popular
                  ? 'bg-primary text-primary-foreground hover:bg-primary/90'
                  : 'border hover:bg-gray-50'
              }`}
            >
              {plan.cta}
            </a>

            <ul className="mt-8 space-y-3">
              {plan.features.map((feature) => (
                <li key={feature} className="flex items-start gap-2 text-sm">
                  <svg
                    className="w-4 h-4 text-green-500 mt-0.5 flex-shrink-0"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                  </svg>
                  {feature}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </div>
  )
}
```


## 課金管理ページ

```tsx
// src/app/dashboard/t/[slug]/settings/billing/page.tsx
import { createClient } from '@/lib/supabase/server'
import { getTenantBySlug, getCurrentUserRole } from '@/lib/tenant'
import { stripe } from '@/lib/stripe/server'
import { notFound, redirect } from 'next/navigation'
import { BillingSettings } from '@/components/dashboard/billing-settings'

export default async function BillingPage({
  params,
  searchParams,
}: {
  params: { slug: string }
  searchParams: { success?: string; canceled?: string }
}) {
  const tenant = await getTenantBySlug(params.slug)
  if (!tenant) notFound()

  const role = await getCurrentUserRole(tenant.id)
  if (role !== 'owner') {
    redirect(`/dashboard/t/${params.slug}`)
  }

  // Stripeのサブスクリプション情報を取得
  let subscription = null
  if (tenant.stripe_subscription_id) {
    try {
      subscription = await stripe.subscriptions.retrieve(
        tenant.stripe_subscription_id,
        { expand: ['default_payment_method', 'latest_invoice'] }
      )
    } catch {
      // サブスクリプションが見つからない場合
    }
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">課金・プラン管理</h1>

      {searchParams.success && (
        <div className="bg-green-50 text-green-700 px-4 py-3 rounded-md mb-6">
          プランの変更が完了しました。
        </div>
      )}

      {searchParams.canceled && (
        <div className="bg-yellow-50 text-yellow-700 px-4 py-3 rounded-md mb-6">
          決済がキャンセルされました。
        </div>
      )}

      <BillingSettings
        tenant={tenant}
        subscription={subscription}
        tenantSlug={params.slug}
      />
    </div>
  )
}
```


## ローカルでのWebhookテスト

Stripe CLIを使ってローカル環境でWebhookをテストする。

```bash
# Stripe CLIのインストール
brew install stripe/stripe-cli/stripe

# Stripeにログイン
stripe login

# Webhookのフォワーディング
stripe listen --forward-to http://localhost:3000/api/webhooks/stripe

# 別ターミナルでテスト決済をトリガー
stripe trigger checkout.session.completed
stripe trigger customer.subscription.updated
stripe trigger invoice.payment_succeeded
```

`stripe listen` コマンドが表示するWebhook signing secretを `.env.local` の `STRIPE_WEBHOOK_SECRET` に設定する。


## 本番環境のWebhook設定

1. Stripeダッシュボードの「Developers」>「Webhooks」
2. 「Add endpoint」をクリック
3. エンドポイントURL: `https://taskflow.example.com/api/webhooks/stripe`
4. イベントを選択:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. Webhook signing secretを本番環境の環境変数に設定


## まとめ

本章で実装した決済機能を整理する。

| 機能 | 実装方法 |
|------|---------|
| プロダクト・料金の作成 | Stripe API スクリプト |
| Checkout Session（決済画面） | Server Action + Stripe Checkout |
| Customer Portal（請求管理） | Server Action + Billing Portal |
| Webhook（イベント処理） | Route Handler + 署名検証 |
| プラン状態管理 | Webhook -> Supabase DB更新 |
| 料金プランページ | マーケティングページ |
| 課金管理ページ | ダッシュボード内 |

決済実装のポイントを整理する。

1. **Stripe Checkoutを使う**: 自前で決済フォームを作らない。PCI DSS準拠の負担を回避
2. **Webhookで状態管理**: Checkout完了をクライアント側だけで判断しない。Webhookが信頼できる情報源
3. **テナントにStripe情報を保持**: `stripe_customer_id` と `stripe_subscription_id` でテナントとStripeを紐付け
4. **admin権限で保護**: 課金関連操作はテナントのowner/adminのみ

次章では、管理画面（ダッシュボード）と分析機能を構築する。
