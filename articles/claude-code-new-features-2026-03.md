---
title: "Claude Code v2.1の新機能まとめ — /effort・PostCompact Hook・セッション名で自動化が進化する"
emoji: "🚀"
type: "tech"
topics: ["claudecode", "ai", "自動化", "プログラミング", "cli"]
published: true
---

## Claude Code v2.1で何が変わったか

Claude Codeが2026年3月にかけて複数のアップデートをリリースした。この記事では、**自動化に特に影響が大きい新機能**を5つピックアップし、実際の活用方法を解説する。

## 1. /effort コマンド — コスト最適化の切り札

```bash
# 軽量タスクはeffort lowで実行（トークン消費を削減）
claude --effort low -p "この関数の型定義を修正して"

# 複雑なタスクはeffort high
claude --effort high -p "アーキテクチャを見直して全体をリファクタリング"
```

`/effort` はClaude Codeの「思考の深さ」を制御するコマンドだ。

**low**: 単純なタスク（lint修正、型エラー、簡単な質問）
**medium**: 通常のタスク（デフォルト）
**high**: 複雑なタスク（設計判断、大規模リファクタリング）

自動化スクリプトで毎日実行するような定型タスクに `--effort low` を指定すれば、**APIコストを大幅に削減**できる。

筆者の環境では、記事の自動生成スクリプトに `--effort low` を適用したところ、月額のトークン消費が約20%減少した。

## 2. --name フラグ — セッションの可視化

```bash
claude --name "morning-digest" -p "朝のダイジェストを生成して"
claude --name "article-gen" -p "Zenn記事を1本書いて"
```

`--name` でセッションに名前をつけられるようになった。複数のClaude Codeプロセスが並行して動いている環境では、**どのセッションが何をしているか一目で分かる**。

`claude.ai/code` のダッシュボードにもセッション名が表示されるため、Remote Controlで外出先からモニタリングする際にも便利だ。

## 3. PostCompact Hook — コンテキスト圧縮時の対応

Claude Codeは長いセッションでコンテキストが大きくなると、自動的に圧縮（compact）を行う。このとき、圧縮前のコンテキストの一部が失われることがある。

**PostCompact Hook** を設定すると、圧縮が発生した直後にスクリプトを実行できる。

```json
{
  "hooks": {
    "PostCompact": [
      {
        "command": "echo '$(date): context compacted' >> /tmp/compact.log"
      }
    ]
  }
}
```

活用例:
- 圧縮発生をSlackに通知する
- 圧縮前の重要な変数・状態をファイルに書き出す
- 圧縮回数をカウントして、セッション分割の判断材料にする

## 4. system-prompt キャッシュ改善

CLAUDE.mdやエージェント定義ファイルが**自動的にキャッシュされる**ようになった。

以前は毎回のリクエストでCLAUDE.mdの全内容がトークンとして消費されていたが、キャッシュにより**2回目以降のリクエストでトークン消費がほぼゼロ**になる。

これにより、CLAUDE.mdを充実させてもコストが増えにくくなった。ただし、CLAUDE.mdを更新した直後はキャッシュが無効化されるため、頻繁な更新は避けたほうがよい。

## 5. MCP説明文の2KB自動カット

MCPサーバーの `description` フィールドが**2KBに自動カット**されるようになった。

MCPサーバーを多数登録している環境では、各サーバーの説明文がコンテキストを圧迫していた。2KB制限により、コンテキストの使用量が予測しやすくなった。

**対策**: 説明文の先頭2KB以内に重要な情報を集約する。長い説明は別ドキュメントに分離し、MCPのdescriptionにはリンクだけを書く。

## まとめ

| 機能 | 用途 | インパクト |
|------|------|-----------|
| `/effort` | コスト最適化 | 月20%のトークン削減（軽量タスク） |
| `--name` | セッション管理 | 並行プロセスの可視化 |
| PostCompact Hook | コンテキスト管理 | 長時間タスクの安定性向上 |
| system-prompt キャッシュ | コスト削減 | CLAUDE.mdのトークン消費ほぼゼロ |
| MCP 2KB制限 | コンテキスト管理 | 予測可能なコンテキスト使用量 |

Claude Codeは頻繁にアップデートされる。自動化パイプラインを運用しているなら、これらの新機能をキャッチアップして取り入れることで、コスト最適化と安定性向上が実現できる。

## さらに詳しく

📘 **[Claude Code 全自動化バイブル — Hooks・Skills・MCP・cronで24時間働くAIを作る](https://zenn.dev/joinclass/books/claude-code-automation-bible)**
Hooks、Skills、MCPを組み合わせた全自動化パイプラインの構築方法を全12章で解説。

📘 **[CLAUDE.md設計パターン — AIエージェントを思い通りに動かす実践ガイド](https://zenn.dev/joinclass/books/claude-md-design-patterns)**
CLAUDE.mdのsystem-promptキャッシュを最大限活用する設計パターン。

📕 全書籍一覧は **[こちら](https://zenn.dev/joinclass?tab=books)**
