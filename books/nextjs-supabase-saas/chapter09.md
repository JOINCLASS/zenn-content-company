---
title: "管理画面の構築 -- ダッシュボード・分析機能"
free: false
---

# 管理画面の構築 -- ダッシュボード・分析機能

## はじめに

SaaSアプリケーションの運用には、データに基づいた意思決定が不可欠だ。本章では、TaskFlowの管理画面を構築する。テナント管理者向けのダッシュボード、プロジェクト分析、メンバー管理、そして活動ログの可視化を実装する。

実装する機能は以下の通りだ。

1. ダッシュボードの概要ビュー（KPI表示）
2. プロジェクト・タスクの分析
3. メンバー管理画面
4. 活動ログの表示
5. テナント設定画面


## ダッシュボードの概要ビュー

### KPIデータの取得

```typescript
// src/lib/analytics.ts
import { createClient } from '@/lib/supabase/server'

export async function getDashboardStats(tenantId: string) {
  const supabase = await createClient()

  // 並列でクエリを実行
  const [
    projectsResult,
    tasksResult,
    membersResult,
    recentActivityResult,
  ] = await Promise.all([
    // プロジェクト数
    supabase
      .from('projects')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', tenantId)
      .eq('status', 'active'),

    // タスク統計
    supabase
      .from('tasks')
      .select('status')
      .eq('tenant_id', tenantId),

    // メンバー数
    supabase
      .from('tenant_members')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', tenantId),

    // 直近の活動ログ
    supabase
      .from('activity_logs')
      .select(`
        *,
        profiles:user_id(full_name, avatar_url)
      `)
      .eq('tenant_id', tenantId)
      .order('created_at', { ascending: false })
      .limit(10),
  ])

  // タスク統計の集計
  const tasks = tasksResult.data || []
  const taskStats = {
    total: tasks.length,
    todo: tasks.filter((t) => t.status === 'todo').length,
    inProgress: tasks.filter((t) => t.status === 'in_progress').length,
    inReview: tasks.filter((t) => t.status === 'in_review').length,
    done: tasks.filter((t) => t.status === 'done').length,
  }

  const completionRate = taskStats.total > 0
    ? Math.round((taskStats.done / taskStats.total) * 100)
    : 0

  return {
    projectCount: projectsResult.count ?? 0,
    taskStats,
    completionRate,
    memberCount: membersResult.count ?? 0,
    recentActivity: recentActivityResult.data ?? [],
  }
}

export async function getWeeklyTaskTrend(tenantId: string) {
  const supabase = await createClient()

  // 過去4週間の週ごとのタスク完了数
  const fourWeeksAgo = new Date()
  fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28)

  const { data: completedTasks } = await supabase
    .from('tasks')
    .select('updated_at')
    .eq('tenant_id', tenantId)
    .eq('status', 'done')
    .gte('updated_at', fourWeeksAgo.toISOString())

  // 週ごとにグループ化
  const weeklyData: Record<string, number> = {}
  for (let i = 3; i >= 0; i--) {
    const weekStart = new Date()
    weekStart.setDate(weekStart.getDate() - i * 7)
    const weekKey = weekStart.toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' })
    weeklyData[weekKey] = 0
  }

  (completedTasks || []).forEach((task) => {
    const date = new Date(task.updated_at)
    const weeksSinceNow = Math.floor((Date.now() - date.getTime()) / (7 * 24 * 60 * 60 * 1000))
    if (weeksSinceNow < 4) {
      const weekStart = new Date()
      weekStart.setDate(weekStart.getDate() - weeksSinceNow * 7)
      const weekKey = weekStart.toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' })
      if (weeklyData[weekKey] !== undefined) {
        weeklyData[weekKey]++
      }
    }
  })

  return Object.entries(weeklyData).map(([week, count]) => ({
    week,
    count,
  }))
}
```

### ダッシュボードページ

```tsx
// src/app/dashboard/t/[slug]/page.tsx
import { getTenantBySlug } from '@/lib/tenant'
import { getDashboardStats, getWeeklyTaskTrend } from '@/lib/analytics'
import { notFound } from 'next/navigation'
import { StatsCards } from '@/components/dashboard/stats-cards'
import { TaskStatusChart } from '@/components/dashboard/task-status-chart'
import { WeeklyTrendChart } from '@/components/dashboard/weekly-trend-chart'
import { RecentActivity } from '@/components/dashboard/recent-activity'

export default async function TenantDashboardPage({
  params,
}: {
  params: { slug: string }
}) {
  const tenant = await getTenantBySlug(params.slug)
  if (!tenant) notFound()

  const [stats, weeklyTrend] = await Promise.all([
    getDashboardStats(tenant.id),
    getWeeklyTaskTrend(tenant.id),
  ])

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold">ダッシュボード</h1>

      {/* KPIカード */}
      <StatsCards stats={stats} />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* タスクステータス分布 */}
        <TaskStatusChart taskStats={stats.taskStats} />

        {/* 週次完了トレンド */}
        <WeeklyTrendChart data={weeklyTrend} />
      </div>

      {/* 最近の活動 */}
      <RecentActivity activities={stats.recentActivity} />
    </div>
  )
}
```

### KPIカードコンポーネント

```tsx
// src/components/dashboard/stats-cards.tsx

type Stats = {
  projectCount: number
  taskStats: {
    total: number
    todo: number
    inProgress: number
    done: number
  }
  completionRate: number
  memberCount: number
}

export function StatsCards({ stats }: { stats: Stats }) {
  const cards = [
    {
      label: 'プロジェクト数',
      value: stats.projectCount,
      description: 'アクティブなプロジェクト',
    },
    {
      label: '総タスク数',
      value: stats.taskStats.total,
      description: `進行中: ${stats.taskStats.inProgress}`,
    },
    {
      label: '完了率',
      value: `${stats.completionRate}%`,
      description: `${stats.taskStats.done}件完了`,
    },
    {
      label: 'メンバー数',
      value: stats.memberCount,
      description: 'アクティブメンバー',
    },
  ]

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      {cards.map((card) => (
        <div key={card.label} className="border rounded-lg p-5">
          <p className="text-sm text-muted-foreground">{card.label}</p>
          <p className="text-3xl font-bold mt-1">{card.value}</p>
          <p className="text-xs text-muted-foreground mt-1">{card.description}</p>
        </div>
      ))}
    </div>
  )
}
```

### タスクステータスチャート

SVGで軽量なドーナツチャートを実装する。外部ライブラリに依存しない方式だ。

```tsx
// src/components/dashboard/task-status-chart.tsx
'use client'

type TaskStats = {
  total: number
  todo: number
  inProgress: number
  inReview: number
  done: number
}

const STATUS_COLORS = {
  todo: '#94a3b8',
  inProgress: '#3b82f6',
  inReview: '#f59e0b',
  done: '#22c55e',
}

export function TaskStatusChart({ taskStats }: { taskStats: TaskStats }) {
  const segments = [
    { label: 'Todo', value: taskStats.todo, color: STATUS_COLORS.todo },
    { label: '進行中', value: taskStats.inProgress, color: STATUS_COLORS.inProgress },
    { label: 'レビュー', value: taskStats.inReview, color: STATUS_COLORS.inReview },
    { label: '完了', value: taskStats.done, color: STATUS_COLORS.done },
  ]

  const total = taskStats.total || 1 // ゼロ除算防止
  let cumulativePercent = 0

  return (
    <div className="border rounded-lg p-5">
      <h3 className="font-semibold mb-4">タスクステータス分布</h3>

      {taskStats.total === 0 ? (
        <p className="text-sm text-muted-foreground py-8 text-center">
          タスクがまだありません
        </p>
      ) : (
        <div className="flex items-center gap-8">
          {/* ドーナツチャート（SVG） */}
          <svg width="120" height="120" viewBox="0 0 120 120" className="flex-shrink-0">
            {segments.map((segment) => {
              if (segment.value === 0) return null

              const percent = (segment.value / total) * 100
              const dashArray = `${percent * 3.14} ${314 - percent * 3.14}`
              const rotation = cumulativePercent * 3.6 - 90
              cumulativePercent += percent

              return (
                <circle
                  key={segment.label}
                  cx="60"
                  cy="60"
                  r="50"
                  fill="none"
                  stroke={segment.color}
                  strokeWidth="20"
                  strokeDasharray={dashArray}
                  transform={`rotate(${rotation} 60 60)`}
                />
              )
            })}
            <text x="60" y="60" textAnchor="middle" dominantBaseline="middle" className="text-2xl font-bold" fill="currentColor">
              {taskStats.total}
            </text>
            <text x="60" y="75" textAnchor="middle" className="text-xs" fill="#94a3b8">
              タスク
            </text>
          </svg>

          {/* 凡例 */}
          <div className="space-y-2">
            {segments.map((segment) => (
              <div key={segment.label} className="flex items-center gap-2 text-sm">
                <div
                  className="w-3 h-3 rounded-full flex-shrink-0"
                  style={{ backgroundColor: segment.color }}
                />
                <span className="text-muted-foreground">{segment.label}</span>
                <span className="font-medium ml-auto">{segment.value}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
```

### 週次トレンドチャート

```tsx
// src/components/dashboard/weekly-trend-chart.tsx

type WeeklyData = {
  week: string
  count: number
}

export function WeeklyTrendChart({ data }: { data: WeeklyData[] }) {
  const maxCount = Math.max(...data.map((d) => d.count), 1)

  return (
    <div className="border rounded-lg p-5">
      <h3 className="font-semibold mb-4">週別タスク完了数</h3>

      <div className="flex items-end gap-4 h-40">
        {data.map((item) => {
          const heightPercent = (item.count / maxCount) * 100

          return (
            <div key={item.week} className="flex-1 flex flex-col items-center gap-2">
              <span className="text-xs font-medium">{item.count}</span>
              <div className="w-full bg-gray-100 rounded-t relative" style={{ height: '120px' }}>
                <div
                  className="absolute bottom-0 w-full bg-primary rounded-t transition-all"
                  style={{ height: `${heightPercent}%` }}
                />
              </div>
              <span className="text-xs text-muted-foreground">{item.week}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
```


## メンバー管理画面

```tsx
// src/app/dashboard/t/[slug]/settings/members/page.tsx
import { createClient } from '@/lib/supabase/server'
import { getTenantBySlug, getCurrentUserRole } from '@/lib/tenant'
import { notFound } from 'next/navigation'
import { MemberList } from '@/components/dashboard/member-list'
import { InviteMemberForm } from '@/components/dashboard/invite-member-form'

export default async function MembersPage({
  params,
}: {
  params: { slug: string }
}) {
  const tenant = await getTenantBySlug(params.slug)
  if (!tenant) notFound()

  const currentRole = await getCurrentUserRole(tenant.id)

  const supabase = await createClient()

  // メンバー一覧
  const { data: members } = await supabase
    .from('tenant_members')
    .select(`
      id,
      role,
      created_at,
      profiles:user_id(
        id,
        email,
        full_name,
        avatar_url
      )
    `)
    .eq('tenant_id', tenant.id)
    .order('created_at', { ascending: true })

  // 保留中の招待
  const { data: invitations } = await supabase
    .from('invitations')
    .select('*')
    .eq('tenant_id', tenant.id)
    .is('accepted_at', null)
    .order('created_at', { ascending: false })

  const isAdmin = currentRole === 'owner' || currentRole === 'admin'

  return (
    <div className="max-w-3xl">
      <h1 className="text-2xl font-bold mb-6">メンバー管理</h1>

      {isAdmin && (
        <div className="mb-8">
          <h2 className="text-lg font-semibold mb-3">メンバーを招待</h2>
          <InviteMemberForm
            tenantId={tenant.id}
            tenantSlug={params.slug}
          />
        </div>
      )}

      {/* 保留中の招待 */}
      {invitations && invitations.length > 0 && (
        <div className="mb-8">
          <h2 className="text-lg font-semibold mb-3">
            保留中の招待 ({invitations.length})
          </h2>
          <div className="space-y-2">
            {invitations.map((inv) => (
              <div key={inv.id} className="flex items-center justify-between border rounded-md p-3">
                <div>
                  <p className="text-sm">{inv.email}</p>
                  <p className="text-xs text-muted-foreground">
                    {inv.role} ・ 有効期限: {new Date(inv.expires_at).toLocaleDateString('ja-JP')}
                  </p>
                </div>
                <span className="text-xs bg-yellow-100 text-yellow-700 px-2 py-1 rounded">
                  保留中
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* メンバー一覧 */}
      <h2 className="text-lg font-semibold mb-3">
        メンバー ({members?.length ?? 0})
      </h2>
      <MemberList
        members={members ?? []}
        currentRole={currentRole}
        tenantId={tenant.id}
        tenantSlug={params.slug}
      />
    </div>
  )
}
```

### メンバー一覧コンポーネント

```tsx
// src/components/dashboard/member-list.tsx
'use client'

import { useState } from 'react'

type Member = {
  id: string
  role: string
  created_at: string
  profiles: {
    id: string
    email: string
    full_name: string | null
    avatar_url: string | null
  }
}

const ROLE_LABELS = {
  owner: { label: 'オーナー', color: 'bg-purple-100 text-purple-700' },
  admin: { label: '管理者', color: 'bg-blue-100 text-blue-700' },
  member: { label: 'メンバー', color: 'bg-gray-100 text-gray-700' },
}

export function MemberList({
  members,
  currentRole,
  tenantId,
  tenantSlug,
}: {
  members: Member[]
  currentRole: string | null
  tenantId: string
  tenantSlug: string
}) {
  const isAdmin = currentRole === 'owner' || currentRole === 'admin'

  return (
    <div className="space-y-2">
      {members.map((member) => {
        const roleInfo = ROLE_LABELS[member.role as keyof typeof ROLE_LABELS]
        const profile = member.profiles

        return (
          <div
            key={member.id}
            className="flex items-center gap-3 border rounded-md p-3"
          >
            {/* アバター */}
            <div className="w-10 h-10 rounded-full bg-gray-200 overflow-hidden flex-shrink-0">
              {profile.avatar_url ? (
                <img src={profile.avatar_url} alt="" className="w-full h-full object-cover" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-sm font-bold text-gray-400">
                  {profile.full_name?.[0] || profile.email[0].toUpperCase()}
                </div>
              )}
            </div>

            {/* 名前・メール */}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">
                {profile.full_name || profile.email}
              </p>
              <p className="text-xs text-muted-foreground truncate">
                {profile.email}
              </p>
            </div>

            {/* ロールバッジ */}
            <span className={`text-xs px-2 py-1 rounded font-medium ${roleInfo.color}`}>
              {roleInfo.label}
            </span>

            {/* アクション */}
            {isAdmin && member.role !== 'owner' && (
              <button className="text-xs text-muted-foreground hover:text-foreground">
                ...
              </button>
            )}
          </div>
        )
      })}
    </div>
  )
}
```


## 活動ログ

```tsx
// src/components/dashboard/recent-activity.tsx

type Activity = {
  id: string
  action: string
  target_type: string
  target_id: string
  metadata: Record<string, any>
  created_at: string
  profiles: {
    full_name: string | null
    avatar_url: string | null
  }
}

const ACTION_LABELS: Record<string, string> = {
  create_project: 'プロジェクトを作成',
  update_project: 'プロジェクトを更新',
  archive_project: 'プロジェクトをアーカイブ',
  create_task: 'タスクを作成',
  update_task: 'タスクを更新',
  complete_task: 'タスクを完了',
  add_comment: 'コメントを投稿',
  upload_file: 'ファイルをアップロード',
  invite_member: 'メンバーを招待',
}

function getTimeAgo(dateString: string): string {
  const diff = Date.now() - new Date(dateString).getTime()
  const minutes = Math.floor(diff / 60000)
  const hours = Math.floor(diff / 3600000)
  const days = Math.floor(diff / 86400000)

  if (minutes < 1) return 'たった今'
  if (minutes < 60) return `${minutes}分前`
  if (hours < 24) return `${hours}時間前`
  if (days < 7) return `${days}日前`
  return new Date(dateString).toLocaleDateString('ja-JP')
}

export function RecentActivity({ activities }: { activities: Activity[] }) {
  if (activities.length === 0) {
    return (
      <div className="border rounded-lg p-5">
        <h3 className="font-semibold mb-4">最近の活動</h3>
        <p className="text-sm text-muted-foreground text-center py-8">
          活動ログがありません
        </p>
      </div>
    )
  }

  return (
    <div className="border rounded-lg p-5">
      <h3 className="font-semibold mb-4">最近の活動</h3>
      <div className="space-y-4">
        {activities.map((activity) => (
          <div key={activity.id} className="flex items-start gap-3">
            <div className="w-8 h-8 rounded-full bg-gray-200 overflow-hidden flex-shrink-0 mt-0.5">
              {activity.profiles?.avatar_url ? (
                <img
                  src={activity.profiles.avatar_url}
                  alt=""
                  className="w-full h-full object-cover"
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-xs font-bold text-gray-400">
                  {activity.profiles?.full_name?.[0] || '?'}
                </div>
              )}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm">
                <span className="font-medium">
                  {activity.profiles?.full_name || 'Unknown'}
                </span>{' '}
                が{ACTION_LABELS[activity.action] || activity.action}
              </p>
              {activity.metadata?.project_name && (
                <p className="text-xs text-muted-foreground">
                  {activity.metadata.project_name}
                </p>
              )}
              {activity.metadata?.task_title && (
                <p className="text-xs text-muted-foreground">
                  {activity.metadata.task_title}
                </p>
              )}
            </div>
            <span className="text-xs text-muted-foreground flex-shrink-0">
              {getTimeAgo(activity.created_at)}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
```


## テナント設定画面

```tsx
// src/app/dashboard/t/[slug]/settings/page.tsx
import { getTenantBySlug, getCurrentUserRole } from '@/lib/tenant'
import { notFound, redirect } from 'next/navigation'
import { TenantSettingsForm } from '@/components/dashboard/tenant-settings-form'

export default async function SettingsPage({
  params,
}: {
  params: { slug: string }
}) {
  const tenant = await getTenantBySlug(params.slug)
  if (!tenant) notFound()

  const role = await getCurrentUserRole(tenant.id)
  if (role !== 'owner' && role !== 'admin') {
    redirect(`/dashboard/t/${params.slug}`)
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">組織設定</h1>
      <TenantSettingsForm tenant={tenant} />
    </div>
  )
}
```


## ナビゲーション

```tsx
// src/components/dashboard/nav.tsx
'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { signOut } from '@/app/(auth)/actions'

const navItems = (slug: string) => [
  { label: 'ダッシュボード', href: `/dashboard/t/${slug}` },
  { label: 'プロジェクト', href: `/dashboard/t/${slug}/projects` },
  { label: 'メンバー', href: `/dashboard/t/${slug}/settings/members` },
  { label: '設定', href: `/dashboard/t/${slug}/settings` },
  { label: '課金', href: `/dashboard/t/${slug}/settings/billing` },
]

export function DashboardNav({ tenantSlug }: { tenantSlug: string }) {
  const pathname = usePathname()

  return (
    <nav className="space-y-1">
      {navItems(tenantSlug).map((item) => {
        const isActive = pathname === item.href ||
          (item.href !== `/dashboard/t/${tenantSlug}` && pathname.startsWith(item.href))

        return (
          <Link
            key={item.href}
            href={item.href}
            className={`block px-3 py-2 rounded-md text-sm transition-colors ${
              isActive
                ? 'bg-gray-100 font-medium'
                : 'text-muted-foreground hover:bg-gray-50'
            }`}
          >
            {item.label}
          </Link>
        )
      })}

      <form action={signOut}>
        <button
          type="submit"
          className="w-full text-left px-3 py-2 rounded-md text-sm text-muted-foreground hover:bg-gray-50 transition-colors"
        >
          ログアウト
        </button>
      </form>
    </nav>
  )
}
```


## パフォーマンス最適化

### Server Componentでのデータフェッチ

ダッシュボードのデータは全てServer Componentでフェッチする。これにより、クライアントバンドルにはデータフェッチロジックが含まれず、初期表示が高速になる。

```tsx
// Server Componentで並列フェッチ
const [stats, trend] = await Promise.all([
  getDashboardStats(tenantId),
  getWeeklyTaskTrend(tenantId),
])
```

### Suspenseとローディングステート

```tsx
// src/app/dashboard/t/[slug]/loading.tsx
export default function DashboardLoading() {
  return (
    <div className="space-y-8">
      <div className="h-8 w-48 bg-gray-200 rounded animate-pulse" />
      <div className="grid grid-cols-4 gap-4">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="border rounded-lg p-5 space-y-2">
            <div className="h-4 w-20 bg-gray-200 rounded animate-pulse" />
            <div className="h-8 w-16 bg-gray-200 rounded animate-pulse" />
          </div>
        ))}
      </div>
    </div>
  )
}
```

### データベースインデックスの確認

ダッシュボードで使用するクエリに対して、インデックスが効いていることを確認する。

```sql
-- 分析用の追加インデックス
CREATE INDEX idx_tasks_tenant_status ON public.tasks(tenant_id, status);
CREATE INDEX idx_activity_logs_tenant_created ON public.activity_logs(tenant_id, created_at DESC);
```


## まとめ

本章で構築した管理画面を整理する。

| 画面 | 機能 |
|------|------|
| ダッシュボード概要 | KPIカード、タスクステータス分布、週次トレンド、最近の活動 |
| メンバー管理 | メンバー一覧、招待、ロール変更 |
| テナント設定 | 組織名、ロゴ、基本設定 |
| 課金管理 | プラン表示、アップグレード、Customer Portal |
| ナビゲーション | サイドバー、テナント切り替え |

ダッシュボード設計のポイントを整理する。

1. **Server Componentでデータフェッチ**: クライアントバンドルを小さく保つ
2. **Promise.allで並列フェッチ**: 複数クエリを同時に実行して初期表示を高速化
3. **SVGで軽量チャート**: Chart.js等のライブラリに依存せず、バンドルサイズを抑える
4. **ロールベースのアクセス制御**: 管理画面へのアクセスをadmin以上に制限

次章では、Row Level Security（RLS）の詳細設計に進む。セキュリティの最も重要な層だ。
