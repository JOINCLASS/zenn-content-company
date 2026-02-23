---
title: "AIリファクタリングの技法 -- 技術的負債を継続的に解消する"
free: false
---

# AIリファクタリングの技法 -- 技術的負債を継続的に解消する

## この章で学ぶこと

技術的負債は、ソフトウェア開発において避けられない現実だ。ビジネスのスピードを優先すれば、コードの品質は後回しになる。「後でリファクタリングする」と言いながら、その「後」は永遠に来ない。

筆者が6つのプロダクトを運営する中で、技術的負債の蓄積は切実な問題だった。1人で全プロダクトを保守する以上、コードの品質が低いとバグ対応に追われ、新機能の開発に時間を割けなくなる。

AIリファクタリングは、この悪循環を断ち切る武器だ。以前なら1日がかりだったリファクタリングが、AIの力を借りれば数時間で完了する。しかも、テストの裏付けのある安全なリファクタリングだ。

本章では以下を扱う。

1. リファクタリングの対象を特定する方法（コードスメル検出）
2. Claude Codeでの大規模リファクタリング（命名統一、パターン置換）
3. Cursorでの部分的リファクタリング（関数分割、型の改善）
4. 安全なリファクタリングのためのテスト戦略
5. 段階的リファクタリングの設計（一度に壊さない）
6. 実践例: モノリシックな500行コンポーネントを分割するフロー


## リファクタリングの対象を特定する -- コードスメル検出

### AIによるコードスメルの自動検出

リファクタリングで最も難しいのは、「何をリファクタリングすべきか」の判断だ。コードベースが大きいほど、問題箇所の特定自体に時間がかかる。

AIは、既知のコードスメル（コードの悪臭）パターンを自動検出できる。

**Claude Codeでの検出方法**:

```
> このプロジェクトのコードスメルを検出して。以下の観点で分析:
> 1. 長すぎる関数（50行以上）
> 2. 長すぎるファイル（300行以上）
> 3. 深すぎるネスト（4段以上）
> 4. 重複コード
> 5. anyの使用箇所
> 6. 未使用のexport
> 7. 循環依存
>
> 優先度（高/中/低）を付けて一覧化して。
```

Claude Codeは、サブエージェントを使ってプロジェクト全体を探索し、以下のようなレポートを生成する。

```markdown
## コードスメル検出レポート

### 優先度: 高
| ファイル | 行数 | 問題 | 推奨アクション |
|---------|------|------|-------------|
| src/features/dashboard/DashboardPage.tsx | 487行 | 長すぎるコンポーネント | ロジック分離、子コンポーネントへの分割 |
| src/lib/api-client.ts | 312行 | 長すぎるファイル、重複コード | 共通処理の抽出、モジュール分割 |
| src/features/payment/processPayment.ts | 89行の関数 | 長すぎる関数、深いネスト | 責務分割、早期return |

### 優先度: 中
| ファイル | 問題 | 推奨アクション |
|---------|------|-------------|
| src/types/api.ts | any が12箇所 | 適切な型の定義 |
| src/features/auth/useAuth.ts | 3箇所で同じバリデーションロジック | 共通関数に抽出 |
| src/components/Form/ | 4つのフォームで同じエラー表示パターン | 共通ErrorMessageコンポーネントに抽出 |

### 優先度: 低
| ファイル | 問題 | 推奨アクション |
|---------|------|-------------|
| src/lib/constants.ts | 未使用のexportが5つ | 削除 |
| src/hooks/useDebounce.ts | 命名が不明瞭（引数名dがdelay） | 引数名の改善 |
```

### 定量的な指標で優先度を判断する

コードスメルの検出だけでなく、リファクタリングの優先度を定量的に判断するための指標もAIに分析させることができる。

```
> 以下の指標で各モジュールをスコアリングして:
> 1. 変更頻度（git logから過去3ヶ月の変更回数）
> 2. バグ修正の回数（git logのcommitメッセージから"fix"を含むもの）
> 3. コードの複雑度（ネストの深さ、分岐数）
>
> 変更頻度が高く、バグ修正が多く、複雑度が高いモジュールが
> リファクタリングの最優先対象。
```

この「ホットスポット分析」は、リファクタリングのROI（投資対効果）を最大化するための有力な手法だ。変更頻度が高いモジュールをリファクタリングすれば、改善の効果が最も広く波及する。


## Claude Codeでの大規模リファクタリング

### 命名の統一

大規模なコードベースでは、時間の経過とともに命名規則がバラバラになりがちだ。同じ概念に対して複数の名前が使われていると、コードの読解が困難になる。

**Before**: 命名がバラバラ

```typescript
// ファイルによって異なる名前で同じ概念を参照
const usr = await getUser(id);          // user の省略形
const currentUser = await fetchUser(id); // 別の関数名
const userData = await loadUser(id);     // さらに別の関数名
```

**Claude Codeでの統一**:

```
> プロジェクト全体で「ユーザーデータの取得」に使われている関数名を
> 全て洗い出して。統一するべき名前を提案した上で、一括リネームして。
>
> ルール:
> - 取得関数は getXxx で統一
> - 変数名は省略しない（usr → user）
> - 型名は PascalCase（UserData → User）
```

Claude Codeは以下の手順を自律的に実行する。

1. サブエージェントがプロジェクト全体を探索し、該当する関数名・変数名を列挙
2. 統一案を提示してユーザーの承認を得る
3. 一括でリネームを実行
4. テストを実行して破壊がないことを確認

```
## 命名統一の提案

### 関数名の統一
| 現在の名前 | 統一後の名前 | 使用箇所数 |
|-----------|------------|-----------|
| getUser | getUser (変更なし) | 12箇所 |
| fetchUser | getUser | 8箇所 |
| loadUser | getUser | 3箇所 |
| findUser | getUserByEmail (用途が異なるため別名) | 5箇所 |

### 変数名の統一
| 現在の名前 | 統一後の名前 | 使用箇所数 |
|-----------|------------|-----------|
| usr | user | 7箇所 |
| currentUser | user (文脈上明らか) | 4箇所 |
| userData | user (型が User なので接尾辞不要) | 6箇所 |

承認しますか？ (y/n)
```

### パターン置換

特定のコードパターンを、プロジェクト全体で別のパターンに置換するのも、Claude Codeの得意分野だ。

**例: コールバック地獄をasync/awaitに変換**

```
> プロジェクト内の全ての .then() チェーンを async/await に変換して。
> 変換後にテストが全てパスすることを確認して。
```

**Before**:

```typescript
function createOrder(items: Item[]) {
  return validateItems(items)
    .then(validItems => calculateTotal(validItems))
    .then(total => applyDiscount(total))
    .then(discountedTotal => processPayment(discountedTotal))
    .then(payment => createOrderRecord(payment))
    .catch(error => {
      logger.error('Order creation failed', error);
      throw error;
    });
}
```

**After**:

```typescript
async function createOrder(items: Item[]): Promise<Order> {
  try {
    const validItems = await validateItems(items);
    const total = await calculateTotal(validItems);
    const discountedTotal = await applyDiscount(total);
    const payment = await processPayment(discountedTotal);
    return await createOrderRecord(payment);
  } catch (error) {
    logger.error('Order creation failed', error);
    throw error;
  }
}
```

### 型の厳格化 -- anyの撲滅

TypeScriptプロジェクトにおける `any` 型の存在は、型安全性を根本から損なう。Claude Codeはプロジェクト全体の `any` を検出し、適切な型に置換できる。

```
> プロジェクト内の全ての any を検出して。
> 各 any に対して、コードの使われ方から推論した適切な型を提案して。
> ただし、外部ライブラリの型定義が不完全で any が避けられない場合は除外して。
```

**Before**:

```typescript
async function fetchData(endpoint: string): Promise<any> {
  const response = await fetch(endpoint);
  const data: any = await response.json();
  return data;
}

function processItems(items: any[]) {
  return items.map((item: any) => ({
    id: item.id,
    name: item.name,
    price: item.price * 1.1,
  }));
}
```

**After**:

```typescript
interface ApiResponse<T> {
  data: T;
  status: number;
  message: string;
}

async function fetchData<T>(endpoint: string): Promise<ApiResponse<T>> {
  const response = await fetch(endpoint);
  const data: ApiResponse<T> = await response.json();
  return data;
}

interface OrderItem {
  id: string;
  name: string;
  price: number;
}

interface ProcessedItem {
  id: string;
  name: string;
  price: number;
}

function processItems(items: OrderItem[]): ProcessedItem[] {
  return items.map(item => ({
    id: item.id,
    name: item.name,
    price: item.price * 1.1,
  }));
}
```

Claude Codeは、関数の呼び出し元や戻り値の使われ方を分析して、適切な型を推論する。プロジェクト全体のコンテキストを持っているからこそ可能な作業だ。


## Cursorでの部分的リファクタリング

### 関数分割 -- Cmd+K でのインラインリファクタリング

Cursorは、コードの選択範囲に対するインラインリファクタリングに優れている。長い関数を選択して `Cmd+K` で「この関数を分割して」と指示するだけで、適切な粒度に分割してくれる。

**Before**: 1つの関数に複数の責務

```typescript
async function handleSubmit(formData: FormData) {
  // バリデーション（20行）
  const name = formData.get('name') as string;
  if (!name || name.length < 2) {
    setError('name', 'Name must be at least 2 characters');
    return;
  }
  const email = formData.get('email') as string;
  if (!email || !email.includes('@')) {
    setError('email', 'Invalid email address');
    return;
  }
  const phone = formData.get('phone') as string;
  if (phone && !/^\d{10,11}$/.test(phone)) {
    setError('phone', 'Invalid phone number');
    return;
  }

  // API呼び出し（15行）
  try {
    const response = await fetch('/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, email, phone }),
    });
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message);
    }
    const user = await response.json();

    // 後処理（10行）
    setUser(user);
    router.push('/dashboard');
    toast.success('Account created successfully');
  } catch (error) {
    if (error instanceof Error) {
      toast.error(error.message);
    } else {
      toast.error('An unexpected error occurred');
    }
  }
}
```

**Cursorへの指示**:

```
（関数全体を選択して Cmd+K）
> この関数を3つに分割して: バリデーション、API呼び出し、後処理。
> 各関数の責務を単一にして。
```

**After**: 責務ごとに分割

```typescript
interface UserFormData {
  name: string;
  email: string;
  phone: string;
}

function validateUserForm(formData: FormData): UserFormData | null {
  const name = formData.get('name') as string;
  if (!name || name.length < 2) {
    setError('name', 'Name must be at least 2 characters');
    return null;
  }

  const email = formData.get('email') as string;
  if (!email || !email.includes('@')) {
    setError('email', 'Invalid email address');
    return null;
  }

  const phone = formData.get('phone') as string;
  if (phone && !/^\d{10,11}$/.test(phone)) {
    setError('phone', 'Invalid phone number');
    return null;
  }

  return { name, email, phone };
}

async function createUser(data: UserFormData): Promise<User> {
  const response = await fetch('/api/users', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.message);
  }

  return response.json();
}

async function handleSubmit(formData: FormData) {
  const validatedData = validateUserForm(formData);
  if (!validatedData) return;

  try {
    const user = await createUser(validatedData);
    setUser(user);
    router.push('/dashboard');
    toast.success('Account created successfully');
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : 'An unexpected error occurred';
    toast.error(message);
  }
}
```

### Composerでの複数ファイルリファクタリング

Cursorの Composer は、複数ファイルにまたがるリファクタリングにも対応する。

```
# Composer に指示
src/components/Form/ 以下の4つのフォームコンポーネントで
同じエラー表示ロジックが重複している。
共通の FormErrorMessage コンポーネントを作成して、全てのフォームで使うように変更して。
```

Composerは差分をプレビューとして表示するため、変更内容を確認してから適用できる。


## 安全なリファクタリングのためのテスト戦略

### リファクタリングの鉄則: テストなしのリファクタリングは禁止

リファクタリングの定義は「外部から見た振る舞いを変えずに、内部構造を改善すること」だ。振る舞いが変わっていないことを保証するには、テストが不可欠だ。

前章で解説したAIテスト生成を活用すれば、リファクタリング前にテストを追加するコストは大幅に下がる。

### リファクタリング前のテスト追加ワークフロー

```
> src/features/dashboard/DashboardPage.tsx をリファクタリングしたい。
> まず、現在の振る舞いを記録する特性化テストを書いて。
> リファクタリング後にこのテストがパスすれば、
> 振る舞いが変わっていないことが保証される。
```

Claude Codeは、コンポーネントの現在の振る舞い（レンダリング結果、ユーザーインタラクション、状態遷移）を網羅するテストを生成する。

```typescript
// src/features/dashboard/__tests__/DashboardPage.characterization.test.tsx
describe('DashboardPage - 特性化テスト', () => {
  it('初期表示で今月のKPIサマリを表示する', async () => {
    render(<DashboardPage />);
    await waitFor(() => {
      expect(screen.getByText('Monthly Revenue')).toBeInTheDocument();
      expect(screen.getByText('Active Users')).toBeInTheDocument();
      expect(screen.getByText('Conversion Rate')).toBeInTheDocument();
    });
  });

  it('期間フィルタを変更するとデータが更新される', async () => {
    render(<DashboardPage />);
    await userEvent.selectOptions(
      screen.getByLabelText('Period'),
      'last-quarter'
    );
    await waitFor(() => {
      expect(mockFetchDashboardData).toHaveBeenCalledWith(
        expect.objectContaining({ period: 'last-quarter' })
      );
    });
  });

  // 現在のコンポーネントの全ての振る舞いを記録
  // (AIがコンポーネントを分析して自動生成)
});
```

### テスト - リファクタリング - テストのサイクル

安全なリファクタリングは、以下のサイクルで進める。

```
1. テストを追加（Green: 全テストパス）
    ↓
2. リファクタリング実行
    ↓
3. テスト実行（Green: 全テストパス → 振る舞い不変を確認）
    ↓
4. 次のリファクタリング → 2に戻る
```

各ステップの間でテストを実行し、グリーン（全テストパス）を維持する。もしテストが失敗したら、リファクタリングを巻き戻すか、修正する。


## 段階的リファクタリングの設計

### なぜ一度にやってはいけないのか

大規模なリファクタリングを1つのPRで行うと、以下の問題が発生する。

1. **レビューが困難**: 100ファイル以上の変更を含むPRは、まともにレビューできない
2. **問題の切り分けが困難**: テストが失敗した時に、どの変更が原因かを特定しにくい
3. **マージコンフリクト**: 他の開発者の変更と衝突しやすい
4. **ロールバックの粒度**: 問題が発覚した時に、全体を戻すか一部を戻すかの判断が難しい

### 段階的リファクタリングの設計方法

Claude Codeに段階的な計画を立てさせることで、安全なリファクタリングが可能になる。

```
> src/features/dashboard/DashboardPage.tsx（487行）を
> リファクタリングしたい。一度にやるとリスクが高いので、
> 以下のルールで段階的な計画を立てて:
>
> 1. 各ステップは1つのPRにまとめる
> 2. 各PRでの変更ファイル数は10ファイル以内
> 3. 各ステップの後でテストがグリーンであること
> 4. 各ステップが独立して意味を持つこと（途中で止めても壊れない）
```

Claude Codeが生成する計画の例:

```markdown
## DashboardPage リファクタリング計画

### Phase 1: カスタムフックの抽出（PR #1）
- DashboardPage内のデータ取得ロジックを useDashboardData フックに抽出
- 変更ファイル: 3ファイル（新規1、変更2）
- テスト: useDashboardData のユニットテストを追加
- 所要時間（AI支援）: 15分

### Phase 2: KPIカードコンポーネントの分離（PR #2）
- KPI表示部分を KPICard / KPISummary コンポーネントに分離
- 変更ファイル: 4ファイル（新規2、変更2）
- テスト: 各コンポーネントのテストを追加
- 所要時間（AI支援）: 20分

### Phase 3: チャートコンポーネントの分離（PR #3）
- グラフ表示部分を RevenueChart / UserChart コンポーネントに分離
- 変更ファイル: 4ファイル（新規2、変更2）
- テスト: 各コンポーネントのテストを追加
- 所要時間（AI支援）: 20分

### Phase 4: フィルタロジックの分離（PR #4）
- 期間フィルタのロジックを useDashboardFilter フックに抽出
- フィルタUIを DashboardFilter コンポーネントに分離
- 変更ファイル: 4ファイル（新規2、変更2）
- テスト: フックとコンポーネントのテストを追加
- 所要時間（AI支援）: 15分

### Phase 5: クリーンアップ（PR #5）
- DashboardPage を各コンポーネントの組み合わせとして再構成
- 不要なimport、未使用変数の削除
- 変更ファイル: 1ファイル
- テスト: 既存の特性化テストがパスすることを確認
- 所要時間（AI支援）: 10分

### 期待される結果
- Before: DashboardPage.tsx (487行)
- After: DashboardPage.tsx (45行) + 6つの子コンポーネント/フック
- 合計所要時間: 約1.5時間
```


## 実践例: モノリシックな500行コンポーネントを分割する

ここからは、上記の計画に基づいて、実際にリファクタリングを実行するフローを詳しく解説する。

### Before: 487行のモノリシックコンポーネント

```tsx
// src/features/dashboard/DashboardPage.tsx (487行 - 一部抜粋)
export default function DashboardPage() {
  const [period, setPeriod] = useState<'this-month' | 'last-quarter'>('this-month');
  const [data, setData] = useState<DashboardData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setIsLoading(true);
    fetch(`/api/dashboard?period=${period}`)
      .then(res => res.json())
      .then(data => {
        setData(data);
        setIsLoading(false);
      })
      .catch(err => {
        setError(err.message);
        setIsLoading(false);
      });
  }, [period]);

  if (isLoading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;
  if (!data) return null;

  // ここから400行以上のJSXが続く
  // KPI表示、グラフ、フィルタ、テーブル、アクションボタン等が
  // 全て1つのコンポーネント内に書かれている
  return (
    <div className="dashboard">
      {/* KPIサマリ (80行) */}
      <div className="kpi-summary">
        <div className="kpi-card">
          <h3>Monthly Revenue</h3>
          <p className="kpi-value">
            {new Intl.NumberFormat('ja-JP', {
              style: 'currency',
              currency: 'JPY',
            }).format(data.revenue)}
          </p>
          <p className={`kpi-change ${data.revenueChange >= 0 ? 'positive' : 'negative'}`}>
            {data.revenueChange >= 0 ? '+' : ''}{data.revenueChange}%
          </p>
        </div>
        {/* 同様のKPIカードがさらに3つ... */}
      </div>

      {/* グラフ (120行) */}
      {/* フィルタ (60行) */}
      {/* テーブル (100行) */}
      {/* アクションボタン (40行) */}
    </div>
  );
}
```

問題点は明白だ。

- 487行のファイルは読むだけで負荷が高い
- データ取得ロジック、表示ロジック、フィルタロジックが混在
- テストが書きにくい（全体をレンダリングしないとテストできない）
- 部分的な変更が全体に影響するリスク

### Phase 1: カスタムフックの抽出

**Claude Codeへの指示**:

```
> DashboardPage.tsx のデータ取得ロジック（useEffect + state管理）を
> useDashboardData カスタムフックに抽出して。
> フックのテストも書いて。
```

**After - カスタムフック**:

```typescript
// src/features/dashboard/hooks/useDashboardData.ts
import { useCallback, useEffect, useState } from 'react';

interface DashboardData {
  revenue: number;
  revenueChange: number;
  activeUsers: number;
  activeUsersChange: number;
  conversionRate: number;
  conversionRateChange: number;
  newSignups: number;
  newSignupsChange: number;
}

type Period = 'this-month' | 'last-quarter' | 'this-year';

interface UseDashboardDataReturn {
  data: DashboardData | null;
  isLoading: boolean;
  error: string | null;
  period: Period;
  setPeriod: (period: Period) => void;
  refetch: () => void;
}

export function useDashboardData(
  initialPeriod: Period = 'this-month'
): UseDashboardDataReturn {
  const [period, setPeriod] = useState<Period>(initialPeriod);
  const [data, setData] = useState<DashboardData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(`/api/dashboard?period=${period}`);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      const result = await response.json();
      setData(result);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      setError(message);
    } finally {
      setIsLoading(false);
    }
  }, [period]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data, isLoading, error, period, setPeriod, refetch: fetchData };
}
```

**After - テスト**:

```typescript
// src/features/dashboard/hooks/__tests__/useDashboardData.test.ts
import { renderHook, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { useDashboardData } from '../useDashboardData';

const mockDashboardData = {
  revenue: 1500000,
  revenueChange: 12.5,
  activeUsers: 350,
  activeUsersChange: 8.2,
  conversionRate: 3.4,
  conversionRateChange: -0.5,
  newSignups: 45,
  newSignupsChange: 15.0,
};

describe('useDashboardData', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
  });

  it('初期状態はローディング中', () => {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify(mockDashboardData))
    );

    const { result } = renderHook(() => useDashboardData());
    expect(result.current.isLoading).toBe(true);
    expect(result.current.data).toBeNull();
  });

  it('データ取得後にローディングが解除される', async () => {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify(mockDashboardData))
    );

    const { result } = renderHook(() => useDashboardData());

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
      expect(result.current.data).toEqual(mockDashboardData);
    });
  });

  it('エラー時にエラーメッセージを設定する', async () => {
    vi.mocked(fetch).mockRejectedValue(new Error('Network error'));

    const { result } = renderHook(() => useDashboardData());

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBe('Network error');
    });
  });
});
```

このPhaseだけで、DashboardPage.tsxから約50行のロジックが分離された。しかも、分離したフックには独立したテストが付いている。

### Phase 2: KPIカードコンポーネントの分離

```
> DashboardPage.tsx のKPI表示部分を KPICard と KPISummary コンポーネントに
> 分離して。テストも書いて。
```

**After - KPICardコンポーネント**:

```tsx
// src/features/dashboard/components/KPICard.tsx
interface KPICardProps {
  title: string;
  value: string;
  change: number;
  format?: 'currency' | 'percent' | 'number';
}

export function KPICard({ title, value, change }: KPICardProps) {
  const isPositive = change >= 0;

  return (
    <div className="kpi-card">
      <h3 className="kpi-title">{title}</h3>
      <p className="kpi-value">{value}</p>
      <p className={`kpi-change ${isPositive ? 'positive' : 'negative'}`}>
        {isPositive ? '+' : ''}{change}%
      </p>
    </div>
  );
}
```

```tsx
// src/features/dashboard/components/KPISummary.tsx
import { KPICard } from './KPICard';

interface KPISummaryProps {
  revenue: number;
  revenueChange: number;
  activeUsers: number;
  activeUsersChange: number;
  conversionRate: number;
  conversionRateChange: number;
  newSignups: number;
  newSignupsChange: number;
}

export function KPISummary(props: KPISummaryProps) {
  const formatCurrency = (value: number) =>
    new Intl.NumberFormat('ja-JP', {
      style: 'currency',
      currency: 'JPY',
    }).format(value);

  return (
    <div className="kpi-summary">
      <KPICard
        title="Monthly Revenue"
        value={formatCurrency(props.revenue)}
        change={props.revenueChange}
      />
      <KPICard
        title="Active Users"
        value={props.activeUsers.toLocaleString()}
        change={props.activeUsersChange}
      />
      <KPICard
        title="Conversion Rate"
        value={`${props.conversionRate}%`}
        change={props.conversionRateChange}
      />
      <KPICard
        title="New Signups"
        value={props.newSignups.toLocaleString()}
        change={props.newSignupsChange}
      />
    </div>
  );
}
```

### Phase 5: 最終形 -- DashboardPageの再構成

全てのPhaseを終えた後の DashboardPage は以下のようになる。

```tsx
// src/features/dashboard/DashboardPage.tsx (45行)
import { DashboardFilter } from './components/DashboardFilter';
import { KPISummary } from './components/KPISummary';
import { RevenueChart } from './components/RevenueChart';
import { UserChart } from './components/UserChart';
import { useDashboardData } from './hooks/useDashboardData';

export default function DashboardPage() {
  const { data, isLoading, error, period, setPeriod } = useDashboardData();

  if (isLoading) return <div role="status">Loading...</div>;
  if (error) return <div role="alert">Error: {error}</div>;
  if (!data) return null;

  return (
    <div className="dashboard">
      <h1>Dashboard</h1>
      <DashboardFilter period={period} onPeriodChange={setPeriod} />
      <KPISummary
        revenue={data.revenue}
        revenueChange={data.revenueChange}
        activeUsers={data.activeUsers}
        activeUsersChange={data.activeUsersChange}
        conversionRate={data.conversionRate}
        conversionRateChange={data.conversionRateChange}
        newSignups={data.newSignups}
        newSignupsChange={data.newSignupsChange}
      />
      <div className="charts">
        <RevenueChart data={data.revenueHistory} period={period} />
        <UserChart data={data.userHistory} period={period} />
      </div>
    </div>
  );
}
```

### Before/After の比較

| 指標 | Before | After | 改善 |
|------|--------|-------|------|
| DashboardPage.tsx の行数 | 487行 | 45行 | -91% |
| テストカバレッジ | 0% | 85% | +85pt |
| コンポーネント数 | 1（モノリシック） | 6（分割済み） | 責務が明確 |
| 再利用可能なコンポーネント | 0 | 4（KPICard等） | 他ページでも使える |
| データ取得ロジックのテスト可能性 | 不可（UIと密結合） | 可（フックとして独立） | テスト容易 |
| 変更時の影響範囲 | 全体 | 該当コンポーネントのみ | リスク低減 |
| 所要時間（AI支援） | -- | 約1.5時間 | 手動なら1-2日 |

487行のモノリシックコンポーネントが、45行のオーケストレーション層と5つの独立したコンポーネント/フックに分割された。各コンポーネントにはテストが付いており、将来の変更にも安全に対応できる。

これが、AIリファクタリングの実力だ。


## リファクタリングの習慣化 -- 「常時きれいに」を実現する

### スプリントにリファクタリング時間を組み込む

リファクタリングは、まとめてやるよりも**継続的に少しずつ**進めるほうが効果的だ。筆者は、開発時間の20%をリファクタリングに充てるルールを設けている。

```
週の開発時間: 40時間
├── 新機能開発: 24時間 (60%)
├── バグ修正: 8時間 (20%)
└── リファクタリング: 8時間 (20%)
```

AIのおかげで、この8時間でかなりの量のリファクタリングが可能だ。手動なら1-2個のモジュールが限界だが、AIを活用すれば5-10個のモジュールを改善できる。

### ボーイスカウトルール + AI

「来た時よりも美しく」というボーイスカウトルールは、ソフトウェア開発にも適用できる。ファイルに触れたら、ついでに小さな改善を加えるという習慣だ。

AIを使えば、この「ついで」の改善コストがほぼゼロになる。

```
> このファイルを修正したついでに、以下の小さな改善も行って:
> - 未使用のimportを削除
> - 変数名をより明確に
> - マジックナンバーを定数化
```

1回あたり1-2分の追加作業で、コードベースの品質が継続的に向上する。


## この章のまとめ

AIリファクタリングは、技術的負債の解消を「いつかやる大掛かりな作業」から「日常的に行う小さな改善」に変える。

1. **コードスメル検出**: Claude Codeがプロジェクト全体を分析し、リファクタリング対象を優先度付きで特定
2. **大規模リファクタリング**: Claude Codeの命名統一、パターン置換、型の厳格化で、プロジェクト全体の一貫性を確保
3. **部分的リファクタリング**: CursorのCmd+KとComposerで、関数分割やコンポーネント分離を手軽に実行
4. **テスト戦略**: リファクタリング前に特性化テストを追加し、振る舞いの不変を保証。テスト-リファクタリング-テストのサイクルを維持
5. **段階的アプローチ**: 一度にやらず、各ステップが独立して意味を持つPhaseに分割。各Phase後にテストがグリーンであることを確認
6. **習慣化**: 開発時間の20%をリファクタリングに充て、ボーイスカウトルール + AIで継続的に品質を向上

AIの支援により、リファクタリングのコストは劇的に下がった。テストの自動生成（第7章）と組み合わせれば、「テストを書いてからリファクタリングする」という理想的なフローが現実的な工数で実現できる。技術的負債を溜め込まず、常にきれいなコードベースを維持していこう。

---

次章では、MCPサーバーを活用したAIツールの拡張方法を解説する。AIコーディングツールをデフォルトの機能だけで使うのではなく、自社の開発フローに合わせてカスタマイズし、さらなる生産性向上を実現する方法を紹介する。
