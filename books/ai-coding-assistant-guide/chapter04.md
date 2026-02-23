---
title: "Cursor 実践ガイド -- AI統合エディタで日常のコーディングを加速する"
free: false
---

# Cursor 実践ガイド -- AI統合エディタで日常のコーディングを加速する

## この章で学ぶこと

前章ではClaude Codeの実践的な使い方を解説した。プロジェクト全体を俯瞰し、複数ファイルにまたがる複雑なタスクを自律的に実行する -- それがClaude Codeの強みだった。

本章で扱うCursorは、それとは異なるアプローチでAIの力を発揮する。**エディタの中で、コーディングのリズムを崩さずに、AIの恩恵を受ける**。これがCursorの思想だ。

筆者の日常で言えば、Claude Codeが「プロジェクトマネージャー兼シニアエンジニア」だとしたら、Cursorは「隣の席に座っている優秀なペアプログラマー」だ。新機能の設計や大規模リファクタリングはClaude Codeに任せるが、UIの微調整、小さなバグ修正、既存パターンに沿った実装はCursorの方が圧倒的に速い。

本章では以下を扱う。

1. .cursorrules の設計 -- CLAUDE.mdとの対比で理解する
2. Tab補完の活用テクニック -- 受け入れ/拒否の判断基準
3. Composer の実践的な使い方 -- 複数ファイル編集のワークフロー
4. @codebase を使ったプロジェクト理解
5. Cursorが特に有効な場面の具体例
6. 実践例: ReactコンポーネントのCSS調整をCursorで行うフロー


## .cursorrules の設計 -- CLAUDE.mdとの対比で理解する

### .cursorrules とは

.cursorrulesは、Cursorに対してプロジェクト固有のルールを伝えるための設定ファイルだ。プロジェクトのルートディレクトリに配置する。前章で解説したCLAUDE.mdと同じ目的を持つが、いくつかの重要な違いがある。

### CLAUDE.md と .cursorrules の比較

| 観点 | CLAUDE.md | .cursorrules |
|------|-----------|-------------|
| 配置場所 | ルート、サブディレクトリ、グローバル | ルートディレクトリのみ（`.cursorrules`）またはプロジェクト設定 |
| 階層構造 | 複数ファイルをマージ | 基本的に1ファイル |
| 記述スタイル | マークダウン形式、構造化 | 自由形式（マークダウンも可） |
| 読み込みタイミング | セッション開始時に自動読み込み | AI機能使用時に自動読み込み |
| 主な消費者 | Claude Code（ターミナル） | Cursor内のAI機能全般（Tab補完、Chat、Composer） |
| 推奨文字数 | 核心情報に絞る（コンテキスト圧迫を避ける） | 同様に簡潔に（ただしCursorはモデル切替が可能で影響が異なる） |

### 効果的な .cursorrules の書き方

.cursorrulesで最も重要なのは、**Tab補完の品質に直結する情報を書く**ことだ。CLAUDE.mdはプロジェクト全体の設計方針や運用ルールまで含めるが、.cursorrulesはコーディング中のリアルタイム補完を最適化する情報にフォーカスするのが効果的だ。

#### 基本テンプレート

```
You are working on a Next.js 15 project with App Router and TypeScript strict mode.

## Tech Stack
- Framework: Next.js 15 (App Router)
- Language: TypeScript (strict)
- Styling: Tailwind CSS
- UI Components: shadcn/ui
- Database: Supabase (PostgreSQL with RLS)
- Auth: Supabase Auth
- i18n: next-intl

## Coding Conventions
- Use functional components only (no class components)
- Use named exports (default export only for page.tsx, layout.tsx)
- Prefer interface over type alias (use type only for unions/intersections)
- Use early returns to reduce nesting
- Maximum nesting depth: 3 levels

## Component Patterns
- Server Components by default, "use client" only when needed
- Props interface named as {ComponentName}Props
- Place shared components in src/components/
- Place feature-specific components in src/features/{feature}/components/

## Styling Rules
- Use Tailwind CSS utility classes, no custom CSS files
- Use cn() helper for conditional classes (from @/lib/utils)
- Follow mobile-first responsive design (sm: md: lg:)
- Color tokens: Use CSS variables defined in globals.css

## Import Order
1. React/Next.js imports
2. Third-party libraries
3. Internal modules (@/)
4. Relative imports
5. Type imports (with 'type' keyword)
```

#### CLAUDE.md の内容を .cursorrules に変換するコツ

既にCLAUDE.mdが存在するプロジェクトでは、その内容を.cursorrulesに転用できる。ただし、そのままコピーするのではなく、以下の変換を行うべきだ。

**残すべき情報:**
- 技術スタック
- コーディング規約
- コンポーネントパターン
- ディレクトリ構成

**省くべき情報:**
- 運用ワークフロー（CI/CDの手順等）
- Permission設定に関する記述
- サブエージェントの定義
- チーム運用のルール

省くべき情報はClaude Code固有の概念であり、Cursorでは使われない。不要な情報を書くとコンテキストを無駄に消費するだけでなく、AIの注意が分散して補完品質が落ちる可能性がある。

### .cursorrules と Cursor Settings の使い分け

Cursorには .cursorrules ファイルの他に、エディタ設定内の「Rules for AI」という設定がある。

| 設定場所 | スコープ | 適した内容 |
|---------|--------|-----------|
| .cursorrules | プロジェクト固有（リポジトリにコミット可能） | プロジェクトの技術スタック、規約 |
| Cursor Settings > Rules for AI | 全プロジェクト共通（ローカル設定） | 個人の作業スタイル、言語設定 |

筆者の場合、Cursor Settings側には以下のようなグローバルルールを設定している。

```
- Respond in Japanese when asked in Japanese
- Keep code simple: prefer early returns, avoid unnecessary abstractions
- When suggesting changes, explain the "why" briefly
```

プロジェクト固有のルールは .cursorrules に、個人の好みは Cursor Settings に、と分離することで管理がしやすくなる。


## Tab補完の活用テクニック

### Tab補完の仕組み

CursorのTab補完は、現在のカーソル位置の前後のコード、開いているファイル、.cursorrulesの内容、そしてプロジェクト内の関連ファイルをコンテキストとして、次に書くべきコードを予測する。

GitHub Copilotのインライン補完と似ているが、Cursorの場合は**プロジェクト全体のコンテキストをより深く参照する**点が異なる。たとえば、プロジェクト内の別ファイルで定義されたインターフェースに沿った実装を、Tab補完が正確に提案してくれる場面が多い。

### Tab補完の受け入れ/拒否の判断基準

Tab補完が表示されたとき、「受け入れるべきか」「拒否すべきか」を瞬時に判断する必要がある。筆者が実践している判断基準を共有する。

#### 受け入れてよい場合

**1. 既存パターンの繰り返し**

プロジェクト内の他のコンポーネントと同じパターンのコードが提案された場合は、高い確率で正しい。

```tsx
// 既存コンポーネントのパターン
export function UserCard({ user }: UserCardProps) {
  return (
    <div className="rounded-lg border p-4">
      <h3 className="text-lg font-semibold">{user.name}</h3>
      <p className="text-sm text-muted-foreground">{user.email}</p>
    </div>
  );
}

// 新しいコンポーネントを書き始めると...
// Cursorは上記パターンに沿った補完を提案する
export function ProjectCard({ project }: ProjectCardProps) {
  // Tab補完 -> 同じカードパターンの構造が提案される
  // -> 受け入れてから、中身を調整する方が速い
```

**2. インポート文**

使おうとしているモジュールのインポート文は、ほぼ正確に補完される。

```tsx
// "import { use" と入力すると
import { useState, useEffect } from "react";  // 正確
import { useRouter } from "next/navigation";   // 正確
import { cn } from "@/lib/utils";              // プロジェクト固有のパスも正確
```

**3. 型定義**

関数の引数やPropsの型定義は、既存の型と整合する補完が期待できる。

```tsx
// 関数名と引数名から、型を正確に推定してくれる
async function fetchUserPosts(userId: string): Promise<Post[]> {
  // Tab補完がPost[]を正しく推定
```

#### 拒否すべき場合

**1. ビジネスロジックの本体**

条件分岐の詳細や、計算ロジックの具体的な実装は、AIが正しく推定できない場合がある。

```tsx
// 価格計算のロジック -- ビジネスルールに依存するため要注意
function calculateDiscount(plan: Plan, coupon?: Coupon): number {
  // Tab補完が提案する割引ロジックは、実際のビジネスルールと異なる可能性が高い
  // -> 拒否して、自分で書く
```

**2. 外部APIのレスポンス構造**

APIのレスポンスの形状は、ドキュメントを確認しないとわからない。Tab補完がそれらしい構造を提案しても、実際のAPIと異なる場合がある。

```tsx
// Stripe APIのレスポンス -- 正確なフィールド名はドキュメントを確認すべき
const session = await stripe.checkout.sessions.create({
  // Tab補完の提案を鵜呑みにしない
```

**3. セキュリティに関わるコード**

認証チェック、権限検証、入力バリデーションなどは、AIの提案をそのまま受け入れるのではなく、必ず自分で確認する。

### Tab補完の精度を上げるテクニック

Tab補完の品質は、書き方のちょっとした工夫で大幅に向上する。

**テクニック1: 関数名と引数名を先に書く**

```tsx
// 悪い例: いきなりfunction bodyから書き始める
function f(x: string) {

// 良い例: 意味のある名前を先に書くと、補完の精度が上がる
function formatCurrency(amount: number, currency: string): string {
  // Tab補完: amount.toLocaleString('ja-JP', { style: 'currency', currency })
```

関数名が `formatCurrency` で引数が `amount` と `currency` であれば、AIは「通貨フォーマットの処理」だと正確に推定できる。

**テクニック2: コメントで意図を先に書く**

```tsx
// ユーザーのサブスクリプション状態を確認し、有効期限が切れていたらfreeプランに降格
async function checkSubscriptionStatus(userId: string) {
  // Tab補完: この関数の意図を理解した上で、適切な実装を提案してくれる
```

関数の上にコメントで意図を書くだけで、Tab補完の精度は劇的に上がる。これはGitHub Copilotでも有効なテクニックだが、Cursorの方がプロジェクトコンテキストを深く参照するため、さらに精度が高い。

**テクニック3: 型定義を先に書く**

```tsx
// インターフェースを先に定義する
interface CreatePostInput {
  title: string;
  content: string;
  tags: string[];
  publishAt?: Date;
  isDraft: boolean;
}

// その後に実装を書くと、型に沿った実装が補完される
async function createPost(input: CreatePostInput): Promise<Post> {
  // Tab補完: input の各フィールドを正しく使った実装が提案される
```

**テクニック4: 部分的に受け入れる**

Cursorでは `Cmd+→`（macOS）で補完を**単語単位で部分的に受け入れる**ことができる。全体は合っているが一部だけ修正したい場合に便利だ。

```tsx
// Tab補完の提案: className="rounded-lg border p-4 bg-white"
// 実際にはbg-whiteではなくbg-card にしたい場合
// -> Cmd+→ で "rounded-lg border p-4 " まで受け入れ、その後自分で "bg-card" と入力
```


## Composer の実践的な使い方

### Composer とは

Composerは、Cursorの中でも最もパワフルな機能だ。**複数のファイルにまたがる変更を、自然言語の指示で一括実行できる**。

Claude CodeのMulti-file editing能力と比較すると、Composerは以下の点で異なる。

| 観点 | Claude Code | Cursor Composer |
|------|------------|----------------|
| 操作方法 | ターミナルからテキスト指示 | エディタ内のUIで指示 |
| 差分確認 | git diffで確認 | エディタ内で差分プレビュー |
| 適用方法 | 自動適用（Permission設定に従う） | ファイル単位で適用/拒否を選択 |
| 取り消し | git restoreで手動 | Cmd+Zで元に戻せる |
| 向いているスケール | 大規模（10ファイル以上） | 中規模（2-8ファイル程度） |

### Composer の起動と基本操作

Composerは `Cmd+I`（macOS）で起動する。

```
起動: Cmd+I
全画面モード: Cmd+Shift+I
```

起動すると画面下部にComposerパネルが表示され、自然言語で指示を入力できる。

### Composer で効果的な指示の書き方

Composerの出力品質は、指示の書き方に大きく左右される。筆者が実践しているパターンを紹介する。

**パターン1: 変更の目的と範囲を明示する**

```
目的: ユーザーのプロフィール画面にSNSリンクの表示を追加する

変更が必要なファイル:
- src/types/user.ts -- User型にsocialLinksフィールドを追加
- src/features/profile/components/ProfileCard.tsx -- SNSリンクの表示を追加
- src/features/profile/hooks/useProfile.ts -- APIレスポンスにsocialLinksを含める

要件:
- socialLinks は { twitter?: string, github?: string, website?: string } のオブジェクト
- 各リンクにはアイコンを表示（lucide-reactのアイコンを使用）
- リンクがない場合は非表示
```

対象ファイルを明示すると、Composerは的確な変更を提案できる。「SNSリンクを追加して」だけだと、どのファイルに何をすべきか推定に頼ることになり、不要なファイルが変更されるリスクがある。

**パターン2: 既存ファイルを参照させる**

```
src/features/profile/components/SkillsSection.tsx と同じパターンで
SNSリンクのセクションコンポーネントを作成してください。
コンポーネント名は SocialLinksSection とします。
```

既存のコードをお手本として指定すると、プロジェクトのパターンに一貫した実装が生成される。

**パターン3: 段階的に指示する**

複雑な変更は、一度に全てを指示するのではなく、段階的に指示する方が品質が高い。

```
ステップ1: まず src/types/user.ts の User interface に socialLinks フィールドを追加して
ステップ2: 次に SocialLinksSection コンポーネントを作成して
ステップ3: ProfileCard に SocialLinksSection を組み込んで
```

### Composer の適用フロー

Composerが変更を提案したら、以下のフローで適用する。

```
1. 差分プレビューを確認
   -> 各ファイルの変更内容をエディタ内で確認できる
   -> 緑色=追加、赤色=削除

2. ファイル単位で適用/拒否を判断
   -> 型定義の変更: 通常は問題ないので Accept
   -> ロジックの変更: 内容を精査してから Accept
   -> 意図しないファイルの変更: Reject

3. 適用後の動作確認
   -> TypeScriptの型エラーがないか確認（tsc --noEmit）
   -> 画面を開いて表示を確認
   -> 必要に応じて微修正（Tab補完で仕上げる）
```

### Agent Mode の活用

Cursorには通常のComposerに加えて **Agent Mode** がある。Agent Modeでは、Composerがターミナルコマンドの実行やファイルの探索を自律的に行える。Claude Codeに近い動作をエディタ内で実現できる機能だ。

```
通常のComposer: 指定されたファイルを編集する
Agent Mode: 必要なファイルを自分で探索し、コマンドも実行する
```

Agent Modeが有効な場面:
- 「このエラーを修正して」（エラーの原因探索から修正まで）
- 「新しいAPIエンドポイントを追加して」（ルーティング、ハンドラ、型定義を一括作成）
- 「このテストが通るように実装して」（テストファイルから仕様を理解して実装）

ただし、Agent Modeは通常のComposerより多くのトークンを消費する。日常的な変更は通常のComposerで行い、探索が必要な複雑なタスクだけAgent Modeを使う、という使い分けが経済的だ。


## @codebase を使ったプロジェクト理解

### @codebase とは

Cursor Chatで `@codebase` と入力すると、プロジェクト全体のコードベースを参照した上でAIが回答してくれる。通常のChatは開いているファイルと選択範囲だけを参照するが、@codebaseはプロジェクト全体にアクセスする。

### @codebase が有効な場面

**1. 新しいプロジェクトのオンボーディング**

```
@codebase このプロジェクトのアーキテクチャの概要を教えてください。
主要なディレクトリの役割と、データの流れを説明してください。
```

新しいプロジェクトに参加したとき、コード全体を読む前にアーキテクチャの概要を把握できる。

**2. 既存の実装パターンの理解**

```
@codebase このプロジェクトでSupabaseのRLS（Row Level Security）はどのように実装されていますか？
具体的なポリシーの例を示してください。
```

「どこで何をやっているか」をプロジェクト全体から横断的に検索し、整理して教えてくれる。grepで断片的にコードを探すよりも、文脈を踏まえた回答が得られる。

**3. 影響範囲の調査**

```
@codebase User型のemailフィールドを変更した場合、影響を受けるファイルと箇所を一覧にしてください。
```

型の変更やAPI仕様の変更が、プロジェクト全体にどのような影響を及ぼすかを事前に調査できる。

**4. リファクタリングの計画**

```
@codebase このプロジェクトで直接 fetch() を使っている箇所を全て見つけて、
共通のAPIクライアント（src/lib/api-client.ts）に統合する計画を立ててください。
```

### @codebase と他の @ メンション の使い分け

Cursorには @codebase 以外にもファイルやコードを参照するためのメンション機能がある。

| メンション | 参照範囲 | 用途 |
|-----------|---------|------|
| `@codebase` | プロジェクト全体 | アーキテクチャ理解、横断検索 |
| `@ファイル名` | 指定したファイル | 特定ファイルに関する質問 |
| `@フォルダ名` | 指定したフォルダ以下 | 特定モジュールに関する質問 |
| `@web` | Web検索結果 | 最新のライブラリ情報、エラーの解決策 |
| `@docs` | 指定したドキュメント | 公式ドキュメントに基づいた質問 |

**使い分けのコツ**: 範囲が広いほどトークン消費が大きく、回答の精度が下がる傾向がある。質問の対象が明確な場合は `@ファイル名` や `@フォルダ名` を使い、対象が不明な場合やプロジェクト横断的な質問にだけ `@codebase` を使うのが効率的だ。


## Cursorが特に有効な場面の具体例

第2章の比較表でも示したが、Cursorが他のツールよりも有効な場面を、具体的なシナリオとともに掘り下げる。

### 場面1: UI / CSSの調整

Cursorが最も輝く場面がUIの調整だ。理由は明確で、**エディタ内でコードを変更し、即座にブラウザでプレビューを確認できる**フローがシームレスだからだ。

Claude Codeでも同じ変更は可能だが、ターミナルでdiffを見て確認し、ブラウザに切り替えて表示を確認し、再度ターミナルに戻って修正指示を出す、というフローになる。視覚的な確認が必要なタスクでは、このオーバーヘッドが無視できない。

```
具体的なシナリオ:
「カードコンポーネントのパディングをもう少し広げて、角丸を大きくしたい」

Claude Codeの場合:
  1. ターミナルで修正指示
  2. Claude Codeがファイルを編集
  3. ブラウザで確認
  4. 微調整が必要ならターミナルに戻って再指示
  -> 往復が発生する

Cursorの場合:
  1. ファイルを開いた状態でTab補完で値を変更
  2. ブラウザで即確認
  3. さらにTab補完で微調整
  -> エディタから離れずに完結する
```

### 場面2: 小さなバグ修正

「この関数の条件分岐が間違っている」「変数名がtypoしている」「nullチェックが漏れている」といった小さなバグ修正は、Cursorが最速だ。

エラーメッセージをCursor Chatに貼り付けるだけで、原因の特定と修正案の提示まで一気に行える。

```
Cursor Chatでの使い方:
> この TypeScript エラーを修正してください:
> Type 'string | undefined' is not assignable to type 'string'.

-> Chatがエラー箇所を特定し、修正コードをインラインで提案
-> Accept で即座に適用
```

### 場面3: 既存パターンに沿った新規実装

プロジェクト内に確立されたパターンがある場合、新しいファイルをそのパターンに沿って作成するのはCursorが得意だ。

```
例: 新しいAPIルートの追加

既存のファイル構造:
src/app/api/users/route.ts     -- ユーザーCRUD
src/app/api/posts/route.ts     -- 投稿CRUD
src/app/api/comments/route.ts  -- コメントCRUD

新しく作りたい:
src/app/api/tags/route.ts      -- タグCRUD

-> src/app/api/tags/route.ts を新規作成し、最初の数行を書き始めると
   既存のroute.tsのパターンに沿ったコードがTab補完で提案される
```

### 場面4: テスト駆動の修正

テストが失敗している状態で、そのテストが通るように実装を修正するシナリオ。

```
手順:
1. 失敗しているテストファイルを開く
2. Cmd+I でComposerを起動
3. 「このテストが通るように、対応する実装を修正してください」と指示
4. Composerがテスト内容から仕様を理解し、実装を修正
5. 差分プレビューで確認してAccept
```


## 実践例: ReactコンポーネントのCSS調整をCursorで行うフロー

ここからは、筆者が実際に行った作業を元に、CursorでのUI調整の全フローを再現する。題材は、Focalizeのランディングページのヒーローセクション改善だ。

### 作業の背景

Focalizeのランディングページで、ヒーローセクションのCTA（Call to Action）ボタンが目立たないというフィードバックを受けた。具体的な改善要件は以下の通り。

1. CTAボタンのサイズを大きくする
2. ボタンの背景色をブランドカラーの青から、より目立つグラデーションに変更
3. ホバー時にアニメーションを追加
4. モバイル表示でのレイアウトを調整

### ステップ1: 現状の把握

まず、該当ファイルを開いてCursor Chatで現状を確認する。

```
@src/components/landing/HeroSection.tsx
このヒーローセクションのCTAボタンの現在のスタイリングを教えてください。
```

Chatが該当するJSXとTailwindクラスを抽出して説明してくれる。

### ステップ2: Composerで一括変更

Cmd+I でComposerを起動し、改善要件を指示する。

```
HeroSection.tsx のCTAボタンを以下のように改善してください:

1. ボタンサイズ: px-8 py-4 text-lg に拡大
2. 背景: bg-gradient-to-r from-blue-600 to-purple-600 のグラデーション
3. ホバーアニメーション: scale-105 のトランジション追加
4. モバイル: sm以下で w-full にしてフル幅に

既存のボタン構造は維持し、Tailwindクラスのみ変更してください。
```

Composerが差分を提示する。

```tsx
// Before
<button className="rounded-md bg-blue-600 px-6 py-3 text-base font-medium text-white hover:bg-blue-700">
  無料で始める
</button>

// After (Composerの提案)
<button className="rounded-md bg-gradient-to-r from-blue-600 to-purple-600 px-8 py-4 text-lg font-semibold text-white transition-transform hover:scale-105 w-full sm:w-auto">
  無料で始める
</button>
```

### ステップ3: プレビューで確認と微調整

差分をAcceptした後、ブラウザのdev serverでプレビューを確認する。

「グラデーションは良いが、角丸がもう少し大きい方がボタンらしく見える」と判断。ファイル上で `rounded-md` にカーソルを置き、Tab補完を使って `rounded-xl` に変更。即座にプレビューで確認。

さらに、ボタン下にテキストリンク（「無料プラン、クレジットカード不要」）を追加したいと判断。CTAボタンのJSXの下にカーソルを移動して、次のコードを書き始める。

```tsx
<button className="...">
  無料で始める
</button>
// ここにカーソルを置いて "< p" と入力すると...
// Tab補完: <p className="mt-2 text-sm text-muted-foreground">無料プラン、クレジットカード不要</p>
```

.cursorrulesにTailwindのスタイリングルールが記述されているため、Tab補完がプロジェクトのスタイルに沿ったクラスを提案してくれる。

### ステップ4: レスポンシブ対応の確認

ブラウザのDevToolsでモバイル表示に切り替え、表示を確認する。CSSの微調整が必要な場合は、再びCursorに戻って修正。

```
Cursor Chatで:
> モバイル表示でCTAボタンとテキストの間のマージンが大きすぎます。
> sm以下の場合にmt-2をmt-1に、ボタンのpy-4をpy-3に変更してください。
```

### 全体のフロー所要時間

```
1. 現状把握（Chat）:     1分
2. 一括変更（Composer）:   2分
3. プレビュー確認・微調整:  3分
4. レスポンシブ確認:       2分
合計: 約8分
```

同じ作業をClaude Codeで行った場合、ターミナルとブラウザの往復が増えるため、15-20分はかかっていた。UIの視覚的な調整では、Cursorのエディタ内完結フローが圧倒的に効率的だ。


## Cursor利用のベストプラクティス

本章のまとめとして、Cursorを日常的に使う上でのベストプラクティスを整理する。

### Do（やるべきこと）

| プラクティス | 理由 |
|------------|------|
| .cursorrules を最初に整備する | Tab補完の品質に直結する |
| Tab補完を「受け入れてから修正」する | ゼロから書くより速い |
| Composerの指示に対象ファイルを明示する | 意図しないファイルの変更を防ぐ |
| 部分受け入れ（Cmd+→）を活用する | 補完の精度を自分でコントロールできる |
| @ファイル名 で範囲を絞ってChatする | トークン節約と回答精度の向上 |

### Don't（避けるべきこと）

| アンチパターン | 代替手段 |
|-------------|---------|
| Tab補完を無条件に受け入れる | ビジネスロジックは自分で確認する |
| Composerで10ファイル以上を一度に変更する | Claude Codeに委任するか、段階的に分割する |
| @codebase を毎回使う | 質問の対象が明確なら @ファイル名 で十分 |
| .cursorrules を書かずに使う | 補完品質が大幅に低下する |
| Agent Modeを日常的に使う | トークン消費が大きい。通常のComposerで十分な場合が多い |


## この章のまとめ

Cursorは「エディタの中でAIの力をシームレスに活用する」ツールだ。本章で解説した4つの柱を振り返る。

1. **.cursorrules**: Tab補完の品質を左右する最重要設定。技術スタック、コーディング規約、コンポーネントパターンを簡潔に記述する
2. **Tab補完**: 受け入れ/拒否の判断基準を持ち、関数名・コメント・型定義を先に書くことで精度を上げる
3. **Composer**: 複数ファイルの変更を自然言語で指示。対象ファイルの明示と段階的な指示で品質を確保する
4. **@codebase**: プロジェクト全体の理解と横断検索に活用。ただし範囲を絞れる場合は @ファイル名 を優先する

CursorとClaude Codeは競合するツールではなく、補完関係にある。大きなタスクはClaude Code、エディタ内の日常作業はCursor。この使い分けが、筆者の開発速度を最大化している基本戦略だ。

---

次章では、3つ目のツールであるGitHub Copilotの実践ガイドに入る。「個人の生産性ツール」としてのClaude Code・Cursorとは異なり、GitHub Copilotは「チーム開発の標準装備」として独自の強みを持っている。インライン補完の精度を上げるコツから、PRレビューの自動化、チーム全体のコーディング速度を底上げする運用方法まで、チーム視点でのAI活用を深掘りする。
