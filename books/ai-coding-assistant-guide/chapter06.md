---
title: "AIによるコードレビュー自動化 -- レビューの質とスピードを両立する"
free: false
---

# AIによるコードレビュー自動化 -- レビューの質とスピードを両立する

## この章で学ぶこと

コードレビューは、ソフトウェア開発における品質の最後の砦だ。しかし、多くの開発現場では「レビューがボトルネックになっている」「形式的なレビューに終わりがち」という課題を抱えている。

筆者が1人で6つのプロダクトを運営する中で、コードレビューの問題は切実だった。自分で書いたコードを自分でレビューするのは、どうしても甘くなる。かといって、外部のレビュアーを雇う余裕はない。

AIコードレビューは、この問題を劇的に改善した。AIは疲れず、見落とさず、バイアスなくコードを検査してくれる。

本章では以下を扱う。

1. 3ツールそれぞれのレビュー機能の比較
2. Claude Codeでの深いコードレビュー（プロジェクト全体を踏まえたレビュー）
3. GitHub Copilotの自動PRレビュー・要約機能
4. Cursorでのインラインレビュー
5. レビュー観点の体系化（セキュリティ、パフォーマンス、可読性、テスト網羅性）
6. 実践例: 実際のPRをAIでレビューするフロー（Before/After）
7. AIレビューと人間レビューの使い分け


## 3ツールのレビュー機能比較

まず、3つのツールがどのようなレビュー機能を提供しているかを整理する。

| 機能 | Claude Code | Cursor | GitHub Copilot |
|------|------------|--------|---------------|
| PRレビュー | プロジェクト全体の文脈を踏まえたレビュー | Composer経由で差分レビュー | GitHub上のネイティブPRレビュー |
| レビュー範囲 | リポジトリ全体（依存関係含む） | 開いているファイル + @codebase | PRの差分ファイル |
| セキュリティチェック | CLAUDE.mdでルール定義可能 | ルール定義で対応 | 組み込みのセキュリティスキャン |
| PR要約の自動生成 | 可能（プロンプトで指示） | 可能 | ネイティブ対応 |
| レビューコメントの生成 | 可能（GitHub連携で） | エディタ内で提案 | GitHub上にコメント |
| CI/CD連携 | スクリプトで統合可能 | 限定的 | GitHub Actions連携 |
| カスタムルール | CLAUDE.mdで詳細定義 | .cursorrulesで定義 | 設定ファイルで限定的に |

3ツールは、レビューの「深さ」と「自動化の容易さ」で異なるポジションを占めている。Claude Codeは深いが手動トリガー、GitHub Copilotは浅いが全自動、Cursorはその中間という位置づけだ。


## Claude Codeでの深いコードレビュー

### Claude Codeレビューの強み

Claude Codeのレビューが他のツールと一線を画す理由は、**プロジェクト全体のコンテキストを踏まえたレビュー**ができる点にある。

単に「このコードにバグがある」と指摘するだけでなく、「このプロジェクトでは認証にSupabase Authを使っているが、この実装ではRLS（Row Level Security）が考慮されていない」といった、プロジェクト固有の文脈を理解した指摘が可能だ。

### 基本的なレビューの流れ

最もシンプルなレビュー方法は、gitの差分をClaude Codeに渡すことだ。

```bash
# Claude Code を起動して差分をレビュー依頼
claude

> git diff main...feature/user-profile をレビューして。
> セキュリティ、パフォーマンス、可読性の観点で問題があれば指摘して。
```

Claude Codeは以下のステップを自律的に実行する。

1. `git diff` で差分を取得
2. 変更されたファイルの周辺コード（変更箇所が依存しているモジュール）を読み取り
3. CLAUDE.mdに定義されたコーディング規約と照合
4. レビューコメントを生成

### CLAUDE.md にレビュールールを定義する

レビューの品質を安定させるには、CLAUDE.mdにレビュー観点を明示しておくのが有効だ。

```markdown
## コードレビュールール

レビュー時は以下の観点で検査すること:

### セキュリティ
- ユーザー入力のバリデーションが行われているか
- SQLインジェクション、XSS、CSRF対策がされているか
- 認証・認可チェックが適切か（Supabase RLSの確認を含む）
- シークレット情報がハードコードされていないか
- 依存パッケージに既知の脆弱性がないか

### パフォーマンス
- N+1クエリが発生していないか
- 不要な再レンダリングが起きていないか（React）
- 大量データの取得にページネーションが実装されているか
- メモリリークの原因になる処理がないか

### 可読性
- 関数名・変数名が意図を正確に表しているか
- 関数の責務が単一か（1つの関数が多くのことをしていないか）
- ネストが3段以上になっていないか
- マジックナンバーが定数化されているか

### テスト
- 変更箇所に対応するテストが追加されているか
- エッジケース（空配列、null、境界値）がテストされているか
- テストが実装の詳細に依存していないか（振る舞いをテストしているか）
```

### サブエージェントを使った並行レビュー

大規模なPR（10ファイル以上の変更）では、サブエージェントを活用した並行レビューが有効だ。

```
> このPRをレビューして。変更ファイルが多いので、以下のように分担して。
> 1. セキュリティ観点でのレビュー
> 2. パフォーマンス観点でのレビュー
> 3. テスト網羅性のチェック
> 4. コーディング規約への準拠チェック
```

Claude Codeはこの指示を受けて、4つのサブエージェントを起動し、それぞれの観点でレビューを並行実行する。結果は統合されて1つのレビューレポートとして返ってくる。

筆者の経験では、10ファイル以上のPRでサブエージェントを使うと、レビュー時間が約40%短縮された。

### 実践的なレビュープロンプト例

日常的に使っているレビュープロンプトの例を紹介する。

**新機能のレビュー**:

```
> feature/payment-integration ブランチの変更をレビューして。
> 特に以下に注意:
> - Stripe APIの呼び出しがエラーハンドリングされているか
> - 決済金額の計算に丸め誤差がないか
> - テストでモックが適切に使われているか
```

**リファクタリングのレビュー**:

```
> refactor/auth-module ブランチの変更をレビューして。
> このPRは認証モジュールのリファクタリング。
> 機能的な変更はなく、コード構造の改善のみのはず。
> 振る舞いが変わっていないことを確認して。
```

**緊急修正のレビュー**:

```
> hotfix/null-pointer ブランチの変更をレビューして。
> 本番で発生しているnullポインタエラーの修正。
> 修正が適切か、他に同様の問題がないかも確認して。
```


## GitHub Copilotの自動PRレビュー・要約機能

### PR要約の自動生成

GitHub Copilotは、Pull Requestを作成する際に変更内容の要約を自動生成する機能を提供している。

この機能は特にチーム開発で威力を発揮する。レビュアーがPRを開いた瞬間に「このPRは何を目的としているか」「どのファイルがどう変わったか」が一目でわかるからだ。

要約は以下のような構造で生成される。

```markdown
## Summary
This PR adds user profile editing functionality.

### Changes
- **src/features/profile/ProfileForm.tsx**: New component for profile editing
- **src/features/profile/useProfile.ts**: Custom hook for profile data fetching
- **src/app/api/profile/route.ts**: API endpoint for profile updates
- **src/lib/validation.ts**: Added profile validation schema

### Key decisions
- Used react-hook-form for form state management
- Implemented optimistic updates for better UX
- Added Zod validation schema shared between client and server
```

### Copilotによるコードレビュー

GitHub Copilotのコードレビュー機能は、PR上で直接動作する。PRの差分を分析し、問題のある箇所にインラインコメントを付与する。

**Copilotレビューが検出する主な問題**:

| カテゴリ | 検出例 |
|---------|--------|
| バグの可能性 | 未処理のnull/undefined、条件分岐の漏れ |
| セキュリティ | ハードコードされた認証情報、未サニタイズの入力 |
| パフォーマンス | 非効率なループ、不要な再計算 |
| ベストプラクティス | 非推奨APIの使用、型安全性の欠如 |

### GitHub Actionsとの連携

Copilotのレビューは、GitHub Actionsと連携することで、PRが作成されるたびに自動的に実行される。

```yaml
# .github/workflows/copilot-review.yml
name: Copilot Code Review

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  pull-requests: write
  contents: read

# GitHub Copilot のレビューはGitHub側の設定で有効化
# リポジトリ Settings > Code review > Copilot
```

リポジトリの設定画面でCopilotレビューを有効にすると、PRが作成されるたびに自動レビューが走る。CIのテストやリンターと併せて、レビュープロセスの最初のフィルターとして機能する。

### Copilotレビューの限界

Copilotレビューは便利だが、以下の限界がある。

1. **プロジェクト全体の文脈の理解が浅い**: PRの差分ファイルを中心に分析するため、プロジェクト全体のアーキテクチャとの整合性は十分にチェックできない
2. **カスタムルールの定義が限定的**: CLAUDE.mdのような詳細なルール定義はできない
3. **ビジネスロジックの正当性**: 「仕様通りに実装されているか」の判断は苦手

これらの限界を補うために、Claude Codeとの併用が有効だ。


## Cursorでのインラインレビュー

### Cursorレビューの特徴

Cursorのレビュー機能は、エディタ内でのインラインレビューに特化している。コードを書いている最中に、リアルタイムで問題を指摘してくれる点が特徴だ。

### 具体的な使い方

**選択範囲のレビュー**:

コードを選択して `Cmd+K`（macOS）/ `Ctrl+K`（Windows/Linux）を押し、「このコードをレビューして」と入力する。

```typescript
// レビュー対象のコード
async function fetchUserData(userId: string) {
  const response = await fetch(`/api/users/${userId}`);
  const data = await response.json();
  return data;
}
```

Cursorは以下のような指摘を返す。

```
問題点:
1. エラーハンドリングがない。fetchが失敗した場合の処理が必要
2. response.ok のチェックがない。4xx/5xxレスポンスが処理されない
3. 戻り値の型が any になる。型安全性の確保が必要

改善案:
```

```typescript
async function fetchUserData(userId: string): Promise<User> {
  const response = await fetch(`/api/users/${userId}`);

  if (!response.ok) {
    throw new ApiError(
      `Failed to fetch user: ${response.status}`,
      response.status
    );
  }

  const data: User = await response.json();
  return data;
}
```

**Composerを使ったPRレビュー**:

Cursorの Composer 機能で、git の差分を含めたレビューも可能だ。

```
# Composer に以下のように指示
@codebase git diff main...HEAD の変更をレビューして。
セキュリティとパフォーマンスの問題を中心に指摘して。
```

`@codebase` を付けることで、プロジェクト全体の構造を考慮したレビューが行われる。ただし、Claude Codeほどの深い文脈理解は期待できない。

### Cursorレビューの活用シーン

Cursorのレビューは以下のシーンで特に有効だ。

| シーン | 使い方 |
|--------|-------|
| コーディング中のセルフチェック | 書いたばかりのコードを選択してレビュー依頼 |
| ペアプログラミングの代替 | AIに「ペアプロ相手」としてコードを見てもらう |
| 学習目的 | 自分のコードのどこが改善できるかを知りたい時 |
| 小規模な変更のクイックレビュー | 数ファイルの変更をエディタ内で素早くレビュー |


## レビュー観点の体系化

AIレビューの品質を安定させるには、レビュー観点を体系的に整理し、チェックリストとして運用することが重要だ。

### セキュリティレビュー

セキュリティは最も優先度の高いレビュー観点だ。AIはパターンマッチングが得意なため、セキュリティ上の定型的な問題を見逃しにくい。

**チェック項目と具体例**:

```typescript
// NG: SQLインジェクションの脆弱性
const query = `SELECT * FROM users WHERE id = '${userId}'`;

// OK: パラメータ化クエリ
const { data } = await supabase
  .from('users')
  .select('*')
  .eq('id', userId);
```

```typescript
// NG: XSSの脆弱性（dangerouslySetInnerHTMLの不用意な使用）
function Comment({ html }: { html: string }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />;
}

// OK: サニタイズ処理を挟む
import DOMPurify from 'dompurify';

function Comment({ html }: { html: string }) {
  const sanitized = DOMPurify.sanitize(html);
  return <div dangerouslySetInnerHTML={{ __html: sanitized }} />;
}
```

```typescript
// NG: シークレットのハードコード
const STRIPE_SECRET = 'sk_live_xxxxxxxxxxxxx';

// OK: 環境変数から取得
const STRIPE_SECRET = process.env.STRIPE_SECRET_KEY;
if (!STRIPE_SECRET) {
  throw new Error('STRIPE_SECRET_KEY is not defined');
}
```

### パフォーマンスレビュー

パフォーマンスの問題は、開発中は気づきにくく、本番でユーザー数が増えてから顕在化する。AIレビューで早期に発見することが重要だ。

```typescript
// NG: N+1クエリ（ユーザーごとにプロフィールを個別取得）
async function getUsersWithProfiles(userIds: string[]) {
  const users = await db.users.findMany({ where: { id: { in: userIds } } });
  // N回のクエリが発生
  for (const user of users) {
    user.profile = await db.profiles.findUnique({ where: { userId: user.id } });
  }
  return users;
}

// OK: JOINまたはバッチ取得
async function getUsersWithProfiles(userIds: string[]) {
  const users = await db.users.findMany({
    where: { id: { in: userIds } },
    include: { profile: true },
  });
  return users;
}
```

```tsx
// NG: 不要な再レンダリング（毎回新しいオブジェクトを生成）
function UserList({ users }: { users: User[] }) {
  return (
    <div>
      {users.map(user => (
        <UserCard
          key={user.id}
          user={user}
          style={{ marginBottom: 16 }}  // 毎回新しいオブジェクト
          onClick={() => handleClick(user.id)}  // 毎回新しい関数
        />
      ))}
    </div>
  );
}

// OK: メモ化で再レンダリングを抑制
const cardStyle = { marginBottom: 16 };

function UserList({ users }: { users: User[] }) {
  const handleClick = useCallback((userId: string) => {
    // クリック処理
  }, []);

  return (
    <div>
      {users.map(user => (
        <UserCard
          key={user.id}
          user={user}
          style={cardStyle}
          onClick={handleClick}
        />
      ))}
    </div>
  );
}
```

### 可読性レビュー

可読性は長期的な保守コストに直結する。AIは命名の不適切さやネストの深さを機械的に検出できる。

```typescript
// NG: 不明瞭な命名、深いネスト
function proc(d: any[]) {
  const r: any[] = [];
  for (let i = 0; i < d.length; i++) {
    if (d[i].status === 'active') {
      if (d[i].type === 'premium') {
        if (d[i].balance > 0) {
          r.push(d[i]);
        }
      }
    }
  }
  return r;
}

// OK: 明確な命名、早期continueでフラット化
function filterActivePremiumUsers(users: User[]): User[] {
  return users.filter(user => {
    if (user.status !== 'active') return false;
    if (user.type !== 'premium') return false;
    if (user.balance <= 0) return false;
    return true;
  });
}
```

### テスト網羅性レビュー

変更に対応するテストが追加されているかどうかも、レビューの重要な観点だ。

```typescript
// レビュー時のチェックポイント

// 1. 正常系のテストがあるか
test('creates user with valid data', async () => {
  const user = await createUser({ name: 'Alice', email: 'alice@example.com' });
  expect(user.name).toBe('Alice');
});

// 2. エッジケースのテストがあるか
test('rejects empty name', async () => {
  await expect(createUser({ name: '', email: 'alice@example.com' }))
    .rejects.toThrow('Name is required');
});

// 3. 境界値のテストがあるか
test('accepts name with exactly 100 characters', async () => {
  const longName = 'a'.repeat(100);
  const user = await createUser({ name: longName, email: 'alice@example.com' });
  expect(user.name).toBe(longName);
});

test('rejects name with 101 characters', async () => {
  const tooLongName = 'a'.repeat(101);
  await expect(createUser({ name: tooLongName, email: 'alice@example.com' }))
    .rejects.toThrow('Name is too long');
});
```


## 実践例: 実際のPRをAIでレビューするフロー

ここからは、筆者が実際に運用しているAIレビューのフローを、Before/After形式で紹介する。

### Before: AIレビュー導入前のフロー

```
1. 開発者がコードを書く（30分）
2. セルフレビュー（5分、形式的）
3. PR作成（5分）
4. レビュアーにアサイン（待ち時間: 数時間〜1日）
5. レビュアーがレビュー（15分）
6. 指摘対応（10分）
7. 再レビュー（5分）
8. マージ

合計: 70分の作業 + 数時間〜1日の待ち時間
```

問題点は明白だ。レビュアーの空き時間に依存するため、待ち時間が長い。しかも、レビュアーが忙しいと形式的なレビューで通してしまうことがある。

### After: AIレビュー導入後のフロー

```
1. 開発者がコードを書く（30分）
2. Claude Codeで深いレビュー（2分）
3. 指摘対応・修正（10分）
4. PR作成（5分）
   ↓ 自動で並行実行
   ├── GitHub Copilotが要約を生成
   └── GitHub CopilotがPRレビュー
5. 人間レビュアーがAIレビュー結果を踏まえてレビュー（5分）
6. マージ

合計: 52分の作業 + 最小限の待ち時間
```

### 具体的なフローの詳細

**ステップ1: 実装完了後、Claude Codeでレビュー**

```bash
claude

> git diff main...HEAD をレビューして。以下の観点で問題があれば指摘して。
> 1. セキュリティ（認証・認可、入力バリデーション）
> 2. パフォーマンス（N+1クエリ、不要な再レンダリング）
> 3. 可読性（命名、ネストの深さ、関数の責務）
> 4. テスト（変更に対応するテストがあるか）
> 5. プロジェクト規約（CLAUDE.mdに定義されたルール）への準拠
```

**ステップ2: AIの指摘を確認し、修正**

Claude Codeから以下のようなレビュー結果が返ってくる。

```markdown
## レビュー結果

### 重要度: 高
1. **src/app/api/users/route.ts:23**
   認証チェックがありません。このエンドポイントはログイン済みユーザーのみ
   アクセス可能にすべきです。
   ```typescript
   // 修正案
   const session = await getServerSession();
   if (!session) {
     return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
   }
   ```

### 重要度: 中
2. **src/features/users/UserList.tsx:45**
   useEffect内でAPIを呼んでいますが、依存配列にqueryが含まれていません。
   queryが変わってもデータが更新されません。
   ```typescript
   // 修正案
   useEffect(() => {
     fetchUsers(query);
   }, [query]);  // queryを依存配列に追加
   ```

### 重要度: 低
3. **src/lib/utils.ts:12**
   関数名 `proc` が何を処理するか不明です。
   `formatUserDisplayName` のような具体的な名前に変更を推奨します。
```

重要度「高」の指摘は必ず対応し、「中」は可能な限り対応、「低」はタスクの優先度に応じて判断する。

**ステップ3: PR作成後、CopilotとClaude Codeで最終チェック**

修正後にPRを作成すると、GitHub Copilotが自動で要約を生成し、レビューを実行する。人間レビュアーは、AIが事前に検出した問題が解決されていることを前提に、ビジネスロジックの正当性やアーキテクチャの整合性に集中してレビューできる。

### 数値で見る導入効果

筆者の実プロジェクトでの測定結果を共有する。

| 指標 | Before | After | 改善率 |
|------|--------|-------|-------|
| レビュー待ち時間（平均） | 4時間 | 30分 | -87% |
| レビューでの重大な指摘数 | 0.3件/PR | 0.1件/PR | -67% |
| 本番障害（レビュー起因） | 月1-2件 | 月0-1件 | -50%以上 |
| レビュー1回あたりの所要時間 | 15分 | 5分 | -67% |

特に「レビュー待ち時間の87%削減」は、開発のスループットに大きく貢献している。1人開発でもチーム開発でも、レビューの待ち時間がボトルネックになっているチームは多い。AIレビューを最初のフィルターとして導入するだけで、このボトルネックは大幅に緩和される。


## AIレビューと人間レビューの使い分け

AIレビューは万能ではない。AIが得意な領域と、人間が不可欠な領域を理解した上で、適切に使い分けることが重要だ。

### AIレビューが得意な領域

| 領域 | 理由 |
|------|------|
| 構文エラー・型エラー | パターンマッチングで確実に検出 |
| セキュリティの定型パターン | SQLインジェクション、XSS等の既知パターンを網羅 |
| コーディング規約の準拠 | 定義されたルールに対する機械的なチェック |
| 命名の不適切さ | 変数名・関数名の意味的な分析 |
| コードの重複 | プロジェクト内の類似コードの検出 |
| パフォーマンスの定型パターン | N+1クエリ、不要な再計算等の既知パターン |

### 人間レビューが不可欠な領域

| 領域 | 理由 |
|------|------|
| ビジネスロジックの正当性 | 「仕様通りに実装されているか」はAIには判断できない |
| アーキテクチャの整合性 | システム全体の設計方針との一貫性は人間の判断が必要 |
| ユーザー体験への影響 | UI/UXの妥当性は主観的な判断を含む |
| チーム方針との整合 | 暗黙知（文書化されていないチームの方針）への準拠 |
| トレードオフの評価 | 「この設計で将来困らないか」という長期的な判断 |
| コードの意図の理解 | 「なぜこう書いたか」の妥当性評価 |

### 推奨する運用パターン

```
フェーズ1: 開発者がコードを書く
    ↓
フェーズ2: AIレビュー（自動 or 手動）
    ├── セキュリティチェック     → AI
    ├── パフォーマンスチェック   → AI
    ├── 規約準拠チェック         → AI
    └── テスト網羅性チェック     → AI
    ↓
フェーズ3: AI指摘の修正
    ↓
フェーズ4: 人間レビュー（AIレビュー結果を前提に）
    ├── ビジネスロジックの正当性 → 人間
    ├── アーキテクチャの整合性   → 人間
    └── 設計意図の妥当性         → 人間
    ↓
フェーズ5: マージ
```

このパターンでは、AIが「定型的な問題」を事前に排除し、人間レビュアーは「判断を要する問題」に集中する。結果として、レビュー全体の品質と速度が同時に向上する。

### ツール別の最適な役割分担

最後に、3ツールの最適な役割分担をまとめる。

| ツール | 最適な役割 | タイミング |
|--------|-----------|-----------|
| Claude Code | 深いコードレビュー（プロジェクト全体の文脈） | コミット前のセルフレビュー |
| Cursor | インラインのクイックレビュー | コーディング中のリアルタイムチェック |
| GitHub Copilot | 自動PRレビューと要約生成 | PR作成時の自動実行 |
| 人間 | ビジネスロジック・アーキテクチャのレビュー | AIレビュー完了後の最終確認 |


## この章のまとめ

AIコードレビューは、レビューの品質とスピードを同時に向上させる強力なアプローチだ。

1. **Claude Code**: プロジェクト全体を理解した深いレビュー。CLAUDE.mdにレビュールールを定義し、サブエージェントで並行レビューを実行
2. **GitHub Copilot**: PR作成時の自動レビューと要約。チーム開発での標準的なフィルターとして機能
3. **Cursor**: コーディング中のリアルタイムレビュー。書きながら問題を発見・修正
4. **人間**: ビジネスロジックの正当性とアーキテクチャの整合性。AIが排除した定型的な問題の先にある、判断を要する問題に集中

重要なのは、AIレビューは人間レビューの**代替**ではなく**前処理**だということだ。AIが定型的な問題を事前に排除することで、人間レビュアーはより高次の問題に集中できる。この使い分けが、レビュープロセス全体の品質を最大化する鍵だ。

---

次章では、AIを使ったテスト自動生成を扱う。「テストを書く時間がない」「レガシーコードにテストがない」という、多くのエンジニアが抱える問題に対して、Claude Code、Cursor、GitHub Copilotがどう解決策を提供するかを具体的に解説する。
