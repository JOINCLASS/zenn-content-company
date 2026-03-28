---
title: "MCPサーバーを30分で作る — Claude Code × MCP開発入門【2026年版】"
emoji: "🔌"
type: "tech"
topics: ["claudecode", "mcp", "typescript", "ai", "プログラミング"]
published: false
---

## MCPとは

**MCP（Model Context Protocol）** は、AIアシスタントが外部のツールやデータソースと安全に連携するための標準プロトコルだ。Anthropicが策定し、2025年後半から急速に普及している。

簡単に言えば、**Claude Codeに「新しい能力」を追加するプラグインの仕組み**。

例えば:
- データベースを直接クエリする
- 外部APIからデータを取得する
- ファイルシステムを操作する
- Slackにメッセージを送る

これらをMCPサーバーとして実装すれば、Claude Codeが自律的に使えるようになる。

## なぜMCPが必要か

Claude Code単体でもBash経由でコマンドは実行できる。しかしMCPには3つの利点がある。

| | Bash直接実行 | MCPサーバー |
|--|------------|------------|
| 安全性 | コマンドインジェクションのリスク | 型付きパラメータで安全 |
| 再利用性 | 毎回コマンドを組み立て | 一度作れば繰り返し使える |
| 発見性 | AIがツールの存在を知らない | AIが自動的にツール一覧を認識 |

## 環境構築（5分）

### 前提条件

- Node.js 18以上
- Claude Code インストール済み

### プロジェクト作成

```bash
mkdir my-mcp-server && cd my-mcp-server
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node
npx tsc --init
```

`tsconfig.json` の主要設定:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "strict": true
  }
}
```

## 最初のMCPサーバー（Hello World）

`src/index.ts` を作成:

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "hello-mcp",
  version: "1.0.0",
});

// Toolの定義
server.tool(
  "greet",
  "指定した名前で挨拶する",
  { name: z.string().describe("挨拶する相手の名前") },
  async ({ name }) => ({
    content: [{ type: "text", text: `こんにちは、${name}さん！` }],
  })
);

// サーバー起動
const transport = new StdioServerTransport();
await server.connect(transport);
```

### ビルドと登録

```bash
npx tsc
```

Claude Codeの設定ファイル（`~/.claude/settings.json` または `.claude/settings.json`）に追加:

```json
{
  "mcpServers": {
    "hello-mcp": {
      "command": "node",
      "args": ["./dist/index.js"]
    }
  }
}
```

これでClaude Codeを再起動すれば、`greet` ツールが使えるようになる。

## MCPの3つの機能

MCPサーバーは3種類の機能を提供できる。

### 1. Tools（ツール）
AIが**能動的に実行**できるアクション。引数を受け取り、結果を返す。

```typescript
server.tool("search-users", "ユーザーを検索する",
  { query: z.string() },
  async ({ query }) => {
    const results = await db.searchUsers(query);
    return { content: [{ type: "text", text: JSON.stringify(results) }] };
  }
);
```

### 2. Resources（リソース）
AIが**参照できるデータ**。固定URIで公開する。

```typescript
server.resource("config://app", "アプリ設定",
  "application/json",
  async () => ({
    contents: [{ text: JSON.stringify(appConfig) }],
  })
);
```

### 3. Prompts（プロンプト）
再利用可能な**プロンプトテンプレート**。

```typescript
server.prompt("code-review", "コードレビュー依頼",
  [{ name: "file", description: "レビュー対象ファイル" }],
  async ({ file }) => ({
    messages: [{
      role: "user",
      content: { type: "text", text: `以下のファイルをレビューしてください: ${file}` }
    }],
  })
);
```

## 実用的なMCPサーバーの例

### データベース連携

```typescript
server.tool("query-customers", "顧客データを検索",
  {
    industry: z.string().optional(),
    limit: z.number().default(10),
  },
  async ({ industry, limit }) => {
    const query = industry
      ? `SELECT * FROM customers WHERE industry = ? LIMIT ?`
      : `SELECT * FROM customers LIMIT ?`;
    const results = await db.all(query, industry ? [industry, limit] : [limit]);
    return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] };
  }
);
```

### 外部API連携

```typescript
server.tool("get-weather", "天気予報を取得",
  { city: z.string() },
  async ({ city }) => {
    const res = await fetch(`https://api.weather.example.com/${city}`);
    const data = await res.json();
    return { content: [{ type: "text", text: `${city}: ${data.temp}°C, ${data.condition}` }] };
  }
);
```

## この先の学習

本記事ではMCPの入門部分を紹介しました。実践的な開発では、以下のテーマが重要になります:

- ファイルシステム操作のCRUD実装
- SQLiteデータベース連携
- 認証・セキュリティ（APIキー管理、アクセス制御）
- 複数MCPサーバーの組み合わせ
- テスト・デバッグ手法
- 本番環境へのデプロイ

これらを全12章のハンズオン形式で体系的に解説した書籍を公開しています。

📘 **[Claude Code × MCP サーバー開発入門 — 外部ツール連携で生産性を10倍にする実践ガイド](https://zenn.dev/joinclass/books/claude-code-mcp-development)**
実際に動くMCPサーバーを作りながら学ぶ。ファイルシステム操作から本番運用まで。

📘 **[CLAUDE.md設計パターン — AIエージェントを思い通りに動かす実践ガイド](https://zenn.dev/joinclass/books/claude-md-design-patterns)**
MCPサーバーをCLAUDE.mdから効果的に活用するための設計パターン。

📘 **[Claude Codeマルチエージェント開発 — 設計・実装・運用の実践ガイド](https://zenn.dev/joinclass/books/claude-code-multi-agent)**
MCPサーバーを複数エージェントで共有・連携させる設計手法。

