---
title: "MCPサーバーでデータベースとClaude Codeを直接つなぐ — SQLite連携ハンズオン"
emoji: "🗄️"
type: "tech"
topics: ["claudecode", "mcp", "typescript", "sqlite", "プログラミング"]
published: true
---

## はじめに — 筆者がMCPサーバーを作った理由

僕はCEO1名+AIで会社の9部門を運営している。その中で「データベースの中身をAIに直接聞きたい」という場面が頻繁に発生した。

お問い合わせの件数、書籍の販売データ、コスト推移。毎回SQLを書くのは面倒だし、ダッシュボードを開くのも手間だ。

MCPサーバーを作ったことで、Claude Codeに「今月の問い合わせ件数は？」と聞くだけでDBから直接答えが返ってくるようになった。実際に当社のお問い合わせ管理システム（base-apis）で運用している仕組みをベースに、このチュートリアルを書いた。

## 「DBからデータ取って」が一言で済む世界

```
> 今月の新規ユーザー数を教えて
→ 今月の新規ユーザーは 47名です（前月比 +12%）
```

Claude Codeにこう聞くだけで、データベースに直接クエリを実行して結果を返す。MCPサーバーを作れば、これが実現できる。

## 完成形の構成

```
Claude Code ←→ MCP Server ←→ SQLite Database
                (TypeScript)
```

MCPサーバーが中間に入り、Claude Codeからのリクエストを受けてDBにクエリを実行する。

## Step 1: プロジェクト作成

```bash
mkdir mcp-db-server && cd mcp-db-server
npm init -y
npm install @modelcontextprotocol/sdk better-sqlite3 zod
npm install -D typescript @types/node @types/better-sqlite3
npx tsc --init
```

## Step 2: データベース初期化

```typescript
// src/db.ts
import Database from "better-sqlite3";

const db = new Database("./data.db");

// テーブル作成
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  )
`);

export default db;
```

## Step 3: MCPサーバー実装

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import db from "./db.js";

const server = new McpServer({
  name: "db-server",
  version: "1.0.0",
});

// Tool: ユーザー検索
server.tool(
  "search-users",
  "ユーザーをキーワードで検索する",
  {
    query: z.string().describe("検索キーワード（名前またはメール）"),
    limit: z.number().default(10).describe("取得件数"),
  },
  async ({ query, limit }) => {
    const rows = db.prepare(
      "SELECT * FROM users WHERE name LIKE ? OR email LIKE ? LIMIT ?"
    ).all(`%${query}%`, `%${query}%`, limit);
    return {
      content: [{ type: "text", text: JSON.stringify(rows, null, 2) }],
    };
  }
);

// Tool: ユーザー追加
server.tool(
  "add-user",
  "新しいユーザーを追加する",
  {
    name: z.string().describe("ユーザー名"),
    email: z.string().email().describe("メールアドレス"),
  },
  async ({ name, email }) => {
    const result = db.prepare(
      "INSERT INTO users (name, email) VALUES (?, ?)"
    ).run(name, email);
    return {
      content: [{ type: "text", text: `ユーザーを追加しました（ID: ${result.lastInsertRowid}）` }],
    };
  }
);

// Tool: 統計情報
server.tool(
  "get-stats",
  "ユーザーの統計情報を取得する",
  {},
  async () => {
    const total = db.prepare("SELECT COUNT(*) as count FROM users").get() as { count: number };
    const thisMonth = db.prepare(
      "SELECT COUNT(*) as count FROM users WHERE created_at >= date('now', 'start of month')"
    ).get() as { count: number };
    return {
      content: [{
        type: "text",
        text: `総ユーザー数: ${total.count}\n今月の新規: ${thisMonth.count}`,
      }],
    };
  }
);

// Resource: スキーマ情報
server.resource(
  "schema://tables",
  "データベースのテーブル構造",
  "application/json",
  async () => {
    const tables = db.prepare(
      "SELECT sql FROM sqlite_master WHERE type='table'"
    ).all();
    return {
      contents: [{ text: JSON.stringify(tables, null, 2) }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

## Step 4: Claude Codeに登録

`.claude/settings.json`:

```json
{
  "mcpServers": {
    "db-server": {
      "command": "node",
      "args": ["./dist/index.js"]
    }
  }
}
```

## 動作確認

Claude Codeを起動して話しかけるだけ。

```
> ユーザー「田中」を検索して
→ search-usersツールを実行... 3件のユーザーが見つかりました

> 今月の統計を教えて
→ get-statsツールを実行... 総ユーザー数: 156、今月の新規: 23

> このDBのテーブル構造を見せて
→ schema://tablesリソースを参照... CREATE TABLE users (...)
```

## 筆者の実運用での学び

当社ではこの仕組みをお問い合わせ管理（base-apis）で実際に使っている。導入して気づいたことを3つ共有する。

1. **読み取り専用にしないと危険。** 最初はINSERT/UPDATEも許可していたが、AIが意図しないデータ変更をする可能性がある。本番DBには必ず読み取り専用で接続すべき。

2. **スキーマ情報のResource公開が便利。** AIがテーブル構造を自動で把握するので、「このテーブルのカラムは何？」と聞く必要がなくなった。

3. **MCP説明文は2KB以内に収める。** Claude Code v2.1からMCPの説明文が2KBで自動カットされるようになった。重要な情報を先頭に書くこと。

## セキュリティの注意点

- **読み取り専用にしたい場合**: `better-sqlite3` の `readonly: true` オプションを使う
- **SQLインジェクション対策**: プリペアドステートメントを必ず使う（上記コードは対策済み）
- **本番DBに接続する場合**: 読み取り専用のレプリカを使うこと

## さらに詳しく

📘 **[Claude Code × MCP サーバー開発入門 — 外部ツール連携で生産性を10倍にする実践ガイド](https://zenn.dev/joinclass/books/claude-code-mcp-development)**
第5章でデータベース連携MCPサーバーの詳細な実装パターンを解説。認証・スキーマ公開・バッチ処理まで。

📘 **[CLAUDE.md設計パターン](https://zenn.dev/joinclass/books/claude-md-design-patterns)**
MCPサーバーをCLAUDE.mdから効果的に活用する設定パターン。

📕 全書籍一覧は **[こちら](https://zenn.dev/joinclass?tab=books)**
