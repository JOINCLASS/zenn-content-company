---
title: "コーディング規約の書き方"
---

# コーディング規約の書き方

CLAUDE.mdの中で最も頻繁に更新するのが、コーディング規約のセクションです。「Claude Codeにこう書いてほしい」というルールを追加していくことで、出力品質が徐々に上がっていきます。

この章では、言語・フレームワーク別にすぐ使えるコーディング規約の書き方を紹介します。

## 規約を書くときの原則

### 1. 具体的に書く

「きれいなコードを書く」は曖昧すぎます。具体的なルールに落とし込みましょう。

```markdown
# 曖昧な書き方
- きれいなコードを書く
- 適切なエラーハンドリングをする

# 具体的な書き方
- 関数は30行以内に収める。超える場合は分割する
- 外部API呼び出しはtry-catchで囲み、エラーはAppErrorクラスでラップする
```

### 2. 選択を排除する

AとBのどちらでもよい、という曖昧さを残すと、AIの出力が安定しません。

```markdown
# 曖昧
- interfaceまたはtypeで型を定義する

# 明確
- 型定義にはtypeを使う。interfaceは使わない
```

### 3. 例外を明示する

ルールに例外がある場合は、その条件を書きます。

```markdown
- 変数名は英語で書く。ただしi18nのキーは日本語を含めてよい
- any型は使わない。ただし外部ライブラリの型定義が不完全な場合は`// eslint-disable`付きで許可
```

## TypeScript規約サンプル

```markdown
## TypeScript規約

### 型
- `strict: true`を前提とする
- 型定義は`type`を使う。`interface`は外部ライブラリとの互換性が必要な場合のみ
- `any`は禁止。`unknown`を使い、型ガードで絞り込む
- ユニオン型は3つまで。それ以上はDiscriminated Unionパターンを使う

### 命名
- 変数・関数: camelCase
- 型・クラス: PascalCase
- 定数: UPPER_SNAKE_CASE（ファイルスコープの定数のみ）
- boolean変数: `is`, `has`, `can`, `should` プレフィックス

### 関数
- 純粋関数を優先する。副作用がある関数は名前で明示する（`saveUser`, `deleteFile`）
- 引数が3つ以上ならオブジェクト引数にする
- 戻り値の型は省略せず明示する

### インポート
- 相対パスは`@/`エイリアスを使う
- 未使用importは許可しない
- 型のみのインポートは`import type`を使う
```

## React規約サンプル

```markdown
## React規約

### コンポーネント
- 関数コンポーネントのみ使用
- `export default`は使わない。名前付きエクスポートのみ
- propsの型は同じファイル内で`type Props = { ... }`として定義
- children propが必要な場合は`React.PropsWithChildren<Props>`を使う

### 状態管理
- ローカル状態: `useState` / `useReducer`
- サーバー状態: TanStack Query
- グローバル状態: Zustand（必要最小限に抑える）
- URLパラメータで表現できる状態はURLで管理する

### パフォーマンス
- `useMemo`と`useCallback`は計測して必要と判明した場合のみ使う
- リストレンダリングは`key`に安定した一意値を使う（indexは禁止）
- 画像は`next/image`を使い、widthとheightを明示する

### テスト
- コンポーネントテストはTesting Libraryを使う
- `getByTestId`は最終手段。`getByRole`, `getByText`を優先する
- ユーザーイベントは`@testing-library/user-event`を使う
```

## バックエンドAPI規約サンプル

```markdown
## API設計規約

### エンドポイント
- RESTfulに設計する
- リソース名は複数形（`/users`, `/orders`）
- ネストは2階層まで（`/users/:id/orders` はOK、`/users/:id/orders/:orderId/items` はNG）
- アクションは動詞ではなくHTTPメソッドで表現する（`POST /orders` であって `/createOrder` ではない）

### レスポンス形式

成功時:
```json
{
  "data": { ... },
  "meta": { "total": 100, "page": 1 }
}
```

エラー時:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Email is required",
    "details": [...]
  }
}
```

### バリデーション
- リクエストボディはZodスキーマで検証する
- バリデーションエラーは400を返す
- スキーマは`schemas/`ディレクトリにリソース単位で配置する

### エラーハンドリング
- 400: バリデーションエラー
- 401: 未認証
- 403: 権限不足
- 404: リソース不存在
- 500: サーバーエラー（ユーザーに内部情報を漏らさない）
```

## データベース規約サンプル

```markdown
## データベース規約

### テーブル設計
- テーブル名: snake_case、複数形（`users`, `order_items`）
- カラム名: snake_case
- 主キー: `id`（UUIDv7）
- タイムスタンプ: `created_at`, `updated_at` を全テーブルに付与
- 論理削除: `deleted_at`（NULL = 有効、日時 = 削除済み）
- boolean カラム: `is_` プレフィックス（`is_active`, `is_verified`）

### マイグレーション
- マイグレーションファイルは自動生成されたものを使う（手動編集禁止）
- 破壊的変更（カラム削除、型変更）は新しいマイグレーションで段階的に行う
- シードデータは`seed.ts`に書く
```

## 規約の段階的な育て方

CLAUDE.mdの規約は、一度に完璧に書く必要はありません。以下のサイクルで育てていきます。

### ステップ1: 最低限のルールから始める

```markdown
## コーディング規約

- TypeScript strictモード
- テストを書く
- any禁止
```

### ステップ2: 不満が出たら追加する

Claude Codeの出力を見て「ここはこうしてほしい」と思ったら、そのルールを追加します。

例えば、Claude Codeがinterfaceを使ったコードを生成して、自分はtypeを使いたかったなら：

```markdown
- 型定義にはtypeを使う。interfaceは使わない
```

### ステップ3: 矛盾を整理する

ルールが20-30個を超えたら、矛盾がないか見直します。カテゴリ別にグルーピングし、重複を削除します。

## まとめ

- 規約は具体的に、選択肢を排除して書く
- 言語・フレームワーク別に整理する
- 最低限から始めて、不満をベースに育てる
- 矛盾がないか定期的に見直す
