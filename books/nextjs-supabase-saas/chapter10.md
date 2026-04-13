---
title: "Row Level Security（RLS）-- データアクセス制御の設計"
free: false
---

# Row Level Security（RLS）-- データアクセス制御の設計

## はじめに

SaaSアプリケーションにおいて最も致命的なバグは、テナントAのデータがテナントBに見えてしまうことだ。これは顧客の信頼を一瞬で失う事故であり、場合によっては法的責任を問われる。

PostgreSQLのRow Level Security（RLS）は、この問題をデータベースレベルで根本的に解決する機能だ。アプリケーションコードにバグがあっても、RLSが最後の砦としてデータを守る。

本章では、第5章で設定した基本的なRLSポリシーを深掘りし、以下を解説する。

1. RLSの仕組みと動作原理
2. ポリシー設計のパターンとベストプラクティス
3. パフォーマンスの最適化
4. テストと検証の方法
5. よくある落とし穴とその回避策


## RLSの仕組み

### RLSとは何か

Row Level Security（RLS）は、PostgreSQLのネイティブ機能で、テーブルに対する行レベルのアクセス制御を実現する。通常のSQLの `WHERE` 句とは異なり、RLSはデータベースエンジン自体が強制するため、アプリケーションが意図的にバイパスすることはできない。

```sql
-- RLSが無効の場合
SELECT * FROM projects;
-- → 全テナントの全プロジェクトが返る

-- RLSが有効の場合
SELECT * FROM projects;
-- → 現在のユーザーが所属するテナントのプロジェクトのみが返る
-- （WHERE句を書かなくても自動的にフィルタされる）
```

### RLSの動作フロー

```
クライアント
    │
    │  SELECT * FROM projects
    │
    v
Supabase PostgREST
    │
    │  JWTからauth.uid()を解決
    │
    v
PostgreSQL
    │
    │  1. RLSが有効か確認
    │  2. 該当テーブルのポリシーを評価
    │  3. ポリシーのUSING句がTRUEの行のみ返す
    │
    v
結果: フィルタされた行のみ
```

### ポリシーの種類

| 操作 | USING句 | WITH CHECK句 |
|------|---------|-------------|
| SELECT | 読み取り可能な行を決定 | - |
| INSERT | - | 挿入可能な行を決定 |
| UPDATE | 更新対象の行を決定 | 更新後の値を検証 |
| DELETE | 削除可能な行を決定 | - |

**USING**: 既存の行に対するフィルタ。「どの行にアクセスできるか」
**WITH CHECK**: 新しい行（INSERTの場合）や更新後の行（UPDATEの場合）に対する検証。「どのような行を書き込めるか」

### 重要な概念: PERMISSIVE vs RESTRICTIVE

```sql
-- PERMISSIVE（デフォルト）: OR で結合される
-- ポリシーAまたはポリシーBのいずれかを満たせばアクセス可能
CREATE POLICY "policy_a" ON table FOR SELECT USING (condition_a);
CREATE POLICY "policy_b" ON table FOR SELECT USING (condition_b);
-- 結果: condition_a OR condition_b

-- RESTRICTIVE: AND で結合される
-- 全てのRESTRICTIVEポリシーを満たさなければアクセス不可
CREATE POLICY "policy_r" ON table AS RESTRICTIVE FOR SELECT USING (condition_r);
-- 結果: (condition_a OR condition_b) AND condition_r
```


## TaskFlowのRLSポリシー詳細設計

### 設計原則

1. **デフォルト拒否**: RLSを有効にした時点で、全てのアクセスがブロックされる。明示的に許可するポリシーのみがアクセスを開放する
2. **テナント分離の徹底**: 全テーブルで `tenant_id` によるフィルタを基本とする
3. **ロールベースの制御**: `owner` > `admin` > `member` の階層で権限を制御
4. **パフォーマンス意識**: JOINを避け、ヘルパー関数とインデックスを活用

### ヘルパー関数の設計

```sql
-- ========================================
-- 1. ユーザーが所属するテナントID一覧
-- ========================================
CREATE OR REPLACE FUNCTION public.get_user_tenant_ids()
RETURNS SETOF UUID
LANGUAGE sql
SECURITY DEFINER  -- 関数はテーブルオーナーの権限で実行
STABLE            -- 同じトランザクション内で結果が変わらない
SET search_path = public
AS $$
  SELECT tenant_id
  FROM public.tenant_members
  WHERE user_id = auth.uid()
$$;

-- ========================================
-- 2. ユーザーのテナント内でのロール
-- ========================================
CREATE OR REPLACE FUNCTION public.get_user_role_in_tenant(p_tenant_id UUID)
RETURNS public.tenant_role
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role
  FROM public.tenant_members
  WHERE tenant_id = p_tenant_id AND user_id = auth.uid()
  LIMIT 1
$$;

-- ========================================
-- 3. ユーザーがテナントのメンバーかどうか
-- ========================================
CREATE OR REPLACE FUNCTION public.is_tenant_member(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tenant_members
    WHERE tenant_id = p_tenant_id AND user_id = auth.uid()
  )
$$;
```

**SECURITY DEFINER** の理由: RLSポリシー内でヘルパー関数を呼ぶ場合、関数自体がRLSの影響を受けないようにする必要がある。`SECURITY DEFINER` を指定すると、関数はテーブルオーナー（通常 `postgres`）の権限で実行され、RLSをバイパスできる。

**STABLE** の理由: 同じトランザクション内で同じ引数に対して同じ結果を返すことをPostgreSQLに伝える。これにより、ポリシーの評価時に関数呼び出しの結果がキャッシュされ、パフォーマンスが向上する。


### ポリシー実装の詳細

#### tasksテーブルの例

```sql
-- SELECT: テナントメンバーは全タスクを閲覧可能
CREATE POLICY "tenant_members_select_tasks"
  ON public.tasks
  FOR SELECT
  USING (
    public.is_tenant_member(tenant_id)
  );

-- INSERT: テナントメンバーはタスクを作成可能
-- WITH CHECKで、正しいtenant_idとcreated_byを強制
CREATE POLICY "tenant_members_insert_tasks"
  ON public.tasks
  FOR INSERT
  WITH CHECK (
    public.is_tenant_member(tenant_id)
    AND created_by = auth.uid()
  );

-- UPDATE: テナントメンバーはタスクを更新可能
-- ただしtenant_idの変更は禁止
CREATE POLICY "tenant_members_update_tasks"
  ON public.tasks
  FOR UPDATE
  USING (
    public.is_tenant_member(tenant_id)
  )
  WITH CHECK (
    public.is_tenant_member(tenant_id)
    -- tenant_idが変更されていないことを確認
    -- （UPDATEのWITH CHECKは更新後の値に対して評価される）
  );

-- DELETE: admin以上のみ削除可能
CREATE POLICY "admins_delete_tasks"
  ON public.tasks
  FOR DELETE
  USING (
    public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
  );
```

#### commentsテーブルの例

```sql
-- 閲覧: テナントメンバーは全コメントを閲覧可能
CREATE POLICY "members_view_comments"
  ON public.comments
  FOR SELECT
  USING (public.is_tenant_member(tenant_id));

-- 作成: テナントメンバーはコメントを投稿可能
-- 自分のuser_idのみ設定可能
CREATE POLICY "members_create_comments"
  ON public.comments
  FOR INSERT
  WITH CHECK (
    public.is_tenant_member(tenant_id)
    AND user_id = auth.uid()
  );

-- 更新: 自分のコメントのみ更新可能
CREATE POLICY "own_comments_update"
  ON public.comments
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 削除: 自分のコメント or admin以上
CREATE POLICY "own_or_admin_delete_comments"
  ON public.comments
  FOR DELETE
  USING (
    user_id = auth.uid()
    OR public.get_user_role_in_tenant(tenant_id) IN ('owner', 'admin')
  );
```


## パフォーマンスの最適化

### RLSのパフォーマンス問題

RLSポリシーは全てのクエリに対して評価される。ポリシーが非効率だと、全てのデータアクセスが遅くなる。

```sql
-- NG: サブクエリでJOINが発生する非効率なポリシー
CREATE POLICY "bad_policy" ON public.tasks
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tenant_members tm
      JOIN public.tenants t ON t.id = tm.tenant_id
      WHERE tm.user_id = auth.uid()
      AND tm.tenant_id = tasks.tenant_id
      AND t.plan != 'suspended'
    )
  );

-- OK: インデックスが効くシンプルなポリシー
CREATE POLICY "good_policy" ON public.tasks
  FOR SELECT
  USING (
    public.is_tenant_member(tenant_id)
  );
```

### インデックス戦略

RLSポリシーで使用されるカラムには、必ずインデックスを作成する。

```sql
-- tenant_members テーブル（RLSの基盤）
CREATE INDEX idx_tenant_members_user_tenant
  ON public.tenant_members(user_id, tenant_id);

-- 各テーブルのtenant_id
CREATE INDEX idx_tasks_tenant_id ON public.tasks(tenant_id);
CREATE INDEX idx_projects_tenant_id ON public.projects(tenant_id);
CREATE INDEX idx_comments_tenant_id ON public.comments(tenant_id);
```

### EXPLAIN ANALYZEでの確認

```sql
-- RLSポリシー込みのクエリ実行計画を確認
-- 認証されたユーザーとして実行する
SET request.jwt.claim.sub = 'user-uuid-here';

EXPLAIN ANALYZE
SELECT * FROM public.tasks
WHERE project_id = 'project-uuid-here'
ORDER BY created_at DESC
LIMIT 20;
```

Seq Scan（シーケンシャルスキャン）が発生している場合、インデックスが不足している可能性がある。


## テストと検証

### RLSポリシーのテスト

RLSが正しく機能していることを検証するためのテストを書く。

```sql
-- supabase/tests/rls_test.sql

-- テスト用ユーザーの作成
-- User A: Tenant 1のowner
-- User B: Tenant 1のmember
-- User C: Tenant 2のowner（Tenant 1にはアクセスできないはず）

-- テスト1: User CはTenant 1のプロジェクトを見えない
SET request.jwt.claim.sub = 'user-c-uuid';
SET role = 'authenticated';

SELECT count(*) FROM public.projects
WHERE tenant_id = 'tenant-1-uuid';
-- 期待結果: 0

-- テスト2: User AはTenant 1のプロジェクトを見える
SET request.jwt.claim.sub = 'user-a-uuid';

SELECT count(*) FROM public.projects
WHERE tenant_id = 'tenant-1-uuid';
-- 期待結果: > 0

-- テスト3: User Bはタスクを削除できない（memberロール）
SET request.jwt.claim.sub = 'user-b-uuid';

DELETE FROM public.tasks
WHERE id = 'some-task-uuid';
-- 期待結果: 0 rows affected（RLSでブロック）

-- テスト4: User Aはタスクを削除できる（ownerロール）
SET request.jwt.claim.sub = 'user-a-uuid';

DELETE FROM public.tasks
WHERE id = 'some-task-uuid';
-- 期待結果: 1 row affected
```

### pgTAPを使った自動テスト

```sql
-- supabase/tests/rls_test.sql (pgTAP形式)
BEGIN;

SELECT plan(4);

-- Tenant 1のオーナーとして認証
SET request.jwt.claim.sub = 'user-a-uuid';
SET role = 'authenticated';

-- テスト: 自分のテナントのプロジェクトが見える
SELECT ok(
  (SELECT count(*) FROM public.projects WHERE tenant_id = 'tenant-1-uuid') > 0,
  'Owner can see own tenant projects'
);

-- テスト: 他のテナントのプロジェクトが見えない
SELECT is(
  (SELECT count(*) FROM public.projects WHERE tenant_id = 'tenant-2-uuid'),
  0::bigint,
  'Owner cannot see other tenant projects'
);

-- Tenant 2のオーナーに切り替え
SET request.jwt.claim.sub = 'user-c-uuid';

-- テスト: Tenant 1のプロジェクトが見えない
SELECT is(
  (SELECT count(*) FROM public.projects WHERE tenant_id = 'tenant-1-uuid'),
  0::bigint,
  'Other tenant owner cannot see tenant 1 projects'
);

-- テスト: 自分のテナントのプロジェクトが見える
SELECT ok(
  (SELECT count(*) FROM public.projects WHERE tenant_id = 'tenant-2-uuid') > 0,
  'Tenant 2 owner can see own projects'
);

SELECT * FROM finish();
ROLLBACK;
```


## よくある落とし穴

### 1. RLSを有効にし忘れる

新しいテーブルを作成したときに `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` を忘れると、全データが公開される。

```sql
-- 対策: テーブル作成時に必ずRLSを有効にする
CREATE TABLE public.new_table (...);
ALTER TABLE public.new_table ENABLE ROW LEVEL SECURITY;
-- さらにポリシーを追加してから使い始める
```

**Supabase CLI のチェック**: `supabase db lint` コマンドでRLSが有効でないテーブルを検出できる。

### 2. service_role キーの誤使用

`service_role` キーはRLSをバイパスする。このキーをクライアントサイドで使うと、全てのRLSが無意味になる。

```typescript
// NG: クライアントで service_role キーを使う
// NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY を使ってはいけない

// OK: サーバーサイドのみで使用
// src/lib/supabase/admin.ts はServer ActionやRoute Handlerからのみimport
```

### 3. JOINを使ったポリシーのパフォーマンス低下

```sql
-- NG: JOINが重い
CREATE POLICY "slow" ON tasks FOR SELECT
USING (
  tenant_id IN (
    SELECT tm.tenant_id
    FROM tenant_members tm
    JOIN profiles p ON p.id = tm.user_id
    WHERE tm.user_id = auth.uid()
    AND p.onboarding_completed = true
  )
);

-- OK: 必要最小限のサブクエリ
CREATE POLICY "fast" ON tasks FOR SELECT
USING (
  public.is_tenant_member(tenant_id)
);
-- onboarding_completedのチェックはアプリ層で行う
```

### 4. INSERT時のtenant_idの不正操作

ユーザーが他のテナントのIDを指定してデータを作成しようとする攻撃を防ぐ。

```sql
-- WITH CHECKでtenant_idの正当性を検証
CREATE POLICY "check_tenant_on_insert" ON public.tasks
FOR INSERT
WITH CHECK (
  -- ユーザーが指定したtenant_idに所属していることを確認
  public.is_tenant_member(tenant_id)
);
```

### 5. UPDATE時のtenant_id変更

悪意のあるユーザーがUPDATE文でtenant_idを変更し、データを他テナントに移す攻撃を防ぐ。

```sql
-- USINGとWITH CHECKの両方で検証
CREATE POLICY "prevent_tenant_change" ON public.tasks
FOR UPDATE
USING (public.is_tenant_member(tenant_id))
WITH CHECK (public.is_tenant_member(tenant_id));
-- UPDATEの場合、USINGは更新前の行、WITH CHECKは更新後の行に対して評価される
-- 両方でis_tenant_memberをチェックすれば、tenant_idの変更は不可能
```

### 6. Realtimeのフィルタリング

Supabase Realtimeは、RLSポリシーに基づいてイベントをフィルタリングする。ただし、`filter` パラメータで追加のフィルタリングを行わないと、テナント内の全イベントが配信される可能性がある。

```typescript
// フィルタを指定してサブスクライブ
const channel = supabase
  .channel('tasks')
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'tasks',
      filter: `project_id=eq.${projectId}`, // 必要なデータのみ
    },
    handler
  )
  .subscribe()
```


## RLSの全体マトリクス

TaskFlowの全テーブルのRLSポリシーをマトリクスで整理する。

| テーブル | SELECT | INSERT | UPDATE | DELETE |
|---------|--------|--------|--------|--------|
| profiles | 全ユーザー（限定列）| トリガー自動 | 自分のみ | - |
| tenants | メンバー | 認証ユーザー | owner/admin | - |
| tenant_members | メンバー | owner/admin (+自己追加) | owner/admin | owner/admin (+自己退会) |
| invitations | メンバー | owner/admin | - | owner/admin |
| projects | メンバー | メンバー | メンバー | owner/admin |
| tasks | メンバー | メンバー | メンバー | owner/admin |
| comments | メンバー | メンバー | 投稿者のみ | 投稿者 or admin |
| project_files | メンバー | メンバー | - | アップロード者 or admin |
| activity_logs | メンバー | メンバー | - | - |


## 本番環境でのRLS監査

定期的にRLSの状態を監査するクエリを紹介する。

```sql
-- 1. RLSが無効なテーブルの一覧
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'public'
AND NOT EXISTS (
  SELECT 1 FROM pg_class
  WHERE relname = tablename
  AND relrowsecurity = true
);

-- 2. ポリシーが未設定のテーブル（RLSは有効だが全アクセスブロック状態）
SELECT c.relname AS table_name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
AND c.relkind = 'r'
AND c.relrowsecurity = true
AND NOT EXISTS (
  SELECT 1 FROM pg_policy
  WHERE polrelid = c.oid
);

-- 3. 全ポリシーの一覧
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual AS using_expression,
  with_check AS check_expression
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```


## 実務で得たRLS設計の教訓

筆者が複数のSaaSプロダクトでRLSを運用してきた中で、最も痛い教訓を共有する。

**RLSポリシーのテスト不足が本番障害を引き起こした事例**: あるプロダクトで新しいテーブルを追加した際、RLSポリシーのテストが不十分なまま本番にデプロイした。結果、特定の条件下でテナント間のデータが閲覧可能な状態が数時間続いた。幸い、影響範囲は限定的だったが、顧客への謝罪と原因報告が必要になった。

この経験から得た教訓は以下の3点である。

1. **RLSポリシーは必ずpgTAPでテストを書く**: 手動確認だけでは見落としが発生する。特に「ポリシーが存在しない＝全拒否」と「ポリシーが間違っている＝意図しないアクセス許可」の区別が重要である
2. **CI/CDにRLSテストを組み込む**: マイグレーション適用後にRLSテストを自動実行し、テナント分離が壊れていないことを毎回検証する
3. **ステージング環境で複数テナントのテストデータを用意する**: 単一テナントのテストだけではテナント間分離の問題を検出できない


## まとめ

本章で学んだRLSの設計原則を整理する。

1. **全テーブルでRLSを有効にする**: 例外なく、全テーブルで有効にする
2. **ヘルパー関数を活用する**: `SECURITY DEFINER` + `STABLE` で効率的かつ安全に
3. **非正規化してtenant_idを各テーブルに持たせる**: JOINを避けてパフォーマンスを確保
4. **INSERTのWITH CHECKを忘れない**: 不正なtenant_idでのデータ作成を防ぐ
5. **UPDATEのWITH CHECKでtenant_id変更を防ぐ**: USINGとWITH CHECKの両方で検証
6. **テストを書く**: pgTAPや手動テストでポリシーの正当性を検証
7. **定期的に監査する**: RLSが無効なテーブルやポリシー未設定のテーブルをチェック

RLSはSaaSのセキュリティの最後の砦だ。「アプリケーションコードを信頼しない」という前提で、データベースレベルでアクセス制御を強制することが、マルチテナントSaaSの安全性を担保する。

次章では、本番環境へのデプロイと運用について解説する。
