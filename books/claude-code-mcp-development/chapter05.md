---
title: "データベース連携MCPサーバー"
free: false
---

# データベース連携MCPサーバー — SQLite/PostgreSQLとの接続

この章では、MCPサーバーからデータベースに接続し、Claude Codeが直接データを操作できる環境を構築します。

**この章で学ぶこと:**

- better-sqlite3を使ったローカルDB連携
- PostgreSQL接続（pgパッケージ）
- CRUD操作をMCP Toolとして実装する方法
- トランザクション管理のパターン
- スキーマ情報をResourcesとして公開するテクニック

## なぜデータベース連携MCPサーバーが必要なのか

開発中に「このテーブルの構造を確認したい」「テストデータを投入したい」「特定のレコードを検索したい」という場面は日常的に発生します。MCPサーバーでデータベース接続を提供すれば、Claude Codeとの対話の中で直接SQLを発行し、結果を受け取れるようになります。

ターミナルとDBクライアントを行き来する必要がなくなり、開発体験が大幅に向上します。

## SQLite連携 — better-sqlite3を使った実装

まずはローカルで手軽に試せるSQLiteから始めましょう。

### プロジェクトのセットアップ

```bash
mkdir mcp-database-server && cd mcp-database-server
npm init -y
npm install @modelcontextprotocol/sdk better-sqlite3 zod
npm install -D typescript @types/better-sqlite3 @types/node
npx tsc --init
```

### MCPサーバーの実装

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import Database from "better-sqlite3";
import { z } from "zod";

const DB_PATH = process.env.DB_PATH || "./data.db";
const db = new Database(DB_PATH);

// WALモードで高速化（読み書きの並行処理が可能になる）
db.pragma("journal_mode = WAL");

const server = new McpServer({
  name: "database-server",
  version: "1.0.0",
});
```

### SELECTクエリ Tool

読み取り専用のクエリを安全に実行するToolを実装します。

```typescript
server.tool(
  "query",
  "SQLiteデータベースにSELECTクエリを実行する",
  {
    sql: z.string().describe("実行するSELECTクエリ"),
    params: z.array(z.union([z.string(), z.number(), z.null()]))
      .optional()
      .describe("バインドパラメータ"),
  },
  async ({ sql, params }) => {
    // SELECT以外のクエリを弾く（安全性の確保）
    const normalized = sql.trim().toUpperCase();
    if (!normalized.startsWith("SELECT") && !normalized.startsWith("WITH")) {
      return {
        content: [{
          type: "text",
          text: "エラー: queryツールではSELECT/WITH文のみ実行可能です。データ変更にはexecuteツールを使用してください。",
        }],
      };
    }

    try {
      const rows = db.prepare(sql).all(...(params || []));
      return {
        content: [{
          type: "text",
          text: JSON.stringify(rows, null, 2),
        }],
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: `SQLエラー: ${error instanceof Error ? error.message : String(error)}`,
        }],
        isError: true,
      };
    }
  }
);
```

### データ変更 Tool（INSERT/UPDATE/DELETE）

```typescript
server.tool(
  "execute",
  "SQLiteデータベースにINSERT/UPDATE/DELETE文を実行する",
  {
    sql: z.string().describe("実行するSQL文"),
    params: z.array(z.union([z.string(), z.number(), z.null()]))
      .optional()
      .describe("バインドパラメータ"),
  },
  async ({ sql, params }) => {
    try {
      const result = db.prepare(sql).run(...(params || []));
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            changes: result.changes,
            lastInsertRowid: Number(result.lastInsertRowid),
          }),
        }],
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: `SQLエラー: ${error instanceof Error ? error.message : String(error)}`,
        }],
        isError: true,
      };
    }
  }
);
```

## トランザクション管理

複数のSQL文をまとめて実行するトランザクションToolを実装しましょう。これは「マスタデータの一括更新」や「テストデータの投入」で非常に便利です。

```typescript
server.tool(
  "transaction",
  "複数のSQL文をトランザクションとして実行する",
  {
    statements: z.array(z.object({
      sql: z.string(),
      params: z.array(z.union([z.string(), z.number(), z.null()])).optional(),
    })).describe("実行するSQL文の配列"),
  },
  async ({ statements }) => {
    const results: Array<{ changes: number }> = [];

    const runTransaction = db.transaction(() => {
      for (const stmt of statements) {
        const result = db.prepare(stmt.sql).run(...(stmt.params || []));
        results.push({ changes: result.changes });
      }
    });

    try {
      runTransaction();
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            success: true,
            totalStatements: statements.length,
            results,
          }, null, 2),
        }],
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: `トランザクションエラー（全てロールバック済み）: ${error instanceof Error ? error.message : String(error)}`,
        }],
        isError: true,
      };
    }
  }
);
```

better-sqlite3の`transaction()`メソッドを使うと、エラー時に自動でロールバックされるため安全です。

## スキーマ情報をResourcesとして公開

Claude Codeがデータベースの構造を把握できるように、テーブル一覧やカラム情報をResourcesとして公開しましょう。これにより「このDBにはどんなテーブルがあるの？」という質問にClaude Codeが自律的に回答できます。

```typescript
server.resource(
  "schema",
  "db://schema",
  async (uri) => {
    const tables = db.prepare(
      "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ).all() as Array<{ name: string; sql: string }>;

    const schemaInfo = tables.map((t) => {
      const columns = db.prepare(`PRAGMA table_info('${t.name}')`).all();
      return {
        table: t.name,
        createStatement: t.sql,
        columns,
      };
    });

    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(schemaInfo, null, 2),
      }],
    };
  }
);
```

## PostgreSQL連携

本番環境で使われることの多いPostgreSQLへの接続も実装してみましょう。基本的な構造はSQLiteと同じですが、接続管理やプレースホルダの書き方が異なります。

```typescript
import pg from "pg";

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5, // コネクションプール数を制限
});

server.tool(
  "pg_query",
  "PostgreSQLデータベースにSELECTクエリを実行する",
  {
    sql: z.string().describe("実行するSELECTクエリ（$1, $2...でパラメータ指定）"),
    params: z.array(z.union([z.string(), z.number(), z.null()]))
      .optional()
      .describe("バインドパラメータ"),
  },
  async ({ sql, params }) => {
    const normalized = sql.trim().toUpperCase();
    if (!normalized.startsWith("SELECT") && !normalized.startsWith("WITH")) {
      return {
        content: [{ type: "text", text: "エラー: SELECT/WITH文のみ実行可能です。" }],
      };
    }

    try {
      const result = await pool.query(sql, params || []);
      return {
        content: [{
          type: "text",
          text: JSON.stringify(result.rows, null, 2),
        }],
      };
    } catch (error) {
      return {
        content: [{ type: "text", text: `SQLエラー: ${error instanceof Error ? error.message : String(error)}` }],
        isError: true,
      };
    }
  }
);
```

PostgreSQLでは`$1, $2`形式のプレースホルダを使う点がSQLiteの`?`と異なります。また、`pg.Pool`を使ってコネクションプーリングを行うのが本番環境でのベストプラクティスです。

## サーバーの起動

```typescript
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Database MCP Server started");
}

main().catch(console.error);
```

## MCP設定への追加

`tsx` はTypeScriptファイルをビルドなしで直接実行できるツールです。`npm install -D tsx` でインストールできます。

`.mcp.json`にデータベースサーバーを登録します。

```json
{
  "mcpServers": {
    "database": {
      "command": "npx",
      "args": ["tsx", "/path/to/mcp-database-server/src/index.ts"],
      "env": {
        "DB_PATH": "./dev.db"
      }
    }
  }
}
```

## まとめ

この章では、MCPサーバーからSQLiteおよびPostgreSQLに接続し、Claude Codeが直接データベースを操作できる環境を構築しました。

- **query/execute の分離**: 読み取りと書き込みを別Toolにすることで安全性を確保
- **トランザクション**: 複数SQL文の一括実行とロールバック
- **スキーマ公開**: Resources機能でテーブル構造をClaude Codeに伝達
- **コネクション管理**: better-sqlite3の同期API、pgのPoolパターン

次章では、SlackやGitHub、NotionなどのSaaS APIと連携するMCPサーバーを構築し、Claude Codeから外部サービスを操作できるようにしていきます。
