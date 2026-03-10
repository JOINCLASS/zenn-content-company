---
title: "外部API連携MCPサーバー"
free: false
---

# 外部API連携 — Slack・GitHub・Notion MCPサーバーの構築

この章では、SaaS APIと連携するMCPサーバーを構築し、Claude Codeから外部サービスを直接操作できるようにします。

**この章で学ぶこと:**

- REST API呼び出しの共通パターン
- Slack MCPサーバーの実装（メッセージ送信・チャンネル一覧）
- GitHub MCPサーバーの実装（Issue作成・PR一覧）
- Notion MCPサーバーの実装（ページ作成・データベースクエリ）
- レート制限とリトライ戦略

## REST API呼び出しの共通パターン

外部APIを呼び出すMCPサーバーには、共通して必要な要素があります。まずはベースとなるHTTPクライアントのユーティリティを作りましょう。

```typescript
// src/api-client.ts
interface ApiClientOptions {
  baseUrl: string;
  headers: Record<string, string>;
  maxRetries?: number;
  retryDelayMs?: number;
}

class ApiClient {
  private baseUrl: string;
  private headers: Record<string, string>;
  private maxRetries: number;
  private retryDelayMs: number;

  constructor(options: ApiClientOptions) {
    this.baseUrl = options.baseUrl;
    this.headers = options.headers;
    this.maxRetries = options.maxRetries ?? 3;
    this.retryDelayMs = options.retryDelayMs ?? 1000;
  }

  async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= this.maxRetries; attempt++) {
      try {
        const response = await fetch(`${this.baseUrl}${path}`, {
          method,
          headers: {
            "Content-Type": "application/json",
            ...this.headers,
          },
          body: body ? JSON.stringify(body) : undefined,
        });

        // レート制限（429）の場合はリトライ
        if (response.status === 429) {
          const retryAfter = response.headers.get("Retry-After");
          const waitMs = retryAfter
            ? parseInt(retryAfter) * 1000
            : this.retryDelayMs * Math.pow(2, attempt);
          await this.sleep(waitMs);
          continue;
        }

        if (!response.ok) {
          const errorBody = await response.text();
          throw new Error(`API Error ${response.status}: ${errorBody}`);
        }

        return await response.json() as T;
      } catch (error) {
        lastError = error as Error;
        if (attempt < this.maxRetries) {
          await this.sleep(this.retryDelayMs * Math.pow(2, attempt));
        }
      }
    }

    throw lastError;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

export { ApiClient };
```

ポイントは **指数バックオフによるリトライ** と **429レスポンスのハンドリング** です。外部APIは必ずレート制限があるため、このパターンは必須と言えます。

## Slack MCPサーバー

Slack APIと連携して、Claude Codeからメッセージの送信やチャンネル情報の取得を行えるようにしましょう。

### セットアップ

Slack Appを作成し、Bot Token（`xoxb-`で始まるトークン）を取得しておきます。必要なスコープは`chat:write`, `channels:read`, `channels:history`です。

```typescript
// src/slack-server.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { ApiClient } from "./api-client.js";

const SLACK_TOKEN = process.env.SLACK_BOT_TOKEN;
if (!SLACK_TOKEN) {
  throw new Error("SLACK_BOT_TOKEN environment variable is required");
}

const slack = new ApiClient({
  baseUrl: "https://slack.com/api",
  headers: { Authorization: `Bearer ${SLACK_TOKEN}` },
});

const server = new McpServer({
  name: "slack-mcp-server",
  version: "1.0.0",
});
```

### チャンネル一覧の取得

```typescript
server.tool(
  "list_channels",
  "Slackのチャンネル一覧を取得する",
  {
    limit: z.number().optional().default(100)
      .describe("取得件数（最大200）"),
  },
  async ({ limit }) => {
    const result = await slack.request<{
      channels: Array<{ id: string; name: string; purpose: { value: string } }>;
    }>("GET", `/conversations.list?types=public_channel&limit=${limit}`);

    const channels = result.channels.map((ch) => ({
      id: ch.id,
      name: ch.name,
      purpose: ch.purpose.value,
    }));

    return {
      content: [{ type: "text", text: JSON.stringify(channels, null, 2) }],
    };
  }
);
```

### メッセージ送信

```typescript
server.tool(
  "send_message",
  "Slackチャンネルにメッセージを送信する",
  {
    channel: z.string().describe("チャンネルID（例: C01ABCDEF）"),
    text: z.string().describe("送信するメッセージ本文"),
  },
  async ({ channel, text }) => {
    const result = await slack.request<{ ok: boolean; error?: string }>(
      "POST",
      "/chat.postMessage",
      { channel, text }
    );

    if (!result.ok) {
      return {
        content: [{ type: "text", text: `送信失敗: ${result.error}` }],
        isError: true,
      };
    }

    return {
      content: [{ type: "text", text: `メッセージを送信しました: #${channel}` }],
    };
  }
);
```

## GitHub MCPサーバー

GitHub APIとの連携を実装します。開発フローの中で「Issueの確認」「PR一覧の取得」「Issueの作成」をClaude Codeから直接行えると非常に便利です。

```typescript
// src/github-server.ts
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
if (!GITHUB_TOKEN) {
  throw new Error("GITHUB_TOKEN environment variable is required");
}

const github = new ApiClient({
  baseUrl: "https://api.github.com",
  headers: {
    Authorization: `Bearer ${GITHUB_TOKEN}`,
    Accept: "application/vnd.github.v3+json",
  },
});

const server = new McpServer({
  name: "github-mcp-server",
  version: "1.0.0",
});
```

### Issue作成

```typescript
server.tool(
  "create_issue",
  "GitHubリポジトリにIssueを作成する",
  {
    owner: z.string().describe("リポジトリオーナー"),
    repo: z.string().describe("リポジトリ名"),
    title: z.string().describe("Issueタイトル"),
    body: z.string().optional().describe("Issue本文（Markdown）"),
    labels: z.array(z.string()).optional().describe("ラベル名の配列"),
  },
  async ({ owner, repo, title, body, labels }) => {
    const issue = await github.request<{ number: number; html_url: string }>(
      "POST",
      `/repos/${owner}/${repo}/issues`,
      { title, body, labels }
    );

    return {
      content: [{
        type: "text",
        text: `Issue #${issue.number} を作成しました: ${issue.html_url}`,
      }],
    };
  }
);
```

### PR一覧取得

```typescript
server.tool(
  "list_pull_requests",
  "GitHubリポジトリのPR一覧を取得する",
  {
    owner: z.string().describe("リポジトリオーナー"),
    repo: z.string().describe("リポジトリ名"),
    state: z.enum(["open", "closed", "all"]).optional().default("open")
      .describe("PRの状態フィルタ"),
  },
  async ({ owner, repo, state }) => {
    const prs = await github.request<Array<{
      number: number;
      title: string;
      state: string;
      user: { login: string };
      html_url: string;
    }>>("GET", `/repos/${owner}/${repo}/pulls?state=${state}`);

    const summary = prs.map((pr) => ({
      number: pr.number,
      title: pr.title,
      author: pr.user.login,
      state: pr.state,
      url: pr.html_url,
    }));

    return {
      content: [{ type: "text", text: JSON.stringify(summary, null, 2) }],
    };
  }
);
```

## Notion MCPサーバー

NotionのAPIを使って、ページ作成やデータベースクエリを行うMCPサーバーを実装します。

```typescript
// src/notion-server.ts
const NOTION_TOKEN = process.env.NOTION_API_KEY;

const notion = new ApiClient({
  baseUrl: "https://api.notion.com/v1",
  headers: {
    Authorization: `Bearer ${NOTION_TOKEN}`,
    "Notion-Version": "2022-06-28",
  },
});

const server = new McpServer({
  name: "notion-mcp-server",
  version: "1.0.0",
});
```

### データベースクエリ

```typescript
server.tool(
  "query_database",
  "Notionデータベースをクエリしてページ一覧を取得する",
  {
    database_id: z.string().describe("NotionデータベースのID"),
    filter: z.record(z.unknown()).optional()
      .describe("Notion APIのフィルタオブジェクト"),
    page_size: z.number().optional().default(10)
      .describe("取得件数"),
  },
  async ({ database_id, filter, page_size }) => {
    const result = await notion.request<{
      results: Array<{ id: string; properties: Record<string, unknown> }>;
    }>("POST", `/databases/${database_id}/query`, {
      filter,
      page_size,
    });

    return {
      content: [{
        type: "text",
        text: JSON.stringify(result.results, null, 2),
      }],
    };
  }
);
```

### ページ作成

```typescript
server.tool(
  "create_page",
  "Notionにページを新規作成する",
  {
    parent_database_id: z.string().describe("親データベースのID"),
    title: z.string().describe("ページタイトル"),
    properties: z.record(z.unknown()).optional()
      .describe("追加のプロパティ"),
  },
  async ({ parent_database_id, title, properties }) => {
    const page = await notion.request<{ id: string; url: string }>(
      "POST",
      "/pages",
      {
        parent: { database_id: parent_database_id },
        properties: {
          Name: {
            title: [{ text: { content: title } }],
          },
          ...properties,
        },
      }
    );

    return {
      content: [{
        type: "text",
        text: `ページを作成しました: ${page.url}`,
      }],
    };
  }
);
```

## レート制限とリトライ戦略

外部API連携で避けて通れないのがレート制限です。各サービスの制限値を把握し、適切に対処しましょう。

| サービス | レート制限 | 推奨対処 |
|---------|----------|---------|
| Slack | Tier別（1-100 req/min） | 429レスポンス時に`Retry-After`ヘッダに従う |
| GitHub | 5,000 req/hour（認証済み） | `X-RateLimit-Remaining`ヘッダを監視 |
| Notion | 3 req/sec | リクエスト間に最低340msのインターバル |

先ほど実装した`ApiClient`は指数バックオフによるリトライを組み込んでいるため、基本的なレート制限には対応できます。より厳密な制御が必要な場合は、トークンバケットアルゴリズムを導入するとよいでしょう。

```typescript
// Notion向けの簡易レートリミッター
class RateLimiter {
  private lastRequestTime = 0;
  private minIntervalMs: number;

  constructor(requestsPerSecond: number) {
    this.minIntervalMs = 1000 / requestsPerSecond;
  }

  async waitIfNeeded(): Promise<void> {
    const now = Date.now();
    const elapsed = now - this.lastRequestTime;
    if (elapsed < this.minIntervalMs) {
      await new Promise((r) => setTimeout(r, this.minIntervalMs - elapsed));
    }
    this.lastRequestTime = Date.now();
  }
}

// 使い方: APIリクエスト前に呼ぶ
const limiter = new RateLimiter(3); // 3 req/sec
await limiter.waitIfNeeded();
```

## MCP設定ファイルへの登録

各サーバーを`.mcp.json`に登録します。

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["tsx", "/path/to/slack-server.ts"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-your-token"
      }
    },
    "github": {
      "command": "npx",
      "args": ["tsx", "/path/to/github-server.ts"],
      "env": {
        "GITHUB_TOKEN": "ghp_your-token"
      }
    },
    "notion": {
      "command": "npx",
      "args": ["tsx", "/path/to/notion-server.ts"],
      "env": {
        "NOTION_API_KEY": "ntn_your-token"
      }
    }
  }
}
```

実際の運用では、トークンを`.mcp.json`に直接書くのではなく、環境変数やシークレットマネージャーから取得するのがベストプラクティスです。この点については次章で詳しく解説します。

## まとめ

この章では、Slack・GitHub・NotionのAPIと連携するMCPサーバーを構築しました。

- **共通APIクライアント**: リトライと指数バックオフを組み込んだ再利用可能なHTTPクライアント
- **Slack連携**: チャンネル一覧取得、メッセージ送信
- **GitHub連携**: Issue作成、PR一覧取得
- **Notion連携**: データベースクエリ、ページ作成
- **レート制限対策**: 429ハンドリング、レートリミッターの実装

外部API連携では、認証トークンの管理が重要な課題になります。次章では、OAuth 2.0フローやAPIキーの安全な管理方法、入力バリデーションなど、MCPサーバーのセキュリティ設計について掘り下げます。
