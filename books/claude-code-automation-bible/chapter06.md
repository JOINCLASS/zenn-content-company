---
title: "MCPサーバーで外部ツールと連携する"
---

# MCPサーバーで外部ツールと連携する

## この章で学ぶこと

- MCP（Model Context Protocol）の3つの機能（Tools, Resources, Prompts）
- 実装例1: Slack通知MCPサーバーの構築
- 実装例2: データベースクエリMCPサーバーの構築
- 実装例3: FTPデプロイMCPサーバーの構築
- Claude Codeへの登録方法（settings.json）
- セキュリティ対策（APIキー管理、アクセス制御）

## MCPとは

MCP（Model Context Protocol）は、AIモデルと外部ツール・データソースを接続するための標準プロトコルです。Anthropicが2024年末にオープンソースとして公開しました。

Claude Codeの文脈では、MCPサーバーは「Claude Codeに新しい能力を追加するプラグイン」と考えてください。Slack通知、データベースクエリ、FTPアップロードなど、Claude Code単体ではできない操作を、MCPサーバー経由で実行できるようになります。

```
Claude Code → MCPクライアント → MCPサーバー → 外部サービス
                                  (あなたが作る)    (Slack, DB, FTP...)
```

## MCPの3つの機能

MCPサーバーは3種類の機能を提供できます。

### Tools（ツール）

AIが呼び出せる関数です。「Slackにメッセージを送信する」「SQLクエリを実行する」のような、**アクションを実行する**機能。

```typescript
// Toolの定義例: Slackにメッセージを送る
server.tool(
  "send_slack",                              // ツール名
  "Slackチャンネルにメッセージを送信する",        // 説明
  { channel: z.string(), message: z.string() }, // パラメータ
  async ({ channel, message }) => {            // 実行関数
    // Slack APIを呼ぶ
  }
);
```

### Resources（リソース）

AIが読み取れるデータソースです。「データベースのスキーマ情報」「設定ファイルの内容」のような、**情報を提供する**機能。

```typescript
// Resourceの定義例: DBのテーブル一覧
server.resource(
  "schema://tables",
  "データベースのテーブル一覧",
  async () => ({
    contents: [{ uri: "schema://tables", text: tableList }]
  })
);
```

### Prompts（プロンプト）

再利用可能なプロンプトテンプレートです。スキルと似ていますが、MCPサーバー側で定義・管理する点が異なります。本書の自動化パイプラインでは主にToolsとResourcesを使うため、Promptsの詳細は割愛します。

### 使い分けの指針

| 機能 | 用途 | 例 |
|------|------|-----|
| Tools | 外部サービスへのアクション | 通知送信、ファイルアップロード、API呼び出し |
| Resources | 情報の提供 | スキーマ情報、設定値、ログ |
| Prompts | テンプレート化された指示 | コードレビュー手順、デプロイチェックリスト |

## MCPサーバーの基本構造

すべてのMCPサーバーは同じ構造で作れます。まずはプロジェクトのセットアップから。

```bash
mkdir mcp-slack-server && cd mcp-slack-server
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node
npx tsc --init
```

`tsconfig.json` の最低限の設定:

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

サーバーの骨格は以下のとおりです。

```typescript
// src/index.ts — すべてのMCPサーバーの出発点
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

// サーバーインスタンスを作成
const server = new McpServer({
  name: "my-server",   // サーバー名（settings.jsonのキーと一致させる）
  version: "1.0.0",
});

// ここにTools, Resources, Promptsを定義
// server.tool(...)
// server.resource(...)

// stdio経由で通信を開始
const transport = new StdioServerTransport();
await server.connect(transport);
```

`StdioServerTransport` は標準入出力を使った通信です。Claude Codeがサーバープロセスを起動し、stdin/stdoutでJSON-RPCメッセージをやり取りします。HTTPサーバーを立てる必要はありません。

## 実装例1: Slack通知MCPサーバー

筆者の自動化パイプラインで最も使うMCPサーバーです。デプロイ完了通知、エラーアラート、日次レポートなど、あらゆる場面でSlack通知を行います。

### 完全な実装

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// 環境変数からWebhook URLを取得（セキュリティ上、コードに埋め込まない）
const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;
if (!SLACK_WEBHOOK_URL) {
  console.error("SLACK_WEBHOOK_URL is required");
  process.exit(1);
}

const server = new McpServer({
  name: "slack-notifier",
  version: "1.0.0",
});

// Tool 1: シンプルなテキスト通知
server.tool(
  "send_message",
  "Slackチャンネルにテキストメッセージを送信する",
  {
    text: z.string().describe("送信するメッセージ本文"),
  },
  async ({ text }) => {
    const response = await fetch(SLACK_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });

    if (!response.ok) {
      return {
        content: [{
          type: "text",
          text: `Slack送信失敗: ${response.status} ${response.statusText}`,
        }],
        isError: true,
      };
    }

    return {
      content: [{ type: "text", text: "Slack送信完了" }],
    };
  }
);

// Tool 2: Block Kit形式のリッチ通知
server.tool(
  "send_blocks",
  "Slack Block Kit形式でリッチなメッセージを送信する",
  {
    blocks: z.string().describe("Block Kit JSONの文字列"),
    text: z.string().describe("フォールバックテキスト（通知プレビュー用）"),
  },
  async ({ blocks, text }) => {
    const response = await fetch(SLACK_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text,
        blocks: JSON.parse(blocks),
      }),
    });

    if (!response.ok) {
      return {
        content: [{
          type: "text",
          text: `Slack送信失敗: ${response.status}`,
        }],
        isError: true,
      };
    }

    return {
      content: [{ type: "text", text: "Block Kit メッセージ送信完了" }],
    };
  }
);

// 起動
const transport = new StdioServerTransport();
await server.connect(transport);
```

### ビルドと動作確認

```bash
# ビルド
npx tsc

# 動作確認（stdioなのでJSON-RPCを直接送る）
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  SLACK_WEBHOOK_URL="your-slack-webhook-url" \
  node dist/index.js
```

正常であれば、`send_message` と `send_blocks` の2つのツールがJSON形式で返ります。

## 実装例2: データベースクエリMCPサーバー

開発中にSQLを直接実行できるMCPサーバーです。Claude Codeとの対話の中で「このテーブルの構造を見せて」「テストデータを3件入れて」とお願いするだけで実行されます。

### 実装（SQLite版）

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import Database from "better-sqlite3";
import { z } from "zod";

const DB_PATH = process.env.DB_PATH || "./data.db";
const db = new Database(DB_PATH);

// WALモードで読み書きの並行処理を可能にする
db.pragma("journal_mode = WAL");

const server = new McpServer({
  name: "database-server",
  version: "1.0.0",
});

// Tool: SELECTクエリ（読み取り専用 — 安全性を確保）
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
    // SELECT/WITH以外を弾く（DROP TABLE等の事故を防ぐ）
    const normalized = sql.trim().toUpperCase();
    if (!normalized.startsWith("SELECT") && !normalized.startsWith("WITH")) {
      return {
        content: [{
          type: "text",
          text: "エラー: queryツールではSELECT/WITH文のみ実行可能です",
        }],
        isError: true,
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
    } catch (error: any) {
      return {
        content: [{
          type: "text",
          text: `SQLエラー: ${error.message}`,
        }],
        isError: true,
      };
    }
  }
);

// Tool: 書き込みクエリ（INSERT/UPDATE/DELETE）
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
    // SELECTは弾く（queryツールを使わせる）
    const normalized = sql.trim().toUpperCase();
    if (normalized.startsWith("SELECT")) {
      return {
        content: [{
          type: "text",
          text: "SELECT文にはqueryツールを使ってください",
        }],
        isError: true,
      };
    }

    try {
      const result = db.prepare(sql).run(...(params || []));
      return {
        content: [{
          type: "text",
          text: `実行完了: ${result.changes}行変更`,
        }],
      };
    } catch (error: any) {
      return {
        content: [{
          type: "text",
          text: `SQLエラー: ${error.message}`,
        }],
        isError: true,
      };
    }
  }
);

// Resource: テーブルスキーマ情報
server.resource(
  "schema://tables",
  "データベースの全テーブルとカラム情報",
  async () => {
    const tables = db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ).all() as { name: string }[];

    const schema = tables.map((t) => {
      const columns = db.prepare(`PRAGMA table_info('${t.name}')`).all();
      return `## ${t.name}\n${JSON.stringify(columns, null, 2)}`;
    }).join("\n\n");

    return {
      contents: [{
        uri: "schema://tables",
        text: schema,
        mimeType: "text/plain",
      }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

### なぜqueryとexecuteを分けるのか

読み取り（SELECT）と書き込み（INSERT/UPDATE/DELETE）を分離することで、以下のメリットがあります。

1. **事故防止** — 「データを見て」と言っただけでDELETE文が走ることを防ぐ
2. **権限制御** — Claude Codeの設定で `query` だけ自動許可し、`execute` は都度確認にできる
3. **ログ分析** — 読み取りと書き込みのログを分けて追跡できる

## 実装例3: FTPデプロイMCPサーバー

第5章の `/deploy` スキルからの呼び出しを想定したMCPサーバーです。

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execSync } from "child_process";

const server = new McpServer({
  name: "ftp-deploy",
  version: "1.0.0",
});

server.tool(
  "deploy",
  "lftpでリモートサーバーにファイルをデプロイする",
  {
    host: z.string().describe("FTPホスト名"),
    user: z.string().describe("FTPユーザー名"),
    password: z.string().describe("FTPパスワード"),
    localDir: z.string().describe("ローカルディレクトリパス"),
    remoteDir: z.string().describe("リモートディレクトリパス"),
  },
  async ({ host, user, password, localDir, remoteDir }) => {
    try {
      // lftpのmirrorコマンドで差分のみ転送する
      const cmd = `lftp -c "
        set ftp:ssl-allow yes;
        set net:max-retries 3;
        set net:reconnect-interval-base 5;
        open -u '${user}','${password}' '${host}';
        mirror --reverse --delete --verbose \
          --exclude .git/ --exclude node_modules/ --exclude .env \
          '${localDir}' '${remoteDir}';
        quit
      "`;

      const output = execSync(cmd, {
        encoding: "utf-8",
        timeout: 300000, // 5分タイムアウト
      });

      return {
        content: [{
          type: "text",
          text: `デプロイ完了:\n${output}`,
        }],
      };
    } catch (error: any) {
      return {
        content: [{
          type: "text",
          text: `デプロイ失敗: ${error.message}`,
        }],
        isError: true,
      };
    }
  }
);

// Tool: デプロイ後の動作確認
server.tool(
  "verify",
  "デプロイしたサイトのHTTPステータスを確認する",
  {
    url: z.string().describe("確認するURL"),
  },
  async ({ url }) => {
    try {
      const response = await fetch(url);
      return {
        content: [{
          type: "text",
          text: `${url}: ${response.status} ${response.statusText}`,
        }],
      };
    } catch (error: any) {
      return {
        content: [{
          type: "text",
          text: `接続失敗: ${error.message}`,
        }],
        isError: true,
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

## Claude Codeへの登録方法

作成したMCPサーバーをClaude Codeに登録するには、`.claude/settings.json`（プロジェクトローカル）または `~/.claude/settings.json`（グローバル）に設定を追加します。

### settings.jsonの構造

```json
{
  "mcpServers": {
    "slack": {
      "command": "node",
      "args": ["/path/to/mcp-slack-server/dist/index.js"],
      "env": {
        "SLACK_WEBHOOK_URL": "環境変数から読み込む"
      }
    },
    "database": {
      "command": "node",
      "args": ["/path/to/mcp-database-server/dist/index.js"],
      "env": {
        "DB_PATH": "/path/to/your/database.db"
      }
    },
    "ftp-deploy": {
      "command": "node",
      "args": ["/path/to/mcp-ftp-server/dist/index.js"]
    }
  }
}
```

### プロジェクトローカル vs グローバル

| 配置場所 | ファイルパス | 用途 |
|---------|------------|------|
| プロジェクトローカル | `.claude/settings.json` | そのプロジェクト専用のサーバー |
| グローバル | `~/.claude/settings.json` | 全プロジェクト共通のサーバー |

Slack通知のような汎用サーバーはグローバル、データベース接続のようなプロジェクト固有のサーバーはローカルに配置するのが基本です。

### 登録後の確認

Claude Codeを再起動すると、MCPサーバーが自動的に起動されます。

```
> /mcp
```

で登録済みサーバー一覧と、各サーバーが提供するToolsを確認できます。

## セキュリティ対策

MCPサーバーは外部サービスへのアクセス権を持つため、セキュリティに注意が必要です。

### APIキー管理

**絶対にやってはいけないこと:**

```json
{
  "mcpServers": {
    "slack": {
      "env": {
        "SLACK_WEBHOOK_URL": "your-slack-webhook-url"
      }
    }
  }
}
```

settings.jsonはGitリポジトリにコミットされる可能性があります。APIキーを直接書いてはいけません。

**推奨する方法:**

1. `.env` ファイルにAPIキーを記載（.gitignoreで除外）
2. MCPサーバーのコード内で `.env` を読み込む
3. settings.jsonの `env` では環境変数の参照のみ使う

```bash
# .env（.gitignoreに含める）
SLACK_WEBHOOK_URL=your-slack-webhook-url
DB_PATH=/Users/you/data/production.db
FTP_PASSWORD=secret
```

### アクセス制御

MCPサーバー内で、危険な操作にガードを入れます。

```typescript
// データベースサーバーでのガード例
server.tool("execute", "...", { sql: z.string() }, async ({ sql }) => {
  const upper = sql.trim().toUpperCase();

  // DROP/TRUNCATE/ALTER は禁止（本番事故防止）
  if (upper.startsWith("DROP") || upper.startsWith("TRUNCATE") || upper.startsWith("ALTER")) {
    return {
      content: [{
        type: "text",
        text: "エラー: DROP/TRUNCATE/ALTER文は安全のため禁止されています",
      }],
      isError: true,
    };
  }

  // 実行処理...
});
```

### Claude Codeの権限設定

Claude Codeの設定で、MCPツールごとに自動許可/都度確認を制御できます。

```json
{
  "permissions": {
    "allow": [
      "mcp__slack__send_message",
      "mcp__database__query"
    ],
    "deny": [
      "mcp__database__execute"
    ]
  }
}
```

- `allow`: 確認なしで自動実行（読み取り系に適用）
- `deny`: 毎回確認を求める（書き込み系に適用）

筆者の環境では、Slack通知とSELECTクエリはallow、INSERT/UPDATE/DELETEとFTPデプロイはdenyにしています。自動化スクリプトから呼ばれる場合は `--allowedTools` フラグで個別に許可します。

## まとめ

- **MCPサーバー**はClaude Codeに外部サービス連携の能力を追加するプラグイン
- **Tools**（アクション実行）、**Resources**（情報提供）、**Prompts**（テンプレート）の3機能を提供
- 実装は `@modelcontextprotocol/sdk` を使い、**stdio通信**で動作する
- **settings.json**でClaude Codeに登録。グローバル（汎用）とローカル（プロジェクト固有）の使い分けが重要
- **APIキーは.envで管理**し、settings.jsonに直接書かない
- **アクセス制御**はサーバー内のガードとClaude Codeのpermissionsの二重防御で実現する
- 次章では、これらのMCPサーバーやスキルを定期実行するための仕組み——launchdとシェルスクリプトについて解説する
