---
title: "テストとデバッグ"
free: false
---

# テストとデバッグ -- MCP Inspector・ログ・エラーハンドリング

## この章で学ぶこと

- MCP Inspectorを使ったインタラクティブなテスト方法
- vitestによるユニットテストの書き方
- 実際にサーバーを起動する統合テスト
- stderr を使ったログ出力のベストプラクティス
- 堅牢なエラーハンドリングパターン
- よくあるトラブルとデバッグのコツ

## MCP Inspector -- 最初のデバッグツール

MCPサーバーを開発するとき、最初に使うべきツールがMCP Inspectorです。ブラウザベースのGUIで、MCPサーバーに接続してTools・Resources・Promptsをインタラクティブに実行・確認できます。

### MCP Inspectorの起動

```bash
npx @modelcontextprotocol/inspector npx tsx src/index.ts
```

このコマンドを実行すると、ブラウザが自動で開き、MCPサーバーの全機能を試せるUIが表示されます。

MCP Inspectorでできることは主に以下の3つです。

1. **ツール一覧の確認** -- 登録されたToolの名前、説明、パラメータスキーマを一覧表示
2. **ツールの手動実行** -- パラメータを入力してToolを実行し、レスポンスを確認
3. **Resources/Promptsの確認** -- リソースの読み取り、プロンプトの展開をテスト

環境変数が必要なサーバーの場合は、以下のように渡します。

```bash
npx @modelcontextprotocol/inspector \
  -e DB_PATH=./test.db \
  -e API_KEY=test-key \
  npx tsx src/index.ts
```

MCP Inspectorは「動くかどうか」の確認には最適ですが、自動テストの代わりにはなりません。次にユニットテストの書き方を見ていきましょう。

## ユニットテスト（vitest）

MCPサーバーのユニットテストでは、ビジネスロジックをサーバー定義から分離するのがコツです。

### テスト対象の分離

```typescript
// src/handlers.ts -- テスト可能なビジネスロジック
import Database from "better-sqlite3";

export function executeQuery(
  db: Database.Database,
  sql: string,
  params: Array<string | number | null> = []
) {
  const normalized = sql.trim().toUpperCase();
  if (!normalized.startsWith("SELECT") && !normalized.startsWith("WITH")) {
    throw new Error("SELECT/WITH文のみ実行可能です");
  }
  return db.prepare(sql).all(...params);
}

export function executeStatement(
  db: Database.Database,
  sql: string,
  params: Array<string | number | null> = []
) {
  const result = db.prepare(sql).run(...params);
  return {
    changes: result.changes,
    lastInsertRowid: Number(result.lastInsertRowid),
  };
}
```

```typescript
// src/index.ts -- サーバー定義はハンドラを呼ぶだけ
import { executeQuery, executeStatement } from "./handlers.js";

server.tool("query", ..., async ({ sql, params }) => {
  try {
    const rows = executeQuery(db, sql, params);
    return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
  } catch (error) {
    return { content: [{ type: "text", text: (error as Error).message }], isError: true };
  }
});
```

### テストの実装

```bash
npm install -D vitest
```

```typescript
// src/__tests__/handlers.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import Database from "better-sqlite3";
import { executeQuery, executeStatement } from "../handlers.js";

describe("executeQuery", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.exec(`
      CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
      INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
      INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');
    `);
  });

  afterEach(() => {
    db.close();
  });

  it("SELECTクエリを実行できる", () => {
    const rows = executeQuery(db, "SELECT * FROM users");
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ name: "Alice" });
  });

  it("パラメータ付きクエリを実行できる", () => {
    const rows = executeQuery(db, "SELECT * FROM users WHERE name = ?", ["Bob"]);
    expect(rows).toHaveLength(1);
  });

  it("SELECT以外のクエリを拒否する", () => {
    expect(() => executeQuery(db, "DELETE FROM users")).toThrow(
      "SELECT/WITH文のみ実行可能です"
    );
  });

  it("WITH句（CTE）を許可する", () => {
    const rows = executeQuery(
      db,
      "WITH active AS (SELECT * FROM users) SELECT * FROM active"
    );
    expect(rows).toHaveLength(2);
  });
});

describe("executeStatement", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
  });

  afterEach(() => {
    db.close();
  });

  it("INSERTを実行し結果を返す", () => {
    const result = executeStatement(
      db,
      "INSERT INTO users (name) VALUES (?)",
      ["Charlie"]
    );
    expect(result.changes).toBe(1);
    expect(result.lastInsertRowid).toBe(1);
  });
});
```

## 統合テスト -- サーバー起動テスト

実際にMCPサーバーを起動し、MCPプロトコルでやり取りする統合テストも書きましょう。`@modelcontextprotocol/sdk`のクライアントを使います。

```typescript
// src/__tests__/integration.test.ts
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

describe("Database MCP Server (統合テスト)", () => {
  let client: Client;
  let transport: StdioClientTransport;

  beforeAll(async () => {
    transport = new StdioClientTransport({
      command: "npx",
      args: ["tsx", "src/index.ts"],
      env: { ...process.env, DB_PATH: ":memory:" },
    });

    client = new Client(
      { name: "test-client", version: "1.0.0" },
      { capabilities: {} }
    );

    await client.connect(transport);
  });

  afterAll(async () => {
    await client.close();
  });

  it("ツール一覧を取得できる", async () => {
    const result = await client.listTools();
    const toolNames = result.tools.map((t) => t.name);
    expect(toolNames).toContain("query");
    expect(toolNames).toContain("execute");
  });

  it("queryツールでSELECTを実行できる", async () => {
    // まずテーブルを作成
    await client.callTool({
      name: "execute",
      arguments: {
        sql: "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, value TEXT)",
      },
    });

    await client.callTool({
      name: "execute",
      arguments: {
        sql: "INSERT INTO test (value) VALUES (?)",
        params: ["hello"],
      },
    });

    const result = await client.callTool({
      name: "query",
      arguments: { sql: "SELECT * FROM test" },
    });

    const text = (result.content as Array<{ type: string; text: string }>)[0].text;
    const rows = JSON.parse(text);
    expect(rows).toHaveLength(1);
    expect(rows[0].value).toBe("hello");
  });
});
```

## ログ出力のベストプラクティス

MCPサーバーでのログ出力には**必ず`console.error`（stderr）を使ってください**。`console.log`（stdout）はMCPプロトコルの通信に使われるため、ログを書くと通信が壊れます。

```typescript
// stdoutに書くと通信が壊れる
console.log("This breaks MCP protocol!");

// stderrに書くのが正解
console.error("This is safe for logging");
```

構造化ログを実装すると、後からのデバッグが格段に楽になります。

```typescript
type LogLevel = "debug" | "info" | "warn" | "error";

function log(level: LogLevel, message: string, data?: Record<string, unknown>) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data,
  };
  console.error(JSON.stringify(entry));
}

// 使用例
log("info", "Tool called", { tool: "query", sql: "SELECT * FROM users" });
log("error", "Query failed", { sql, error: err.message });
```

ファイルにログを書き出したい場合は、stderrのリダイレクトを`.mcp.json`で設定できます。

```json
{
  "mcpServers": {
    "database": {
      "command": "sh",
      "args": ["-c", "npx tsx src/index.ts 2>> /tmp/mcp-database.log"]
    }
  }
}
```

## エラーハンドリングパターン

MCPサーバーでエラーが発生した場合、サーバープロセスをクラッシュさせてはいけません。エラーをキャッチして、`isError: true`のレスポンスを返しましょう。

```typescript
// エラーハンドリングのラッパー関数
function withErrorHandling<T extends Record<string, unknown>>(
  handler: (args: T) => Promise<{ content: Array<{ type: string; text: string }> }>
) {
  return async (args: T) => {
    try {
      return await handler(args);
    } catch (error) {
      log("error", "Tool execution failed", {
        error: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      });
      return {
        content: [{
          type: "text" as const,
          text: `エラーが発生しました: ${error instanceof Error ? error.message : String(error)}`,
        }],
        isError: true as const,
      };
    }
  };
}
```

タイムアウトの実装も重要です。外部APIを呼ぶToolでは、無限に待ち続けることを防ぎましょう。

```typescript
function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error(`Timeout after ${ms}ms`)), ms)
    ),
  ]);
}

// 使用例
server.tool("api_call", ..., async ({ url }) => {
  const response = await withTimeout(fetch(url), 10000);
  // ...
});
```

## よくあるトラブルとデバッグのコツ

### 1. サーバーが起動しない

最も多い原因は`console.log`の使用です。stdoutに余計な出力があるとMCPプロトコルのハンドシェイクが失敗します。すべてのログ出力を`console.error`に変更してください。

### 2. ツールが認識されない

サーバーは起動するが、Claude Codeでツールが表示されない場合は、MCP Inspectorで確認しましょう。`server.tool()`の呼び出しが`server.connect()`より前に行われているか確認してください。

### 3. 環境変数が渡らない

`.mcp.json`の`env`フィールドに設定した環境変数は、サーバープロセスの環境に注入されます。`process.env`で読み取れない場合は、JSONの構文エラー（末尾カンマなど）がないか確認しましょう。

### 4. 大きなレスポンスでタイムアウトする

MCPのレスポンスが大きすぎると、Claude Codeのコンテキストウインドウを圧迫します。結果を要約するか、ページネーションで分割しましょう。

```typescript
// 結果が大きい場合はサマリーを返す
const rows = db.prepare(sql).all();
if (rows.length > 100) {
  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        totalCount: rows.length,
        preview: rows.slice(0, 10),
        message: `${rows.length}件中10件を表示。limitで絞り込んでください。`,
      }, null, 2),
    }],
  };
}
```

## まとめ

- **MCP Inspector**はサーバー開発の必須ツール。まずここで動作確認する
- ビジネスロジックをハンドラに分離して**vitestでユニットテスト**を書く
- **SDKのClient**を使った統合テストで、プロトコルレベルの動作を検証する
- ログは**必ずstderr**（`console.error`）に出力する。stdoutはMCP通信に使われる
- エラーは**キャッチしてisError:trueで返す**。プロセスをクラッシュさせない
- トラブルの大半は`console.log`の混入、環境変数の未設定、レスポンスサイズの肥大化

次章では、MCPサーバーを本番環境で安定稼働させるためのDocker化、モニタリング、CI/CDについて学びます。
