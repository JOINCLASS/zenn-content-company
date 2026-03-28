---
title: "データベース設計 -- マルチテナント対応のスキーマ設計"
free: false
---

# データベース設計 -- マルチテナント対応のスキーマ設計

## はじめに

SaaSアプリケーションの設計において、最も重要かつ失敗が許されないのがデータベース設計だ。特にマルチテナント（複数の顧客企業がひとつのアプリケーションを共有する）の設計は、SaaSの根幹に関わる。

本章では、TaskFlowのデータベーススキーマを設計・実装する。テナント（組織）を中心とした設計、メンバーシップ管理、権限モデル、そしてRLSによるテナント間データ分離の基盤を構築する。

RLSの詳細な設計と実装は第10章で行うが、本章ではスキーマ設計の段階で必要なRLSの基礎を併せて実装する。


## マルチテナントアーキテクチャの選択

第1章で紹介した3つの方式から、本書では**行レベル分離（Shared Database, Shared Schema）**を採用する。

```
┌────────────────────────────────────────┐
│           PostgreSQL Database           │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │         public schema             │  │
│  │                                    │  │
│  │  tenants     tenant_members       │  │
│  │  ┌─────┐    ┌──────────────┐    │  │
│  │  │t_id │    │tenant_id     │    │  │
│  │  │name │    │user_id       │    │  │
│  │  └─────┘    │role          │    │  │
│  │              └──────────────┘    │  │
│  │                                    │  │
│  │  projects    tasks                │  │
│  │  ┌─────────┐ ┌──────────────┐   │  │
│  │  │tenant_id│ │tenant_id     │   │  │
│  │  │name     │ │project_id    │   │  │
│  │  └─────────┘ │title         │   │  │
│  │               └──────────────┘   │  │
│  └──────────────────────────────────┘  │
│                                        │
│  RLS: WHERE tenant_id = current_tenant │
└────────────────────────────────────────┘
```

この方式の特徴は以下の通りだ。

**メリット:**

- インフラコストが最も低い（1つのDBで全テナントを収容）
- マイグレーションが1回で全テナントに適用される
- テナント横断の分析クエリが可能

**デメリット:**

- RLSの設計を間違えるとデータ漏洩のリスクがある
- 特定テナントの大量データが全体に影響する可能性
- テナント単位のバックアップ・リストアが困難

SaaSのMVP段階では、行レベル分離が圧倒的に適している。テナント数が数千を超え、テナントごとのデータ量が大きくなった段階で、スキーマ分離やデータベース分離への移行を検討すれば良い。


## ER図 -- TaskFlowのデータモデル

TaskFlowの全テーブルのER図を示す。

```
auth.users
    │
    ├── 1:1 ── profiles
    │              │
    │              └── N:M ── tenants (via tenant_members)
    │                            │
    │                            ├── 1:N ── projects
    │                            │              │
    │                            │              ├── 1:N ── tasks
    │                            │              │           │
    │                            │              │           └── 1:N ── comments
    │                            │              │
    │                            │              └── 1:N ── project_files
    │                            │
    │                            ├── 1:N ── invitations
    │                            │
    │                            └── 1:1 ── subscriptions
    │
    └── 1:N ── activity_logs
```


## テナント（組織）テーブル

```bash
supabase migration new create_tenants
```

```sql
-- supabase/migrations/20260223000200_create_tenants.sql

-- ========================================
-- テナント（組織）テーブル
-- ========================================
CREATE TABLE public.tenants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  logo_url TEXT,
  plan TEXT DEFAULT 'free' CHECK (plan IN ('free', 'pro', 'business')),
  stripe_customer_id TEXT UNIQUE,
  stripe_subscription_id TEXT UNIQUE,
  settings JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- slugのインデックス（URLに使用）
CREATE UNIQUE INDEX idx_tenants_slug ON public.tenants(slug);

-- RLS有効化
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

-- updated_at トリガー
CREATE TRIGGER update_tenants_updated_at
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();


-- ========================================
-- テナントメンバーテーブル
-- ========================================
CREATE TYPE public.tenant_role AS ENUM ('owner', 'admin', 'member');

CREATE TABLE public.tenant_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.tenant_role NOT NULL DEFAULT 'member',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  -- 同じテナントに同じユーザーは1回のみ
  UNIQUE(tenant_id, user_id)
);

-- インデックス
CREATE INDEX idx_tenant_members_tenant_id ON public.tenant_members(tenant_id);
CREATE INDEX idx_tenant_members_user_id ON public.tenant_members(user_id);

-- RLS有効化
ALTER TABLE public.tenant_members ENABLE ROW LEVEL SECURITY;

-- updated_at トリガー
CREATE TRIGGER update_tenant_members_updated_at
  BEFORE UPDATE ON public.tenant_members
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();


-- ========================================
-- 招待テーブル
-- ========================================
CREATE TABLE public.invitations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role public.tenant_role NOT NULL DEFAULT 'member',
  invited_by UUID NOT NULL REFERENCES auth.users(id),
  token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days'),
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),

  -- 同じテナントに同じメールの未使用招待は1つのみ
  UNIQUE(tenant_id, email) -- accepted_atがNULLの場合の制約は部分インデックスで
);

CREATE UNIQUE INDEX idx_invitations_pending
  ON public.invitations(tenant_id, email)
  WHERE accepted_at IS NULL;

CREATE INDEX idx_invitations_token ON public.invitations(token);

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
```

### テナントの設計ポイント

**slug**: URLに使用する短縮名。`taskflow.app/org/my-company` のように使う。ユニーク制約を設ける。

**plan**: 料金プランを直接テナントに持たせる。Stripeとの連携情報（`stripe_customer_id`, `stripe_subscription_id`）も同じテーブルに保持する。

**settings**: JSONB型で柔軟な設定を格納。テナントごとのカスタマイズ（通知設定、デフォルト設定等）に使用する。

**tenant_role**: ENUM型で `owner`, `admin`, `member` の3段階。

| ロール | 権限 |
|--------|------|
| owner | 全権限。テナントの削除、プラン変更、メンバー管理 |
| admin | テナント設定の変更、メンバー管理、プロジェクト管理 |
| member | プロジェクト・タスクの操作のみ |


## プロジェクトテーブル

```bash
supabase migration new create_projects
```

```sql
-- supabase/migrations/20260223000300_create_projects.sql

-- ========================================
-- プロジェクトテーブル
-- ========================================
CREATE TYPE public.project_status AS ENUM ('active', 'archived', 'deleted');

CREATE TABLE public.projects (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  status public.project_status DEFAULT 'active',
  color TEXT DEFAULT '#6366f1', -- プロジェクトのテーマカラー
  sort_order INTEGER DEFAULT 0,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- インデックス
CREATE INDEX idx_projects_tenant_id ON public.projects(tenant_id);
CREATE INDEX idx_projects_status ON public.projects(status);

-- RLS有効化
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

-- updated_at トリガー
CREATE TRIGGER update_projects_updated_at
  BEFORE UPDATE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
```


## タスクテーブル

```bash
supabase migration new create_tasks
```

```sql
-- supabase/migrations/20260223000400_create_tasks.sql

-- ========================================
-- タスクテーブル
-- ========================================
CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'in_review', 'done');
CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');

CREATE TABLE public.tasks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  status public.task_status DEFAULT 'todo',
  priority public.task_priority DEFAULT 'medium',
  assignee_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  due_date DATE,
  sort_order INTEGER DEFAULT 0,
  parent_task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- インデックス
CREATE INDEX idx_tasks_tenant_id ON public.tasks(tenant_id);
CREATE INDEX idx_tasks_project_id ON public.tasks(project_id);
CREATE INDEX idx_tasks_assignee_id ON public.tasks(assignee_id);
CREATE INDEX idx_tasks_status ON public.tasks(status);
CREATE INDEX idx_tasks_parent_task_id ON public.tasks(parent_task_id);

-- RLS有効化
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- updated_at トリガー
CREATE TRIGGER update_tasks_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Realtime有効化
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;


-- ========================================
-- コメントテーブル
-- ========================================
CREATE TABLE public.comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- インデックス
CREATE INDEX idx_comments_task_id ON public.comments(task_id);
CREATE INDEX idx_comments_user_id ON public.comments(user_id);

-- RLS有効化
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- updated_at トリガー
CREATE TRIGGER update_comments_updated_at
  BEFORE UPDATE ON public.comments
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Realtime有効化
ALTER PUBLICATION supabase_realtime ADD TABLE public.comments;
```

### タスクの設計ポイント

**tenant_id**: 全てのテーブルに `tenant_id` を持たせる。`project_id` から間接的にテナントを辿ることも可能だが、RLSポリシーの効率のために直接持たせる。JOINを使ったRLSポリシーはパフォーマンスが低下するため、非正規化してでも `tenant_id` を各テーブルに含めることが重要だ。

**parent_task_id**: サブタスク（子タスク）を表現するための自己参照外部キー。

**sort_order**: カンバンボード等でのドラッグ&ドロップ並び替えに使用。


## 活動ログテーブル

```bash
supabase migration new create_activity_logs
```

```sql
-- supabase/migrations/20260223000500_create_activity_logs.sql

-- ========================================
-- 活動ログテーブル
-- ========================================
CREATE TABLE public.activity_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  action TEXT NOT NULL, -- 'create_project', 'update_task', 'add_comment' 等
  target_type TEXT NOT NULL, -- 'project', 'task', 'comment' 等
  target_id UUID NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- インデックス
CREATE INDEX idx_activity_logs_tenant_id ON public.activity_logs(tenant_id);
CREATE INDEX idx_activity_logs_user_id ON public.activity_logs(user_id);
CREATE INDEX idx_activity_logs_created_at ON public.activity_logs(created_at DESC);

-- RLS有効化
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
```


## 基本的なRLSポリシー

各テーブルに基本的なRLSポリシーを設定する。全ポリシーに共通するのは、**ユーザーが所属するテナントのデータのみアクセスできる**というルールだ。

```bash
supabase migration new create_rls_policies
```

```sql
-- supabase/migrations/20260223000600_create_rls_policies.sql

-- ========================================
-- ヘルパー関数: ユーザーが所属するテナントID一覧を返す
-- ========================================
CREATE OR REPLACE FUNCTION public.get_user_tenant_ids()
RETURNS SETOF UUID AS $$
  SELECT tenant_id
  FROM public.tenant_members
  WHERE user_id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ========================================
-- ヘルパー関数: ユーザーのテナント内でのロールを返す
-- ========================================
CREATE OR REPLACE FUNCTION public.get_user_role_in_tenant(p_tenant_id UUID)
RETURNS public.tenant_role AS $$
  SELECT role
  FROM public.tenant_members
  WHERE tenant_id = p_tenant_id AND user_id = auth.uid()
  LIMIT 1
$$ LANGUAGE sql SECURITY DEFINER STABLE;


-- ========================================
-- tenants テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Members can view their tenants"
  ON public.tenants FOR SELECT
  USING (id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Owners can update their tenant"
  ON public.tenants FOR UPDATE
  USING (
    public.get_user_role_in_tenant(id) IN ('owner', 'admin')
  );

-- テナント作成は誰でも可能（サインアップ後のオンボーディング）
CREATE POLICY "Authenticated users can create tenants"
  ON public.tenants FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);


-- ========================================
-- tenant_members テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Members can view tenant members"
  ON public.tenant_members FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

-- owner/adminのみメンバー追加可能
CREATE POLICY "Admins can add members"
  ON public.tenant_members FOR INSERT
  WITH CHECK (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
    OR
    -- 新規テナント作成時にownerとして自分を追加する場合
    (user_id = auth.uid() AND role = 'owner')
  );

CREATE POLICY "Admins can update member roles"
  ON public.tenant_members FOR UPDATE
  USING (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
  );

CREATE POLICY "Admins can remove members"
  ON public.tenant_members FOR DELETE
  USING (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
    OR user_id = auth.uid() -- 自分自身の退会
  );


-- ========================================
-- projects テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Members can view projects"
  ON public.projects FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can create projects"
  ON public.projects FOR INSERT
  WITH CHECK (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can update projects"
  ON public.projects FOR UPDATE
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can delete projects"
  ON public.projects FOR DELETE
  USING (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
  );


-- ========================================
-- tasks テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Members can view tasks"
  ON public.tasks FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can create tasks"
  ON public.tasks FOR INSERT
  WITH CHECK (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can update tasks"
  ON public.tasks FOR UPDATE
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can delete tasks"
  ON public.tasks FOR DELETE
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));


-- ========================================
-- comments テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Members can view comments"
  ON public.comments FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can create comments"
  ON public.comments FOR INSERT
  WITH CHECK (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Users can update own comments"
  ON public.comments FOR UPDATE
  USING (user_id = auth.uid());

CREATE POLICY "Users can delete own comments"
  ON public.comments FOR DELETE
  USING (user_id = auth.uid());


-- ========================================
-- activity_logs テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Members can view activity logs"
  ON public.activity_logs FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "System can insert activity logs"
  ON public.activity_logs FOR INSERT
  WITH CHECK (tenant_id IN (SELECT public.get_user_tenant_ids()));


-- ========================================
-- invitations テーブルのRLSポリシー
-- ========================================
CREATE POLICY "Admins can view invitations"
  ON public.invitations FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can create invitations"
  ON public.invitations FOR INSERT
  WITH CHECK (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
  );

CREATE POLICY "Admins can delete invitations"
  ON public.invitations FOR DELETE
  USING (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
  );
```


## テナント作成フロー

オンボーディング時のテナント作成ロジックを実装する。

```typescript
// src/app/onboarding/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'

export async function createTenant(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return { error: '認証が必要です' }
  }

  const name = formData.get('name') as string
  const slug = formData.get('slug') as string

  // バリデーション
  if (!name?.trim()) {
    return { error: '組織名を入力してください' }
  }

  if (!slug?.trim()) {
    return { error: 'URLスラッグを入力してください' }
  }

  // slugのフォーマットチェック
  if (!/^[a-z0-9-]+$/.test(slug)) {
    return { error: 'URLスラッグには小文字英数字とハイフンのみ使用できます' }
  }

  // slugの重複チェック
  const { data: existing } = await supabase
    .from('tenants')
    .select('id')
    .eq('slug', slug)
    .single()

  if (existing) {
    return { error: 'このURLスラッグは既に使用されています' }
  }

  // テナント作成
  const { data: tenant, error: tenantError } = await supabase
    .from('tenants')
    .insert({
      name: name.trim(),
      slug: slug.trim(),
    })
    .select()
    .single()

  if (tenantError) {
    return { error: tenantError.message }
  }

  // 作成者をownerとしてメンバーに追加
  const { error: memberError } = await supabase
    .from('tenant_members')
    .insert({
      tenant_id: tenant.id,
      user_id: user.id,
      role: 'owner',
    })

  if (memberError) {
    return { error: memberError.message }
  }

  // オンボーディング完了フラグを更新
  await supabase
    .from('profiles')
    .update({ onboarding_completed: true })
    .eq('id', user.id)

  revalidatePath('/', 'layout')
  redirect('/dashboard')
}
```


## テナント切り替え機能

ユーザーが複数のテナントに所属する場合、テナントを切り替える機能が必要だ。

### 現在のテナントの管理

現在選択中のテナントIDをCookieまたはURLパスで管理する。本書ではURLパスベースの方式を採用する。

```
/dashboard                    -> テナント選択画面
/dashboard/t/{tenant_slug}/   -> 特定テナントのダッシュボード
/dashboard/t/{tenant_slug}/projects -> プロジェクト一覧
```

```typescript
// src/lib/tenant.ts
import { createClient } from '@/lib/supabase/server'

export async function getUserTenants() {
  const supabase = await createClient()

  const { data: memberships } = await supabase
    .from('tenant_members')
    .select(`
      role,
      tenants (
        id,
        name,
        slug,
        logo_url,
        plan
      )
    `)

  if (!memberships) return []

  return memberships.map((m) => ({
    ...m.tenants,
    role: m.role,
  }))
}

export async function getTenantBySlug(slug: string) {
  const supabase = await createClient()

  const { data: tenant } = await supabase
    .from('tenants')
    .select('*')
    .eq('slug', slug)
    .single()

  return tenant
}

export async function getCurrentUserRole(tenantId: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return null

  const { data: membership } = await supabase
    .from('tenant_members')
    .select('role')
    .eq('tenant_id', tenantId)
    .eq('user_id', user.id)
    .single()

  return membership?.role ?? null
}
```


## プラン制限の実装

テナントの料金プランに応じたリソース制限を実装する。

```typescript
// src/lib/plans.ts

export type Plan = 'free' | 'pro' | 'business'

export const PLAN_LIMITS = {
  free: {
    maxProjects: 1,
    maxMembers: 3,
    maxStorageMb: 100,
    features: {
      realtime: false,
      analytics: false,
      customFields: false,
    },
  },
  pro: {
    maxProjects: 10,
    maxMembers: 20,
    maxStorageMb: 10240, // 10GB
    features: {
      realtime: true,
      analytics: true,
      customFields: false,
    },
  },
  business: {
    maxProjects: Infinity,
    maxMembers: Infinity,
    maxStorageMb: 102400, // 100GB
    features: {
      realtime: true,
      analytics: true,
      customFields: true,
    },
  },
} as const

export function getPlanLimits(plan: Plan) {
  return PLAN_LIMITS[plan]
}

export async function checkPlanLimit(
  tenantId: string,
  resource: 'projects' | 'members'
): Promise<{ allowed: boolean; current: number; limit: number }> {
  const { createClient } = await import('@/lib/supabase/server')
  const supabase = await createClient()

  // テナントのプランを取得
  const { data: tenant } = await supabase
    .from('tenants')
    .select('plan')
    .eq('id', tenantId)
    .single()

  if (!tenant) {
    return { allowed: false, current: 0, limit: 0 }
  }

  const limits = getPlanLimits(tenant.plan as Plan)

  let current = 0

  if (resource === 'projects') {
    const { count } = await supabase
      .from('projects')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', tenantId)
      .neq('status', 'deleted')
    current = count ?? 0
    return { allowed: current < limits.maxProjects, current, limit: limits.maxProjects }
  }

  if (resource === 'members') {
    const { count } = await supabase
      .from('tenant_members')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', tenantId)
    current = count ?? 0
    return { allowed: current < limits.maxMembers, current, limit: limits.maxMembers }
  }

  return { allowed: false, current: 0, limit: 0 }
}
```


## メンバー招待フロー

```typescript
// src/app/dashboard/t/[slug]/settings/members/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { checkPlanLimit } from '@/lib/plans'
import { revalidatePath } from 'next/cache'

export async function inviteMember(tenantId: string, formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return { error: '認証が必要です' }
  }

  const email = formData.get('email') as string
  const role = (formData.get('role') as string) || 'member'

  if (!email) {
    return { error: 'メールアドレスを入力してください' }
  }

  // プラン制限チェック
  const limitCheck = await checkPlanLimit(tenantId, 'members')
  if (!limitCheck.allowed) {
    return {
      error: `メンバー数の上限（${limitCheck.limit}名）に達しています。プランをアップグレードしてください。`,
    }
  }

  // 既にメンバーかチェック
  const adminClient = createAdminClient()
  const { data: existingUsers } = await adminClient.auth.admin.listUsers()
  const invitedUser = existingUsers?.users.find((u) => u.email === email)

  if (invitedUser) {
    const { data: existingMember } = await supabase
      .from('tenant_members')
      .select('id')
      .eq('tenant_id', tenantId)
      .eq('user_id', invitedUser.id)
      .single()

    if (existingMember) {
      return { error: 'このユーザーは既にメンバーです' }
    }
  }

  // 招待を作成
  const { error } = await supabase
    .from('invitations')
    .insert({
      tenant_id: tenantId,
      email,
      role: role as 'owner' | 'admin' | 'member',
      invited_by: user.id,
    })

  if (error) {
    if (error.code === '23505') {
      return { error: 'このメールアドレスには既に招待を送信しています' }
    }
    return { error: error.message }
  }

  // 招待メールの送信（実際にはメール送信処理を実装）
  // await sendInvitationEmail(email, tenantId, token)

  revalidatePath(`/dashboard/t/`)
  return { success: true }
}
```


## シードデータ

開発時に使うシードデータを作成する。

```sql
-- supabase/seed.sql

-- テスト用ユーザーの作成は supabase start 時に自動で行われるため、
-- ここではアプリケーションデータのシードのみ

-- テスト用テナント（ユーザー作成後に手動で実行）
-- INSERT INTO public.tenants (id, name, slug, plan)
-- VALUES
--   ('00000000-0000-0000-0000-000000000001', 'Demo Company', 'demo', 'pro');

-- テスト用プロジェクト
-- INSERT INTO public.projects (tenant_id, name, description, created_by)
-- VALUES
--   ('00000000-0000-0000-0000-000000000001', 'Website Redesign', 'コーポレートサイトのリニューアル', '{user_id}');
```


## マイグレーションの適用と型生成

```bash
# 全マイグレーションを適用
supabase db reset

# TypeScript型定義を再生成
pnpm db:types
```

型生成後、Supabaseクライアントに型を適用する。

```typescript
// src/lib/supabase/server.ts（更新）
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import type { Database } from '@/types/database'

export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient<Database>(
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
            // Server Componentからの場合は無視
          }
        },
      },
    }
  )
}
```


## パフォーマンスの考慮事項

### インデックス戦略

頻繁に使われるクエリに対してインデックスを設計する。

```sql
-- 複合インデックス: テナント内のアクティブプロジェクト一覧
CREATE INDEX idx_projects_tenant_status
  ON public.projects(tenant_id, status)
  WHERE status = 'active';

-- 複合インデックス: プロジェクト内のタスク一覧（ステータス別）
CREATE INDEX idx_tasks_project_status
  ON public.tasks(project_id, status);

-- 複合インデックス: テナント内の活動ログ（時系列）
CREATE INDEX idx_activity_logs_tenant_time
  ON public.activity_logs(tenant_id, created_at DESC);
```

### RLSポリシーのパフォーマンス

`get_user_tenant_ids()` 関数は全てのRLSポリシーで使用されるため、パフォーマンスが重要だ。`tenant_members` テーブルの `user_id` にインデックスが設定されていることを確認する（前述のマイグレーションで設定済み）。

```sql
-- RLSポリシーの実行計画を確認
EXPLAIN ANALYZE
SELECT * FROM public.projects
WHERE tenant_id IN (
  SELECT tenant_id FROM public.tenant_members
  WHERE user_id = 'some-user-id'
);
```


## まとめ

本章で設計・実装したデータベーススキーマを整理する。

| テーブル | 役割 | RLS |
|---------|------|-----|
| profiles | ユーザープロフィール | 自分のプロフィールのみ |
| tenants | テナント（組織） | メンバーのみ閲覧・更新 |
| tenant_members | テナントメンバーシップ | メンバーのみ閲覧、admin以上が管理 |
| invitations | 招待 | admin以上が管理 |
| projects | プロジェクト | テナントメンバーのみ |
| tasks | タスク | テナントメンバーのみ |
| comments | コメント | テナントメンバーが閲覧、自分のもののみ編集・削除 |
| activity_logs | 活動ログ | テナントメンバーのみ |

設計の原則は以下の通りだ。

1. **全テーブルに `tenant_id` を持たせる** -- RLSの効率のため
2. **RLSを全テーブルで有効にする** -- デフォルトでデータを保護
3. **ヘルパー関数でポリシーを簡潔にする** -- `get_user_tenant_ids()` で統一
4. **ENUM型でステータス・ロールを管理** -- 型安全かつパフォーマンス良好
5. **トリガーで `updated_at` を自動更新** -- アプリ側の手間を減らす

次章では、このスキーマを使ってCRUD操作とリアルタイム機能を実装する。
