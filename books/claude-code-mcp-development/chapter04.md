---
title: "ファイルシステムMCPサーバーを作る -- CRUD操作の実装"
free: false
---

# ファイルシステムMCPサーバーを作る -- CRUD操作の実装

## この章で学ぶこと

- 実用的なMCPサーバーの設計プロセス
- ファイルの作成・読み取り・更新・削除（CRUD）の実装
- ディレクトリ操作とファイル検索の実装
- セキュリティ上の考慮点（パストラバーサル対策）
- Resourcesによるディレクトリ構造の公開

## なぜファイルシステムから始めるのか

MCPサーバー開発の最初の実践題材として、ファイルシステム操作は最適です。理由は3つ。

1. **外部依存がない** -- データベースやAPIキーが不要で、Node.jsの標準ライブラリだけで完結する
2. **CRUD操作が直感的** -- ファイルの作成・読み取り・更新・削除は、あらゆるシステムの基本
3. **セキュリティを学べる** -- パストラバーサルなど、実務で必須のセキュリティ対策を体験できる

## プロジェクトのセットアップ

新しいプロジェクトを作成します。

```bash
mkdir fs-mcp-server
cd fs-mcp-server
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install -D typescript @types/node
```

`tsconfig.json` と `package.json` の設定は第2章と同じです。`src/index.ts` を作成して実装を始めましょう。

## 設計方針

このMCPサーバーでは、以下の機能を実装します。

**Tools（書き込み系）:**
- `write-file` -- ファイルの作成・上書き
- `delete-file` -- ファイルの削除
- `move-file` -- ファイルの移動・リネーム
- `create-directory` -- ディレクトリの作成

**Tools（読み取り系）:**
- `read-file` -- ファイルの内容を読み取る（`read-file`は動的なパスを引数で受け取るため、固定URIのResourceよりもToolとして実装するほうが柔軟です）
- `list-files` -- ディレクトリ内のファイル一覧を取得
- `search-files` -- ファイル名のパターン検索

**Resources:**
- `directory-tree` -- 指定ディレクトリのツリー構造を公開

まず、全体の骨格から書いていきます。

## ベースの実装

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as fs from "fs/promises";
import * as path from "path";

// 操作を許可するベースディレクトリ（環境変数から取得）
const BASE_DIR = process.env.FS_BASE_DIR || process.cwd();

const server = new McpServer({
  name: "fs-mcp-server",
  version: "1.0.0",
});
```

`BASE_DIR` が重要です。MCPサーバーがアクセスできるディレクトリを制限するための起点パスです。環境変数 `FS_BASE_DIR` で指定でき、未設定の場合はカレントディレクトリを使います。

## パストラバーサル対策

ファイルシステム操作で最も重要なのが、パストラバーサル攻撃への対策です。`../../etc/passwd` のようなパスで、許可されていないディレクトリにアクセスされるのを防ぎます。

```typescript
function resolveSafePath(inputPath: string): string {
  const resolved = path.resolve(BASE_DIR, inputPath);

  // ベースディレクトリの外にはアクセスさせない
  if (!resolved.startsWith(path.resolve(BASE_DIR))) {
    throw new Error(
      `アクセス拒否: ${inputPath} はベースディレクトリの外です`
    );
  }

  return resolved;
}
```

`path.resolve` で絶対パスに変換し、ベースディレクトリで始まるかをチェックします。すべてのファイル操作で、この関数を通すことが鉄則です。

:::message alert
**セキュリティ上の重要な注意**: MCPサーバーはAIモデルからの入力を受け取ります。AIモデルが生成するパスは信頼できないものとして扱い、必ずバリデーションを行ってください。
:::

## CRUD操作の実装

### Create -- ファイルの作成

```typescript
server.tool(
  "write-file",
  "指定パスにファイルを作成または上書きします。親ディレクトリが存在しない場合は自動作成します",
  {
    filePath: z.string().describe("ファイルパス（ベースディレクトリからの相対パス）"),
    content: z.string().describe("ファイルに書き込む内容"),
  },
  async ({ filePath, content }) => {
    try {
      const safePath = resolveSafePath(filePath);

      // 親ディレクトリを再帰的に作成
      await fs.mkdir(path.dirname(safePath), { recursive: true });
      await fs.writeFile(safePath, content, "utf-8");

      const stats = await fs.stat(safePath);

      return {
        content: [
          {
            type: "text",
            text: `ファイルを作成しました: ${filePath} (${stats.size} bytes)`,
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `ファイルの作成に失敗: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
      };
    }
  }
);
```

`recursive: true` をつけることで、`docs/api/v2/spec.md` のような深いパスでも一発で作成できます。

### Read -- ファイルの読み取り

```typescript
server.tool(
  "read-file",
  "指定パスのファイル内容を読み取ります。テキストファイルのみ対応",
  {
    filePath: z.string().describe("ファイルパス（ベースディレクトリからの相対パス）"),
  },
  async ({ filePath }) => {
    try {
      const safePath = resolveSafePath(filePath);
      const content = await fs.readFile(safePath, "utf-8");
      const stats = await fs.stat(safePath);

      return {
        content: [
          {
            type: "text",
            text: `--- ${filePath} (${stats.size} bytes, 更新: ${stats.mtime.toISOString()}) ---\n${content}`,
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `ファイルの読み取りに失敗: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
      };
    }
  }
);
```

### Update -- ファイルの移動・リネーム

```typescript
server.tool(
  "move-file",
  "ファイルまたはディレクトリを移動・リネームします",
  {
    sourcePath: z.string().describe("移動元のパス"),
    destPath: z.string().describe("移動先のパス"),
  },
  async ({ sourcePath, destPath }) => {
    try {
      const safeSource = resolveSafePath(sourcePath);
      const safeDest = resolveSafePath(destPath);

      // 移動先の親ディレクトリを作成
      await fs.mkdir(path.dirname(safeDest), { recursive: true });
      await fs.rename(safeSource, safeDest);

      return {
        content: [
          {
            type: "text",
            text: `移動しました: ${sourcePath} → ${destPath}`,
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `移動に失敗: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
      };
    }
  }
);
```

### Delete -- ファイルの削除

```typescript
server.tool(
  "delete-file",
  "指定パスのファイルまたは空ディレクトリを削除します",
  {
    filePath: z.string().describe("削除するファイルのパス"),
  },
  async ({ filePath }) => {
    try {
      const safePath = resolveSafePath(filePath);
      const stats = await fs.stat(safePath);

      if (stats.isDirectory()) {
        await fs.rmdir(safePath);
      } else {
        await fs.unlink(safePath);
      }

      return {
        content: [
          {
            type: "text",
            text: `削除しました: ${filePath}`,
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `削除に失敗: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
      };
    }
  }
);
```

ディレクトリの削除は `rmdir` を使い、空でない場合はエラーにしています。再帰的な削除は危険なため、意図的にサポートしていません。

## ディレクトリ操作

```typescript
server.tool(
  "list-files",
  "指定ディレクトリのファイル・サブディレクトリ一覧を取得します",
  {
    dirPath: z.string().default(".").describe("ディレクトリパス（デフォルト: ベースディレクトリ）"),
  },
  async ({ dirPath }) => {
    try {
      const safePath = resolveSafePath(dirPath);
      const entries = await fs.readdir(safePath, { withFileTypes: true });

      const result = entries.map((entry) => ({
        name: entry.name,
        type: entry.isDirectory() ? "directory" : "file",
      }));

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `一覧の取得に失敗: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
      };
    }
  }
);

server.tool(
  "create-directory",
  "ディレクトリを作成します。親ディレクトリも自動作成されます",
  {
    dirPath: z.string().describe("作成するディレクトリのパス"),
  },
  async ({ dirPath }) => {
    try {
      const safePath = resolveSafePath(dirPath);
      await fs.mkdir(safePath, { recursive: true });

      return {
        content: [
          {
            type: "text",
            text: `ディレクトリを作成しました: ${dirPath}`,
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `ディレクトリの作成に失敗: ${error instanceof Error ? error.message : String(error)}`,
          },
        ],
      };
    }
  }
);
```

## Resourcesでディレクトリ構造を公開

Toolsに加えて、ディレクトリのツリー構造をResourceとして公開しましょう。AIモデルがプロジェクトの全体像を把握するのに役立ちます。

```typescript
async function buildDirectoryTree(
  dirPath: string,
  prefix: string = "",
  depth: number = 3
): Promise<string> {
  if (depth <= 0) return prefix + "...\n";

  const entries = await fs.readdir(dirPath, { withFileTypes: true });
  const lines: string[] = [];

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const isLast = i === entries.length - 1;
    const connector = isLast ? "└── " : "├── ";
    const childPrefix = isLast ? "    " : "│   ";

    if (entry.name.startsWith(".")) continue; // 隠しファイルをスキップ

    lines.push(`${prefix}${connector}${entry.name}`);

    if (entry.isDirectory()) {
      const subtree = await buildDirectoryTree(
        path.join(dirPath, entry.name),
        prefix + childPrefix,
        depth - 1
      );
      if (subtree) lines.push(subtree);
    }
  }

  return lines.join("\n");
}

server.resource(
  "directory-tree",
  "tree://workspace",
  async (uri) => {
    const tree = await buildDirectoryTree(BASE_DIR);
    return {
      contents: [
        {
          uri: uri.href,
          mimeType: "text/plain",
          text: `${path.basename(BASE_DIR)}/\n${tree}`,
        },
      ],
    };
  }
);
```

## サーバーの起動

最後にサーバーを起動するコードを追加します。

```typescript
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`FS MCP Server started. Base directory: ${BASE_DIR}`);
}

main().catch(console.error);
```

## Claude Codeへの登録と動作確認

ビルドして登録しましょう。

```bash
npm run build

# ベースディレクトリを指定して登録
claude mcp add fs-server \
  -e FS_BASE_DIR=/path/to/your/workspace \
  node /absolute/path/to/fs-mcp-server/dist/index.js
```

`-e` フラグで環境変数を渡せます。`FS_BASE_DIR` にアクセスを許可するディレクトリを指定してください。

Claude Codeで試してみましょう。

```
> workspaceのファイル一覧を表示して

> src/config.ts を読んで

> docs/setup.md というファイルを作成して、セットアップ手順を書いて
```

AIモデルが自然な対話の中で、あなたのMCPサーバーのツールを使ってファイル操作を行ってくれるはずです。

## まとめ

- ファイルシステムMCPサーバーは、外部依存なしでMCP開発の基本を学べる最適な題材
- `resolveSafePath` によるパストラバーサル対策は全ファイル操作の前提
- CRUD操作はそれぞれ独立したToolとして実装し、説明文を丁寧に書く
- Resourcesでディレクトリ構造を公開すると、AIモデルがプロジェクトを俯瞰しやすくなる
- 環境変数（`FS_BASE_DIR`）でベースディレクトリを制御し、アクセス範囲を制限する

次の章では、データベースと連携するMCPサーバーを作ります。SQLite/PostgreSQLとの接続を通じて、より実践的なデータ操作を学びましょう。
