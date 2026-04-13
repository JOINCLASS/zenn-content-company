---
title: "CRUD操作とリアルタイム機能 -- Supabase Realtimeの活用"
free: false
---

# CRUD操作とリアルタイム機能 -- Supabase Realtimeの活用

## はじめに

本章では、前章で設計したデータベーススキーマを使って、TaskFlowのコア機能であるプロジェクト管理とタスク管理のCRUD操作を実装する。さらに、Supabase Realtimeを活用して、タスクの変更がリアルタイムに他のユーザーに反映される機能を構築する。

本章で実装する機能は以下の通りだ。

1. プロジェクトのCRUD（一覧、作成、編集、削除）
2. タスクのCRUD（一覧、作成、編集、削除、ステータス変更）
3. カンバンボード風のタスク表示
4. Supabase Realtimeによるリアルタイム同期
5. コメント機能
6. 活動ログの自動記録


## プロジェクトのCRUD

### プロジェクト一覧ページ

```tsx
// src/app/dashboard/t/[slug]/projects/page.tsx
import { createClient } from '@/lib/supabase/server'
import { getTenantBySlug } from '@/lib/tenant'
import { notFound } from 'next/navigation'
import { ProjectGrid } from '@/components/dashboard/project-grid'
import { CreateProjectButton } from '@/components/dashboard/create-project-button'

export default async function ProjectsPage({
  params,
}: {
  params: { slug: string }
}) {
  const tenant = await getTenantBySlug(params.slug)
  if (!tenant) notFound()

  const supabase = await createClient()
  const { data: projects } = await supabase
    .from('projects')
    .select(`
      *,
      tasks:tasks(count)
    `)
    .eq('tenant_id', tenant.id)
    .neq('status', 'deleted')
    .order('sort_order', { ascending: true })

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">プロジェクト</h1>
        <CreateProjectButton tenantId={tenant.id} tenantSlug={params.slug} />
      </div>
      <ProjectGrid projects={projects ?? []} tenantSlug={params.slug} />
    </div>
  )
}
```

### プロジェクト作成のServer Action

```typescript
// src/app/dashboard/t/[slug]/projects/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { checkPlanLimit } from '@/lib/plans'
import { revalidatePath } from 'next/cache'

export async function createProject(tenantId: string, tenantSlug: string, formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return { error: '認証が必要です' }

  const name = formData.get('name') as string
  const description = formData.get('description') as string

  if (!name?.trim()) return { error: 'プロジェクト名を入力してください' }

  // プラン制限チェック
  const limit = await checkPlanLimit(tenantId, 'projects')
  if (!limit.allowed) {
    return {
      error: `プロジェクト数の上限（${limit.limit}件）に達しています。プランをアップグレードしてください。`,
    }
  }

  const { data: project, error } = await supabase
    .from('projects')
    .insert({
      tenant_id: tenantId,
      name: name.trim(),
      description: description?.trim() || null,
      created_by: user.id,
    })
    .select()
    .single()

  if (error) return { error: error.message }

  // 活動ログ
  await supabase.from('activity_logs').insert({
    tenant_id: tenantId,
    user_id: user.id,
    action: 'create_project',
    target_type: 'project',
    target_id: project.id,
    metadata: { project_name: project.name },
  })

  revalidatePath(`/dashboard/t/${tenantSlug}/projects`)
  return { success: true, project }
}

export async function updateProject(
  projectId: string,
  tenantSlug: string,
  formData: FormData
) {
  const supabase = await createClient()

  const name = formData.get('name') as string
  const description = formData.get('description') as string

  if (!name?.trim()) return { error: 'プロジェクト名を入力してください' }

  const { error } = await supabase
    .from('projects')
    .update({
      name: name.trim(),
      description: description?.trim() || null,
    })
    .eq('id', projectId)

  if (error) return { error: error.message }

  revalidatePath(`/dashboard/t/${tenantSlug}/projects`)
  return { success: true }
}

export async function archiveProject(projectId: string, tenantSlug: string) {
  const supabase = await createClient()

  const { error } = await supabase
    .from('projects')
    .update({ status: 'archived' })
    .eq('id', projectId)

  if (error) return { error: error.message }

  revalidatePath(`/dashboard/t/${tenantSlug}/projects`)
  return { success: true }
}
```

### プロジェクトグリッドコンポーネント

```tsx
// src/components/dashboard/project-grid.tsx
'use client'

import Link from 'next/link'

type Project = {
  id: string
  name: string
  description: string | null
  color: string
  status: string
  tasks: { count: number }[]
}

export function ProjectGrid({
  projects,
  tenantSlug,
}: {
  projects: Project[]
  tenantSlug: string
}) {
  if (projects.length === 0) {
    return (
      <div className="text-center py-12 border rounded-lg bg-gray-50">
        <p className="text-muted-foreground mb-4">
          プロジェクトがまだありません
        </p>
        <p className="text-sm text-muted-foreground">
          「新規プロジェクト」ボタンから最初のプロジェクトを作成しましょう
        </p>
      </div>
    )
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {projects.map((project) => {
        const taskCount = project.tasks?.[0]?.count ?? 0

        return (
          <Link
            key={project.id}
            href={`/dashboard/t/${tenantSlug}/projects/${project.id}`}
            className="block border rounded-lg p-5 hover:shadow-md transition-shadow"
          >
            <div className="flex items-start gap-3">
              <div
                className="w-3 h-3 rounded-full mt-1.5 flex-shrink-0"
                style={{ backgroundColor: project.color }}
              />
              <div className="flex-1 min-w-0">
                <h3 className="font-semibold truncate">{project.name}</h3>
                {project.description && (
                  <p className="text-sm text-muted-foreground mt-1 line-clamp-2">
                    {project.description}
                  </p>
                )}
                <p className="text-xs text-muted-foreground mt-3">
                  {taskCount} タスク
                </p>
              </div>
            </div>
          </Link>
        )
      })}
    </div>
  )
}
```


## タスクのCRUD

### タスク一覧（カンバンボード）

```tsx
// src/app/dashboard/t/[slug]/projects/[projectId]/page.tsx
import { createClient } from '@/lib/supabase/server'
import { getTenantBySlug } from '@/lib/tenant'
import { notFound } from 'next/navigation'
import { KanbanBoard } from '@/components/dashboard/kanban-board'

export default async function ProjectPage({
  params,
}: {
  params: { slug: string; projectId: string }
}) {
  const tenant = await getTenantBySlug(params.slug)
  if (!tenant) notFound()

  const supabase = await createClient()

  const { data: project } = await supabase
    .from('projects')
    .select('*')
    .eq('id', params.projectId)
    .eq('tenant_id', tenant.id)
    .single()

  if (!project) notFound()

  const { data: tasks } = await supabase
    .from('tasks')
    .select(`
      *,
      assignee:profiles!tasks_assignee_id_fkey(
        id, full_name, avatar_url
      ),
      comments:comments(count)
    `)
    .eq('project_id', project.id)
    .is('parent_task_id', null)
    .order('sort_order', { ascending: true })

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold">{project.name}</h1>
        {project.description && (
          <p className="text-muted-foreground mt-1">{project.description}</p>
        )}
      </div>
      <KanbanBoard
        tasks={tasks ?? []}
        projectId={project.id}
        tenantId={tenant.id}
        tenantSlug={params.slug}
      />
    </div>
  )
}
```

### タスクのServer Actions

```typescript
// src/app/dashboard/t/[slug]/projects/[projectId]/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function createTask(
  tenantId: string,
  projectId: string,
  tenantSlug: string,
  formData: FormData
) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return { error: '認証が必要です' }

  const title = formData.get('title') as string
  const status = (formData.get('status') as string) || 'todo'
  const priority = (formData.get('priority') as string) || 'medium'

  if (!title?.trim()) return { error: 'タスク名を入力してください' }

  const { data: task, error } = await supabase
    .from('tasks')
    .insert({
      tenant_id: tenantId,
      project_id: projectId,
      title: title.trim(),
      status: status as 'todo' | 'in_progress' | 'in_review' | 'done',
      priority: priority as 'low' | 'medium' | 'high' | 'urgent',
      created_by: user.id,
    })
    .select()
    .single()

  if (error) return { error: error.message }

  // 活動ログ
  await supabase.from('activity_logs').insert({
    tenant_id: tenantId,
    user_id: user.id,
    action: 'create_task',
    target_type: 'task',
    target_id: task.id,
    metadata: { task_title: task.title, project_id: projectId },
  })

  revalidatePath(`/dashboard/t/${tenantSlug}/projects/${projectId}`)
  return { success: true, task }
}

export async function updateTaskStatus(
  taskId: string,
  status: string,
  tenantSlug: string,
  projectId: string
) {
  const supabase = await createClient()

  const { error } = await supabase
    .from('tasks')
    .update({ status: status as 'todo' | 'in_progress' | 'in_review' | 'done' })
    .eq('id', taskId)

  if (error) return { error: error.message }

  revalidatePath(`/dashboard/t/${tenantSlug}/projects/${projectId}`)
  return { success: true }
}

export async function updateTask(
  taskId: string,
  tenantSlug: string,
  projectId: string,
  data: {
    title?: string
    description?: string
    priority?: string
    assignee_id?: string | null
    due_date?: string | null
  }
) {
  const supabase = await createClient()

  const { error } = await supabase
    .from('tasks')
    .update(data)
    .eq('id', taskId)

  if (error) return { error: error.message }

  revalidatePath(`/dashboard/t/${tenantSlug}/projects/${projectId}`)
  return { success: true }
}

export async function deleteTask(
  taskId: string,
  tenantSlug: string,
  projectId: string
) {
  const supabase = await createClient()

  const { error } = await supabase
    .from('tasks')
    .delete()
    .eq('id', taskId)

  if (error) return { error: error.message }

  revalidatePath(`/dashboard/t/${tenantSlug}/projects/${projectId}`)
  return { success: true }
}
```

### カンバンボードコンポーネント

```tsx
// src/components/dashboard/kanban-board.tsx
'use client'

import { useState } from 'react'
import { createTask, updateTaskStatus } from '@/app/dashboard/t/[slug]/projects/[projectId]/actions'

type Task = {
  id: string
  title: string
  description: string | null
  status: string
  priority: string
  due_date: string | null
  assignee: {
    id: string
    full_name: string | null
    avatar_url: string | null
  } | null
  comments: { count: number }[]
}

const COLUMNS = [
  { id: 'todo', label: 'Todo', color: 'bg-gray-100' },
  { id: 'in_progress', label: '進行中', color: 'bg-blue-50' },
  { id: 'in_review', label: 'レビュー', color: 'bg-yellow-50' },
  { id: 'done', label: '完了', color: 'bg-green-50' },
]

const PRIORITY_LABELS = {
  low: { label: '低', color: 'text-gray-500' },
  medium: { label: '中', color: 'text-blue-500' },
  high: { label: '高', color: 'text-orange-500' },
  urgent: { label: '緊急', color: 'text-red-500' },
}

export function KanbanBoard({
  tasks,
  projectId,
  tenantId,
  tenantSlug,
}: {
  tasks: Task[]
  projectId: string
  tenantId: string
  tenantSlug: string
}) {
  const [addingToColumn, setAddingToColumn] = useState<string | null>(null)

  function getTasksByStatus(status: string) {
    return tasks.filter((t) => t.status === status)
  }

  async function handleAddTask(formData: FormData) {
    formData.set('status', addingToColumn || 'todo')
    await createTask(tenantId, projectId, tenantSlug, formData)
    setAddingToColumn(null)
  }

  async function handleDragEnd(taskId: string, newStatus: string) {
    await updateTaskStatus(taskId, newStatus, tenantSlug, projectId)
  }

  return (
    <div className="flex gap-4 overflow-x-auto pb-4">
      {COLUMNS.map((column) => {
        const columnTasks = getTasksByStatus(column.id)

        return (
          <div
            key={column.id}
            className={`flex-shrink-0 w-72 rounded-lg p-3 ${column.color}`}
            onDragOver={(e) => e.preventDefault()}
            onDrop={(e) => {
              const taskId = e.dataTransfer.getData('taskId')
              if (taskId) handleDragEnd(taskId, column.id)
            }}
          >
            {/* カラムヘッダー */}
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-medium text-sm">
                {column.label}
                <span className="ml-2 text-muted-foreground">
                  {columnTasks.length}
                </span>
              </h3>
              <button
                onClick={() => setAddingToColumn(column.id)}
                className="text-muted-foreground hover:text-foreground text-lg leading-none"
              >
                +
              </button>
            </div>

            {/* タスク一覧 */}
            <div className="space-y-2">
              {columnTasks.map((task) => (
                <TaskCard key={task.id} task={task} />
              ))}

              {/* タスク追加フォーム */}
              {addingToColumn === column.id && (
                <form action={handleAddTask} className="bg-white rounded-md border p-3">
                  <input
                    name="title"
                    placeholder="タスク名を入力..."
                    autoFocus
                    required
                    className="w-full text-sm border-0 focus:ring-0 p-0 mb-2"
                  />
                  <div className="flex gap-2">
                    <button
                      type="submit"
                      className="text-xs bg-primary text-primary-foreground px-3 py-1 rounded"
                    >
                      追加
                    </button>
                    <button
                      type="button"
                      onClick={() => setAddingToColumn(null)}
                      className="text-xs text-muted-foreground"
                    >
                      キャンセル
                    </button>
                  </div>
                </form>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}

function TaskCard({ task }: { task: Task }) {
  const priority = PRIORITY_LABELS[task.priority as keyof typeof PRIORITY_LABELS]
  const commentCount = task.comments?.[0]?.count ?? 0

  return (
    <div
      draggable
      onDragStart={(e) => e.dataTransfer.setData('taskId', task.id)}
      className="bg-white rounded-md border p-3 cursor-grab active:cursor-grabbing hover:shadow-sm transition-shadow"
    >
      <p className="text-sm font-medium">{task.title}</p>

      <div className="flex items-center gap-2 mt-2 text-xs">
        {priority && (
          <span className={priority.color}>{priority.label}</span>
        )}
        {task.due_date && (
          <span className="text-muted-foreground">
            {new Date(task.due_date).toLocaleDateString('ja-JP')}
          </span>
        )}
        {commentCount > 0 && (
          <span className="text-muted-foreground">
            {commentCount} コメント
          </span>
        )}
      </div>

      {task.assignee && (
        <div className="flex items-center gap-1.5 mt-2">
          <div className="w-5 h-5 rounded-full bg-gray-200 overflow-hidden">
            {task.assignee.avatar_url ? (
              <img src={task.assignee.avatar_url} alt="" className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-[10px] font-bold text-gray-400">
                {task.assignee.full_name?.[0] || '?'}
              </div>
            )}
          </div>
          <span className="text-xs text-muted-foreground">
            {task.assignee.full_name || 'Unknown'}
          </span>
        </div>
      )}
    </div>
  )
}
```


> 本書のドラッグ＆ドロップはHTML5 Drag and Drop APIを使った最小実装である。本番環境ではdnd-kit等のライブラリを使うことで、アクセシビリティ対応やモバイルタッチ操作のサポートが得られるため推奨する。


## Supabase Realtimeの実装

ここからが本章のメインテーマだ。Supabase Realtimeを使って、タスクの変更をリアルタイムに反映する。

### Realtimeの仕組み

```
User A (ブラウザ)                    User B (ブラウザ)
    │                                     │
    │  タスクを更新                         │
    │──────> Supabase Database            │
    │        ┌──────────────┐             │
    │        │  UPDATE tasks │             │
    │        │  SET status   │             │
    │        └──────┬───────┘             │
    │               │                     │
    │               v                     │
    │        ┌──────────────┐             │
    │        │  Realtime     │──────────> │  変更を受信
    │        │  (WebSocket)  │             │  UIを更新
    │        └──────────────┘             │
```

### Realtimeフック

```typescript
// src/hooks/use-realtime-tasks.ts
'use client'

import { useEffect, useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { RealtimePostgresChangesPayload } from '@supabase/supabase-js'

type Task = {
  id: string
  title: string
  description: string | null
  status: string
  priority: string
  assignee_id: string | null
  due_date: string | null
  project_id: string
  tenant_id: string
  sort_order: number
  created_at: string
  updated_at: string
}

export function useRealtimeTasks(projectId: string, initialTasks: Task[]) {
  const [tasks, setTasks] = useState<Task[]>(initialTasks)

  // initialTasksが変わったら更新
  useEffect(() => {
    setTasks(initialTasks)
  }, [initialTasks])

  const handleChange = useCallback(
    (payload: RealtimePostgresChangesPayload<Task>) => {
      switch (payload.eventType) {
        case 'INSERT': {
          const newTask = payload.new as Task
          if (newTask.project_id === projectId) {
            setTasks((prev) => {
              // 重複チェック
              if (prev.some((t) => t.id === newTask.id)) return prev
              return [...prev, newTask]
            })
          }
          break
        }

        case 'UPDATE': {
          const updatedTask = payload.new as Task
          setTasks((prev) =>
            prev.map((t) => (t.id === updatedTask.id ? updatedTask : t))
          )
          break
        }

        case 'DELETE': {
          const deletedTask = payload.old as { id: string }
          setTasks((prev) => prev.filter((t) => t.id !== deletedTask.id))
          break
        }
      }
    },
    [projectId]
  )

  useEffect(() => {
    const supabase = createClient()

    const channel = supabase
      .channel(`tasks:${projectId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'tasks',
          filter: `project_id=eq.${projectId}`,
        },
        handleChange
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [projectId, handleChange])

  return tasks
}
```

### Realtimeカンバンボード

先ほどのカンバンボードをリアルタイム対応にする。

```tsx
// src/components/dashboard/realtime-kanban-board.tsx
'use client'

import { useRealtimeTasks } from '@/hooks/use-realtime-tasks'
import { KanbanColumn } from './kanban-column'

type Task = {
  id: string
  title: string
  description: string | null
  status: string
  priority: string
  assignee_id: string | null
  due_date: string | null
  project_id: string
  tenant_id: string
  sort_order: number
  created_at: string
  updated_at: string
}

const COLUMNS = [
  { id: 'todo', label: 'Todo', color: 'bg-gray-100' },
  { id: 'in_progress', label: '進行中', color: 'bg-blue-50' },
  { id: 'in_review', label: 'レビュー', color: 'bg-yellow-50' },
  { id: 'done', label: '完了', color: 'bg-green-50' },
]

export function RealtimeKanbanBoard({
  initialTasks,
  projectId,
  tenantId,
  tenantSlug,
}: {
  initialTasks: Task[]
  projectId: string
  tenantId: string
  tenantSlug: string
}) {
  // Realtimeで常に最新のタスクを保持
  const tasks = useRealtimeTasks(projectId, initialTasks)

  return (
    <div className="flex gap-4 overflow-x-auto pb-4">
      {COLUMNS.map((column) => (
        <KanbanColumn
          key={column.id}
          column={column}
          tasks={tasks.filter((t) => t.status === column.id)}
          projectId={projectId}
          tenantId={tenantId}
          tenantSlug={tenantSlug}
        />
      ))}
    </div>
  )
}
```

### オンラインプレゼンス

Supabase RealtimeのPresence機能を使って、「誰がこのプロジェクトを見ているか」をリアルタイムに表示する。

```typescript
// src/hooks/use-presence.ts
'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

type PresenceState = {
  id: string
  name: string
  avatarUrl: string | null
  onlineAt: string
}

export function usePresence(channelName: string, currentUser: {
  id: string
  name: string
  avatarUrl: string | null
}) {
  const [onlineUsers, setOnlineUsers] = useState<PresenceState[]>([])

  useEffect(() => {
    const supabase = createClient()

    const channel = supabase.channel(channelName, {
      config: {
        presence: {
          key: currentUser.id,
        },
      },
    })

    channel
      .on('presence', { event: 'sync' }, () => {
        const state = channel.presenceState<PresenceState>()
        const users = Object.values(state)
          .flat()
          .filter((u) => u.id !== currentUser.id)
        setOnlineUsers(users)
      })
      .subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          await channel.track({
            id: currentUser.id,
            name: currentUser.name,
            avatarUrl: currentUser.avatarUrl,
            onlineAt: new Date().toISOString(),
          })
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  }, [channelName, currentUser])

  return onlineUsers
}
```

```tsx
// src/components/dashboard/online-users.tsx
'use client'

import { usePresence } from '@/hooks/use-presence'

export function OnlineUsers({
  channelName,
  currentUser,
}: {
  channelName: string
  currentUser: {
    id: string
    name: string
    avatarUrl: string | null
  }
}) {
  const onlineUsers = usePresence(channelName, currentUser)

  if (onlineUsers.length === 0) return null

  return (
    <div className="flex items-center gap-1">
      <span className="text-xs text-muted-foreground mr-1">オンライン:</span>
      <div className="flex -space-x-2">
        {onlineUsers.slice(0, 5).map((user) => (
          <div
            key={user.id}
            className="w-6 h-6 rounded-full bg-gray-200 border-2 border-white overflow-hidden"
            title={user.name}
          >
            {user.avatarUrl ? (
              <img src={user.avatarUrl} alt={user.name} className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-[10px] font-bold text-gray-400">
                {user.name[0]}
              </div>
            )}
          </div>
        ))}
        {onlineUsers.length > 5 && (
          <div className="w-6 h-6 rounded-full bg-gray-300 border-2 border-white flex items-center justify-center text-[10px] font-bold">
            +{onlineUsers.length - 5}
          </div>
        )}
      </div>
    </div>
  )
}
```


## コメント機能

```typescript
// src/app/dashboard/t/[slug]/projects/[projectId]/tasks/[taskId]/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function addComment(
  tenantId: string,
  taskId: string,
  formData: FormData
) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return { error: '認証が必要です' }

  const content = formData.get('content') as string
  if (!content?.trim()) return { error: 'コメントを入力してください' }

  const { error } = await supabase
    .from('comments')
    .insert({
      tenant_id: tenantId,
      task_id: taskId,
      user_id: user.id,
      content: content.trim(),
    })

  if (error) return { error: error.message }

  return { success: true }
}
```

### リアルタイムコメントフック

```typescript
// src/hooks/use-realtime-comments.ts
'use client'

import { useEffect, useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'

type Comment = {
  id: string
  content: string
  user_id: string
  created_at: string
  profiles?: {
    full_name: string | null
    avatar_url: string | null
  }
}

export function useRealtimeComments(taskId: string, initialComments: Comment[]) {
  const [comments, setComments] = useState<Comment[]>(initialComments)

  useEffect(() => {
    setComments(initialComments)
  }, [initialComments])

  const handleChange = useCallback((payload: any) => {
    if (payload.eventType === 'INSERT') {
      const newComment = payload.new
      if (newComment.task_id === taskId) {
        setComments((prev) => {
          if (prev.some((c) => c.id === newComment.id)) return prev
          return [...prev, newComment]
        })
      }
    } else if (payload.eventType === 'DELETE') {
      setComments((prev) => prev.filter((c) => c.id !== payload.old.id))
    }
  }, [taskId])

  useEffect(() => {
    const supabase = createClient()

    const channel = supabase
      .channel(`comments:${taskId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'comments',
          filter: `task_id=eq.${taskId}`,
        },
        handleChange
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [taskId, handleChange])

  return comments
}
```


## 楽観的更新（Optimistic Updates）

ユーザー体験を向上させるため、サーバーレスポンスを待たずにUIを更新する楽観的更新パターンを実装する。

```tsx
// src/components/dashboard/optimistic-task-status.tsx
'use client'

import { useOptimistic, useTransition } from 'react'
import { updateTaskStatus } from '@/app/dashboard/t/[slug]/projects/[projectId]/actions'

export function TaskStatusButton({
  taskId,
  currentStatus,
  targetStatus,
  label,
  tenantSlug,
  projectId,
}: {
  taskId: string
  currentStatus: string
  targetStatus: string
  label: string
  tenantSlug: string
  projectId: string
}) {
  const [isPending, startTransition] = useTransition()
  const [optimisticStatus, setOptimisticStatus] = useOptimistic(currentStatus)

  function handleClick() {
    startTransition(async () => {
      setOptimisticStatus(targetStatus)
      await updateTaskStatus(taskId, targetStatus, tenantSlug, projectId)
    })
  }

  const isActive = optimisticStatus === targetStatus

  return (
    <button
      onClick={handleClick}
      disabled={isPending || isActive}
      className={`text-xs px-2 py-1 rounded transition-colors ${
        isActive
          ? 'bg-primary text-primary-foreground'
          : 'bg-gray-100 hover:bg-gray-200'
      } ${isPending ? 'opacity-50' : ''}`}
    >
      {label}
    </button>
  )
}
```


## ページネーションとインフィニットスクロール

タスク数が多い場合のページネーションを実装する。

```typescript
// src/hooks/use-infinite-tasks.ts
'use client'

import { useState, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'

const PAGE_SIZE = 20

export function useInfiniteTasks(projectId: string) {
  const [tasks, setTasks] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const [page, setPage] = useState(0)

  const loadMore = useCallback(async () => {
    if (loading || !hasMore) return

    setLoading(true)
    const supabase = createClient()

    const { data, error } = await supabase
      .from('tasks')
      .select('*')
      .eq('project_id', projectId)
      .order('created_at', { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1)

    if (error) {
      console.error('Error loading tasks:', error)
      setLoading(false)
      return
    }

    if (data.length < PAGE_SIZE) {
      setHasMore(false)
    }

    setTasks((prev) => [...prev, ...data])
    setPage((prev) => prev + 1)
    setLoading(false)
  }, [projectId, page, loading, hasMore])

  return { tasks, loading, hasMore, loadMore }
}
```


## まとめ

本章で実装した機能を整理する。

| 機能 | 実装方法 | リアルタイム対応 |
|------|---------|---------------|
| プロジェクトCRUD | Server Actions + revalidatePath | - |
| タスクCRUD | Server Actions + revalidatePath | Realtime対応 |
| カンバンボード | Client Component + Drag & Drop | Realtime対応 |
| コメント | Server Actions | Realtime対応 |
| オンラインユーザー表示 | Presence | Realtime |
| 楽観的更新 | useOptimistic + useTransition | - |

実装のポイントを整理する。

1. **Server ComponentでSSR + Client Componentでインタラクション**: 初期データはサーバーでフェッチし、リアルタイム更新はクライアントで処理
2. **Realtimeのフィルタリング**: `filter` パラメータで必要なデータのみ受信し、無駄な通信を削減
3. **楽観的更新**: `useOptimistic` を使ってUXを向上
4. **活動ログの自動記録**: 操作のたびにログを記録し、後の分析に活用

次章では、ファイルアップロードとストレージ管理を実装する。タスクへのファイル添付、プロジェクト内のファイル管理、アクセス制御を構築する。
