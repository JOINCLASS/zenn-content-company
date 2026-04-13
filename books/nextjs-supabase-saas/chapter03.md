---
title: "Supabaseの基本 -- 認証・データベース・ストレージ"
free: true
---

# Supabaseの基本 -- 認証・データベース・ストレージ

## はじめに

本章では、SaaSアプリケーションの実装に入る前に、Supabaseの3つの基本機能を一通り体験する。認証（Auth）、データベース（PostgreSQL）、ストレージ（Storage）のそれぞれについて、基本的な操作方法をハンズオン形式で学ぶ。

第4章以降でTaskFlowの本格的な実装に入るが、その前にSupabaseの「動かし方」を理解しておくことで、後の章の理解がスムーズになる。


## Supabase Auth -- 認証の基本

### Supabase Authのアーキテクチャ

Supabase Authは、内部的にGoTrueというオープンソースの認証サーバーを使用している。

```
┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  Next.js App  │────>│  Supabase    │────>│  PostgreSQL  │
│  (Client)     │     │  Auth/GoTrue │     │  auth.users  │
└───────────────┘     └──────────────┘     └──────────────┘
```

認証に関する主要な概念は以下の通りだ。

| 概念 | 説明 |
|------|------|
| `auth.users` | Supabaseが管理するユーザーテーブル。メール、メタデータ等を格納 |
| JWT | 認証トークン。SupabaseはJWTベースの認証を使用 |
| `auth.uid()` | 現在のログインユーザーのID。RLSポリシーで使用 |
| Session | クライアントサイドで管理されるセッション。自動更新される |

### メール/パスワード認証

最も基本的な認証方法を試す。

```typescript
// サインアップ
import { createClient } from '@/lib/supabase/client'

const supabase = createClient()

async function signUp(email: string, password: string) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      // メール確認後のリダイレクト先
      emailRedirectTo: `${window.location.origin}/auth/callback`,
      // ユーザーのメタデータ
      data: {
        full_name: 'テスト ユーザー',
      },
    },
  })

  if (error) {
    console.error('SignUp Error:', error.message)
    return
  }

  console.log('SignUp Success:', data.user)
  // ローカル開発では http://127.0.0.1:54324 (Inbucket) でメールを確認
}
```

```typescript
// サインイン
async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  })

  if (error) {
    console.error('SignIn Error:', error.message)
    return
  }

  console.log('SignIn Success:', data.user)
  console.log('Session:', data.session)
}
```

```typescript
// サインアウト
async function signOut() {
  const { error } = await supabase.auth.signOut()

  if (error) {
    console.error('SignOut Error:', error.message)
  }
}
```

```typescript
// 現在のユーザーを取得
async function getCurrentUser() {
  const { data: { user }, error } = await supabase.auth.getUser()

  if (error || !user) {
    console.log('未ログイン')
    return null
  }

  console.log('Current User:', user)
  return user
}
```

### OAuth認証（Google）

Google OAuthを例に、ソーシャルログインの実装方法を見る。

まず、Supabaseダッシュボードで Google プロバイダを有効にする。

1. Supabaseダッシュボード >「Authentication」>「Providers」
2. 「Google」を有効にする
3. Google Cloud ConsoleでOAuthクライアントIDを作成し、Client IDとClient Secretを設定

```typescript
// Google OAuth サインイン
async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: `${window.location.origin}/auth/callback`,
      queryParams: {
        access_type: 'offline',
        prompt: 'consent',
      },
    },
  })

  if (error) {
    console.error('OAuth Error:', error.message)
  }
  // ブラウザがGoogleの認証画面にリダイレクトされる
}
```

OAuthのコールバック処理用のRoute Handlerを作成する。

```typescript
// src/app/auth/callback/route.ts
import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = searchParams.get('next') ?? '/dashboard'

  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)

    if (!error) {
      const forwardedHost = request.headers.get('x-forwarded-host')
      const isLocalEnv = process.env.NODE_ENV === 'development'

      if (isLocalEnv) {
        return NextResponse.redirect(`${origin}${next}`)
      } else if (forwardedHost) {
        return NextResponse.redirect(`https://${forwardedHost}${next}`)
      } else {
        return NextResponse.redirect(`${origin}${next}`)
      }
    }
  }

  // エラー時はログインページにリダイレクト
  return NextResponse.redirect(`${origin}/login?error=auth_callback_error`)
}
```

### Magic Link認証

メールアドレスだけでログインできるMagic Linkも簡単に実装できる。

```typescript
// Magic Link サインイン
async function signInWithMagicLink(email: string) {
  const { data, error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: `${window.location.origin}/auth/callback`,
    },
  })

  if (error) {
    console.error('Magic Link Error:', error.message)
    return
  }

  console.log('メールを送信しました。メールのリンクをクリックしてログインしてください。')
}
```

### 認証状態の監視

クライアントサイドで認証状態の変化をリアルタイムに検知する。

```typescript
// 認証状態の監視
'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import type { User } from '@supabase/supabase-js'

export function useUser() {
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const supabase = createClient()

    // 初回ロード時にユーザーを取得
    supabase.auth.getUser().then(({ data: { user } }) => {
      setUser(user)
      setLoading(false)
    })

    // 認証状態の変化を監視
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
    })

    return () => subscription.unsubscribe()
  }, [])

  return { user, loading }
}
```

### Server Componentでのユーザー取得

サーバーサイドでは `cookies()` を使ったクライアントでユーザーを取得する。

```typescript
// Server Component でのユーザー取得
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

export default async function DashboardPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  return (
    <div>
      <h1>こんにちは、{user.email}さん</h1>
      <p>ユーザーID: {user.id}</p>
    </div>
  )
}
```


## Supabase Database -- PostgreSQLの基本

### テーブルの作成

Supabaseでは、テーブルの作成に2つの方法がある。

1. **ダッシュボードのTable Editor**: GUIでテーブルを作成
2. **SQLマイグレーション**: SQLファイルでテーブルを作成（推奨）

本書ではSQLマイグレーションを使用する。マイグレーションファイルはバージョン管理でき、チーム開発にも対応できる。

```bash
# マイグレーションファイルの作成
supabase migration new create_todos_table
```

生成されたマイグレーションファイルにSQLを記述する。

```sql
-- supabase/migrations/20260223000000_create_todos_table.sql

-- todosテーブルの作成
CREATE TABLE public.todos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  is_completed BOOLEAN DEFAULT FALSE,
  due_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- インデックスの作成
CREATE INDEX idx_todos_user_id ON public.todos(user_id);
CREATE INDEX idx_todos_created_at ON public.todos(created_at DESC);

-- RLSを有効化
ALTER TABLE public.todos ENABLE ROW LEVEL SECURITY;

-- RLSポリシー: ユーザーは自分のTodoのみアクセス可能
CREATE POLICY "Users can view own todos"
  ON public.todos FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own todos"
  ON public.todos FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own todos"
  ON public.todos FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own todos"
  ON public.todos FOR DELETE
  USING (auth.uid() = user_id);

-- updated_atを自動更新するトリガー
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_todos_updated_at
  BEFORE UPDATE ON public.todos
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
```

```bash
# マイグレーションを適用
supabase db reset
```

### CRUD操作

Supabaseクライアントを使った基本的なCRUD操作を見ていく。

#### Create（作成）

```typescript
const { data, error } = await supabase
  .from('todos')
  .insert({
    title: 'Next.jsの勉強をする',
    description: 'App RouterとServer Componentsについて学ぶ',
    due_date: '2026-03-01T00:00:00Z',
  })
  .select()
  .single()

// user_idはRLSにより自動的にauth.uid()が適用される
// .select() を付けると、insertした行を返す
// .single() を付けると、配列ではなく単一オブジェクトとして返す
```

#### Read（取得）

```typescript
// 全件取得
const { data: todos, error } = await supabase
  .from('todos')
  .select('*')
  .order('created_at', { ascending: false })

// 条件付き取得
const { data: incompleteTodos } = await supabase
  .from('todos')
  .select('*')
  .eq('is_completed', false)
  .order('due_date', { ascending: true })

// 単一行の取得
const { data: todo } = await supabase
  .from('todos')
  .select('*')
  .eq('id', todoId)
  .single()

// ページネーション
const { data: pagedTodos, count } = await supabase
  .from('todos')
  .select('*', { count: 'exact' })
  .range(0, 9)  // 0番目から9番目（10件）
  .order('created_at', { ascending: false })

// テキスト検索
const { data: searchResults } = await supabase
  .from('todos')
  .select('*')
  .ilike('title', '%Next.js%')
```

#### Update（更新）

```typescript
const { data, error } = await supabase
  .from('todos')
  .update({
    is_completed: true,
  })
  .eq('id', todoId)
  .select()
  .single()
```

#### Delete（削除）

```typescript
const { error } = await supabase
  .from('todos')
  .delete()
  .eq('id', todoId)
```

### リレーションとJOIN

PostgreSQLの外部キー制約に基づいて、Supabaseは自動的にリレーションを解決する。

```sql
-- コメントテーブルの作成
CREATE TABLE public.comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  todo_id UUID NOT NULL REFERENCES public.todos(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

```typescript
// todoとそのコメントを一緒に取得（自動JOIN）
const { data } = await supabase
  .from('todos')
  .select(`
    *,
    comments (
      id,
      content,
      created_at
    )
  `)
  .eq('id', todoId)
  .single()

// data.comments にコメント一覧が含まれる
```

```typescript
// 逆方向: コメントからtodoの情報を取得
const { data } = await supabase
  .from('comments')
  .select(`
    *,
    todos (
      id,
      title
    )
  `)
  .eq('user_id', userId)
```

### フィルタリング演算子

Supabaseのクエリビルダーは、豊富なフィルタリング演算子を提供する。

| メソッド | SQL相当 | 例 |
|---------|---------|-----|
| `.eq()` | `=` | `.eq('status', 'active')` |
| `.neq()` | `!=` | `.neq('status', 'deleted')` |
| `.gt()` | `>` | `.gt('priority', 3)` |
| `.gte()` | `>=` | `.gte('due_date', '2026-01-01')` |
| `.lt()` | `<` | `.lt('priority', 5)` |
| `.lte()` | `<=` | `.lte('price', 1000)` |
| `.like()` | `LIKE` | `.like('title', '%Next%')` |
| `.ilike()` | `ILIKE` | `.ilike('title', '%next%')` |
| `.in()` | `IN` | `.in('status', ['active', 'pending'])` |
| `.is()` | `IS` | `.is('deleted_at', null)` |
| `.contains()` | `@>` | `.contains('tags', ['react'])` |
| `.or()` | `OR` | `.or('status.eq.active,priority.gt.3')` |

### トランザクション

Supabaseでは、PostgreSQLの関数（Stored Functions）を使ってトランザクションを実現する。

```sql
-- トランザクション的な操作をPostgreSQL関数として定義
CREATE OR REPLACE FUNCTION complete_todo_and_add_log(
  p_todo_id UUID,
  p_user_id UUID
)
RETURNS VOID AS $$
BEGIN
  -- Todoを完了にする
  UPDATE public.todos
  SET is_completed = TRUE, updated_at = now()
  WHERE id = p_todo_id AND user_id = p_user_id;

  -- 該当Todoが見つからなかった場合はエラー（UPDATEの直後にチェック）
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Todo not found or access denied';
  END IF;

  -- 完了ログを記録
  INSERT INTO public.activity_logs (user_id, action, target_id)
  VALUES (p_user_id, 'complete_todo', p_todo_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

```typescript
// クライアントからの呼び出し
const { error } = await supabase.rpc('complete_todo_and_add_log', {
  p_todo_id: todoId,
  p_user_id: userId,
})
```


## Supabase Storage -- ファイル管理の基本

### バケットの作成

Supabase Storageでは、ファイルを「バケット」単位で管理する。

```sql
-- マイグレーションでバケットを作成
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  TRUE,  -- 公開バケット
  1048576,  -- 1MB制限
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- ストレージのRLSポリシー
CREATE POLICY "Users can upload own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Anyone can view avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Users can update own avatar"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete own avatar"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );
```

ここでのポイントは、ファイルパスにユーザーIDを含めることで、RLSでアクセス制御を実現していることだ。`avatars/{user_id}/profile.png` のような構造にする。

### ファイルのアップロード

```typescript
// ファイルアップロード
async function uploadAvatar(userId: string, file: File) {
  const fileExt = file.name.split('.').pop()
  const filePath = `${userId}/avatar.${fileExt}`

  const { data, error } = await supabase.storage
    .from('avatars')
    .upload(filePath, file, {
      cacheControl: '3600',
      upsert: true, // 既存ファイルを上書き
    })

  if (error) {
    console.error('Upload Error:', error.message)
    return null
  }

  return data.path
}
```

### ファイルのURLを取得

```typescript
// 公開バケットの場合: パブリックURL
function getAvatarUrl(path: string) {
  const { data } = supabase.storage
    .from('avatars')
    .getPublicUrl(path)

  return data.publicUrl
}

// 非公開バケットの場合: 署名付きURL（有効期限付き）
async function getPrivateFileUrl(path: string) {
  const { data, error } = await supabase.storage
    .from('private-documents')
    .createSignedUrl(path, 3600) // 1時間有効

  if (error) {
    console.error('URL generation error:', error.message)
    return null
  }

  return data.signedUrl
}
```

### ファイルの一覧取得

```typescript
// 特定ディレクトリのファイル一覧
async function listFiles(userId: string) {
  const { data, error } = await supabase.storage
    .from('documents')
    .list(userId, {
      limit: 100,
      offset: 0,
      sortBy: { column: 'created_at', order: 'desc' },
    })

  if (error) {
    console.error('List Error:', error.message)
    return []
  }

  return data
}
```

### ファイルの削除

```typescript
// ファイルの削除
async function deleteFile(path: string) {
  const { error } = await supabase.storage
    .from('documents')
    .remove([path])

  if (error) {
    console.error('Delete Error:', error.message)
  }
}
```

### 画像の変換

Supabase Storageは、画像のリサイズや変換を自動で行う機能がある。

```typescript
// 画像のリサイズ（サムネイル生成）
function getResizedImageUrl(path: string) {
  const { data } = supabase.storage
    .from('avatars')
    .getPublicUrl(path, {
      transform: {
        width: 100,
        height: 100,
        resize: 'cover', // 'contain' | 'cover' | 'fill'
        quality: 80,
        format: 'webp',
      },
    })

  return data.publicUrl
}
```

これにより、オリジナル画像をアップロードするだけで、サムネイルやプロフィール用の小さな画像を動的に生成できる。


## Supabase Realtime -- リアルタイム機能の概要

Supabase Realtimeは、データベースの変更をWebSocket経由でクライアントにリアルタイム配信する機能だ。詳しくは第6章で実装するが、ここでは概要を紹介する。

### Realtimeの種類

| 種類 | 用途 | 例 |
|------|------|-----|
| Database Changes | テーブルの変更を監視 | 新しいタスクが追加されたら通知 |
| Broadcast | チャネルへのメッセージ送信 | カーソル位置の共有 |
| Presence | ユーザーのオンライン状態を共有 | 「現在3人がオンライン」 |

### Database Changesの例

```typescript
// todosテーブルの変更をリアルタイムに監視
const channel = supabase
  .channel('todos-changes')
  .on(
    'postgres_changes',
    {
      event: '*',       // INSERT, UPDATE, DELETE の全て
      schema: 'public',
      table: 'todos',
      filter: `user_id=eq.${userId}`,
    },
    (payload) => {
      console.log('Change received:', payload)

      switch (payload.eventType) {
        case 'INSERT':
          console.log('New todo:', payload.new)
          break
        case 'UPDATE':
          console.log('Updated todo:', payload.new)
          break
        case 'DELETE':
          console.log('Deleted todo:', payload.old)
          break
      }
    }
  )
  .subscribe()

// クリーンアップ
// channel.unsubscribe()
```

### Realtimeを有効にするための設定

テーブルのRealtimeを有効にするには、Supabaseダッシュボードまたはマイグレーションで設定する。

```sql
-- テーブルのRealtime公開を有効にする
ALTER PUBLICATION supabase_realtime ADD TABLE public.todos;
```


## Supabase Edge Functions -- サーバーレスファンクション

Supabase Edge Functionsは、Denoランタイムで動作するサーバーレスファンクションだ。本書では、StripeのWebhook処理（第8章）でNext.jsのRoute Handlerを使用するが、Edge Functionsも選択肢として紹介する。

### Edge Functionの作成

```bash
# Edge Functionの作成
supabase functions new hello-world
```

```typescript
// supabase/functions/hello-world/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts"

serve(async (req) => {
  const { name } = await req.json()

  const data = {
    message: `Hello ${name}!`,
  }

  return new Response(
    JSON.stringify(data),
    { headers: { "Content-Type": "application/json" } },
  )
})
```

```bash
# ローカルでテスト
supabase functions serve hello-world

# デプロイ
supabase functions deploy hello-world
```

```typescript
// クライアントからの呼び出し
const { data, error } = await supabase.functions.invoke('hello-world', {
  body: { name: 'World' },
})
```


## Supabase Studioでの操作

ローカル環境では `http://127.0.0.1:54323`、クラウドではSupabaseダッシュボードで、GUIベースの操作ができる。

### 便利な機能

| 機能 | 説明 |
|------|------|
| Table Editor | テーブルの閲覧・編集・作成 |
| SQL Editor | SQLを直接実行 |
| Authentication | ユーザーの管理・確認 |
| Storage | バケットとファイルの管理 |
| Database > Policies | RLSポリシーの管理 |
| Logs | APIリクエスト、認証、PostgreSQLのログ |

### SQL Editorの活用

開発中、SQLを直接実行してデータを確認・操作することが多い。

```sql
-- ユーザー一覧の確認
SELECT id, email, created_at
FROM auth.users
ORDER BY created_at DESC
LIMIT 10;

-- テーブルのRLSポリシー一覧
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public';

-- テーブルの統計情報
SELECT
  relname AS table_name,
  n_live_tup AS row_count,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```


## 実践: 簡易Todoアプリの作成

ここまで学んだ知識を統合して、簡易的なTodoアプリを作成する。これはTaskFlowの実装に入る前のウォームアップだ。

### マイグレーション

前述の `create_todos_table` マイグレーションを適用する。

```bash
supabase db reset
pnpm db:types
```

### Server Component でTodo一覧を表示

```tsx
// src/app/dashboard/page.tsx
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { TodoList } from '@/components/dashboard/todo-list'
import { AddTodoForm } from '@/components/dashboard/add-todo-form'

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  const { data: todos } = await supabase
    .from('todos')
    .select('*')
    .order('created_at', { ascending: false })

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">Todoリスト</h1>
      <AddTodoForm />
      <TodoList todos={todos ?? []} />
    </div>
  )
}
```

### Server Action でTodoを追加

```typescript
// src/app/dashboard/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function addTodo(formData: FormData) {
  const supabase = await createClient()
  const title = formData.get('title') as string

  if (!title?.trim()) {
    return { error: 'タイトルを入力してください' }
  }

  const { error } = await supabase
    .from('todos')
    .insert({ title: title.trim() })

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/dashboard')
  return { success: true }
}

export async function toggleTodo(id: string, isCompleted: boolean) {
  const supabase = await createClient()

  const { error } = await supabase
    .from('todos')
    .update({ is_completed: !isCompleted })
    .eq('id', id)

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/dashboard')
  return { success: true }
}

export async function deleteTodo(id: string) {
  const supabase = await createClient()

  const { error } = await supabase
    .from('todos')
    .delete()
    .eq('id', id)

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/dashboard')
  return { success: true }
}
```

### Client Component でフォームとリスト

```tsx
// src/components/dashboard/add-todo-form.tsx
'use client'

import { useRef } from 'react'
import { addTodo } from '@/app/dashboard/actions'

export function AddTodoForm() {
  const formRef = useRef<HTMLFormElement>(null)

  async function handleSubmit(formData: FormData) {
    const result = await addTodo(formData)
    if (result.success) {
      formRef.current?.reset()
    }
  }

  return (
    <form ref={formRef} action={handleSubmit} className="flex gap-2 mb-6">
      <input
        name="title"
        placeholder="新しいタスクを入力..."
        className="flex-1 border rounded-md px-3 py-2"
        required
      />
      <button
        type="submit"
        className="bg-primary text-primary-foreground px-4 py-2 rounded-md"
      >
        追加
      </button>
    </form>
  )
}
```

```tsx
// src/components/dashboard/todo-list.tsx
'use client'

import { toggleTodo, deleteTodo } from '@/app/dashboard/actions'

type Todo = {
  id: string
  title: string
  is_completed: boolean
  created_at: string
}

export function TodoList({ todos }: { todos: Todo[] }) {
  if (todos.length === 0) {
    return (
      <p className="text-muted-foreground text-center py-8">
        タスクがありません。上のフォームから追加してください。
      </p>
    )
  }

  return (
    <ul className="space-y-2">
      {todos.map((todo) => (
        <li
          key={todo.id}
          className="flex items-center gap-3 border rounded-md p-3"
        >
          <button
            onClick={() => toggleTodo(todo.id, todo.is_completed)}
            className={`w-5 h-5 rounded border-2 flex items-center justify-center
              ${todo.is_completed ? 'bg-primary border-primary' : 'border-gray-300'}`}
          >
            {todo.is_completed && (
              <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
              </svg>
            )}
          </button>
          <span className={`flex-1 ${todo.is_completed ? 'line-through text-muted-foreground' : ''}`}>
            {todo.title}
          </span>
          <button
            onClick={() => deleteTodo(todo.id)}
            className="text-sm text-red-500 hover:text-red-700"
          >
            削除
          </button>
        </li>
      ))}
    </ul>
  )
}
```

この簡易Todoアプリで、以下の一連の流れを体験できる。

1. **Supabase Auth**: ログインしないとダッシュボードにアクセスできない
2. **Server Component**: サーバーサイドでデータをフェッチしてSSR
3. **Server Action**: フォーム送信でデータを変更、`revalidatePath`で再描画
4. **RLS**: 各ユーザーは自分のTodoだけにアクセスできる


## まとめ

本章で学んだSupabaseの基本機能を整理する。

| 機能 | 学んだ内容 |
|------|-----------|
| Auth | メール/パスワード、OAuth、Magic Link認証。状態監視、Server/Client両方での使い方 |
| Database | テーブル作成（マイグレーション）、CRUD操作、リレーション、フィルタリング、RPC |
| Storage | バケット作成、ファイルアップロード/ダウンロード/削除、画像変換 |
| Realtime | Database Changes、Broadcast、Presenceの概要 |
| Edge Functions | サーバーレスファンクションの概要 |
| Studio | GUI操作、SQL Editor |

次章からは、これらの知識を活用してTaskFlowの本格的な実装に入る。まずは認証機能の実装から始める。
