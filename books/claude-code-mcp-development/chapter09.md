---
title: "複数MCPサーバーの組み合わせ"
free: false
---

# 複数MCPサーバーの組み合わせ -- マイクロサービス的アーキテクチャ

## この章で学ぶこと

- 複数MCPサーバーを同時に利用するパターンと設計思想
- サーバー間のデータフロー設計
- 共通ユーティリティの共有方法
- 依存関係の管理とMonorepo構成（npmワークスペース）
- 実践的なマルチサーバー構成の`.mcp.json`設定

## なぜ複数サーバーが必要になるのか

MCPサーバーを1つ作って使い始めると、すぐに「もう1つ欲しい」となります。データベース操作サーバー、外部API連携サーバー、ファイル操作サーバー。機能が増えるたびに1つのサーバーに詰め込んでいくと、巨大な「モノリス」MCPサーバーが出来上がってしまいます。

マイクロサービスと同じ発想で、MCPサーバーも**責務ごとに分割する**のがベストプラクティスです。

```
モノリス構成（避けたい）:
  1つのMCPサーバー → DB操作 + Slack連携 + ファイル操作 + 認証管理

マイクロサービス構成（推奨）:
  MCPサーバー: database  → DB操作に特化
  MCPサーバー: slack     → Slack連携に特化
  MCPサーバー: files     → ファイル操作に特化
  MCPサーバー: auth      → 認証・トークン管理に特化
```

## 複数MCPサーバーの同時利用パターン

Claude Codeでは`.mcp.json`に複数のサーバーを登録するだけで、すべてのToolを横断的に利用できます。

```json
{
  "mcpServers": {
    "database": {
      "command": "npx",
      "args": ["tsx", "./servers/database/src/index.ts"],
      "env": { "DB_PATH": "./dev.db" }
    },
    "slack": {
      "command": "npx",
      "args": ["tsx", "./servers/slack/src/index.ts"],
      "env": { "SLACK_TOKEN": "xoxb-..." }
    },
    "github": {
      "command": "npx",
      "args": ["tsx", "./servers/github/src/index.ts"],
      "env": { "GITHUB_TOKEN": "ghp_..." }
    }
  }
}
```

Claude Codeはすべてのサーバーのツール一覧を統合して認識します。ユーザーが「Slackの未読メッセージをデータベースに保存して」と指示すれば、Claude Codeが自動的に`slack`サーバーの`get_messages`ツールと`database`サーバーの`execute`ツールを順番に呼び出します。

### 設計のポイント: Tool名の命名規則

複数サーバーのToolが混在するため、名前の衝突を防ぐ命名規則を決めましょう。

```typescript
// 悪い例: 汎用的すぎて他サーバーと衝突しやすい
server.tool("search", ...);
server.tool("create", ...);

// 良い例: プレフィックスで所属を明確にする
server.tool("db_search", ...);
server.tool("slack_create_message", ...);
```

## サーバー間のデータフロー設計

複数のMCPサーバーは直接通信しません。データの受け渡しは、常にClaude Code（ホスト）を介して行われます。

```
ユーザー: 「Slackの#generalの最新10件をDBに保存して」

Claude Code の処理フロー:
  1. slack サーバー: get_messages(channel="#general", limit=10)
     → メッセージ一覧を取得
  2. database サーバー: execute(sql="INSERT INTO messages ...")
     → 取得したデータをDBに保存
  3. ユーザーに結果を報告
```

この「ホスト経由のデータフロー」はシンプルですが、いくつか注意点があります。

```typescript
// データ量が大きい場合の対策: ページネーション対応
server.tool(
  "slack_get_messages",
  "チャンネルのメッセージを取得する",
  {
    channel: z.string(),
    limit: z.number().max(100).default(20),
    cursor: z.string().optional().describe("ページネーションカーソル"),
  },
  async ({ channel, limit, cursor }) => {
    const result = await slack.conversations.history({
      channel,
      limit,
      cursor,
    });

    return {
      content: [{
        type: "text",
        text: JSON.stringify({
          messages: result.messages,
          next_cursor: result.response_metadata?.next_cursor || null,
        }, null, 2),
      }],
    };
  }
);
```

大量のデータをサーバー間で流す場合は、中間ファイルを使うパターンも有効です。

```typescript
// サーバーA: データをファイルに書き出し
server.tool("export_to_file", ..., async ({ query }) => {
  const rows = db.prepare(query).all();
  const filePath = `/tmp/export-${Date.now()}.json`;
  writeFileSync(filePath, JSON.stringify(rows));
  return { content: [{ type: "text", text: `Exported to ${filePath}` }] };
});

// サーバーB: ファイルから読み込んで処理
server.tool("import_from_file", ..., async ({ filePath }) => {
  const data = JSON.parse(readFileSync(filePath, "utf-8"));
  // ... 処理
});
```

## 共通ユーティリティの共有

複数のMCPサーバーを作っていくと、共通で使いたいコードが出てきます。ログ出力、エラーハンドリング、設定管理など。これらを`shared`パッケージとして切り出しましょう。

```typescript
// packages/shared/src/logger.ts
export function createLogger(serverName: string) {
  return {
    info: (msg: string) => console.error(`[${serverName}] INFO: ${msg}`),
    warn: (msg: string) => console.error(`[${serverName}] WARN: ${msg}`),
    error: (msg: string, err?: Error) => {
      console.error(`[${serverName}] ERROR: ${msg}`);
      if (err) console.error(err.stack);
    },
  };
}
```

```typescript
// packages/shared/src/errors.ts
export function formatToolError(error: unknown): {
  content: Array<{ type: "text"; text: string }>;
  isError: true;
} {
  const message = error instanceof Error ? error.message : String(error);
  return {
    content: [{ type: "text" as const, text: `Error: ${message}` }],
    isError: true,
  };
}
```

```typescript
// packages/shared/src/config.ts
import { z } from "zod";

export function loadConfig<T extends z.ZodType>(
  schema: T,
  prefix: string
): z.infer<T> {
  const envVars: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (key.startsWith(prefix) && value) {
      const configKey = key.slice(prefix.length).toLowerCase();
      envVars[configKey] = value;
    }
  }
  return schema.parse(envVars);
}
```

各サーバーから共通ユーティリティを利用します。

```typescript
// servers/database/src/index.ts
import { createLogger } from "@myorg/shared/logger";
import { formatToolError } from "@myorg/shared/errors";

const logger = createLogger("database");

server.tool("query", ..., async ({ sql, params }) => {
  logger.info(`Executing query: ${sql}`);
  try {
    const rows = db.prepare(sql).all(...(params || []));
    return { content: [{ type: "text", text: JSON.stringify(rows, null, 2) }] };
  } catch (error) {
    logger.error("Query failed", error as Error);
    return formatToolError(error);
  }
});
```

## Monorepo構成（npmワークスペース）

複数のMCPサーバーと共通パッケージを1つのリポジトリで管理するMonorepo構成を紹介します。npmワークスペースを使えば、パッケージマネージャの設定だけで依存関係を解決できます。

### ディレクトリ構成

```
mcp-servers/
├── package.json          # ルートのワークスペース設定
├── tsconfig.base.json    # 共通のTypeScript設定
├── packages/
│   └── shared/           # 共通ユーティリティ
│       ├── package.json
│       ├── tsconfig.json
│       └── src/
│           ├── logger.ts
│           ├── errors.ts
│           └── config.ts
└── servers/
    ├── database/         # DB操作サーバー
    │   ├── package.json
    │   ├── tsconfig.json
    │   └── src/
    │       └── index.ts
    ├── slack/            # Slack連携サーバー
    │   ├── package.json
    │   ├── tsconfig.json
    │   └── src/
    │       └── index.ts
    └── github/           # GitHub連携サーバー
        ├── package.json
        ├── tsconfig.json
        └── src/
            └── index.ts
```

### ルートの package.json

```json
{
  "name": "mcp-servers",
  "private": true,
  "workspaces": [
    "packages/*",
    "servers/*"
  ],
  "scripts": {
    "build": "npm run build --workspaces",
    "lint": "npm run lint --workspaces",
    "test": "npm run test --workspaces"
  }
}
```

### 各サーバーの package.json

`tsx` はTypeScriptを直接実行するツールです（第5章参照）。

```json
{
  "name": "@myorg/mcp-database",
  "version": "1.0.0",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.12.0",
    "@myorg/shared": "*",
    "better-sqlite3": "^11.0.0",
    "zod": "^3.23.0"
  },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts"
  }
}
```

### 共通の tsconfig.base.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "strict": true,
    "esModuleInterop": true,
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "./src"
  }
}
```

各サーバーの`tsconfig.json`はベースを継承します。

```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src"
  },
  "references": [
    { "path": "../../packages/shared" }
  ]
}
```

### セットアップと実行

```bash
# ルートで依存関係を一括インストール
npm install

# 全サーバーをビルド
npm run build

# 個別サーバーを開発モードで起動
npm run dev --workspace=servers/database
```

## まとめ

- 複数のMCPサーバーは`.mcp.json`に並列登録するだけで同時利用できる
- サーバー間のデータフローはClaude Code（ホスト）が自動的に仲介する
- Tool名にプレフィックスをつけて名前の衝突を防ぐ
- 共通ユーティリティは`shared`パッケージに切り出す
- npmワークスペースのMonorepo構成で管理すると、依存関係がクリーンに保てる

次章では、こうして作ったMCPサーバーのテストとデバッグ方法を学びます。品質の高いMCPサーバーを維持するための実践的なテクニックを紹介します。
