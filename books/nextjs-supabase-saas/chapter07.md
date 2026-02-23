---
title: "ファイルアップロードとストレージ管理"
free: false
---

# ファイルアップロードとストレージ管理

## はじめに

SaaSアプリケーションにおいてファイルの管理は避けて通れない機能だ。ユーザーはプロジェクトにドキュメントを添付し、タスクにスクリーンショットを貼り付け、プロフィール画像をアップロードする。

本章では、Supabase Storageを使ってTaskFlowのファイル管理機能を構築する。具体的には以下を実装する。

1. ストレージバケットの設計とRLSポリシー
2. タスクへのファイル添付
3. ドラッグ&ドロップアップロード
4. ファイルプレビューとダウンロード
5. 画像のリサイズと最適化
6. プラン別のストレージ制限管理


## ストレージの設計

### バケット構成

TaskFlowでは、用途別に3つのバケットを作成する。

| バケット名 | 公開/非公開 | 用途 |
|-----------|-----------|------|
| `avatars` | 公開 | ユーザーのプロフィール画像 |
| `project-files` | 非公開 | タスクの添付ファイル、プロジェクトドキュメント |
| `tenant-assets` | 公開 | テナントのロゴ画像等 |

### ファイルパスの設計

アクセス制御のために、ファイルパスにテナントIDを含める。

```
avatars/
  └── {user_id}/
      └── avatar.{ext}

project-files/
  └── {tenant_id}/
      └── {project_id}/
          └── {task_id}/
              └── {timestamp}_{filename}

tenant-assets/
  └── {tenant_id}/
      └── logo.{ext}
```

### マイグレーション

```bash
supabase migration new create_storage_buckets
```

```sql
-- supabase/migrations/20260223000700_create_storage_buckets.sql

-- ========================================
-- バケット作成
-- ========================================

-- avatars バケット（公開）
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  TRUE,
  1048576,  -- 1MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
);

-- project-files バケット（非公開）
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'project-files',
  'project-files',
  FALSE,
  52428800,  -- 50MB
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain', 'text/csv', 'text/markdown',
    'application/zip', 'application/gzip'
  ]
);

-- tenant-assets バケット（公開）
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'tenant-assets',
  'tenant-assets',
  TRUE,
  2097152,  -- 2MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml']
);


-- ========================================
-- avatars バケットのRLSポリシー
-- ========================================
CREATE POLICY "Anyone can view avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Users can upload own avatar"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars' AND
    auth.uid()::text = (storage.foldername(name))[1]
  );

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


-- ========================================
-- project-files バケットのRLSポリシー
-- ========================================

-- テナントメンバーのみ閲覧可能
CREATE POLICY "Tenant members can view project files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'project-files' AND
    (storage.foldername(name))[1]::uuid IN (
      SELECT public.get_user_tenant_ids()
    )
  );

-- テナントメンバーのみアップロード可能
CREATE POLICY "Tenant members can upload project files"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'project-files' AND
    (storage.foldername(name))[1]::uuid IN (
      SELECT public.get_user_tenant_ids()
    )
  );

-- テナントメンバーのみ更新可能
CREATE POLICY "Tenant members can update project files"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'project-files' AND
    (storage.foldername(name))[1]::uuid IN (
      SELECT public.get_user_tenant_ids()
    )
  );

-- テナントのadmin以上が削除可能
CREATE POLICY "Admins can delete project files"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'project-files' AND
    public.get_user_role_in_tenant(
      (storage.foldername(name))[1]::uuid
    ) IN ('owner', 'admin')
  );


-- ========================================
-- tenant-assets バケットのRLSポリシー
-- ========================================
CREATE POLICY "Anyone can view tenant assets"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'tenant-assets');

CREATE POLICY "Admins can upload tenant assets"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'tenant-assets' AND
    public.get_user_role_in_tenant(
      (storage.foldername(name))[1]::uuid
    ) IN ('owner', 'admin')
  );

CREATE POLICY "Admins can update tenant assets"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'tenant-assets' AND
    public.get_user_role_in_tenant(
      (storage.foldername(name))[1]::uuid
    ) IN ('owner', 'admin')
  );

CREATE POLICY "Admins can delete tenant assets"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'tenant-assets' AND
    public.get_user_role_in_tenant(
      (storage.foldername(name))[1]::uuid
    ) IN ('owner', 'admin')
  );


-- ========================================
-- ファイルメタデータテーブル
-- ========================================
CREATE TABLE public.project_files (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  task_id UUID REFERENCES public.tasks(id) ON DELETE SET NULL,
  uploaded_by UUID NOT NULL REFERENCES auth.users(id),
  file_name TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_project_files_project ON public.project_files(project_id);
CREATE INDEX idx_project_files_task ON public.project_files(task_id);

ALTER TABLE public.project_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view project files metadata"
  ON public.project_files FOR SELECT
  USING (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Members can upload project files"
  ON public.project_files FOR INSERT
  WITH CHECK (tenant_id IN (SELECT public.get_user_tenant_ids()));

CREATE POLICY "Admins can delete project files metadata"
  ON public.project_files FOR DELETE
  USING (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
    OR uploaded_by = auth.uid()
  );
```


## ファイルアップロードのServer Action

```typescript
// src/app/dashboard/t/[slug]/projects/[projectId]/files/actions.ts
'use server'

import { createClient } from '@/lib/supabase/server'
import { getPlanLimits, type Plan } from '@/lib/plans'
import { revalidatePath } from 'next/cache'

// ファイルサイズのフォーマット
function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`
}

export async function uploadFile(
  tenantId: string,
  projectId: string,
  taskId: string | null,
  tenantSlug: string,
  formData: FormData
) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return { error: '認証が必要です' }

  const file = formData.get('file') as File

  if (!file || file.size === 0) {
    return { error: 'ファイルを選択してください' }
  }

  // テナントのプランを取得してストレージ制限をチェック
  const { data: tenant } = await supabase
    .from('tenants')
    .select('plan')
    .eq('id', tenantId)
    .single()

  if (!tenant) return { error: 'テナントが見つかりません' }

  const limits = getPlanLimits(tenant.plan as Plan)

  // 現在のストレージ使用量を計算
  const { data: files } = await supabase
    .from('project_files')
    .select('file_size')
    .eq('tenant_id', tenantId)

  const currentUsageMb = (files || []).reduce((sum, f) => sum + f.file_size, 0) / (1024 * 1024)

  const fileSizeMb = file.size / (1024 * 1024)

  if (currentUsageMb + fileSizeMb > limits.maxStorageMb) {
    return {
      error: `ストレージの上限（${limits.maxStorageMb}MB）を超えます。現在の使用量: ${formatFileSize(currentUsageMb * 1024 * 1024)}。プランをアップグレードしてください。`,
    }
  }

  // ファイルパスを生成
  const timestamp = Date.now()
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const basePath = taskId
    ? `${tenantId}/${projectId}/${taskId}`
    : `${tenantId}/${projectId}`
  const storagePath = `${basePath}/${timestamp}_${safeName}`

  // Supabase Storageにアップロード
  const { error: uploadError } = await supabase.storage
    .from('project-files')
    .upload(storagePath, file, {
      cacheControl: '3600',
      upsert: false,
    })

  if (uploadError) {
    return { error: `アップロードに失敗しました: ${uploadError.message}` }
  }

  // メタデータをDBに保存
  const { error: dbError } = await supabase
    .from('project_files')
    .insert({
      tenant_id: tenantId,
      project_id: projectId,
      task_id: taskId,
      uploaded_by: user.id,
      file_name: file.name,
      file_size: file.size,
      mime_type: file.type,
      storage_path: storagePath,
    })

  if (dbError) {
    // DB保存に失敗した場合、アップロードしたファイルを削除
    await supabase.storage.from('project-files').remove([storagePath])
    return { error: dbError.message }
  }

  // 活動ログ
  await supabase.from('activity_logs').insert({
    tenant_id: tenantId,
    user_id: user.id,
    action: 'upload_file',
    target_type: 'file',
    target_id: projectId,
    metadata: { file_name: file.name, file_size: file.size },
  })

  revalidatePath(`/dashboard/t/${tenantSlug}/projects/${projectId}`)
  return { success: true }
}

export async function deleteFile(
  fileId: string,
  storagePath: string,
  tenantSlug: string,
  projectId: string
) {
  const supabase = await createClient()

  // ストレージから削除
  const { error: storageError } = await supabase.storage
    .from('project-files')
    .remove([storagePath])

  if (storageError) {
    return { error: `ファイルの削除に失敗しました: ${storageError.message}` }
  }

  // メタデータを削除
  const { error: dbError } = await supabase
    .from('project_files')
    .delete()
    .eq('id', fileId)

  if (dbError) {
    return { error: dbError.message }
  }

  revalidatePath(`/dashboard/t/${tenantSlug}/projects/${projectId}`)
  return { success: true }
}

export async function getFileUrl(storagePath: string) {
  const supabase = await createClient()

  const { data, error } = await supabase.storage
    .from('project-files')
    .createSignedUrl(storagePath, 3600) // 1時間有効

  if (error) return { error: error.message }

  return { url: data.signedUrl }
}
```


## ドラッグ&ドロップアップロードコンポーネント

```tsx
// src/components/dashboard/file-uploader.tsx
'use client'

import { useState, useRef, useCallback } from 'react'
import { uploadFile } from '@/app/dashboard/t/[slug]/projects/[projectId]/files/actions'

export function FileUploader({
  tenantId,
  projectId,
  taskId,
  tenantSlug,
}: {
  tenantId: string
  projectId: string
  taskId?: string
  tenantSlug: string
}) {
  const [isDragging, setIsDragging] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleUpload = useCallback(async (files: FileList | null) => {
    if (!files || files.length === 0) return

    setUploading(true)
    setError(null)

    for (let i = 0; i < files.length; i++) {
      const file = files[i]
      setProgress(`${file.name} をアップロード中... (${i + 1}/${files.length})`)

      const formData = new FormData()
      formData.set('file', file)

      const result = await uploadFile(
        tenantId,
        projectId,
        taskId || null,
        tenantSlug,
        formData
      )

      if (result.error) {
        setError(result.error)
        break
      }
    }

    setUploading(false)
    setProgress(null)
  }, [tenantId, projectId, taskId, tenantSlug])

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    handleUpload(e.dataTransfer.files)
  }, [handleUpload])

  return (
    <div>
      <div
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={() => fileInputRef.current?.click()}
        className={`border-2 border-dashed rounded-lg p-8 text-center cursor-pointer transition-colors ${
          isDragging
            ? 'border-primary bg-primary/5'
            : 'border-gray-200 hover:border-gray-300'
        }`}
      >
        <input
          ref={fileInputRef}
          type="file"
          multiple
          className="hidden"
          onChange={(e) => handleUpload(e.target.files)}
        />

        {uploading ? (
          <div>
            <div className="animate-pulse text-primary mb-2">
              アップロード中...
            </div>
            {progress && (
              <p className="text-sm text-muted-foreground">{progress}</p>
            )}
          </div>
        ) : (
          <div>
            <p className="text-sm text-muted-foreground">
              ファイルをドラッグ&ドロップ、またはクリックして選択
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              最大50MBまで。複数ファイル対応。
            </p>
          </div>
        )}
      </div>

      {error && (
        <div className="mt-2 bg-red-50 text-red-700 text-sm px-3 py-2 rounded-md">
          {error}
        </div>
      )}
    </div>
  )
}
```


## ファイル一覧コンポーネント

```tsx
// src/components/dashboard/file-list.tsx
'use client'

import { useState } from 'react'
import { deleteFile, getFileUrl } from '@/app/dashboard/t/[slug]/projects/[projectId]/files/actions'

type FileItem = {
  id: string
  file_name: string
  file_size: number
  mime_type: string
  storage_path: string
  created_at: string
  uploaded_by: string
}

function formatSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`
}

function getFileIcon(mimeType: string): string {
  if (mimeType.startsWith('image/')) return 'image'
  if (mimeType === 'application/pdf') return 'pdf'
  if (mimeType.includes('spreadsheet') || mimeType.includes('excel')) return 'spreadsheet'
  if (mimeType.includes('document') || mimeType.includes('word')) return 'document'
  return 'file'
}

export function FileList({
  files,
  tenantSlug,
  projectId,
  canDelete,
}: {
  files: FileItem[]
  tenantSlug: string
  projectId: string
  canDelete: boolean
}) {
  const [loadingId, setLoadingId] = useState<string | null>(null)

  async function handleDownload(file: FileItem) {
    setLoadingId(file.id)
    const result = await getFileUrl(file.storage_path)

    if (result.url) {
      window.open(result.url, '_blank')
    }

    setLoadingId(null)
  }

  async function handleDelete(file: FileItem) {
    if (!confirm(`${file.file_name} を削除しますか？`)) return

    setLoadingId(file.id)
    await deleteFile(file.id, file.storage_path, tenantSlug, projectId)
    setLoadingId(null)
  }

  if (files.length === 0) {
    return (
      <p className="text-sm text-muted-foreground py-4">
        ファイルがありません
      </p>
    )
  }

  return (
    <div className="space-y-2">
      {files.map((file) => {
        const isLoading = loadingId === file.id
        const isImage = file.mime_type.startsWith('image/')

        return (
          <div
            key={file.id}
            className="flex items-center gap-3 border rounded-md p-3 hover:bg-gray-50"
          >
            {/* ファイルアイコン */}
            <div className="w-10 h-10 rounded bg-gray-100 flex items-center justify-center text-xs text-muted-foreground flex-shrink-0">
              {getFileIcon(file.mime_type)}
            </div>

            {/* ファイル情報 */}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{file.file_name}</p>
              <p className="text-xs text-muted-foreground">
                {formatSize(file.file_size)} ・{' '}
                {new Date(file.created_at).toLocaleDateString('ja-JP')}
              </p>
            </div>

            {/* アクション */}
            <div className="flex gap-2">
              <button
                onClick={() => handleDownload(file)}
                disabled={isLoading}
                className="text-xs text-primary hover:underline disabled:opacity-50"
              >
                ダウンロード
              </button>
              {canDelete && (
                <button
                  onClick={() => handleDelete(file)}
                  disabled={isLoading}
                  className="text-xs text-red-500 hover:underline disabled:opacity-50"
                >
                  削除
                </button>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}
```


## 画像プレビュー

Supabase Storageの画像変換機能を使ったサムネイル生成を実装する。

```typescript
// src/lib/storage.ts
import { createClient } from '@/lib/supabase/client'

export function getImageThumbnailUrl(
  storagePath: string,
  options: {
    width?: number
    height?: number
    quality?: number
  } = {}
) {
  const supabase = createClient()
  const { width = 200, height = 200, quality = 80 } = options

  // 公開バケットの場合
  const { data } = supabase.storage
    .from('avatars')
    .getPublicUrl(storagePath, {
      transform: {
        width,
        height,
        resize: 'cover',
        quality,
        format: 'webp',
      },
    })

  return data.publicUrl
}

// 非公開バケット用の署名付きURL（サーバーサイド）
export async function getSignedImageUrl(
  storagePath: string,
  options: {
    width?: number
    height?: number
    expiresIn?: number
  } = {}
) {
  const { createClient: createServerClient } = await import('@/lib/supabase/server')
  const supabase = await createServerClient()

  const { width = 400, height = 300, expiresIn = 3600 } = options

  const { data, error } = await supabase.storage
    .from('project-files')
    .createSignedUrl(storagePath, expiresIn, {
      transform: {
        width,
        height,
        resize: 'contain',
        quality: 80,
        format: 'webp',
      },
    })

  if (error) return null
  return data.signedUrl
}
```


## ストレージ使用量の表示

```tsx
// src/components/dashboard/storage-usage.tsx
import { createClient } from '@/lib/supabase/server'
import { getPlanLimits, type Plan } from '@/lib/plans'

function formatSize(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`
  return `${mb.toFixed(1)} MB`
}

export async function StorageUsage({ tenantId }: { tenantId: string }) {
  const supabase = await createClient()

  const { data: tenant } = await supabase
    .from('tenants')
    .select('plan')
    .eq('id', tenantId)
    .single()

  if (!tenant) return null

  const limits = getPlanLimits(tenant.plan as Plan)

  const { data: files } = await supabase
    .from('project_files')
    .select('file_size')
    .eq('tenant_id', tenantId)

  const usedBytes = (files || []).reduce((sum, f) => sum + f.file_size, 0)
  const usedMb = usedBytes / (1024 * 1024)
  const percentage = Math.min((usedMb / limits.maxStorageMb) * 100, 100)

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-sm">
        <span>ストレージ使用量</span>
        <span className="text-muted-foreground">
          {formatSize(usedMb)} / {formatSize(limits.maxStorageMb)}
        </span>
      </div>
      <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all ${
            percentage > 90 ? 'bg-red-500' : percentage > 70 ? 'bg-yellow-500' : 'bg-primary'
          }`}
          style={{ width: `${percentage}%` }}
        />
      </div>
      {percentage > 90 && (
        <p className="text-xs text-red-500">
          ストレージがほぼ満杯です。プランをアップグレードしてください。
        </p>
      )}
    </div>
  )
}
```


## セキュリティの考慮事項

### ファイル名のサニタイズ

ユーザーがアップロードするファイル名には、特殊文字やパストラバーサル攻撃用の文字列が含まれる可能性がある。

```typescript
function sanitizeFileName(name: string): string {
  return name
    .replace(/\.\./g, '') // パストラバーサル防止
    .replace(/[^a-zA-Z0-9._-]/g, '_') // 安全な文字のみ
    .replace(/_{2,}/g, '_') // 連続アンダースコアを1つに
    .slice(0, 255) // 長さ制限
}
```

### MIMEタイプの検証

クライアントから送られるMIMEタイプは信頼できないため、サーバーサイドでも検証する。Supabase Storageのバケット設定で `allowed_mime_types` を指定しているため、基本的な防御は実現されている。

### ウイルススキャン

本番環境では、アップロードされたファイルのウイルススキャンを検討する。ClamAVなどのオープンソースツールをEdge FunctionやWebhookと連携させる方法がある。


## まとめ

本章で実装したファイル管理機能を整理する。

| 機能 | 実装状態 |
|------|---------|
| バケット設計（avatars, project-files, tenant-assets） | 完了 |
| ストレージRLSポリシー | 完了 |
| ファイルメタデータテーブル | 完了 |
| ファイルアップロード（Server Action） | 完了 |
| ドラッグ&ドロップUI | 完了 |
| ファイル一覧・ダウンロード | 完了 |
| 画像サムネイル生成 | 完了 |
| ストレージ使用量表示 | 完了 |
| プラン別ストレージ制限 | 完了 |

実装のポイントを整理する。

1. **ファイルパスにテナントIDを含める**: RLSポリシーでテナント分離を実現
2. **メタデータはDBで管理**: ストレージのファイルとDBのメタデータを紐付け
3. **プラン制限はアップロード前にチェック**: 制限超過時は明確なエラーメッセージ
4. **非公開バケットには署名付きURL**: 一時的なURLでセキュアにアクセス

次章では、Stripe連携によるサブスクリプション決済の実装に進む。SaaSビジネスの心臓部だ。
