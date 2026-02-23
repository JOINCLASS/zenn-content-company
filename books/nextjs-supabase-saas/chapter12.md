---
title: "SaaS成長戦略 -- PLG・料金設計・スケーリング"
free: false
---

# SaaS成長戦略 -- PLG・料金設計・スケーリング

## はじめに

ここまで10章にわたって、Next.js + Supabaseを使ったSaaSアプリケーションの技術的な構築方法を解説してきた。しかし、SaaSビジネスの成功は技術だけでは決まらない。

最終章では、技術の外側にある「SaaSをどう成長させるか」について解説する。Product-Led Growth（PLG）、料金設計、メトリクス管理、そしてスケーリングの考え方を紹介する。

エンジニアが技術だけでなくビジネス面も理解することで、プロダクトの方向性を適切に判断でき、結果としてより良いSaaSを作れる。


## Product-Led Growth（PLG）

### PLGとは

Product-Led Growth（PLG）は、プロダクト自体がユーザー獲得・活性化・収益化の主要なドライバーとなる成長戦略だ。営業チームがリードを追いかけるSales-Led Growth（SLG）とは対照的に、PLGでは**ユーザーがプロダクトを使って価値を実感し、自ら有料化する**。

代表的なPLG企業:

| 企業 | 無料プラン | 有料化トリガー |
|------|----------|-------------|
| Slack | メッセージ上限 | 履歴検索の制限で困る |
| Notion | ブロック上限 | チームでの利用が増える |
| Figma | プロジェクト数制限 | デザインチームが拡大 |
| GitHub | パブリックのみ無料 | プライベートリポジトリが必要 |

### PLGの実装パターン

TaskFlowでPLGを実現するための具体的な実装パターンを紹介する。

#### 1. フリーミアム: 無料で始めて有料へ

第8章で実装した料金プラン（Free / Pro / Business）がこれにあたる。

**成功するフリーミアムの設計原則:**

1. **無料プランで十分な価値を提供する**: ユーザーが「これは使える」と感じるレベル
2. **有料プランでしか得られない価値を明確にする**: 機能、容量、サポートのいずれか
3. **無料から有料への移行がスムーズ**: データの移行やダウンタイムなし

```typescript
// プラン制限に達した時のアップグレード誘導
function PlanLimitBanner({ resource, current, limit }: {
  resource: string
  current: number
  limit: number
}) {
  const percentage = (current / limit) * 100

  if (percentage < 80) return null

  return (
    <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-4">
      <p className="text-sm text-yellow-800">
        {resource}の使用量が上限の{Math.round(percentage)}%に達しています
        （{current}/{limit}）。
        <a href="/settings/billing" className="font-medium underline ml-1">
          プランをアップグレード
        </a>
        して制限を解除しましょう。
      </p>
    </div>
  )
}
```

#### 2. バイラルループ: ユーザーがユーザーを呼ぶ

```
ユーザーA
  │ プロジェクトを作成
  │ チームメンバーを招待
  v
ユーザーB (招待されてサインアップ)
  │ TaskFlowの価値を体験
  │ 自分の別チームにも導入
  v
ユーザーC, D, E ...
```

実装のポイント:
- **招待フロー**: メンバー招待を簡単にする（メールアドレス入力のみ）
- **共有機能**: プロジェクトやタスクの外部共有リンク
- **ブランディング**: 無料プランではTaskFlowのロゴを表示（「Powered by TaskFlow」）

#### 3. プロダクト内アップセル

```typescript
// 有料機能にアクセスした時の誘導
function ProFeatureGate({
  children,
  featureName,
  currentPlan,
}: {
  children: React.ReactNode
  featureName: string
  currentPlan: string
}) {
  if (currentPlan !== 'free') {
    return <>{children}</>
  }

  return (
    <div className="relative">
      <div className="opacity-50 pointer-events-none">{children}</div>
      <div className="absolute inset-0 flex items-center justify-center bg-white/80 rounded-lg">
        <div className="text-center p-6">
          <p className="font-semibold mb-2">{featureName}はProプランの機能です</p>
          <a
            href="/settings/billing"
            className="inline-block bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm"
          >
            Proにアップグレード
          </a>
        </div>
      </div>
    </div>
  )
}
```


## 料金設計

### 料金設計の3つの軸

SaaSの料金設計には3つの軸がある。

| 軸 | 説明 | TaskFlowの例 |
|----|------|-------------|
| 機能ベース | 利用できる機能で差別化 | Free: 基本, Pro: リアルタイム+分析 |
| 使用量ベース | 利用量に応じて課金 | プロジェクト数、メンバー数、ストレージ |
| ユーザー数ベース | 利用ユーザー数に応じて課金 | 1ユーザーあたり月額課金 |

TaskFlowでは、**機能ベース + 使用量ベースのハイブリッド**を採用している。基本は機能で差別化し、各プランに使用量の上限を設ける方式だ。

### 料金テスト

料金は一度決めたら終わりではない。定期的にA/Bテストを行い、最適な価格帯を探る。

```typescript
// 料金のA/Bテスト例
// ユーザーIDのハッシュでグループ分けし、異なる料金を表示
function getPriceVariant(userId: string): 'A' | 'B' {
  const hash = userId.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0)
  return hash % 2 === 0 ? 'A' : 'B'
}

const PRICE_VARIANTS = {
  A: { pro: 980, business: 2980 },  // 現行価格
  B: { pro: 1280, business: 3480 }, // テスト価格
}
```

### 年額プランのインセンティブ

年額プランへの誘導は、キャッシュフローの安定化とチャーン（解約）率の低下に寄与する。

```
月額: ¥980/月 = ¥11,760/年
年額: ¥9,800/年（約17%オフ、2ヶ月分お得）
```

「2ヶ月分お得」というフレーミングは、ユーザーにとってわかりやすい。


## SaaSのメトリクス

### 追跡すべきメトリクス

| メトリクス | 説明 | 計算方法 |
|-----------|------|---------|
| MRR | Monthly Recurring Revenue | 月次の定期収益合計 |
| ARR | Annual Recurring Revenue | MRR x 12 |
| Churn Rate | 月次解約率 | 解約ユーザー / 月初ユーザー |
| ARPU | Average Revenue Per User | MRR / 有料ユーザー数 |
| CAC | Customer Acquisition Cost | マーケ費用 / 新規顧客数 |
| LTV | Customer Lifetime Value | ARPU / Churn Rate |
| Conversion Rate | 無料→有料の転換率 | 有料ユーザー / 全ユーザー |
| DAU/MAU | アクティブユーザー比率 | 日次AU / 月次AU |

### メトリクスの実装

```sql
-- MRRの計算
SELECT
  SUM(CASE
    WHEN t.plan = 'pro' THEN 980
    WHEN t.plan = 'business' THEN 2980
    ELSE 0
  END) AS mrr
FROM public.tenants t
WHERE t.plan != 'free'
AND t.stripe_subscription_id IS NOT NULL;

-- 月次のユーザー増加
SELECT
  DATE_TRUNC('month', created_at) AS month,
  COUNT(*) AS new_users
FROM auth.users
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY month DESC
LIMIT 12;

-- テナントごとのアクティブユーザー（過去30日にログイン）
SELECT
  t.name AS tenant_name,
  t.plan,
  COUNT(DISTINCT al.user_id) AS active_users_30d
FROM public.tenants t
LEFT JOIN public.activity_logs al
  ON al.tenant_id = t.id
  AND al.created_at > now() - INTERVAL '30 days'
GROUP BY t.id, t.name, t.plan
ORDER BY active_users_30d DESC;
```

### ダッシュボードへの組み込み

```typescript
// src/lib/analytics.ts に追加

export async function getSaaSMetrics() {
  const supabase = await createClient()

  // 有料テナント数
  const { count: paidTenants } = await supabase
    .from('tenants')
    .select('*', { count: 'exact', head: true })
    .neq('plan', 'free')

  // 全テナント数
  const { count: totalTenants } = await supabase
    .from('tenants')
    .select('*', { count: 'exact', head: true })

  // MRRの計算
  const { data: tenantPlans } = await supabase
    .from('tenants')
    .select('plan')
    .neq('plan', 'free')

  const mrr = (tenantPlans || []).reduce((sum, t) => {
    if (t.plan === 'pro') return sum + 980
    if (t.plan === 'business') return sum + 2980
    return sum
  }, 0)

  // 転換率
  const conversionRate = totalTenants
    ? ((paidTenants || 0) / totalTenants * 100).toFixed(1)
    : '0'

  return {
    mrr,
    arr: mrr * 12,
    paidTenants: paidTenants ?? 0,
    totalTenants: totalTenants ?? 0,
    conversionRate: `${conversionRate}%`,
  }
}
```


## チャーン対策

### プロアクティブなチャーン防止

```typescript
// 解約しそうなテナントを検出
export async function getAtRiskTenants() {
  const supabase = await createClient()

  // 過去14日間にアクティビティがない有料テナント
  const { data: inactiveTenants } = await supabase
    .from('tenants')
    .select(`
      id,
      name,
      plan,
      activity_logs!inner(created_at)
    `)
    .neq('plan', 'free')
    .lt('activity_logs.created_at', new Date(Date.now() - 14 * 86400000).toISOString())

  return inactiveTenants || []
}
```

### 解約フローの最適化

解約を完全に防ぐことはできないが、解約フローの中でフィードバックを収集し、可能であれば引き留めることは有効だ。

```typescript
// 解約理由の収集
const CANCELLATION_REASONS = [
  { id: 'too_expensive', label: '料金が高い' },
  { id: 'missing_features', label: '必要な機能がない' },
  { id: 'switched_competitor', label: '他のサービスに乗り換えた' },
  { id: 'no_longer_needed', label: 'もう必要なくなった' },
  { id: 'difficult_to_use', label: '使い方が難しい' },
  { id: 'other', label: 'その他' },
]

// 料金が高い場合はダウングレードを提案
// 必要な機能がない場合はフィードバックを記録してロードマップに反映
```


## スケーリング

### Supabaseのスケーリング

Supabaseのスケーリングは、主にPostgreSQLのスケーリングだ。

| 段階 | ユーザー数 | 対策 |
|------|----------|------|
| 初期 | ~1,000 | Supabase Free/Pro |
| 成長期 | ~10,000 | クエリ最適化、インデックス追加 |
| 拡大期 | ~100,000 | Supabase Team、Read Replica |
| 大規模 | 100,000+ | カスタムインフラ、Supabase Enterprise |

### クエリの最適化

```sql
-- スロークエリの特定
SELECT
  query,
  calls,
  mean_exec_time,
  total_exec_time,
  rows
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- 100ms以上のクエリ
ORDER BY mean_exec_time DESC
LIMIT 20;
```

### Read Replicaの活用

読み取りが多いクエリ（ダッシュボード、分析等）をRead Replicaに向けることで、プライマリDBの負荷を軽減できる。

```typescript
// Read Replica用のクライアント
import { createClient } from '@supabase/supabase-js'

const readOnlyClient = createClient(
  process.env.SUPABASE_READ_REPLICA_URL!,
  process.env.SUPABASE_ANON_KEY!
)

// 分析クエリをRead Replicaに向ける
export async function getAnalytics(tenantId: string) {
  const { data } = await readOnlyClient
    .from('activity_logs')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false })
    .limit(1000)

  return data
}
```

### Vercelのスケーリング

Vercelはサーバーレスアーキテクチャのため、自動的にスケールする。ただし、以下の点に注意が必要だ。

| 考慮事項 | 対策 |
|---------|------|
| コールドスタート | Edge Runtimeの活用 |
| 実行時間制限 | 重い処理はバックグラウンドジョブへ |
| 同時接続数 | Supabaseの接続プーリングを使用 |
| バンドルサイズ | Server Componentsでクライアントバンドルを削減 |


## 次のステップ

本書で構築したTaskFlowをベースに、さらに発展させるためのアイデアを紹介する。

### 機能面

| 機能 | 実装方法 |
|------|---------|
| AI機能（タスクの自動分類、要約） | Supabase pgvector + OpenAI API |
| モバイルアプリ | React Native + Supabase |
| API提供 | Next.js Route Handlers + APIキー認証 |
| Webhook送信 | Edge Functions + イベントキュー |
| カスタムフィールド | JSONB型 + 動的フォーム |
| 多言語対応 | next-intl |
| ダークモード | Tailwind CSS dark mode |

### ビジネス面

| 施策 | 目的 |
|------|------|
| コンテンツマーケティング | SEO流入の獲得 |
| リファラルプログラム | ユーザーによるユーザー獲得 |
| パートナーシップ | 他ツールとの連携 |
| カスタマーサクセス | チャーン率の低下 |
| Product Hunt ローンチ | 初期ユーザーの獲得 |


## 本書のまとめ

全12章を通じて、Next.js + Supabaseを使ったSaaSアプリケーションの構築方法を解説した。最後に、各章で学んだことを振り返る。

| 章 | テーマ | 主な学び |
|----|-------|---------|
| 1 | 技術選定 | Next.js App Router + Supabase PostgreSQLの優位性 |
| 2 | 環境構築 | Next.js + Supabase CLI + shadcn/ui + Vercel |
| 3 | Supabaseの基本 | Auth, Database, Storage, Realtimeの基本操作 |
| 4 | 認証機能 | メール/パスワード, OAuth, Magic Link, プロフィール管理 |
| 5 | DB設計 | マルチテナント, テナント・メンバーシップ, RLSの基盤 |
| 6 | CRUD + Realtime | カンバンボード, Realtime同期, Presence, 楽観的更新 |
| 7 | ストレージ | ファイル管理, RLS付きバケット, 画像変換, 容量制限 |
| 8 | 決済 | Stripe Checkout, Webhook, サブスクリプション管理 |
| 9 | 管理画面 | ダッシュボード, KPI, 分析, メンバー管理 |
| 10 | RLS | ポリシー設計, パフォーマンス, テスト, 落とし穴 |
| 11 | デプロイ | Vercel + Supabase本番環境, CI/CD, 監視, バックアップ |
| 12 | 成長戦略 | PLG, 料金設計, メトリクス, スケーリング |

### SaaS開発の3つの教訓

本書を通じて最も伝えたかった教訓を3つにまとめる。

**1. 速く出して、速く学ぶ**

Next.js + Supabaseの最大の利点は、MVPを速く構築できることだ。完璧なプロダクトを目指して開発に時間をかけるのではなく、最小限の機能で市場に出し、ユーザーのフィードバックを元に改善するサイクルを回すことが重要だ。

**2. セキュリティはインフラ層で担保する**

RLSによるテナント間分離は、「アプリケーションコードを信頼しない」という設計思想に基づいている。コードにバグがあっても、データベースレベルでデータが守られる。この多層防御の考え方は、SaaSの信頼性を根本から支える。

**3. 技術とビジネスの両方を理解する**

エンジニアがPLGや料金設計を理解していれば、「どの機能を無料にし、どの機能を有料にするか」をプロダクトの設計段階で正しく判断できる。技術的に正しいだけでなく、ビジネスとして成立するプロダクトを作ることが、SaaS開発者の真の価値だ。

本書が、あなたのSaaSプロダクト開発の助けになれば幸いだ。Next.js + Supabaseで、世界中のユーザーに価値を届けるプロダクトを作ろう。
