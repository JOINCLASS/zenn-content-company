---
title: "Claude Code Computer Useを試してみた — Playwrightと比較して分かった「使いどころ」"
emoji: "🖥️"
type: "tech"
topics: ["claudecode", "ai", "自動化", "playwright", "テスト"]
published: true
---

## Claude Codeが「画面を見て操作する」時代

2026年3月、Anthropicが発表した。

> Computer use is now in Claude Code. Claude can open your apps, click through your UI, and test what it built, right from the CLI.

Claude Codeが、ターミナルからデスクトップアプリやブラウザを直接操作できるようになった。スクリーンショットを撮影して画面を認識し、マウスクリックやキーボード入力を実行する。

「これでPlaywrightが不要になるのでは？」と思い、実際に試してみた。結論から言う。

**繰り返し実行する自動化にはPlaywrightが圧倒的に優れている。Computer Useの価値は別のところにある。**

## Computer Useとは

Claude Codeに `computer use` を有効化すると、以下のことができる。

- スクリーンショットを撮影して画面を認識
- マウスクリック、ドラッグ、スクロール
- キーボード入力（テキスト、ショートカット）
- アプリケーションの起動・操作
- ブラウザを開いてWebページを操作

使い方は簡単だ。

```bash
claude config set --global computerUse true
```

あとはClaude Codeに「ブラウザを開いてlocalhost:3000の画面を確認して」と言うだけ。

## Playwright vs Computer Use — 比較してみた

筆者はCEO1名+AIで9部門を運営しており、Playwrightでnoteへの記事自動投稿やKDP登録を自動化している。これをComputer Useに置き換えられるか試した。

### 速度

**Playwright**: 記事投稿1件あたり約3分
**Computer Use**: 記事投稿1件あたり約15分

Computer Useは「スクリーンショット撮影 → API送信 → 応答受信 → 操作実行」のサイクルを1操作ごとに繰り返す。文字入力も1文字ごとにこのサイクルが走る。

### 精度

**Playwright**: DOMセレクタで確実に要素を特定。ピクセル単位の精度
**Computer Use**: 座標ベースのクリック。解像度やウィンドウサイズが変わるとズレる

実際にnoteのエディタでComputer Useを試したところ、「公開設定」ボタンの隣の「保存」ボタンを誤クリックした。Playwrightならセレクタで確実に「公開設定」を指定できる。

### コスト

**Playwright**: 無料（OSS）
**Computer Use**: スクリーンショット1枚あたり数千トークン消費。記事投稿1件で約$0.5-1.0

毎日の自動投稿にComputer Useを使うと、月$15-30の追加コストが発生する。Playwrightなら$0。

### セットアップ

**Playwright**: スクリプト作成が必要（初回のみ）
**Computer Use**: `computerUse true` を設定するだけ

ここだけはComputer Useが圧勝。「とりあえず動かしたい」ならComputer Useの方が圧倒的に速い。

### 比較まとめ

| 観点 | Playwright | Computer Use |
|------|-----------|-------------|
| 速度 | 速い（3分/件） | 遅い（15分/件） |
| 精度 | 高い（DOM直接操作） | 中（座標ベース） |
| コスト | 無料 | 高い（トークン消費） |
| セットアップ | コード必要 | 即使用可能 |
| 対象 | ブラウザのみ | 任意のアプリ |
| 再現性 | 高い | 低い |
| ヘッドレス | 標準対応 | 困難 |

## Computer Useの「本当の使いどころ」

ではComputer Useは使えないのか？そうではない。**使いどころが違う。**

### 1. 開発中のUIを視覚的にテストする

```
> 作ったReactアプリをブラウザで開いて、ボタンが動くか確認して
```

コードを書いた直後に、AIに「見て確認して」と言えるのは革新的だ。Playwrightでテストスクリプトを書く前に、まずComputer Useで目視確認 → 問題がなければPlaywrightで本テストを書く、という流れが効率的。

### 2. APIが存在しないサービスのプロトタイピング

新しいWebサービスを自動化したい時、まずComputer Useで「こうやって操作すればいい」とAIに学習させ、その操作をPlaywrightスクリプトに落とし込む。

「Computer Useで探索 → Playwrightで本番化」のワークフロー。

### 3. ネイティブアプリの操作

Playwrightはブラウザしか操作できない。Computer UseはFinderやターミナル、Excel等のネイティブアプリも操作できる。

ただし、ネイティブアプリの自動化が日常的に必要なケースは少ない。

## 筆者の結論

| やりたいこと | 使うべき技術 |
|-------------|-------------|
| 毎日の定型自動化 | **Playwright**（安定・高速・無料） |
| 開発中のUI確認 | **Computer Use**（即座に視覚テスト） |
| 新サービスの探索 | **Computer Use → Playwright化** |
| ネイティブアプリ操作 | **Computer Use**（唯一の選択肢） |

**Computer Useは「探索ツール」、Playwrightは「本番ツール」。** 役割が違う。

現在の自動化パイプライン（note投稿、KDP登録、SNS配信）はすべてPlaywrightのまま維持する。Computer Useは開発中の画面確認や、新しいサービスの自動化を検討する際の探索ツールとして使う。

## さらに詳しく

📘 **[Claude Code 全自動化バイブル — Hooks・Skills・MCP・cronで24時間働くAIを作る](https://zenn.dev/joinclass/books/claude-code-automation-bible)**
Playwright、Hooks、Skills、MCPを組み合わせた全自動化パイプラインの構築方法。第8章でPlaywrightの活用を詳しく解説。

📘 **[CLAUDE.md設計パターン](https://zenn.dev/joinclass/books/claude-md-design-patterns)**
Computer Use有効化時のCLAUDE.md設計も含む。

📕 全書籍一覧は **[こちら](https://zenn.dev/joinclass?tab=books)**
