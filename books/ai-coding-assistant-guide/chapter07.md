---
title: "AIテスト生成の実践 -- テストカバレッジを劇的に向上させる"
free: false
---

# AIテスト生成の実践 -- テストカバレッジを劇的に向上させる

## この章で学ぶこと

「テストを書く時間がない」

これは、エンジニアが最も多く口にする言い訳の1つだろう。筆者も以前はそうだった。しかし、AIテスト生成を導入してから、この問題はほぼ解消された。

以前は1つの関数のテストを書くのに10-15分かかっていた。AIを使えば、同じテストが30秒-1分で生成される。しかも、人間が見落としがちなエッジケースまでカバーしてくれる。

6つのプロダクトを1人で運営する筆者にとって、AIテスト生成は「あると便利な機能」ではなく「なければ運営が成り立たない必須の仕組み」だ。

本章では以下を扱う。

1. ユニットテストの自動生成（Jest, Vitest, pytest等）
2. E2Eテストの自動生成（Playwright等）
3. エッジケースの自動発見
4. Claude Codeでのテスト一括生成ワークフロー
5. Cursorでのインラインテスト生成
6. Copilotでのテスト補完
7. TDD（テスト駆動開発）とAIの組み合わせ
8. 実践例: テストがないレガシーコードにテストを追加するフロー


## ユニットテストの自動生成

### 基本パターン: 関数のテスト

最もシンプルなケースから始めよう。純粋関数のユニットテストは、AIが最も得意とする領域だ。

以下のようなユーティリティ関数があるとする。

```typescript
// src/lib/price.ts
export function calculateDiscountedPrice(
  originalPrice: number,
  discountPercent: number,
  taxRate: number = 0.1
): number {
  if (originalPrice < 0) throw new Error('Price must be non-negative');
  if (discountPercent < 0 || discountPercent > 100) {
    throw new Error('Discount must be between 0 and 100');
  }

  const discounted = originalPrice * (1 - discountPercent / 100);
  const withTax = Math.round(discounted * (1 + taxRate));
  return withTax;
}
```

**Claude Codeへの指示**:

```
> src/lib/price.ts の calculateDiscountedPrice のテストを書いて。
> 正常系、異常系、境界値をカバーして。テストフレームワークはVitest。
```

**生成されるテスト**:

```typescript
// src/lib/__tests__/price.test.ts
import { describe, expect, it } from 'vitest';
import { calculateDiscountedPrice } from '../price';

describe('calculateDiscountedPrice', () => {
  // 正常系
  describe('正常な入力', () => {
    it('割引なし、デフォルト税率で計算する', () => {
      expect(calculateDiscountedPrice(1000, 0)).toBe(1100);
    });

    it('10%割引、デフォルト税率で計算する', () => {
      expect(calculateDiscountedPrice(1000, 10)).toBe(990);
    });

    it('50%割引、デフォルト税率で計算する', () => {
      expect(calculateDiscountedPrice(1000, 50)).toBe(550);
    });

    it('100%割引で0円になる', () => {
      expect(calculateDiscountedPrice(1000, 100)).toBe(0);
    });

    it('カスタム税率を適用する', () => {
      expect(calculateDiscountedPrice(1000, 0, 0.08)).toBe(1080);
    });

    it('端数を四捨五入する', () => {
      // 1000 * 0.67 * 1.1 = 737
      expect(calculateDiscountedPrice(1000, 33)).toBe(737);
    });
  });

  // 境界値
  describe('境界値', () => {
    it('価格0円を受け付ける', () => {
      expect(calculateDiscountedPrice(0, 50)).toBe(0);
    });

    it('割引率0%を受け付ける', () => {
      expect(calculateDiscountedPrice(1000, 0)).toBe(1100);
    });

    it('割引率100%を受け付ける', () => {
      expect(calculateDiscountedPrice(1000, 100)).toBe(0);
    });

    it('税率0%を受け付ける', () => {
      expect(calculateDiscountedPrice(1000, 10, 0)).toBe(900);
    });

    it('非常に大きな金額を処理する', () => {
      const result = calculateDiscountedPrice(999999999, 10);
      expect(result).toBe(989999999);
    });
  });

  // 異常系
  describe('異常な入力', () => {
    it('負の価格でエラーをスローする', () => {
      expect(() => calculateDiscountedPrice(-1, 10))
        .toThrow('Price must be non-negative');
    });

    it('負の割引率でエラーをスローする', () => {
      expect(() => calculateDiscountedPrice(1000, -1))
        .toThrow('Discount must be between 0 and 100');
    });

    it('100%超の割引率でエラーをスローする', () => {
      expect(() => calculateDiscountedPrice(1000, 101))
        .toThrow('Discount must be between 0 and 100');
    });
  });
});
```

注目すべきは、AIが**人間が見落としがちなケース**を自動的にカバーしている点だ。「非常に大きな金額」「端数の四捨五入」「割引率の境界値（0%と100%）」は、手動でテストを書く際に忘れがちだが、AIはこれらを体系的に網羅する。

### Reactコンポーネントのテスト

Reactコンポーネントのテストは、純粋関数のテストよりも複雑になる。レンダリング、ユーザーインタラクション、非同期処理のテストが必要だ。

```tsx
// src/components/UserProfileCard.tsx
interface UserProfileCardProps {
  userId: string;
  onEdit: () => void;
}

export function UserProfileCard({ userId, onEdit }: UserProfileCardProps) {
  const { data: user, isLoading, error } = useUser(userId);

  if (isLoading) return <div role="status">Loading...</div>;
  if (error) return <div role="alert">Failed to load user</div>;
  if (!user) return null;

  return (
    <div data-testid="user-profile-card">
      <img src={user.avatarUrl} alt={`${user.name}'s avatar`} />
      <h2>{user.name}</h2>
      <p>{user.email}</p>
      {user.isCurrentUser && (
        <button onClick={onEdit}>Edit Profile</button>
      )}
    </div>
  );
}
```

**Claude Codeへの指示**:

```
> src/components/UserProfileCard.tsx のテストを書いて。
> Testing Library + Vitest。useUser はモックして。
> ローディング、エラー、正常表示、編集ボタンの表示条件をテスト。
```

**生成されるテスト**:

```tsx
// src/components/__tests__/UserProfileCard.test.tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { UserProfileCard } from '../UserProfileCard';
import { useUser } from '@/hooks/useUser';

vi.mock('@/hooks/useUser');
const mockUseUser = vi.mocked(useUser);

const mockUser = {
  id: 'user-1',
  name: 'Alice',
  email: 'alice@example.com',
  avatarUrl: 'https://example.com/alice.jpg',
  isCurrentUser: false,
};

describe('UserProfileCard', () => {
  const defaultProps = {
    userId: 'user-1',
    onEdit: vi.fn(),
  };

  it('ローディング中はローディング表示を出す', () => {
    mockUseUser.mockReturnValue({
      data: undefined,
      isLoading: true,
      error: null,
    });

    render(<UserProfileCard {...defaultProps} />);
    expect(screen.getByRole('status')).toHaveTextContent('Loading...');
  });

  it('エラー時はエラーメッセージを表示する', () => {
    mockUseUser.mockReturnValue({
      data: undefined,
      isLoading: false,
      error: new Error('Network error'),
    });

    render(<UserProfileCard {...defaultProps} />);
    expect(screen.getByRole('alert')).toHaveTextContent('Failed to load user');
  });

  it('ユーザー情報を表示する', () => {
    mockUseUser.mockReturnValue({
      data: mockUser,
      isLoading: false,
      error: null,
    });

    render(<UserProfileCard {...defaultProps} />);

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('alice@example.com')).toBeInTheDocument();
    expect(screen.getByAltText("Alice's avatar")).toHaveAttribute(
      'src',
      'https://example.com/alice.jpg'
    );
  });

  it('自分のプロフィールの場合は編集ボタンを表示する', () => {
    mockUseUser.mockReturnValue({
      data: { ...mockUser, isCurrentUser: true },
      isLoading: false,
      error: null,
    });

    render(<UserProfileCard {...defaultProps} />);
    expect(screen.getByRole('button', { name: 'Edit Profile' }))
      .toBeInTheDocument();
  });

  it('他人のプロフィールの場合は編集ボタンを非表示にする', () => {
    mockUseUser.mockReturnValue({
      data: { ...mockUser, isCurrentUser: false },
      isLoading: false,
      error: null,
    });

    render(<UserProfileCard {...defaultProps} />);
    expect(screen.queryByRole('button', { name: 'Edit Profile' }))
      .not.toBeInTheDocument();
  });

  it('編集ボタンのクリックでonEditが呼ばれる', async () => {
    const onEdit = vi.fn();
    mockUseUser.mockReturnValue({
      data: { ...mockUser, isCurrentUser: true },
      isLoading: false,
      error: null,
    });

    render(<UserProfileCard {...defaultProps} onEdit={onEdit} />);
    await userEvent.click(
      screen.getByRole('button', { name: 'Edit Profile' })
    );
    expect(onEdit).toHaveBeenCalledOnce();
  });
});
```

AIが生成したテストは、Testing Libraryの推奨プラクティス（`getByRole`、`getByText`を優先的に使用）に従っている。また、モックの設定、各状態（ローディング/エラー/正常）のテスト、条件付きレンダリングのテストまでカバーしている。


## E2Eテストの自動生成

### Playwrightでのページ単位テスト

ユニットテストがコンポーネントや関数の単位で動作を検証するのに対し、E2Eテストはユーザーの操作フロー全体を検証する。

**Claude Codeへの指示**:

```
> ユーザー登録からログイン、プロフィール編集までのE2Eテストを書いて。
> Playwrightを使用。以下のフローをテスト:
> 1. /signup ページでメールアドレスとパスワードを入力して登録
> 2. 登録後、自動的にダッシュボードにリダイレクト
> 3. プロフィール編集ページで名前を変更して保存
> 4. ダッシュボードに戻ると変更された名前が表示されている
```

**生成されるテスト**:

```typescript
// e2e/user-registration-flow.spec.ts
import { expect, test } from '@playwright/test';

test.describe('ユーザー登録からプロフィール編集までのフロー', () => {
  const testEmail = `test-${Date.now()}@example.com`;
  const testPassword = 'SecureP@ssw0rd!';

  test('新規ユーザーが登録し、プロフィールを編集できる', async ({ page }) => {
    // Step 1: ユーザー登録
    await page.goto('/signup');
    await page.getByLabel('Email').fill(testEmail);
    await page.getByLabel('Password').fill(testPassword);
    await page.getByLabel('Confirm Password').fill(testPassword);
    await page.getByRole('button', { name: 'Sign Up' }).click();

    // Step 2: ダッシュボードにリダイレクトされる
    await expect(page).toHaveURL('/dashboard');
    await expect(page.getByRole('heading', { name: 'Dashboard' }))
      .toBeVisible();

    // Step 3: プロフィール編集
    await page.getByRole('link', { name: 'Profile' }).click();
    await expect(page).toHaveURL('/profile');

    await page.getByLabel('Display Name').fill('Alice');
    await page.getByRole('button', { name: 'Save' }).click();

    // 保存完了の通知を確認
    await expect(page.getByText('Profile updated successfully'))
      .toBeVisible();

    // Step 4: ダッシュボードで変更を確認
    await page.getByRole('link', { name: 'Dashboard' }).click();
    await expect(page.getByText('Alice')).toBeVisible();
  });

  test('無効なメールアドレスでは登録できない', async ({ page }) => {
    await page.goto('/signup');
    await page.getByLabel('Email').fill('invalid-email');
    await page.getByLabel('Password').fill(testPassword);
    await page.getByLabel('Confirm Password').fill(testPassword);
    await page.getByRole('button', { name: 'Sign Up' }).click();

    await expect(page.getByText('Please enter a valid email'))
      .toBeVisible();
    await expect(page).toHaveURL('/signup');
  });

  test('パスワードが一致しない場合は登録できない', async ({ page }) => {
    await page.goto('/signup');
    await page.getByLabel('Email').fill(testEmail);
    await page.getByLabel('Password').fill(testPassword);
    await page.getByLabel('Confirm Password').fill('DifferentPassword!');
    await page.getByRole('button', { name: 'Sign Up' }).click();

    await expect(page.getByText('Passwords do not match')).toBeVisible();
  });
});
```

### E2Eテスト生成のコツ

E2Eテストの生成では、以下の情報をAIに伝えると品質が上がる。

1. **ページのURL構造**: `/signup`, `/dashboard`, `/profile` 等
2. **フォームのラベル**: AIがアクセシビリティに配慮したセレクタを使えるようになる
3. **期待する動作**: リダイレクト先、表示されるメッセージ等
4. **テスト用データの戦略**: 固定値 vs 動的生成（`Date.now()` を使ったユニークなメール等）


## エッジケースの自動発見

AIテスト生成の最大の価値は、テストコード自体の生成ではなく、**人間が見落としがちなエッジケースの発見**にある。

### AIにエッジケースを探索させるプロンプト

```
> src/features/payment/calculateTotal.ts の関数を分析して、
> 考えられるエッジケースを全て列挙して。
> テストコードは書かなくてよい。まずはケース一覧だけ出して。
```

**AIの応答例**:

```markdown
## calculateTotal のエッジケース分析

### 入力値に関するエッジケース
1. 空の配列（商品が0個）
2. 商品が1個のみ
3. 商品が非常に多い（1000個以上）
4. 価格が0円の商品が含まれる
5. 価格が小数点以下を含む（例: $9.99 * 3 = $29.97の丸め）
6. 数量が0の商品が含まれる
7. 数量が非常に大きい（Integer.MAX_VALUE付近）

### 計算に関するエッジケース
8. 割引適用後の価格が負になるケース
9. 複数の割引が重複するケース
10. 税率が0%のケース（免税）
11. 合計金額がNumber.MAX_SAFE_INTEGERを超えるケース
12. 通貨の丸め（0.1 + 0.2 !== 0.3問題）

### ビジネスルールに関するエッジケース
13. クーポンコードが無効な場合
14. クーポンの利用回数上限に達している場合
15. 最低注文金額を下回る場合
16. 送料無料の閾値ちょうどの金額
```

この一覧を見て、テストが必要なケースを人間が選別する。全てをテストする必要はないが、一覧を網羅的に出してくれること自体に価値がある。

### 実際のエッジケーステスト

上記の分析結果から、特にリスクが高い項目のテストを生成させる。

```
> 上記のうち、項目5（小数の丸め）、8（割引後の負の価格）、12（浮動小数点精度）の
> テストを書いて。
```

```typescript
describe('calculateTotal - エッジケース', () => {
  describe('小数点の丸め', () => {
    it('$9.99 x 3 を正確に計算する', () => {
      const items = [{ price: 9.99, quantity: 3 }];
      // 9.99 * 3 = 29.97（浮動小数点誤差なし）
      expect(calculateTotal(items)).toBe(29.97);
    });

    it('$0.1 + $0.2 の浮動小数点問題を処理する', () => {
      const items = [
        { price: 0.1, quantity: 1 },
        { price: 0.2, quantity: 1 },
      ];
      // 0.1 + 0.2 = 0.3（0.30000000000000004ではなく）
      expect(calculateTotal(items)).toBe(0.3);
    });
  });

  describe('割引後の負の価格', () => {
    it('割引が商品価格を超える場合は0円にする', () => {
      const items = [{ price: 100, quantity: 1 }];
      const discount = 150; // 100円の商品に150円の割引
      expect(calculateTotal(items, { discount })).toBe(0);
    });
  });
});
```


## Claude Codeでのテスト一括生成ワークフロー

### プロジェクト全体のテストカバレッジ向上

Claude Codeの真の強みは、プロジェクト全体を俯瞰してテストを一括生成できる点にある。

**ワークフロー1: テスト未作成ファイルの洗い出し**

```
> このプロジェクトでテストが書かれていないモジュールを一覧化して。
> src/features/ と src/lib/ 以下の .ts ファイルについて、
> 対応する .test.ts が存在するかチェックして。
```

Claude Codeはファイルシステムを探索し、テストが不足しているファイルの一覧を返す。

```markdown
## テスト未作成ファイル一覧

### src/features/payment/ (0/4 テスト済み)
- [ ] calculateTotal.ts
- [ ] applyDiscount.ts
- [ ] validateCoupon.ts
- [ ] formatReceipt.ts

### src/features/auth/ (1/3 テスト済み)
- [x] validateEmail.ts (テストあり)
- [ ] generateToken.ts
- [ ] refreshSession.ts

### src/lib/ (2/5 テスト済み)
- [x] formatDate.ts (テストあり)
- [x] slugify.ts (テストあり)
- [ ] retry.ts
- [ ] rateLimit.ts
- [ ] cache.ts
```

**ワークフロー2: 一括テスト生成**

```
> テスト未作成のファイルのうち、src/features/payment/ 以下の4ファイルについて
> テストを一括生成して。各ファイルに対して、正常系、異常系、境界値をカバーして。
```

Claude Codeはサブエージェントを使い、4つのテストファイルを並行して生成する。各テストファイルは、対象モジュールの実装を読み取った上で、適切なテストケースを生成する。

### テスト生成後の検証フロー

テストを生成したら、必ず以下の手順で検証する。

```bash
# 1. テストが全てパスするか確認
npx vitest run

# 2. カバレッジを確認
npx vitest run --coverage

# 3. テストの品質を確認（Claude Codeに依頼）
```

```
> 生成したテストのカバレッジレポートを確認して。
> カバレッジが80%未満のファイルがあれば、追加のテストケースを提案して。
```

筆者のプロジェクトでは、この一括生成ワークフローにより、テストカバレッジを**42%から78%に1日で引き上げた**実績がある。手動で同じことをやろうとすれば、1-2週間はかかっただろう。


## Cursorでのインラインテスト生成

### Tab補完によるテスト生成

Cursorのインラインテスト生成は、日常的なコーディングの中で最も手軽に使える方法だ。

テストファイルを開き、`describe` ブロックの名前を書き始めると、Cursorが対象モジュールのコードを読み取り、テストケースを提案してくれる。

```typescript
// テストファイルを開いて入力を始める
import { slugify } from '../slugify';

describe('slugify', () => {
  // ここでTabを押すと、Cursorが以下を提案
  it('converts spaces to hyphens', () => {
    expect(slugify('hello world')).toBe('hello-world');
  });
  // さらにTabで次のテストケースも提案される
```

### Cmd+K でのテスト生成

特定の関数を選択して `Cmd+K` を押し、「テストを書いて」と指示する方法も有効だ。

```
（関数を選択した状態で Cmd+K）
> この関数のユニットテストを書いて。Vitestで。エッジケースも含めて。
```

Cursorはインラインで差分を提示し、承認するとテストファイルが生成される。

### Composerでの複数ファイルテスト生成

Composerを使えば、複数の関連ファイルのテストをまとめて生成できる。

```
# Composer に指示
src/features/auth/ 以下の全ファイルのテストを生成して。
既存の src/features/auth/__tests__/validateEmail.test.ts のスタイルに
合わせて書いて。
```

「既存のテストのスタイルに合わせて」と指示することで、テストの書き方がプロジェクト内で統一される。これは重要なポイントだ。AIが生成するテストは、指示なしだとツール独自のスタイルになりがちだが、既存のコードを参照させることで一貫性が保たれる。


## Copilotでのテスト補完

### インライン補完でのテスト生成

GitHub Copilotのテスト生成は、エディタ内のインライン補完として動作する。テストファイルを開いて `it(` と入力すると、テストケースの内容を提案してくれる。

```typescript
describe('formatDate', () => {
  it('formats date in YYYY-MM-DD format', () => {  // Copilotが提案
    expect(formatDate(new Date(2026, 0, 15))).toBe('2026-01-15');
  });

  it('handles single digit months', () => {  // 次のテストも提案
    expect(formatDate(new Date(2026, 2, 5))).toBe('2026-03-05');
  });
```

Copilotの強みは、コーディングのリズムを崩さずにテストを書ける点だ。Tabキーで補完を受け入れるだけで、テストケースが次々と生成される。

### Copilot Chatでのテスト生成

サイドパネルのCopilot Chatで、コードを選択して「テストを生成して」と指示することも可能だ。

```
/tests Generate comprehensive unit tests for the selected code
```

Copilotの `/tests` コマンドは、選択したコードのテストを自動生成する専用コマンドだ。通常のチャットよりもテスト生成に最適化された出力が得られる。

### 3ツールのテスト生成比較

| 特性 | Claude Code | Cursor | GitHub Copilot |
|------|------------|--------|---------------|
| テスト生成の深さ | 深い（プロジェクト全体を考慮） | 中程度（ファイル単位） | 浅い（関数単位） |
| エッジケースの網羅性 | 非常に高い | 高い | 中程度 |
| 一括生成 | 得意（サブエージェントで並行） | Composerで対応 | 1ファイルずつ |
| 生成速度 | やや遅い（深い分析） | 速い | 最速（インライン） |
| カスタマイズ | CLAUDE.mdでルール定義 | .cursorrulesで定義 | 限定的 |
| 最適なシーン | テストカバレッジの大幅改善 | 日常的なテスト追加 | コーディング中のテスト補完 |

使い分けの指針は明確だ。**大規模なテスト追加はClaude Code**、**日常のテスト作成はCursorまたはCopilot**、**コーディング中の手軽な補完はCopilot**という棲み分けが最も効率的だ。


## TDD（テスト駆動開発）とAIの組み合わせ

### AIがTDDを加速する理由

TDD（テスト駆動開発）は「テストを先に書き、テストが通るように実装する」という開発手法だ。理論的には優れたアプローチだが、「テストを先に書くのが面倒」「何をテストすべきかわからない」という理由で実践されないことが多い。

AIはこの2つの問題を解決する。テストの記述自体をAIに任せることで「面倒さ」が解消され、エッジケースの自動発見で「何をテストすべきか」が明確になる。

### AI-TDDのワークフロー

**ステップ1: 仕様をAIに伝え、テストを先に生成する**

```
> ユーザー招待機能を実装する。仕様は以下:
> - 既存ユーザーが他のユーザーをチームに招待できる
> - 招待にはメールアドレスを指定する
> - 招待メールが送信される
> - 既にチームに所属しているユーザーへの招待はエラーになる
> - 招待には有効期限（7日）がある
>
> まずテストだけを書いて。実装はまだ書かないで。
```

**AIが生成するテスト**:

```typescript
// src/features/invite/__tests__/inviteUser.test.ts
import { describe, expect, it, vi } from 'vitest';
import { inviteUser } from '../inviteUser';

// モックの定義
const mockSendEmail = vi.fn();
const mockFindUser = vi.fn();
const mockFindTeamMember = vi.fn();
const mockCreateInvite = vi.fn();

vi.mock('@/lib/email', () => ({ sendInviteEmail: mockSendEmail }));

describe('inviteUser', () => {
  const inviterUserId = 'user-1';
  const teamId = 'team-1';
  const inviteeEmail = 'bob@example.com';

  beforeEach(() => {
    vi.clearAllMocks();
    mockFindTeamMember.mockResolvedValue(null); // デフォルトは未所属
    mockCreateInvite.mockResolvedValue({
      id: 'invite-1',
      teamId,
      email: inviteeEmail,
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
    });
  });

  it('有効なメールアドレスで招待を作成する', async () => {
    const result = await inviteUser({
      inviterUserId,
      teamId,
      email: inviteeEmail,
    });

    expect(result.id).toBeDefined();
    expect(result.teamId).toBe(teamId);
    expect(result.email).toBe(inviteeEmail);
  });

  it('招待メールを送信する', async () => {
    await inviteUser({ inviterUserId, teamId, email: inviteeEmail });

    expect(mockSendEmail).toHaveBeenCalledWith(
      expect.objectContaining({
        to: inviteeEmail,
        teamId,
      })
    );
  });

  it('招待に7日間の有効期限を設定する', async () => {
    const before = Date.now();
    const result = await inviteUser({
      inviterUserId,
      teamId,
      email: inviteeEmail,
    });

    const expiresAt = new Date(result.expiresAt).getTime();
    const sevenDays = 7 * 24 * 60 * 60 * 1000;

    expect(expiresAt).toBeGreaterThanOrEqual(before + sevenDays - 1000);
    expect(expiresAt).toBeLessThanOrEqual(before + sevenDays + 1000);
  });

  it('既にチームに所属しているユーザーへの招待はエラーになる', async () => {
    mockFindTeamMember.mockResolvedValue({ userId: 'existing-user' });

    await expect(
      inviteUser({ inviterUserId, teamId, email: inviteeEmail })
    ).rejects.toThrow('User is already a member of this team');
  });

  it('無効なメールアドレスではエラーになる', async () => {
    await expect(
      inviteUser({ inviterUserId, teamId, email: 'invalid' })
    ).rejects.toThrow('Invalid email address');
  });
});
```

**ステップ2: テストが全てFailすることを確認**

```bash
npx vitest run src/features/invite/
# 全テストが FAIL になることを確認
```

**ステップ3: テストが通る実装をAIに生成させる**

```
> 上記のテストが全てパスするように inviteUser 関数を実装して。
```

このフローでは、**テストが仕様書の役割**を果たす。AIが生成した実装がテストを全てパスすれば、仕様通りに実装されたことが保証される。

### AI-TDDの利点

| 利点 | 説明 |
|------|------|
| 仕様の明確化 | テストを先に書くことで、仕様の曖昧さが事前に解消される |
| 安全なAI実装 | 「AIが生成したコードが正しいか」をテストで自動検証 |
| リファクタリングの安心感 | テストがある状態で実装を改善できる |
| ドキュメントとしてのテスト | テストコードが仕様書の代わりになる |


## 実践例: レガシーコードにテストを追加するフロー

最後に、最も需要の高いユースケースを取り上げる。「テストがないレガシーコードにテストを追加する」フローだ。

### 前提状況

500行のユーティリティモジュールがある。テストはゼロ。直接的なリファクタリングはリスクが高い。

```typescript
// src/lib/legacy-utils.ts (一部抜粋)
export function processOrder(order: any) {
  // 300行の複雑な処理...
  // 条件分岐が多い、型がany、副作用あり
}
```

### ステップ1: 現状の把握（Claude Code）

```
> src/lib/legacy-utils.ts を分析して。
> 1. 公開されている関数の一覧と、それぞれの役割
> 2. 各関数の入力と出力の型
> 3. 副作用（DB書き込み、API呼び出し等）の有無
> 4. テストの難易度（副作用の多さ、依存の複雑さ）
>
> テストは書かなくてよい。まず分析結果だけ出して。
```

Claude Codeが分析結果を返す。

```markdown
## legacy-utils.ts 分析結果

### 公開関数一覧
| 関数 | 役割 | 入力 | 出力 | 副作用 | テスト難易度 |
|------|------|------|------|--------|------------|
| processOrder | 注文処理全体 | any | any | DB書込、メール送信 | 高 |
| calculateShipping | 送料計算 | address, items | number | なし | 低 |
| validateAddress | 住所バリデーション | address | boolean | 外部API | 中 |
| formatInvoice | 請求書フォーマット | order | string | なし | 低 |
| applyPromotion | プロモーション適用 | order, code | order | DB読取 | 中 |
```

### ステップ2: 低リスクな関数からテストを追加

テスト難易度が「低」の関数（副作用なしの純粋関数）から始める。

```
> calculateShipping と formatInvoice のテストを書いて。
> この2つは副作用がないので、モック不要で直接テストできるはず。
> 現在の実装の振る舞いを「正」として、その振る舞いを記録するテスト
> （特性化テスト / characterization test）を書いて。
```

**特性化テスト**とは、既存コードの振る舞いを「記録」するためのテストだ。「正しい振る舞い」を定義するのではなく、「現在の振る舞い」を記録する。これにより、後のリファクタリングで意図しない振る舞いの変更があった場合に検出できる。

```typescript
// src/lib/__tests__/legacy-utils.characterization.test.ts
describe('calculateShipping - 特性化テスト', () => {
  it('国内配送で重量5kg以下は500円', () => {
    const result = calculateShipping(
      { country: 'JP', prefecture: 'Tokyo' },
      [{ weight: 2 }, { weight: 3 }]
    );
    expect(result).toBe(500);
  });

  it('国内配送で重量5kg超は1000円', () => {
    const result = calculateShipping(
      { country: 'JP', prefecture: 'Tokyo' },
      [{ weight: 3 }, { weight: 3 }]
    );
    expect(result).toBe(1000);
  });

  // AIが実装を読み取って、現在の振る舞いを全て記録
});
```

### ステップ3: 副作用のある関数のテスト

副作用のある関数は、モックを使ってテストする。

```
> applyPromotion のテストを書いて。
> DB読み取り（findPromotion）をモックして。
> 有効なプロモーション、期限切れ、使用回数上限超過のケースをテスト。
```

### ステップ4: 主要関数のテスト

最後に、最も複雑な `processOrder` のテストを追加する。

```
> processOrder のテストを書いて。
> 副作用（DB書込、メール送信）は全てモックする。
> この関数は300行あるので、以下のように段階的にテストを追加:
> 1. まず正常系（標準的な注文処理）のテストだけ
> 2. 次に異常系（在庫切れ、決済失敗等）のテスト
> 3. 最後にエッジケース
```

### ステップ5: カバレッジの確認

```bash
npx vitest run --coverage src/lib/legacy-utils.ts
```

```
> カバレッジレポートを確認して。
> カバー率が低い行（赤い行）を特定し、追加のテストケースを提案して。
```

### タイムライン

このフロー全体の所要時間を、手動とAI支援で比較する。

| ステップ | 手動 | AI支援 |
|---------|------|--------|
| 現状分析 | 2時間 | 5分 |
| 純粋関数のテスト（2関数） | 1時間 | 10分 |
| 副作用ありのテスト（2関数） | 2時間 | 20分 |
| 主要関数のテスト | 4時間 | 40分 |
| カバレッジ改善 | 2時間 | 15分 |
| **合計** | **11時間** | **1.5時間** |

AIを使うことで、レガシーコードへのテスト追加にかかる時間を**約85%削減**できる。これは、「テストを書く時間がない」という言い訳を根本から覆す数字だ。


## この章のまとめ

AIテスト生成は、テストに対するエンジニアの向き合い方を根本から変える。

1. **ユニットテスト**: 純粋関数からReactコンポーネントまで、AIは正常系、異常系、境界値を体系的にカバーしたテストを生成する
2. **E2Eテスト**: ユーザーフロー全体のPlaywrightテストも、仕様を伝えるだけで生成可能
3. **エッジケース発見**: AIの最大の価値は、人間が見落としがちなエッジケースを網羅的に列挙してくれること
4. **ツール使い分け**: 大規模テスト追加はClaude Code、日常はCursor、手軽な補完はCopilot
5. **TDDとの相性**: AIがテストの記述を引き受けることで、TDDの「面倒さ」が解消される
6. **レガシーコード対応**: 特性化テストから始める段階的アプローチで、安全にテストを追加

テストの作成コストが限りなくゼロに近づいた今、テストを書かない理由はもはやない。AIテスト生成を日常のワークフローに組み込み、テストカバレッジを戦略的に向上させていこう。

---

次章では、AIリファクタリングの技法を扱う。テストで安全網を張った上で、Claude Code、Cursor、GitHub Copilotを使って技術的負債を継続的に解消する具体的な手法を解説する。
