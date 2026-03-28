---
title: "CLAUDE.mdの書き方ガイド2026 — AIエージェントを思い通りに動かす設定ファイル"
emoji: "📝"
type: "tech"
topics: ["claudecode", "ai", "開発環境", "プログラミング", "自動化"]
published: false
---

## CLAUDE.md とは

Claude Codeを使い始めると、最初に気づくことがある。**「毎回同じ指示を繰り返している」** と。

- 「TypeScriptで書いて」
- 「テストはVitestで」
- 「コミットメッセージは日本語で」

プロジェクトごとに決まっているルールを、毎回口頭で伝えるのは非効率だ。

**CLAUDE.md** は、プロジェクトのルート（または `~/.claude/`）に置く設定ファイル。ここに書いたルールは、Claude Codeが**毎回の会話で自動的に読み込む**。いわば「AIへの永続的な指示書」だ。

## 基本構成

```markdown
# プロジェクト名

## 技術スタック
- 言語: TypeScript
- フレームワーク: Next.js 14
- DB: Supabase (PostgreSQL)
- テスト: Vitest

## コーディング規約
- 関数名はcamelCase
- コミットメッセージは日本語
- 型定義は明示的に書く

## 禁止事項
- any型の使用禁止
- console.logをコミットしない
```

これだけで、Claude Codeは**毎回の指示に規約を自動適用**する。

## 実践的な設計パターン

### パターン1: Thin Orchestrator

大規模プロジェクトでは、CLAUDE.mdが肥大化しがちだ。**Thin Orchestrator** パターンでは、CLAUDE.mdは指揮者に徹し、詳細は別ファイルに委譲する。

```markdown
# AI-CEO Framework

## あなたの役割
CEOの経営判断を支援するOrchestratorです。
複雑なタスクは .claude/agents/ のサブエージェントに委任してください。

## サブエージェント一覧
- dev-coder: コーディング実行
- dev-reviewer: コードレビュー
- mkt-content: コンテンツ作成
```

### パターン2: 権限レベル制御

AIに何を自動実行させ、何を人間の承認に回すかを明示する。

```markdown
## 権限レベル
- read-only: 分析・レポートは自動実行OK
- draft: メール・SNS投稿はドラフト作成のみ。送信は承認後
- execute: テスト実行・ビルドは自動実行OK
```

### パターン3: エラーハンドリング

AIがエラーに遭遇した時の振る舞いを定義する。

```markdown
## エラー時のルール
- 3回失敗したらエスカレーション
- 破壊的操作（git push --force等）は絶対に実行しない
- 不明な場合は必ず確認を求める
```

## よくある失敗と対策

| 失敗 | 原因 | 対策 |
|------|------|------|
| 指示が無視される | CLAUDE.mdが長すぎて埋もれる | 200行以内に収める。詳細は別ファイルへ |
| 意図と違う動作をする | 指示が曖昧 | 「〜してください」ではなく具体例を示す |
| 毎回スタイルがバラつく | コード規約が未定義 | linter設定 + CLAUDE.mdで二重に定義 |

## チーム開発での活用

CLAUDE.mdはGitで管理できるため、チーム全体で共有できる。

```
プロジェクトルート/
  CLAUDE.md          ← チーム共通ルール
  .claude/
    agents/
      dev-coder.md   ← 開発者向け指示
      reviewer.md    ← レビュアー向け指示
```

新メンバーが入っても、CLAUDE.mdを読めばプロジェクトの規約がすべてわかる。

## さらに深く学ぶ

本記事で紹介したのは基本的なパターンだけです。以下の書籍では、Hooks・Skills・MCP連携、マルチエージェント構成、セキュリティ設計まで、実務で使える設計パターンを全10章で網羅しています。

📘 **[CLAUDE.md設計パターン — AIエージェントを思い通りに動かす実践ガイド](https://zenn.dev/joinclass/books/claude-md-design-patterns)**
コピペで使えるテンプレート付き。プロジェクト規模別の設計ガイド。

📘 **[Claude Codeで会社を動かす — AIエージェント経営の実践記録](https://zenn.dev/joinclass/books/claude-code-ai-ceo)**
CLAUDE.mdを使って会社全体を運営する実践記録。

📘 **[Claude Codeマルチエージェント開発 — 設計・実装・運用の実践ガイド](https://zenn.dev/joinclass/books/claude-code-multi-agent)**
複数エージェントを協調させるための設計・実装パターン。

