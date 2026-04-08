---
title: "Claude Codeマルチエージェント設計パターン — Orchestrator・Worker・Reviewerの使い分け"
emoji: "🤖"
type: "tech"
topics: ["claudecode", "ai", "マルチエージェント", "設計パターン", "プログラミング"]
published: true
---

## 1つのAIでは限界がある

Claude Codeを使い込んでいくと、ある壁にぶつかる。**「1つのセッションで全部やらせると、品質が落ちる」** という問題だ。

コードを書かせながらレビューもさせると、自分で書いたコードのバグを見逃す。開発と経理を同じセッションで処理すると、コンテキストが混ざって精度が下がる。

解決策は、**複数のエージェントを役割分担させる**こと。

## 3つの基本パターン

### パターン1: Orchestrator（指揮者）

全体を統括するエージェント。自分では実作業をせず、タスクを適切なWorkerに振り分ける。

```markdown
# CLAUDE.md（Orchestrator）
あなたはOrchestratorです。
- 複雑なタスクは .claude/agents/ のサブエージェントに委任
- 自分でコーディングや文書作成を行わない
- コンテキスト使用率を10-15%に維持する
```

**使うべき場面:** プロジェクト全体の管理、複数部門の調整

### パターン2: Worker（作業者）

特定の専門タスクを実行するエージェント。1つの役割に特化させることで精度が上がる。

```markdown
# .claude/agents/dev-coder.md
あなたはコーディング専門のWorkerです。
- TypeScript + Next.jsの実装のみを担当
- テストコードも同時に書く
- レビューは別のエージェントが行う
```

**使うべき場面:** コーディング、記事作成、データ分析、提案書作成

### パターン3: Reviewer（検証者）

Workerの成果物を検証するエージェント。**書いた本人にレビューさせない**のがポイント。

```markdown
# .claude/agents/dev-reviewer.md
あなたはコードレビュー専門のReviewerです。
- セキュリティ脆弱性のチェック
- パフォーマンス問題の指摘
- コーディング規約の準拠確認
```

**使うべき場面:** コードレビュー、文書校正、セキュリティ監査

## 実践例: 開発フロー

```
CEO: 「ログイン機能を実装して」
  ↓
Orchestrator: タスクを分解
  ↓
dev-coder (Worker): 実装
  ↓
dev-reviewer (Reviewer): レビュー → 指摘事項
  ↓
dev-coder (Worker): 修正
  ↓
Orchestrator: 完了報告
```

1つのセッションで全部やるより、**品質が圧倒的に高くなる**。

## エージェント間の通信

Claude Codeのサブエージェント機能を使えば、自動的にエージェント間でタスクが流れる。

```markdown
## CLAUDE.mdでの設定
サブエージェントに委任する際は、以下を渡す:
1. タスクの目的（1文で）
2. 参照ファイルパス
3. 成果物の出力先
4. 権限レベル（read-only / draft / execute）
5. 品質基準
```

## やってはいけないアンチパターン

### ❌ 全部Orchestratorにやらせる

Orchestratorが実作業まで行うと、コンテキストが膨張して精度が落ちる。指揮者は指揮に専念。

### ❌ Worker同士を直接連携させる

Worker A → Worker B の直接通信は管理が難しい。必ずOrchestratorを経由させる。

### ❌ Reviewerに修正もさせる

レビューと修正を同じエージェントがやると、レビューの客観性が失われる。指摘と修正は分離する。

## まとめ

| パターン | 役割 | コンテキスト |
|---------|------|------------|
| Orchestrator | タスク振り分け・全体管理 | 最小限（パスだけ渡す） |
| Worker | 専門タスクの実行 | 担当領域のみ |
| Reviewer | 成果物の検証 | 成果物+基準のみ |

## さらに詳しく

📘 **[Claude Codeマルチエージェント開発 — 設計・実装・運用の実践ガイド](https://zenn.dev/joinclass/books/claude-code-multi-agent)**
Orchestrator・Worker・Reviewerの具体的な実装コードと運用ノウハウを全12章で解説。

📘 **[CLAUDE.md設計パターン — AIエージェントを思い通りに動かす実践ガイド](https://zenn.dev/joinclass/books/claude-md-design-patterns)**
各エージェントのCLAUDE.md設計パターンを網羅。

📕 全書籍一覧は **[こちら](https://zenn.dev/joinclass?tab=books)**
