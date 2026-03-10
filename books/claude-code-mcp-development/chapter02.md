---
title: "環境構築とHello World -- 最初のMCPサーバーを5分で作る"
free: true
---

# 環境構築とHello World -- 最初のMCPサーバーを5分で作る

## この章で学ぶこと

- MCP開発に必要な環境のセットアップ
- TypeScript SDKを使った最小のMCPサーバーの実装
- Claude Codeへの接続と動作確認
- MCPサーバーのライフサイクルの基本

## 前提環境

本書のコードを動かすために、以下が必要です。

- **Node.js** 20以上（推奨: 22 LTS）
- **npm** または **pnpm**
- **Claude Code** がインストール済みであること
- **TypeScript** の基本知識

Node.jsのバージョンを確認しましょう。

```bash
node -v
# v22.x.x

npm -v
# 10.x.x
```

## プロジェクトの初期化

まず、MCPサーバーのプロジェクトを作成します。

```bash
mkdir my-first-mcp-server
cd my-first-mcp-server
npm init -y
```

必要なパッケージをインストールします。

```bash
npm install @modelcontextprotocol/sdk@^1.12.0 zod
npm install -D typescript @types/node
```

各パッケージの役割は以下のとおりです。

| パッケージ | 役割 |
|-----------|------|
| `@modelcontextprotocol/sdk` | MCP公式TypeScript SDK。サーバー/クライアントの実装に使う |
| `zod` | スキーマバリデーション。ツールの入力定義に使う |
| `typescript` | TypeScriptコンパイラ |
| `@types/node` | Node.jsの型定義 |

TypeScriptの設定ファイルを作成します。

```bash
npx tsc --init
```

`tsconfig.json` を以下のように編集しましょう。

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true
  },
  "include": ["src/**/*"]
}
```

`package.json` に以下を追加します。

```json
{
  "type": "module",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  }
}
```

## 最小のMCPサーバーを書く

`src/index.ts` を作成します。これが最小構成のMCPサーバーです。

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// MCPサーバーのインスタンスを作成
const server = new McpServer({
  name: "my-first-mcp-server",
  version: "1.0.0",
});

// 最初のツールを登録
server.tool(
  "greet",
  "指定した名前に挨拶を返します",
  {
    name: z.string().describe("挨拶する相手の名前"),
  },
  async ({ name }) => {
    return {
      content: [
        {
          type: "text",
          text: `Hello, ${name}! Welcome to MCP!`,
        },
      ],
    };
  }
);

// サーバーを起動
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("MCP Server started on stdio");
}

main().catch(console.error);
```

たったこれだけです。順番に見ていきましょう。

### McpServerの作成

```typescript
const server = new McpServer({
  name: "my-first-mcp-server",
  version: "1.0.0",
});
```

`McpServer` はMCPサーバーの中核クラスです。`name` と `version` はクライアントがサーバーを識別するために使います。

### ツールの登録

```typescript
server.tool(
  "greet",                              // ツール名
  "指定した名前に挨拶を返します",           // 説明文
  { name: z.string().describe("...") }, // 入力スキーマ（Zodで定義）
  async ({ name }) => { ... }           // ハンドラー関数
);
```

`server.tool()` メソッドでツールを登録します。4つの引数を取ります。

1. **ツール名**: AIモデルが呼び出すときに使う識別子
2. **説明文**: AIモデルがツールの用途を理解するための説明。ここの書き方が重要です
3. **入力スキーマ**: Zodスキーマで入力パラメータを定義。型安全性とバリデーションを両立できます
4. **ハンドラー関数**: 実際の処理を行う非同期関数

### トランスポートの接続

```typescript
const transport = new StdioServerTransport();
await server.connect(transport);
```

MCPは複数のトランスポートをサポートしていますが、ローカル開発では`stdio`（標準入出力）を使うのが最もシンプルです。サーバープロセスのstdin/stdoutを通じてJSON-RPCメッセージをやり取りします。

:::message
**なぜ console.error を使うのか**

MCPサーバーでは、stdoutはクライアントとの通信に使われます。ログ出力に `console.log` を使うとプロトコルが壊れるため、必ず `console.error`（stderr）を使ってください。これは初心者がハマりやすいポイントです。
:::

## ビルドと動作確認

ビルドしましょう。

```bash
npm run build
```

`dist/index.js` が生成されたら成功です。

## Claude Codeに接続する

作成したMCPサーバーをClaude Codeに登録します。

```bash
claude mcp add my-first-server node /absolute/path/to/my-first-mcp-server/dist/index.js
```

ポイントは以下の3つです。

- `my-first-server` はClaude Code内での識別名（任意の名前）
- `node` は起動コマンド
- パスは**絶対パス**で指定すること

登録を確認します。

```bash
claude mcp list
```

登録したサーバーが表示されれば準備完了です。

## 動かしてみる

Claude Codeを起動して、以下のように話しかけてみましょう。

```
> greetツールを使って「太郎」に挨拶してください
```

Claude Codeが `greet` ツールを呼び出し、以下のような結果が返ってくるはずです。

```
Hello, 太郎! Welcome to MCP!
```

これで、あなたの最初のMCPサーバーが動きました。

## 設定ファイルの仕組み

`claude mcp add` で登録した設定は、プロジェクトの `.mcp.json` ファイルに保存されます。中身を見てみましょう。

```json
{
  "mcpServers": {
    "my-first-server": {
      "command": "node",
      "args": ["/absolute/path/to/my-first-mcp-server/dist/index.js"],
      "env": {}
    }
  }
}
```

`command` が起動コマンド、`args` が引数、`env` が環境変数です。APIキーなどの秘密情報は `env` に設定することで、コードにハードコードせずに渡せます。

```json
{
  "mcpServers": {
    "my-api-server": {
      "command": "node",
      "args": ["dist/index.js"],
      "env": {
        "API_KEY": "your-api-key-here"
      }
    }
  }
}
```

:::message alert
`.mcp.json` にAPIキーを直接書く場合は、必ず `.gitignore` に追加してください。本番環境での秘密情報管理は第7章で詳しく解説します。
:::

## ツールを追加してみる

せっかくなので、もう1つツールを追加しましょう。現在時刻を返すツールです。

```typescript
server.tool(
  "current-time",
  "現在の日時をISO 8601形式で返します",
  {},
  async () => {
    return {
      content: [
        {
          type: "text",
          text: new Date().toISOString(),
        },
      ],
    };
  }
);
```

入力パラメータが不要なツールは、スキーマに空オブジェクト `{}` を渡します。

ビルドし直して、Claude Codeで試してみましょう。

```bash
npm run build
```

```
> 今何時ですか？（current-timeツールを使って）
```

## まとめ

- MCP開発には `@modelcontextprotocol/sdk` と `zod` があれば始められる
- `McpServer` クラスでサーバーを作り、`server.tool()` でツールを登録する
- トランスポートには `StdioServerTransport`（標準入出力）を使う
- ログは `console.error`（stderr）に出力する（stdoutはプロトコル通信に使われる）
- `claude mcp add` でClaude Codeに接続し、すぐに試せる

次の章では、MCPの3つの機能 -- Tools、Resources、Prompts -- をそれぞれ深掘りして解説します。
