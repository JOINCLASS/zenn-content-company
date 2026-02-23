---
title: "MCPサーバーによるツール拡張 -- AIの能力を無限に広げる"
free: false
---

# MCPサーバーによるツール拡張 -- AIの能力を無限に広げる

## この章で学ぶこと

第3-8章では、Claude Code、Cursor、GitHub Copilotそれぞれの実践的な使い方と、コードレビュー・テスト生成・リファクタリングでの活用法を解説してきた。

しかし、これらのツールの能力は「素」の状態では限定的だ。ファイルの読み書きやシェルコマンドの実行はできるが、Slackにメッセージを送る、データベースを直接クエリする、Figmaのデザインデータを取得する、といった「外部サービスとの連携」はそのままではできない。

ここで登場するのが**MCP（Model Context Protocol）**だ。

MCPを使えば、AIコーディングツールに新しい「ツール」を追加して、能力を拡張できる。本章では、MCPの仕組みから実用的なサーバーの紹介、さらに自作MCPサーバーの構築方法までを解説する。


## MCP（Model Context Protocol）とは何か

### 一言で言えば「AIにツールを追加する仕組み」

MCPは、Anthropicが提唱したオープンプロトコルだ。AIモデル（Claude等）と外部のツールやデータソースを接続するための標準規格として設計されている。

従来、AIが外部サービスと連携するには、各サービスごとに個別のインテグレーションを開発する必要があった。MCPは、この接続を**標準化**する。USBがさまざまなデバイスを1つのポートで接続できるようにしたのと同様に、MCPはさまざまな外部サービスを1つのプロトコルでAIに接続する。

```
従来のアプローチ:
  AI → 個別API連携 → GitHub
  AI → 個別API連携 → Slack
  AI → 個別API連携 → データベース
  （それぞれ別の実装が必要）

MCPアプローチ:
  AI → MCP → GitHub MCPサーバー → GitHub
  AI → MCP → Slack MCPサーバー → Slack
  AI → MCP → DB MCPサーバー → データベース
  （同じプロトコルで統一的に接続）
```

### MCPの3つの要素

MCPサーバーは、以下の3つの要素をAIに提供できる。

| 要素 | 説明 | 例 |
|------|------|-----|
| **Tools（ツール）** | AIが呼び出せる関数 | `create_issue`、`send_message`、`query_database` |
| **Resources（リソース）** | AIが読み取れるデータ | ファイル内容、データベースのスキーマ、API仕様書 |
| **Prompts（プロンプト）** | 定型のプロンプトテンプレート | コードレビューテンプレート、ドキュメント生成テンプレート |

実務で最も頻繁に使うのは**Tools**だ。MCPサーバーを通じて、AIに「GitHubのIssueを作成する」「Slackにメッセージを送る」「データベースにクエリを実行する」といった新しいアクションを追加できる。


## AIコーディングツールのMCP対応状況

### Claude Code -- ネイティブ対応

Claude CodeはMCPにネイティブ対応しており、MCPサーバーの追加が最も簡単だ。

設定は `.claude/settings.json` に記述する。

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxxxxxxxxxx"
      }
    },
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-xxxxxxxxxxxx"
      }
    }
  }
}
```

この設定だけで、Claude Codeに `create_github_issue` や `send_slack_message` といった新しいツールが追加される。あとは自然言語で「この修正のIssueをGitHubに作って」と指示すれば、MCPサーバー経由でGitHub APIが呼び出される。

### Cursor -- MCP対応

CursorもMCPに対応している。設定は `.cursor/mcp.json` に記述する。

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxxxxxxxxxx"
      }
    }
  }
}
```

CursorのAgent ModeでMCPツールが利用可能になる。Composer内でAIが必要に応じてMCPツールを呼び出す形で動作する。

### GitHub Copilot -- Extensions

GitHub Copilotは独自のExtensionsエコシステムを持っており、MCPとは異なるアプローチで外部サービスとの連携を実現している。Docker、Azure、Sentryなどのパートナー企業が提供するExtensionを通じて機能を拡張できる。


## 実用的なMCPサーバー一覧

2026年現在、多数のMCPサーバーが公開されている。開発業務で特に役立つものを紹介する。

### 開発ツール連携

| MCPサーバー | 提供するツール | 活用シーン |
|------------|--------------|-----------|
| **@modelcontextprotocol/server-github** | Issue作成、PR操作、リポジトリ検索 | タスク管理の自動化、PR作成の自動化 |
| **@modelcontextprotocol/server-gitlab** | Issue、MR、パイプライン操作 | GitLabベースの開発ワークフロー |
| **@modelcontextprotocol/server-filesystem** | 高度なファイル操作 | サンドボックス外のファイルアクセス |

### コミュニケーション連携

| MCPサーバー | 提供するツール | 活用シーン |
|------------|--------------|-----------|
| **@modelcontextprotocol/server-slack** | メッセージ送受信、チャンネル操作 | 開発通知の自動送信、日報の自動投稿 |
| **@anthropic/mcp-server-linear** | Issue管理、プロジェクト操作 | Linearでのタスク管理自動化 |

### データベース連携

| MCPサーバー | 提供するツール | 活用シーン |
|------------|--------------|-----------|
| **@modelcontextprotocol/server-postgres** | SQLクエリ実行、スキーマ取得 | データ分析、マイグレーション支援 |
| **@modelcontextprotocol/server-sqlite** | SQLiteの読み書き | ローカルDBの操作、プロトタイピング |

### デザイン・ドキュメント連携

| MCPサーバー | 提供するツール | 活用シーン |
|------------|--------------|-----------|
| **Figma MCP** | デザインデータの取得 | デザインからコードへの変換 |
| **@modelcontextprotocol/server-puppeteer** | Webページのスクリーンショット、操作 | E2Eテスト、ビジュアルチェック |

### 筆者が実際に使っているMCPサーバー構成

合同会社ジョインクラスの開発環境では、以下の組み合わせで運用している。

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "${DEV_DATABASE_URL}"
      }
    },
    "puppeteer": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-puppeteer"]
    }
  }
}
```

特に**GitHub MCP + PostgreSQL MCP**の組み合わせは強力だ。「データベースのスキーマを見て、対応するTypeScript型定義とCRUD APIを生成して、GitHubにPRを作って」という一連の作業がClaude Codeへの1回の指示で完結する。


## 自作MCPサーバーの構築方法

既存のMCPサーバーでは足りない場合、自前でMCPサーバーを構築できる。TypeScript SDKを使えば、数十行のコードで基本的なMCPサーバーが作れる。

### 準備

```bash
mkdir my-mcp-server
cd my-mcp-server
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node
```

### 最小構成のMCPサーバー

以下は、社内のAPIからプロジェクト情報を取得するMCPサーバーの例だ。

```typescript
// src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "internal-api",
  version: "1.0.0",
});

// ツールの定義: プロジェクト一覧を取得
server.tool(
  "list_projects",
  "社内プロジェクトの一覧を取得する",
  {},
  async () => {
    const response = await fetch("https://internal-api.example.com/projects", {
      headers: {
        Authorization: `Bearer ${process.env.INTERNAL_API_KEY}`,
      },
    });
    const projects = await response.json();

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(projects, null, 2),
        },
      ],
    };
  }
);

// ツールの定義: プロジェクトのメトリクスを取得
server.tool(
  "get_project_metrics",
  "指定プロジェクトのKPIメトリクスを取得する",
  {
    projectId: z.string().describe("プロジェクトID"),
    period: z.enum(["daily", "weekly", "monthly"]).describe("集計期間"),
  },
  async ({ projectId, period }) => {
    const response = await fetch(
      `https://internal-api.example.com/projects/${projectId}/metrics?period=${period}`,
      {
        headers: {
          Authorization: `Bearer ${process.env.INTERNAL_API_KEY}`,
        },
      }
    );
    const metrics = await response.json();

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(metrics, null, 2),
        },
      ],
    };
  }
);

// サーバー起動
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
```

### 解説

このコードのポイントを整理する。

**1. McpServerの初期化**

```typescript
const server = new McpServer({
  name: "internal-api",
  version: "1.0.0",
});
```

MCPサーバーの名前とバージョンを指定する。この名前がClaude Codeの設定で参照される。

**2. server.tool()でツールを定義**

```typescript
server.tool(
  "list_projects",       // ツール名（AIが呼び出す際の識別子）
  "社内プロジェクト...", // 説明（AIがツールの用途を理解するために使う）
  {},                    // 入力パラメータのスキーマ（zodで定義）
  async () => { ... }    // 実際の処理
);
```

第3引数の入力スキーマは、AIがパラメータを正しく渡すためのガイドになる。zodを使って型安全に定義できる。

**3. StdioServerTransportでの接続**

MCPサーバーとAIクライアント間の通信は、標準入出力（stdio）を通じて行われる。複雑なネットワーク設定は不要だ。

### Claude Codeへの登録

ビルド後、Claude Codeの設定に追加する。

```bash
npx tsc
```

```json
{
  "mcpServers": {
    "internal-api": {
      "command": "node",
      "args": ["/path/to/my-mcp-server/dist/index.js"],
      "env": {
        "INTERNAL_API_KEY": "your-api-key-here"
      }
    }
  }
}
```

これで、Claude Codeに「プロジェクト一覧を見せて」と言えば、自作MCPサーバーを通じて社内APIからデータが取得される。

### より実践的な例: デプロイメント管理MCPサーバー

実務で役立つ、もう少し実践的な例も示しておく。以下は、ステージング環境へのデプロイとその状態確認を行うMCPサーバーの骨格だ。

```typescript
server.tool(
  "deploy_staging",
  "ステージング環境にデプロイする（本番環境は対象外）",
  {
    service: z.string().describe("デプロイ対象のサービス名"),
    branch: z.string().describe("デプロイするブランチ名"),
  },
  async ({ service, branch }) => {
    // 本番環境への誤デプロイを防ぐガード
    const allowedServices = ["web-staging", "api-staging"];
    if (!allowedServices.includes(service)) {
      return {
        content: [{
          type: "text",
          text: `エラー: ${service} はデプロイ対象外です。許可されたサービス: ${allowedServices.join(", ")}`,
        }],
        isError: true,
      };
    }

    // デプロイAPIを呼び出す
    const response = await fetch("https://deploy.example.com/api/deploy", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${process.env.DEPLOY_API_KEY}`,
      },
      body: JSON.stringify({ service, branch }),
    });

    const result = await response.json();

    return {
      content: [{
        type: "text",
        text: `デプロイ開始: ${service} (branch: ${branch})\nデプロイID: ${result.deployId}\nステータス: ${result.status}`,
      }],
    };
  }
);

server.tool(
  "check_deploy_status",
  "デプロイの状態を確認する",
  {
    deployId: z.string().describe("デプロイID"),
  },
  async ({ deployId }) => {
    const response = await fetch(
      `https://deploy.example.com/api/deploy/${deployId}`,
      {
        headers: {
          Authorization: `Bearer ${process.env.DEPLOY_API_KEY}`,
        },
      }
    );
    const status = await response.json();

    return {
      content: [{
        type: "text",
        text: JSON.stringify(status, null, 2),
      }],
    };
  }
);
```

ポイントは**ガード節**だ。本番環境へのデプロイを防ぐために、許可されたサービス名をホワイトリストで制限している。MCPサーバーは「AIが呼び出す関数」なので、安全性の確保は特に重要だ。


## MCP活用のベストプラクティス

### 1. セキュリティを最優先にする

MCPサーバーは外部サービスへのアクセス権を持つため、セキュリティには細心の注意が必要だ。

- **APIキーは環境変数で管理する**: MCPサーバーの設定ファイルにAPIキーを直書きしない。`env` フィールドで環境変数を渡す
- **最小権限の原則**: MCPサーバーに渡すAPIトークンは、必要最小限の権限だけを付与する。GitHub MCPに渡すトークンは、リポジトリの読み取り権限だけで十分な場合が多い
- **破壊的操作にはガードを設ける**: 自作MCPサーバーでは、削除やデプロイなどの破壊的操作にホワイトリスト制限やconfirmationフローを入れる
- **本番環境の認証情報は渡さない**: 開発・ステージング環境の認証情報のみをMCPサーバーに渡す

### 2. ツールの説明文を丁寧に書く

MCPサーバーで定義するツールの `description`（説明文）は、AIがそのツールを適切に使うかどうかを左右する重要な情報だ。

```typescript
// 悪い例: 説明が曖昧
server.tool("query", "データを取得する", ...);

// 良い例: 具体的で制約が明確
server.tool(
  "query_users",
  "ユーザーテーブルからSELECTクエリを実行する。読み取り専用。最大100件まで。WHERE句とORDER BY句を指定可能。",
  ...
);
```

AIは説明文を読んでツールの使い方を判断する。曖昧な説明は、誤った使い方につながる。

### 3. エラーハンドリングを充実させる

MCPサーバーがエラーを返す場合は、AIが次のアクションを判断できるよう、具体的なエラーメッセージを含める。

```typescript
// 悪い例
return { content: [{ type: "text", text: "エラーが発生しました" }], isError: true };

// 良い例
return {
  content: [{
    type: "text",
    text: `GitHub APIエラー (403 Forbidden): トークンにissue作成権限がありません。必要なスコープ: repo。現在のスコープ: read:org`,
  }],
  isError: true,
};
```

### 4. 冪等性を意識する

AIは同じツールを複数回呼び出す可能性がある。たとえば、リトライや確認のために同じクエリを2回実行することがある。MCPサーバーのツールは、可能な限り冪等（同じ操作を何度実行しても結果が変わらない）に設計する。

特にデータの作成や更新を行うツールでは、重複チェックの仕組みを入れておくと安全だ。

### 5. 開発環境と本番環境を明確に分離する

MCPサーバーの設定ファイルは、環境ごとに分離する。

```
.claude/
  settings.json            # 開発環境用（デフォルト）
  settings.production.json # 本番環境用（通常は使わない）
```

開発環境では自由にMCPサーバーを使い、本番環境の操作は必ず手動確認を経るようにする。


## MCPがもたらす開発ワークフローの変化

MCPを導入すると、開発ワークフローは以下のように変化する。

### 導入前

```
エンジニア → ブラウザでGitHub操作 → ターミナルでDB操作 → Slackで通知送信
（それぞれ別の画面・ツールに切り替えが必要）
```

### 導入後

```
エンジニア → Claude Code → MCP経由で全て一括操作
「DBスキーマを確認して、対応するAPIとテストを実装して、PRを作って、Slackで通知して」
（1つの指示で全て完結）
```

コンテキストスイッチの削減は、集中力の維持に直結する。ブラウザ、ターミナル、Slack、GitHub、データベースクライアントの間を行き来する必要がなくなることの生産性への影響は、想像以上に大きい。

筆者の体感では、MCPを導入する前と後で、1つの機能実装にかかる**周辺作業の時間が40-50%削減**された。コードを書く時間自体はAIツールで既に短縮されていたが、MCPは「コードを書く以外の開発作業」まで効率化してくれる。


## この章のまとめ

MCPは、AIコーディングツールの能力を外部サービスに拡張するためのオープンプロトコルだ。

- **MCPの3要素**: Tools（関数）、Resources（データ）、Prompts（テンプレート）
- **Claude CodeはMCPにネイティブ対応**: settings.jsonに設定するだけでツールが追加される
- **実用的なMCPサーバー**: GitHub、Slack、PostgreSQL、Puppeteerなど、開発業務をカバーするサーバーが揃っている
- **自作も容易**: TypeScript SDKを使えば、数十行で自社API連携のMCPサーバーを構築できる
- **セキュリティが最重要**: APIキー管理、最小権限の原則、破壊的操作のガードを徹底する

MCPの本質は「AIの手足を増やす」ことだ。AIが優秀な頭脳を持っていても、外部サービスに触れなければできることは限られる。MCPでツールを追加するほど、AIに委任できる作業の範囲が広がる。

---

次章では、AIコーディングで陥りがちなアンチパターンを整理する。AIツールの力を引き出すだけでなく、「やってはいけないこと」を知ることが、長期的な生産性向上の鍵になる。
