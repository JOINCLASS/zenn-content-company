---
title: "MCP連携で外部ツールをつなぐ"
---

# MCP連携で外部ツールをつなぐ

Model Context Protocol（MCP）は、Claude Codeが外部のツールやサービスと連携するための標準プロトコルです。MCPサーバーを接続することで、Claude Codeの能力を拡張できます。

## MCPとは

MCPは、AIモデルが外部ツールにアクセスするための標準化されたインターフェースです。Claude Codeには標準でファイル操作やBash実行のツールが組み込まれていますが、MCPを使うと、データベースクエリ、API呼び出し、ブラウザ操作など、追加のツールを接続できます。

MCPサーバーは独立したプロセスとして動作し、Claude Codeと標準入出力（stdio）またはHTTPで通信します。

## MCPサーバーの設定

MCPサーバーは`.claude/settings.json`で設定します。

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "postgresql://user:pass@localhost:5432/mydb"
      }
    }
  }
}
```

## 実用的なMCPサーバー

### PostgreSQL / MySQL

データベースに直接クエリを実行できます。

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "postgresql://user:pass@localhost:5432/devdb"
      }
    }
  }
}
```

Claude Codeに「usersテーブルの件数を教えて」と聞くだけで、SQLを実行して結果を返してくれます。

### ファイルシステム

指定したディレクトリ外のファイルにもアクセスできるようにします。

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/dir"]
    }
  }
}
```

### GitHub

GitHubのIssue、PR、リポジトリ情報にアクセスできます。

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..."
      }
    }
  }
}
```

### Slack

Slackのメッセージ送信やチャンネル一覧の取得ができます。

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-..."
      }
    }
  }
}
```

### Fetch（Web取得）

URLからWebページの内容を取得できます。

```json
{
  "mcpServers": {
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-fetch"]
    }
  }
}
```

## CLAUDE.mdでMCPツールの使い方を指示する

MCPサーバーを接続しただけでは、Claude Codeがいつどのように使えばいいか分かりません。CLAUDE.mdで使い方を指示します。

```markdown
## 外部ツール

### データベース
- 開発用DBにはMCP経由でクエリ可能
- SELECT文のみ実行してよい。INSERT/UPDATE/DELETEは事前確認が必要
- 本番DBへの接続は禁止

### GitHub
- IssueとPRの情報はMCP経由で取得可能
- Issueの作成、PRのコメントは自動で行ってよい
- PRのマージは手動で行う
```

## MCPサーバーの自作

公開されているMCPサーバーでカバーできない場合は、自分でMCPサーバーを作ることもできます。

### TypeScriptでの最小構成

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new Server(
  { name: "my-tool", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler("tools/list", async () => ({
  tools: [
    {
      name: "greet",
      description: "名前を受け取って挨拶を返す",
      inputSchema: {
        type: "object",
        properties: {
          name: { type: "string", description: "名前" }
        },
        required: ["name"]
      }
    }
  ]
}));

server.setRequestHandler("tools/call", async (request) => {
  if (request.params.name === "greet") {
    const name = request.params.arguments.name;
    return {
      content: [{ type: "text", text: `こんにちは、${name}さん！` }]
    };
  }
  throw new Error("Unknown tool");
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

### 設定に追加

```json
{
  "mcpServers": {
    "my-tool": {
      "command": "npx",
      "args": ["tsx", "path/to/my-server.ts"]
    }
  }
}
```

## 実践例: 社内APIとの連携

社内のREST APIにアクセスするMCPサーバーを作る例です。

```markdown
## CLAUDE.md

### 社内ツール

- 顧客情報はMCPの`company-api`サーバー経由で取得可能
- `search_customers`ツールで顧客検索
- `get_customer_detail`ツールで詳細取得
- 顧客情報の更新は禁止。閲覧のみ
```

CLAUDE.mdでツールの存在と制約を記述し、MCPサーバーの設定で実際の接続先を定義する、という二層構造になります。

## MCPサーバーの管理

### セキュリティの考慮

MCPサーバーは外部サービスへの接続を持つため、セキュリティに注意が必要です。

- **認証情報は環境変数で渡す** — settings.jsonに直接トークンを書かない
- **アクセス範囲を最小限にする** — データベースならSELECT権限のみのユーザーを使う
- **本番環境に接続しない** — 開発用の環境のみに接続する

### バージョン管理

`.claude/settings.json`をGitで管理する場合、認証情報を含めないように注意します。

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}"
      }
    }
  }
}
```

環境変数を参照する形にしておけば、各開発者が自分の`.env`で値を設定できます。

## まとめ

- MCPはClaude Codeの能力を拡張するプロトコル
- `.claude/settings.json`でMCPサーバーを設定する
- DB、GitHub、Slack、Webフェッチなど多くのサーバーが公開されている
- CLAUDE.mdでMCPツールの使い方と制約を指示する
- 自作MCPサーバーで社内ツールと連携できる
- 認証情報は環境変数で管理し、本番接続を避ける
