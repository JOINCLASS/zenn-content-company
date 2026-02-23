---
title: "認証機能の実装 -- メール/パスワード、OAuth、Magic Link"
free: false
---

# 認証機能の実装 -- メール/パスワード、OAuth、Magic Link

## はじめに

本章では、TaskFlowの認証機能を本格的に実装する。第3章で学んだSupabase Authの基本を土台に、SaaSアプリケーションとして必要な認証フローを完成させる。

具体的には以下を実装する。

1. サインアップページ（メール/パスワード）
2. ログインページ（メール/パスワード + OAuth + Magic Link）
3. OAuthコールバック処理
4. メール確認フロー
5. パスワードリセットフロー
6. ユーザープロフィール（public.profiles テーブル）
7. 認証後のオンボーディングフロー

本章を終える頃には、ユーザーが3種類の方法でサインアップ・ログインでき、プロフィール情報を管理できる状態になる。


## profilesテーブルの設計

Supabaseの `auth.users` テーブルは認証に必要な情報（メール、パスワードハッシュ等）を保持するが、アプリケーション固有のユーザー情報（表示名、アバター、設定等）は別テーブルで管理するのがベストプラクティスだ。

### マイグレーション

```bash
supabase migration new create_profiles_table
```

```sql
-- supabase/migrations/20260223000100_create_profiles_table.sql

-- profilesテーブル
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  onboarding_completed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- インデックス
CREATE INDEX idx_profiles_email ON public.profiles(email);

-- RLS有効化
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- RLSポリシー
CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 他のユーザーのプロフィール（名前とアバター）は閲覧可能
CREATE POLICY "Users can view other profiles (limited)"
  ON public.profiles FOR SELECT
  USING (TRUE);

-- updated_at自動更新トリガー
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- 新規ユーザー登録時に自動的にprofileを作成するトリガー
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
```

**ポイント:**

- `profiles.id` は `auth.users.id` と同じUUID。外部キーで参照
- `handle_new_user` トリガーにより、ユーザー登録時にprofileが自動作成される
- OAuthでログインした場合、`raw_user_meta_data` からフルネームとアバターURLを取得

### マイグレーション適用と型生成

```bash
supabase db reset
pnpm db:types
```


## 認証関連のServer Actions

サインアップ、ログイン、ログアウト等の認証操作をServer Actionsとして定義する。

```typescript
// src/app/(auth)/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { headers } from 'next/headers'
import { revalidatePath } from 'next/cache'

// ========================================
// サインアップ（メール/パスワード）
// ========================================
export async function signUp(formData: FormData) {
  const supabase = await createClient()
  const headersList = await headers()
  const origin = headersList.get('origin') || 'http://localhost:3000'

  const email = formData.get('email') as string
  const password = formData.get('password') as string
  const fullName = formData.get('full_name') as string

  // バリデーション
  if (!email || !password) {
    return { error: 'メールアドレスとパスワードは必須です' }
  }

  if (password.length < 8) {
    return { error: 'パスワードは8文字以上で入力してください' }
  }

  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${origin}/auth/callback`,
      data: {
        full_name: fullName || '',
      },
    },
  })

  if (error) {
    return { error: error.message }
  }

  // メール確認が必要な場合
  if (data.user && !data.session) {
    return {
      success: true,
      message: '確認メールを送信しました。メール内のリンクをクリックしてアカウントを有効化してください。',
    }
  }

  // 自動ログインされた場合（メール確認が不要な設定の場合）
  revalidatePath('/', 'layout')
  redirect('/dashboard')
}

// ========================================
// ログイン（メール/パスワード）
// ========================================
export async function signIn(formData: FormData) {
  const supabase = await createClient()

  const email = formData.get('email') as string
  const password = formData.get('password') as string

  if (!email || !password) {
    return { error: 'メールアドレスとパスワードは必須です' }
  }

  const { error } = await supabase.auth.signInWithPassword({
    email,
    password,
  })

  if (error) {
    if (error.message === 'Invalid login credentials') {
      return { error: 'メールアドレスまたはパスワードが正しくありません' }
    }
    return { error: error.message }
  }

  revalidatePath('/', 'layout')
  redirect('/dashboard')
}

// ========================================
// Magic Link ログイン
// ========================================
export async function signInWithMagicLink(formData: FormData) {
  const supabase = await createClient()
  const headersList = await headers()
  const origin = headersList.get('origin') || 'http://localhost:3000'

  const email = formData.get('email') as string

  if (!email) {
    return { error: 'メールアドレスを入力してください' }
  }

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: `${origin}/auth/callback`,
    },
  })

  if (error) {
    return { error: error.message }
  }

  return {
    success: true,
    message: 'ログインリンクを送信しました。メールを確認してください。',
  }
}

// ========================================
// OAuth ログイン
// ========================================
export async function signInWithOAuth(provider: 'google' | 'github') {
  const supabase = await createClient()
  const headersList = await headers()
  const origin = headersList.get('origin') || 'http://localhost:3000'

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: `${origin}/auth/callback`,
    },
  })

  if (error) {
    return { error: error.message }
  }

  if (data.url) {
    redirect(data.url)
  }
}

// ========================================
// ログアウト
// ========================================
export async function signOut() {
  const supabase = await createClient()
  await supabase.auth.signOut()
  revalidatePath('/', 'layout')
  redirect('/login')
}

// ========================================
// パスワードリセット（リクエスト）
// ========================================
export async function resetPasswordRequest(formData: FormData) {
  const supabase = await createClient()
  const headersList = await headers()
  const origin = headersList.get('origin') || 'http://localhost:3000'

  const email = formData.get('email') as string

  if (!email) {
    return { error: 'メールアドレスを入力してください' }
  }

  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${origin}/auth/callback?next=/reset-password`,
  })

  if (error) {
    return { error: error.message }
  }

  return {
    success: true,
    message: 'パスワードリセットのメールを送信しました。メールを確認してください。',
  }
}

// ========================================
// パスワードリセット（実行）
// ========================================
export async function resetPassword(formData: FormData) {
  const supabase = await createClient()

  const password = formData.get('password') as string
  const confirmPassword = formData.get('confirm_password') as string

  if (!password || !confirmPassword) {
    return { error: 'パスワードを入力してください' }
  }

  if (password !== confirmPassword) {
    return { error: 'パスワードが一致しません' }
  }

  if (password.length < 8) {
    return { error: 'パスワードは8文字以上で入力してください' }
  }

  const { error } = await supabase.auth.updateUser({
    password,
  })

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/', 'layout')
  redirect('/dashboard')
}
```


## 認証ページのレイアウト

認証関連ページ共通のレイアウトを作成する。

```tsx
// src/app/(auth)/layout.tsx
export default function AuthLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="w-full max-w-md mx-auto px-4">
        <div className="text-center mb-8">
          <a href="/" className="text-2xl font-bold">
            TaskFlow
          </a>
        </div>
        {children}
      </div>
    </div>
  )
}
```


## サインアップページ

```tsx
// src/app/(auth)/signup/page.tsx
import { SignUpForm } from '@/components/auth/signup-form'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'アカウント作成 | TaskFlow',
  description: 'TaskFlowのアカウントを作成して、チームのタスク管理を始めましょう。',
}

export default function SignUpPage() {
  return (
    <div className="bg-white rounded-lg shadow-sm border p-8">
      <h1 className="text-xl font-semibold text-center mb-6">
        アカウントを作成
      </h1>
      <SignUpForm />
      <p className="text-sm text-center text-muted-foreground mt-6">
        すでにアカウントをお持ちですか？{' '}
        <a href="/login" className="text-primary hover:underline">
          ログイン
        </a>
      </p>
    </div>
  )
}
```

```tsx
// src/components/auth/signup-form.tsx
'use client'

import { useState } from 'react'
import { signUp, signInWithOAuth } from '@/app/(auth)/actions'

export function SignUpForm() {
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(formData: FormData) {
    setLoading(true)
    setError(null)
    setMessage(null)

    const result = await signUp(formData)

    if (result?.error) {
      setError(result.error)
    } else if (result?.message) {
      setMessage(result.message)
    }

    setLoading(false)
  }

  return (
    <div className="space-y-4">
      {/* OAuth ボタン */}
      <div className="space-y-2">
        <form action={() => signInWithOAuth('google')}>
          <button
            type="submit"
            className="w-full flex items-center justify-center gap-2 border rounded-md px-4 py-2 hover:bg-gray-50 transition-colors"
          >
            <GoogleIcon />
            Googleで続ける
          </button>
        </form>
        <form action={() => signInWithOAuth('github')}>
          <button
            type="submit"
            className="w-full flex items-center justify-center gap-2 border rounded-md px-4 py-2 hover:bg-gray-50 transition-colors"
          >
            <GitHubIcon />
            GitHubで続ける
          </button>
        </form>
      </div>

      {/* 区切り線 */}
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-white px-2 text-muted-foreground">
            または
          </span>
        </div>
      </div>

      {/* メール/パスワード フォーム */}
      <form action={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="full_name" className="block text-sm font-medium mb-1">
            お名前
          </label>
          <input
            id="full_name"
            name="full_name"
            type="text"
            placeholder="山田 太郎"
            className="w-full border rounded-md px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="email" className="block text-sm font-medium mb-1">
            メールアドレス
          </label>
          <input
            id="email"
            name="email"
            type="email"
            placeholder="you@example.com"
            required
            className="w-full border rounded-md px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="password" className="block text-sm font-medium mb-1">
            パスワード
          </label>
          <input
            id="password"
            name="password"
            type="password"
            placeholder="8文字以上"
            required
            minLength={8}
            className="w-full border rounded-md px-3 py-2 text-sm"
          />
        </div>

        {error && (
          <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
            {error}
          </div>
        )}

        {message && (
          <div className="bg-green-50 text-green-700 text-sm px-3 py-2 rounded-md">
            {message}
          </div>
        )}

        <button
          type="submit"
          disabled={loading}
          className="w-full bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
        >
          {loading ? '処理中...' : 'アカウントを作成'}
        </button>
      </form>

      <p className="text-xs text-muted-foreground text-center">
        アカウントを作成することで、
        <a href="/terms" className="underline">利用規約</a>と
        <a href="/privacy" className="underline">プライバシーポリシー</a>
        に同意したものとみなされます。
      </p>
    </div>
  )
}

function GoogleIcon() {
  return (
    <svg className="w-5 h-5" viewBox="0 0 24 24">
      <path
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"
        fill="#4285F4"
      />
      <path
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
        fill="#34A853"
      />
      <path
        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
        fill="#FBBC05"
      />
      <path
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
        fill="#EA4335"
      />
    </svg>
  )
}

function GitHubIcon() {
  return (
    <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
    </svg>
  )
}
```


## ログインページ

```tsx
// src/app/(auth)/login/page.tsx
import { LoginForm } from '@/components/auth/login-form'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'ログイン | TaskFlow',
  description: 'TaskFlowにログインして、プロジェクトを管理しましょう。',
}

export default function LoginPage({
  searchParams,
}: {
  searchParams: { redirect?: string; error?: string }
}) {
  return (
    <div className="bg-white rounded-lg shadow-sm border p-8">
      <h1 className="text-xl font-semibold text-center mb-6">
        ログイン
      </h1>

      {searchParams.error && (
        <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md mb-4">
          認証に失敗しました。もう一度お試しください。
        </div>
      )}

      <LoginForm redirectTo={searchParams.redirect} />

      <p className="text-sm text-center text-muted-foreground mt-6">
        アカウントをお持ちでないですか？{' '}
        <a href="/signup" className="text-primary hover:underline">
          アカウントを作成
        </a>
      </p>
    </div>
  )
}
```

```tsx
// src/components/auth/login-form.tsx
'use client'

import { useState } from 'react'
import { signIn, signInWithOAuth, signInWithMagicLink } from '@/app/(auth)/actions'

type LoginMode = 'password' | 'magic-link'

export function LoginForm({ redirectTo }: { redirectTo?: string }) {
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<LoginMode>('password')

  async function handlePasswordLogin(formData: FormData) {
    setLoading(true)
    setError(null)
    const result = await signIn(formData)
    if (result?.error) {
      setError(result.error)
    }
    setLoading(false)
  }

  async function handleMagicLinkLogin(formData: FormData) {
    setLoading(true)
    setError(null)
    setMessage(null)
    const result = await signInWithMagicLink(formData)
    if (result?.error) {
      setError(result.error)
    } else if (result?.message) {
      setMessage(result.message)
    }
    setLoading(false)
  }

  return (
    <div className="space-y-4">
      {/* OAuth ボタン */}
      <div className="space-y-2">
        <form action={() => signInWithOAuth('google')}>
          <button
            type="submit"
            className="w-full flex items-center justify-center gap-2 border rounded-md px-4 py-2 hover:bg-gray-50 transition-colors"
          >
            Googleでログイン
          </button>
        </form>
        <form action={() => signInWithOAuth('github')}>
          <button
            type="submit"
            className="w-full flex items-center justify-center gap-2 border rounded-md px-4 py-2 hover:bg-gray-50 transition-colors"
          >
            GitHubでログイン
          </button>
        </form>
      </div>

      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-white px-2 text-muted-foreground">または</span>
        </div>
      </div>

      {/* モード切替タブ */}
      <div className="flex gap-1 bg-gray-100 p-1 rounded-md">
        <button
          type="button"
          onClick={() => { setMode('password'); setError(null); setMessage(null) }}
          className={`flex-1 text-sm py-1.5 rounded transition-colors ${
            mode === 'password' ? 'bg-white shadow-sm font-medium' : 'text-muted-foreground'
          }`}
        >
          パスワード
        </button>
        <button
          type="button"
          onClick={() => { setMode('magic-link'); setError(null); setMessage(null) }}
          className={`flex-1 text-sm py-1.5 rounded transition-colors ${
            mode === 'magic-link' ? 'bg-white shadow-sm font-medium' : 'text-muted-foreground'
          }`}
        >
          Magic Link
        </button>
      </div>

      {/* パスワードログイン */}
      {mode === 'password' && (
        <form action={handlePasswordLogin} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium mb-1">
              メールアドレス
            </label>
            <input
              id="email"
              name="email"
              type="email"
              placeholder="you@example.com"
              required
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>
          <div>
            <div className="flex items-center justify-between mb-1">
              <label htmlFor="password" className="block text-sm font-medium">
                パスワード
              </label>
              <a
                href="/forgot-password"
                className="text-xs text-primary hover:underline"
              >
                パスワードを忘れた方
              </a>
            </div>
            <input
              id="password"
              name="password"
              type="password"
              required
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>

          {error && (
            <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
          >
            {loading ? '処理中...' : 'ログイン'}
          </button>
        </form>
      )}

      {/* Magic Link ログイン */}
      {mode === 'magic-link' && (
        <form action={handleMagicLinkLogin} className="space-y-4">
          <div>
            <label htmlFor="magic-email" className="block text-sm font-medium mb-1">
              メールアドレス
            </label>
            <input
              id="magic-email"
              name="email"
              type="email"
              placeholder="you@example.com"
              required
              className="w-full border rounded-md px-3 py-2 text-sm"
            />
          </div>

          {error && (
            <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
              {error}
            </div>
          )}

          {message && (
            <div className="bg-green-50 text-green-700 text-sm px-3 py-2 rounded-md">
              {message}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
          >
            {loading ? '処理中...' : 'ログインリンクを送信'}
          </button>

          <p className="text-xs text-muted-foreground text-center">
            入力したメールアドレスにログインリンクが届きます。
            パスワードの入力は不要です。
          </p>
        </form>
      )}
    </div>
  )
}
```


## パスワードリセットページ

```tsx
// src/app/(auth)/forgot-password/page.tsx
import { ForgotPasswordForm } from '@/components/auth/forgot-password-form'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'パスワードリセット | TaskFlow',
}

export default function ForgotPasswordPage() {
  return (
    <div className="bg-white rounded-lg shadow-sm border p-8">
      <h1 className="text-xl font-semibold text-center mb-2">
        パスワードリセット
      </h1>
      <p className="text-sm text-muted-foreground text-center mb-6">
        登録済みのメールアドレスを入力してください。
        パスワードリセット用のリンクを送信します。
      </p>
      <ForgotPasswordForm />
      <p className="text-sm text-center text-muted-foreground mt-6">
        <a href="/login" className="text-primary hover:underline">
          ログインに戻る
        </a>
      </p>
    </div>
  )
}
```

```tsx
// src/components/auth/forgot-password-form.tsx
'use client'

import { useState } from 'react'
import { resetPasswordRequest } from '@/app/(auth)/actions'

export function ForgotPasswordForm() {
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(formData: FormData) {
    setLoading(true)
    setError(null)
    setMessage(null)

    const result = await resetPasswordRequest(formData)

    if (result?.error) {
      setError(result.error)
    } else if (result?.message) {
      setMessage(result.message)
    }

    setLoading(false)
  }

  return (
    <form action={handleSubmit} className="space-y-4">
      <div>
        <label htmlFor="email" className="block text-sm font-medium mb-1">
          メールアドレス
        </label>
        <input
          id="email"
          name="email"
          type="email"
          placeholder="you@example.com"
          required
          className="w-full border rounded-md px-3 py-2 text-sm"
        />
      </div>

      {error && (
        <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
          {error}
        </div>
      )}

      {message && (
        <div className="bg-green-50 text-green-700 text-sm px-3 py-2 rounded-md">
          {message}
        </div>
      )}

      <button
        type="submit"
        disabled={loading}
        className="w-full bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
      >
        {loading ? '処理中...' : 'リセットリンクを送信'}
      </button>
    </form>
  )
}
```

```tsx
// src/app/(auth)/reset-password/page.tsx
import { ResetPasswordForm } from '@/components/auth/reset-password-form'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: '新しいパスワードの設定 | TaskFlow',
}

export default function ResetPasswordPage() {
  return (
    <div className="bg-white rounded-lg shadow-sm border p-8">
      <h1 className="text-xl font-semibold text-center mb-2">
        新しいパスワードの設定
      </h1>
      <p className="text-sm text-muted-foreground text-center mb-6">
        新しいパスワードを入力してください。
      </p>
      <ResetPasswordForm />
    </div>
  )
}
```

```tsx
// src/components/auth/reset-password-form.tsx
'use client'

import { useState } from 'react'
import { resetPassword } from '@/app/(auth)/actions'

export function ResetPasswordForm() {
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(formData: FormData) {
    setLoading(true)
    setError(null)
    const result = await resetPassword(formData)
    if (result?.error) {
      setError(result.error)
    }
    setLoading(false)
  }

  return (
    <form action={handleSubmit} className="space-y-4">
      <div>
        <label htmlFor="password" className="block text-sm font-medium mb-1">
          新しいパスワード
        </label>
        <input
          id="password"
          name="password"
          type="password"
          placeholder="8文字以上"
          required
          minLength={8}
          className="w-full border rounded-md px-3 py-2 text-sm"
        />
      </div>
      <div>
        <label htmlFor="confirm_password" className="block text-sm font-medium mb-1">
          パスワードの確認
        </label>
        <input
          id="confirm_password"
          name="confirm_password"
          type="password"
          placeholder="もう一度入力"
          required
          minLength={8}
          className="w-full border rounded-md px-3 py-2 text-sm"
        />
      </div>

      {error && (
        <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
          {error}
        </div>
      )}

      <button
        type="submit"
        disabled={loading}
        className="w-full bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
      >
        {loading ? '処理中...' : 'パスワードを変更'}
      </button>
    </form>
  )
}
```


## プロフィール管理

### プロフィール取得のユーティリティ

```typescript
// src/lib/auth.ts
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

export async function getSession() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  return user
}

export async function requireAuth() {
  const user = await getSession()
  if (!user) {
    redirect('/login')
  }
  return user
}

export async function getProfile() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return null

  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single()

  return profile
}

export async function requireProfile() {
  const profile = await getProfile()
  if (!profile) {
    redirect('/login')
  }
  return profile
}
```

### プロフィール編集ページ

```tsx
// src/app/dashboard/settings/page.tsx
import { requireProfile } from '@/lib/auth'
import { ProfileForm } from '@/components/dashboard/profile-form'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'プロフィール設定 | TaskFlow',
}

export default async function SettingsPage() {
  const profile = await requireProfile()

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">プロフィール設定</h1>
      <ProfileForm profile={profile} />
    </div>
  )
}
```

```typescript
// src/app/dashboard/settings/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function updateProfile(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return { error: '認証が必要です' }
  }

  const fullName = formData.get('full_name') as string

  const { error } = await supabase
    .from('profiles')
    .update({
      full_name: fullName,
    })
    .eq('id', user.id)

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/dashboard/settings')
  return { success: true }
}

export async function uploadAvatar(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return { error: '認証が必要です' }
  }

  const file = formData.get('avatar') as File

  if (!file || file.size === 0) {
    return { error: 'ファイルを選択してください' }
  }

  if (file.size > 1024 * 1024) {
    return { error: 'ファイルサイズは1MB以下にしてください' }
  }

  const fileExt = file.name.split('.').pop()
  const filePath = `${user.id}/avatar.${fileExt}`

  // アップロード
  const { error: uploadError } = await supabase.storage
    .from('avatars')
    .upload(filePath, file, { upsert: true })

  if (uploadError) {
    return { error: uploadError.message }
  }

  // 公開URLを取得
  const { data: urlData } = supabase.storage
    .from('avatars')
    .getPublicUrl(filePath)

  // profilesテーブルのavatar_urlを更新
  const { error: updateError } = await supabase
    .from('profiles')
    .update({ avatar_url: urlData.publicUrl })
    .eq('id', user.id)

  if (updateError) {
    return { error: updateError.message }
  }

  revalidatePath('/dashboard/settings')
  return { success: true, avatarUrl: urlData.publicUrl }
}
```

```tsx
// src/components/dashboard/profile-form.tsx
'use client'

import { useState } from 'react'
import { updateProfile, uploadAvatar } from '@/app/dashboard/settings/actions'

type Profile = {
  id: string
  email: string
  full_name: string | null
  avatar_url: string | null
}

export function ProfileForm({ profile }: { profile: Profile }) {
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [avatarUrl, setAvatarUrl] = useState(profile.avatar_url)

  async function handleProfileUpdate(formData: FormData) {
    setError(null)
    setSuccess(false)
    const result = await updateProfile(formData)
    if (result.error) {
      setError(result.error)
    } else {
      setSuccess(true)
    }
  }

  async function handleAvatarUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return

    const formData = new FormData()
    formData.append('avatar', file)

    const result = await uploadAvatar(formData)
    if (result.error) {
      setError(result.error)
    } else if (result.avatarUrl) {
      setAvatarUrl(result.avatarUrl)
    }
  }

  return (
    <div className="space-y-8">
      {/* アバター */}
      <div className="space-y-2">
        <label className="block text-sm font-medium">アバター</label>
        <div className="flex items-center gap-4">
          <div className="w-16 h-16 rounded-full bg-gray-200 overflow-hidden">
            {avatarUrl ? (
              <img src={avatarUrl} alt="アバター" className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-gray-400 text-xl font-bold">
                {profile.full_name?.[0] || profile.email[0].toUpperCase()}
              </div>
            )}
          </div>
          <label className="cursor-pointer text-sm text-primary hover:underline">
            画像を変更
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
              onChange={handleAvatarUpload}
            />
          </label>
        </div>
      </div>

      {/* プロフィール情報 */}
      <form action={handleProfileUpdate} className="space-y-4">
        <div>
          <label htmlFor="email" className="block text-sm font-medium mb-1">
            メールアドレス
          </label>
          <input
            id="email"
            type="email"
            value={profile.email}
            disabled
            className="w-full border rounded-md px-3 py-2 text-sm bg-gray-50 text-muted-foreground"
          />
          <p className="text-xs text-muted-foreground mt-1">
            メールアドレスは変更できません
          </p>
        </div>

        <div>
          <label htmlFor="full_name" className="block text-sm font-medium mb-1">
            表示名
          </label>
          <input
            id="full_name"
            name="full_name"
            type="text"
            defaultValue={profile.full_name ?? ''}
            placeholder="山田 太郎"
            className="w-full border rounded-md px-3 py-2 text-sm"
          />
        </div>

        {error && (
          <div className="bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
            {error}
          </div>
        )}

        {success && (
          <div className="bg-green-50 text-green-700 text-sm px-3 py-2 rounded-md">
            プロフィールを更新しました
          </div>
        )}

        <button
          type="submit"
          className="bg-primary text-primary-foreground px-4 py-2 rounded-md text-sm font-medium hover:bg-primary/90"
        >
          保存
        </button>
      </form>
    </div>
  )
}
```


## オンボーディングフロー

新規ユーザーがサインアップした後、組織の作成を促すオンボーディングフローを実装する。

```tsx
// src/app/onboarding/page.tsx
import { requireProfile } from '@/lib/auth'
import { redirect } from 'next/navigation'
import { OnboardingForm } from '@/components/auth/onboarding-form'

export default async function OnboardingPage() {
  const profile = await requireProfile()

  // オンボーディング完了済みの場合はダッシュボードにリダイレクト
  if (profile.onboarding_completed) {
    redirect('/dashboard')
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="w-full max-w-lg mx-auto px-4">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold">TaskFlowへようこそ</h1>
          <p className="text-muted-foreground mt-2">
            まずは組織を作成して、チームでのタスク管理を始めましょう。
          </p>
        </div>
        <OnboardingForm profile={profile} />
      </div>
    </div>
  )
}
```

オンボーディングの詳細な実装（組織の作成）は第5章で行う。ここでは、認証フローの一部としてオンボーディングの入り口を用意しておく。


## ダッシュボードレイアウトへの認証情報の組み込み

```tsx
// src/app/dashboard/layout.tsx
import { requireProfile } from '@/lib/auth'
import { DashboardNav } from '@/components/dashboard/nav'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const profile = await requireProfile()

  return (
    <div className="min-h-screen flex">
      {/* サイドバー */}
      <aside className="w-64 border-r bg-gray-50/50 p-4">
        <div className="mb-8">
          <a href="/dashboard" className="text-xl font-bold">
            TaskFlow
          </a>
        </div>
        <DashboardNav />
        {/* ユーザー情報 */}
        <div className="mt-auto pt-4 border-t">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-gray-200 overflow-hidden">
              {profile.avatar_url ? (
                <img src={profile.avatar_url} alt="" className="w-full h-full object-cover" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-xs font-bold text-gray-400">
                  {profile.full_name?.[0] || profile.email[0].toUpperCase()}
                </div>
              )}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">
                {profile.full_name || profile.email}
              </p>
              <p className="text-xs text-muted-foreground truncate">
                {profile.email}
              </p>
            </div>
          </div>
        </div>
      </aside>

      {/* メインコンテンツ */}
      <main className="flex-1 p-8">{children}</main>
    </div>
  )
}
```


## セキュリティのベストプラクティス

認証機能の実装にあたり、以下のセキュリティ対策を確認する。

### 1. サーバーサイドでの認証確認を徹底する

```typescript
// NG: クライアントサイドだけで認証チェック
// -> ブラウザのJavaScriptを無効にすれば回避できる

// OK: Server Component / Server Action で認証チェック
const { data: { user } } = await supabase.auth.getUser()
if (!user) {
  redirect('/login')
}
```

### 2. getUser()を使う（getSession()ではなく）

```typescript
// NG: getSession() はJWTを検証しないため、改ざんされたトークンを受け入れる可能性がある
const { data: { session } } = await supabase.auth.getSession()

// OK: getUser() はSupabaseサーバーにJWTの有効性を確認する
const { data: { user } } = await supabase.auth.getUser()
```

### 3. Service Roleキーをクライアントに公開しない

```typescript
// NG: クライアントサイドでservice_roleキーを使う
// NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY のようにしない

// OK: サーバーサイド専用のファイルでのみ使用
// src/lib/supabase/admin.ts は Server Component / Server Action からのみimport
```

### 4. OAuth のリダイレクトURLを制限する

Supabaseダッシュボードの「Authentication」>「URL Configuration」>「Redirect URLs」に、許可するURLのみを登録する。

```
# 開発環境
http://localhost:3000/auth/callback

# 本番環境
https://taskflow.example.com/auth/callback
```

### 5. レート制限

Supabase Authは、デフォルトでメール送信にレート制限が設定されている。本番環境では、ブルートフォース攻撃を防ぐために適切な制限を確認する。


## まとめ

本章で実装した認証機能を整理する。

| 機能 | 実装状態 |
|------|---------|
| サインアップ（メール/パスワード） | 完了 |
| ログイン（メール/パスワード） | 完了 |
| ログイン（Google OAuth） | 完了 |
| ログイン（GitHub OAuth） | 完了 |
| ログイン（Magic Link） | 完了 |
| パスワードリセット | 完了 |
| OAuthコールバック処理 | 完了 |
| Middleware（認証チェック） | 完了 |
| profilesテーブル（自動作成トリガー） | 完了 |
| プロフィール編集（表示名、アバター） | 完了 |
| オンボーディング（入り口） | 完了 |

認証はSaaSの基盤中の基盤だ。本章で構築した認証システムの上に、次章からテナント管理、プロジェクト管理、決済といったSaaS固有の機能を積み上げていく。

次章では、マルチテナント対応のデータベース設計に進む。SaaSの核心であるテナント間データ分離の設計と実装を行う。
