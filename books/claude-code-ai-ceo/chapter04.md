---
title: "CTO部門の自動化 -- CI/CD・コードレビュー・テスト"
free: false
---

# CTO部門の自動化 -- CI/CD・コードレビュー・テスト

## CTO部門が最初に自動化すべき理由

AI-CEO Frameworkの6部門の中で、最初に本格稼働させたのはCTO部門だ。これには明確な理由がある。

**開発部門は、すべての他部門の基盤になる。**

マーケ部門がLP改善施策を立てても、実装するのは開発部門だ。営業部門が提案書を作っても、プロダクトのデモ環境を整えるのは開発部門だ。CS部門がバグ報告を受けても、修正するのは開発部門だ。

つまり、開発部門のスループットが上がれば、全部門の生産性が上がる。逆に、開発部門がボトルネックになると、他のすべてが止まる。

さらに、筆者は6つのプロダクトを同時に保守・改善する必要がある。各プロダクトにCI/CD環境を整え、コードレビューの品質を担保し、テストカバレッジを維持するだけでも、手動では到底追いつかない。

CTO部門エージェントの導入で、この状況が劇的に改善した。


## CTO部門エージェントの役割定義

まず、CTO部門エージェント（`ai-ceo-cto.md`）の定義を改めて見てみよう。

```markdown
---
name: ai-ceo-cto
description: CTO/開発部長エージェント。プロダクト開発全般を統括する。
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
---

# CTO / 開発部長エージェント

あなたは AI-CEO Framework の CTO（最高技術責任者）です。

## ペルソナ

経験豊富なテックリード。実用性を重視し、
オーバーエンジニアリングを避ける。
「動くものを最速で出し、フィードバックを得て改善する」がモットー。

## 担当領域

- プロダクト開発全般（設計、実装、テスト、デプロイ）
- 技術的意思決定
- スプリント管理
- コードレビュー・セキュリティ

## 権限レベル

- execute: コーディング、テスト実行、ステージングデプロイ、内部ドキュメント
- draft: 本番デプロイ、アーキテクチャの大幅変更、新規ライブラリ導入
```

ポイントは以下の3つだ。

**1. ツールの選択**: `Bash`ツールが含まれている。これにより、エージェントはGitコマンド、npm/yarnコマンド、テスト実行コマンドなどをターミナルで直接実行できる。CI/CDの設定やテスト実行に不可欠だ。

**2. ペルソナの「実用性重視」**: これが意外と重要だ。ペルソナを指定しないと、エージェントは過度に複雑なソリューションを提案しがちだ。「オーバーエンジニアリングを避ける」と明記することで、シンプルで保守しやすい実装を優先する。

**3. 権限のdraft/execute分離**: バグ修正やテスト追加は自動実行（execute）だが、本番デプロイや新規ライブラリ導入は承認必要（draft）。この境界が、安全性と効率のバランスを取る。


## GitHub Actions連携でCI/CDを自動構築

### 6プロダクトのCI/CD統一化

筆者が抱えていた課題の一つが、プロダクトごとにCI/CD環境がバラバラだったことだ。

| プロダクト | CI/CD状態（導入前） |
|-----------|-------------------|
| ShareToku | なし |
| MochiQ Landing | なし |
| MochiQ App | なし |
| Focalize | 手動デプロイ |
| 元気ボタンアプリ | なし |
| スキル管理SaaS | 手動デプロイ |

6プロダクトのうち、まともなCI/CDが動いていたものはゼロだった。デプロイは毎回手動で、テストも手動で実行していた（そもそもテストが書かれていないプロダクトもあった）。

CTO部門エージェントに`/ai-ceo:dev:sprint`を実行したところ、以下のタスクが自動で計画・実行された。

### 実践例: 元気ボタンアプリのCI/CD追加

元気ボタンアプリ（genkibutton）へのCI/CD追加は、AI-CEO Frameworkで自動化した最初の実案件だ。その過程を時系列で追ってみよう。

#### ステップ1: スプリント計画

CEOが以下のコマンドを実行する。

```
/ai-ceo:dev:sprint
```

Orchestratorがai-ceo-ctoエージェントを呼び出し、CTOエージェントが以下のフローを実行する。

1. `.company/products/genki-button/STATE.md`を読み取り、現在のプロダクト状態を把握
2. `.company/departments/dev/STATE.md`を読み取り、開発部門のバックログを確認
3. 優先度に基づいてタスクを選定

CTOエージェントの判断:

```
選定タスク:
1. [高] genkibutton リポジトリにCI/CDを追加
   - GitHub Actions ワークフロー作成
   - 自動テスト実行
   - コード品質チェック
```

#### ステップ2: 仕様策定

CTOエージェントが、タスクの仕様をCC-SDD（Claude Code Software Design Document）形式で作成する。

```markdown
# CC-SDD: genkibutton CI/CD追加

## Requirements
- PRが作成された時に自動でCI/CDが走る
- テスト（flutter test）が自動実行される
- 静的解析（flutter analyze）が自動実行される
- CIが失敗した場合、PRにステータスが表示される

## Design
- GitHub Actions のワークフローファイルを作成
- トリガー: pull_request イベント（main, develop ブランチ）
- ジョブ: Flutter 環境セットアップ → analyze → test

## Tasks
1. .github/workflows/ci.yml を作成
2. ワークフローの動作確認
3. PRを作成
```

#### ステップ3: 実装

CTOエージェントが、以下のGitHub Actionsワークフローファイルを生成する。

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main]

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: 'stable'

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test
```

シンプルだが実用的なワークフローだ。「オーバーエンジニアリングを避ける」ペルソナが効いている。最初から複雑なマトリクスビルドやキャッシュ設定を入れるのではなく、まず動くものを作り、必要に応じて改善するアプローチだ。

#### ステップ4: PR作成

CTOエージェントがGitでブランチを作成し、コミットし、PRを作成する。

```bash
git checkout -b feature/add-ci-cd
git add .github/workflows/ci.yml
git commit -m "feat: add CI/CD pipeline with Flutter analyze and test"
git push origin feature/add-ci-cd
gh pr create --title "feat: CI/CD追加" --body "..."
```

実際に作成されたのが **genkibutton リポジトリのPR #1** だ。これが、AI-CEO Framework経由で自動作成された最初のPRとなった。

#### ステップ5: 承認と状態更新

PRが作成されると、CTOエージェントは承認キューにアイテムを追加する。

```markdown
# approval-queue.md
- [AQ-001] 開発: genkibutton CI/CD追加 PR #1 | github.com/xxx/genkibutton/pull/1
```

CEOがPRの内容を確認し、`/ai-ceo:approve AQ-001`で承認。その後、CTOエージェントがPRをマージし、`.company/departments/dev/STATE.md`を更新する。

```markdown
## 最近の成果物
| 日付 | 成果物 | 備考 |
|------|--------|------|
| 2026-02-17 | genkibutton CI/CD追加 | PR #1 マージ済み |
```

**ここまでの一連のフローで、CEOが手を動かしたのはPRの確認と承認ボタンを押すことだけだ。** 所要時間は約15分。手動で同じことをやったら半日はかかっていた。


## PRの自動レビュー

CI/CDの次に自動化したのが、コードレビューだ。

### 課題: 1人でレビューする限界

1人開発では、コードレビューが形骸化しやすい。自分で書いたコードを自分でレビューしても、バグや設計上の問題を見落としがちだ。「まあ、動いているからいいか」で通してしまう。

しかし、6プロダクトを保守する上で、コードの品質を維持することは死活問題だ。1つのプロダクトでの品質低下が、技術的負債として将来の開発速度を著しく落とすことになる。

### Claude Codeによるレビュー委任

CTOエージェントには、コードレビューのワークフローが組み込まれている。

```markdown
## スプリントフロー
...
5. dev-reviewer でコードレビュー
   - コードの品質チェック
   - セキュリティチェック
   - tech-stack.md 準拠確認
   - テストカバレッジ確認
```

実際のレビューでは、以下の観点をチェックする。

#### レビュー観点

```markdown
1. コード品質
   - 不要な複雑さがないか
   - 関数の責務が適切に分離されているか
   - エラーハンドリングが適切か
   - 命名が明確か

2. セキュリティ
   - APIキーやシークレットがハードコードされていないか
   - SQLインジェクション、XSSの脆弱性がないか
   - 入力バリデーションが適切か

3. tech-stack.md 準拠
   - 承認されたライブラリのみを使用しているか
   - コーディング規約に従っているか
   - ディレクトリ構造が規約に合っているか

4. テスト
   - 新規コードにテストが追加されているか
   - エッジケースがカバーされているか
   - テストが意味のあるアサーションをしているか
```

### GitHub Actions連携による自動レビュー

さらに進んだ段階として、GitHub Actionsと連携してPR作成時に自動でレビューを実行する仕組みも構築した。

```yaml
# .github/workflows/ai-review.yml
name: AI Code Review

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  pull-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get diff
        id: diff
        run: |
          echo "diff<<EOF" >> $GITHUB_OUTPUT
          git diff origin/main...HEAD >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: AI Review
        uses: anthropics/claude-code-action@v1
        with:
          model: claude-sonnet-4-20250514
          prompt: |
            以下のdiffをレビューしてください。
            観点: コード品質、セキュリティ、テストカバレッジ
            問題がなければ「LGTM」と記載してください。
            問題があれば具体的な改善案を提示してください。
```

このワークフローにより、PRが作成されるたびにAIレビューが自動で走る。レビュー結果はPRのコメントとして投稿され、CEOはレビュー結果を確認した上でマージの判断を行う。

### レビューの実際の効果

MochiQアプリのリポジトリにこの仕組みを導入した結果、以下のような変化があった。

- **見落としていたバグの検出**: null安全性の問題、エラーハンドリングの漏れなど、自分では気づきにくいバグが検出された
- **コーディング規約の自動チェック**: 命名規則の揺れ、不要なimport、unused変数などが自動で指摘された
- **セキュリティ上の問題**: APIキーのハードコードを1件検出。環境変数に移行するきっかけになった

重要なのは、**レビューの品質が安定する**ことだ。人間のレビューは、疲れている時やタスクが溜まっている時に品質が落ちる。AIレビューは常に同じ水準でチェックを行う。


## テスト自動生成

### テストがない現実

正直に言おう。筆者の6プロダクトのうち、まともなテストが書かれていたのは2プロダクトだけだった。残り4プロダクトはテストカバレッジがほぼ0%だ。

「テストを書くべきだ」ということは分かっている。しかし、機能開発とバグ修正で手一杯の状態では、テストを書く時間を確保できない。テストのないコードが増え、リファクタリングが怖くなり、技術的負債が蓄積する。典型的な悪循環だ。

### CTOエージェントによるテスト一括生成

CTOエージェントには、既存コードに対してテストを自動生成するワークフローが含まれている。

```
CEOの指示:
/ai-ceo:dev:sprint
→ タスク: MochiQ のテストカバレッジ改善

CTOエージェントのフロー:
1. 既存コードを読み取り
2. テストが不足しているモジュールを特定
3. 各モジュールに対してユニットテストを生成
4. テストを実行して全パスを確認
5. PRを作成
```

実際に生成されるテストの例を見てみよう。

#### 例: Firebase Cloud Functions のテスト

元のコード（テストなし）:

```typescript
// functions/src/quiz.ts
export async function generateQuiz(
  userId: string,
  topicId: string
): Promise<Quiz> {
  const topic = await getTopicById(topicId);
  if (!topic) {
    throw new Error(`Topic not found: ${topicId}`);
  }

  const userHistory = await getUserQuizHistory(userId, topicId);
  const difficulty = calculateDifficulty(userHistory);

  const questions = await generateQuestions(topic, difficulty, 5);

  return {
    id: generateId(),
    userId,
    topicId,
    questions,
    difficulty,
    createdAt: new Date(),
  };
}
```

CTOエージェントが生成したテスト:

```typescript
// functions/src/__tests__/quiz.test.ts
import { generateQuiz } from '../quiz';
import { getTopicById } from '../topics';
import { getUserQuizHistory } from '../history';

jest.mock('../topics');
jest.mock('../history');

const mockGetTopicById = getTopicById as jest.MockedFunction<
  typeof getTopicById
>;
const mockGetUserQuizHistory = getUserQuizHistory as jest.MockedFunction<
  typeof getUserQuizHistory
>;

describe('generateQuiz', () => {
  const userId = 'user-001';
  const topicId = 'topic-001';

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should generate a quiz with correct structure', async () => {
    mockGetTopicById.mockResolvedValue({
      id: topicId,
      name: 'JavaScript Basics',
      content: '...',
    });
    mockGetUserQuizHistory.mockResolvedValue([]);

    const quiz = await generateQuiz(userId, topicId);

    expect(quiz).toMatchObject({
      userId,
      topicId,
      questions: expect.any(Array),
      difficulty: expect.any(Number),
    });
    expect(quiz.questions).toHaveLength(5);
    expect(quiz.id).toBeDefined();
    expect(quiz.createdAt).toBeInstanceOf(Date);
  });

  it('should throw error when topic not found', async () => {
    mockGetTopicById.mockResolvedValue(null);

    await expect(generateQuiz(userId, topicId)).rejects.toThrow(
      'Topic not found: topic-001'
    );
  });

  it('should adjust difficulty based on user history', async () => {
    mockGetTopicById.mockResolvedValue({
      id: topicId,
      name: 'JavaScript Basics',
      content: '...',
    });
    mockGetUserQuizHistory.mockResolvedValue([
      { score: 90, difficulty: 3 },
      { score: 85, difficulty: 3 },
      { score: 95, difficulty: 4 },
    ]);

    const quiz = await generateQuiz(userId, topicId);

    // High scores should increase difficulty
    expect(quiz.difficulty).toBeGreaterThan(3);
  });
});
```

エージェントが生成するテストの特徴は以下の通りだ。

- **モックの適切な使用**: 外部依存（データベース、API）を適切にモック化する
- **正常系と異常系の両方**: 正常なケースだけでなく、エラーケース（Topic not found）もカバーする
- **エッジケースの考慮**: ユーザー履歴に基づく難易度調整のテストなど、ビジネスロジックのエッジケースも含む

### テスト生成の品質と限界

率直に言うと、エージェントが生成するテストの100%がそのまま使えるわけではない。体感では以下の割合だ。

| 品質レベル | 割合 | 対応 |
|-----------|------|------|
| そのまま使える | 60-70% | PRにそのままマージ |
| 軽微な修正が必要 | 20-25% | モックの調整、アサーションの追加 |
| 書き直しが必要 | 5-10% | 複雑なビジネスロジックのテスト |

それでも、「テストカバレッジ0%」から「60-70%」への改善が、エージェントに指示するだけで実現できる。残りの調整は人間が行うが、0からテストを書くよりはるかに速い。


## ホットフィックスの自動化ワークフロー

### /ai-ceo:dev:hotfix のフロー

本番環境でバグが発見された場合のフローも自動化している。

```
CEOの指示:
/ai-ceo:dev:hotfix "Focalizeのダッシュボードでデータが表示されない"

CTOエージェントのフロー（GSD Quick Mode）:
1. 問題の特定
   - エラーログの確認
   - 関連コードの調査
   - 原因の特定

2. 修正
   - 最小限のコード変更
   - 修正に対するテスト追加

3. テスト
   - 既存テストの全実行
   - 追加テストの実行

4. PR作成
   - hotfix/xxxx ブランチ
   - 修正内容の説明
   - → approval-queue.md に追加（本番デプロイは draft）
```

「GSD Quick Mode」とは、通常のスプリントフローを簡略化した緊急対応モードだ。問題の特定から修正、テスト、PR作成までを一気に実行する。

### 実際のホットフィックスの流れ

ある日、Focalizeのユーザーダッシュボードでデータが正しく表示されないバグが報告された。

CEOの操作は以下のコマンドを打つだけだ。

```
/ai-ceo:dev:hotfix "Focalizeのダッシュボードで
ユーザーのフォーカスセッションデータが表示されない。
Firestore のクエリが空の結果を返している可能性がある"
```

CTOエージェントが以下のフローを自動実行する。

```
[自動] Focalize リポジトリのコードを調査
[自動] ダッシュボードコンポーネントのFirestoreクエリを特定
[自動] クエリの条件式にバグを発見
       （日付フィルタのタイムゾーン処理が不正）
[自動] 修正コードを作成
[自動] テストを追加して実行（全パス）
[自動] hotfix/fix-dashboard-query ブランチでPR作成
[自動] approval-queue.md にアイテム追加
```

CEOは、approval-queue.mdに追加されたアイテムを確認し、PRの内容を見て承認する。

```
/ai-ceo:approve AQ-005
```

承認後、CTOエージェントがPRをマージし、本番デプロイの手順を実行する（デプロイ自体もdraftモードで確認を挟む場合がある）。

**バグ報告から修正PRの完成まで、CEOの実作業時間は約10分だ。** 従来なら、バグの原因調査だけで30分、修正とテストで1-2時間はかかっていた。


## 複数プロダクトのCI/CD管理パターン

6つのプロダクトにCI/CDを導入した結果、管理上のパターンが見えてきた。

### 技術スタック別のワークフローテンプレート

プロダクトごとにCI/CDの設定を1から書くのではなく、技術スタック別にテンプレートを用意している。

```
テンプレート1: Next.js プロダクト（ShareToku, Focalize, スキル管理SaaS）
  → lint + type-check + test + build

テンプレート2: Flutter アプリ（MochiQ App, 元気ボタン）
  → analyze + test

テンプレート3: 静的サイト（ランディングページ系）
  → lint + build + Lighthouse CI
```

CTOエージェントは、新しいプロダクトにCI/CDを追加する際、`.company/steering/tech-stack.md`を参照して適切なテンプレートを選択する。

### PRのステータスチェック統一

すべてのプロダクトで、以下のステータスチェックを統一している。

```yaml
# 必須チェック（全プロダクト共通）
required_checks:
  - lint          # コード品質
  - type-check    # 型チェック（TypeScript）
  - test          # テスト
  - build         # ビルド成功

# 推奨チェック（対応プロダクトのみ）
optional_checks:
  - ai-review     # AIコードレビュー
  - lighthouse    # パフォーマンス
  - security      # 依存パッケージの脆弱性
```

### 開発部門状態の自動更新

CI/CDの実行結果は、`.company/departments/dev/STATE.md`に自動的に反映される。

```markdown
## CI/CD 状況

| プロダクト | 最終ビルド | ステータス | テストカバレッジ |
|-----------|-----------|-----------|----------------|
| ShareToku | 2026-02-22 | 成功 | 45% |
| MochiQ App | 2026-02-21 | 成功 | 32% |
| Focalize | 2026-02-22 | 成功 | 28% |
| 元気ボタン | 2026-02-17 | 成功 | 15% |
| スキル管理SaaS | 2026-02-20 | 成功 | 22% |
```

CEOは`/ai-ceo:morning`コマンドでこの情報を含むダイジェストを受け取り、全プロダクトのCI/CD状態を一目で把握できる。


## 実践から得た教訓

CTO部門の自動化を1ヶ月以上運用して、いくつかの重要な教訓を得た。

### 教訓1: 最初のエージェント定義は不完全でいい

最初のCTOエージェント定義は、現在の半分以下の内容だった。使いながら「ここが足りない」「ここはもっと具体的に書くべき」と気づき、徐々に改善してきた。

完璧なエージェント定義を最初から作ろうとすると、いつまでも始められない。「動くものを最速で出し、フィードバックを得て改善する」-- これはCTOエージェントのペルソナだが、エージェント定義の作り方にも当てはまる。

### 教訓2: 権限の粒度は運用しながら調整する

最初はすべてのアクションをdraftにしていた。安全だが、承認キューが溜まって非効率だった。逆に、executionに移行しすぎると、意図しない変更が自動実行されるリスクがある。

現在の粒度（バグ修正はexecute、本番デプロイはdraft）に落ち着くまで、2-3週間の試行錯誤があった。

### 教訓3: ステータスファイルの更新を忘れない

エージェントにタスクを実行させた後、`.company/departments/dev/STATE.md`の更新を忘れると、`/ai-ceo:morning`のダイジェストが実態と乖離する。

CTOエージェントのワークフローに「最後にSTATE.mdを更新する」ステップを明示的に組み込んだことで、この問題は解消した。

### 教訓4: エージェント間の連携が価値を生む

CTOエージェント単体でも十分に価値があるが、他部門のエージェントと連携した時に、その価値は倍増する。

例えば、CMOエージェントが「FocalizeのLP改善でCVRが低い」と分析し、改善案を出す。CTOエージェントがその改善案を実装し、PRを作成する。CSO部門のエージェントが、改善されたLPを使って提案資料を更新する。

この部門横断の連携が、次章以降で解説するAIエージェント経営の真髄だ。

---

次の章では、CMO部門の自動化について解説する。SEO記事の量産、LP改善サイクル、SNS運用の自動化、そしてZenn有料書籍の企画・執筆フローまで、マーケティング全体をエージェントで回す方法を詳しく見ていく。

---

> **CTO部門の自動化を自社に導入したい方へ**
> 「CI/CDの統一化」「AIコードレビューの導入」「テスト自動生成」など、開発チームの生産性を劇的に向上させる方法を無料診断でお伝えします。合同会社ジョインクラスの AI業務自動化コンサルティングについては [joinclass.co.jp](https://joinclass.co.jp) をご覧ください。
