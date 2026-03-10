---
title: "実践プロジェクト"
free: false
---

# 実践プロジェクト -- 社内ナレッジベースMCPサーバーを作る

## この章で学ぶこと

- これまで学んだ知識を統合して実用的なMCPサーバーを設計・実装する
- 要件定義からTools/Resources/Promptsの設計プロセス
- 全文検索とベクトル検索の実装
- テスト・Docker化・運用までの一連の流れ
- MCPサーバー開発の次のステップ

## プロジェクト概要

最終章では、「社内ドキュメント検索MCPサーバー」を作ります。Markdownで書かれた社内ドキュメント（設計書、議事録、手順書など）をインデックス化し、Claude Codeから自然言語で検索できるサーバーです。

完成するとClaude Codeに対して「認証の設計方針はどうなっていたっけ？」と聞くだけで、関連するドキュメントを見つけてくれるようになります。

## 要件定義

### 機能要件

| 機能 | MCP機能 | 説明 |
|------|---------|------|
| 全文検索 | Tool | キーワードでドキュメントを検索 |
| ベクトル検索 | Tool | 自然言語の質問で意味的に近いドキュメントを検索 |
| ドキュメント一覧 | Resource | インデックス済みドキュメントの一覧を取得 |
| ドキュメント読み取り | Resource Template | 特定ドキュメントの内容を取得 |
| Q&Aプロンプト | Prompt | ナレッジベースに基づいた質問応答テンプレート |
| インデックス更新 | Tool | ドキュメントの追加・再インデックス |

### 技術スタック

- TypeScript + `@modelcontextprotocol/sdk`
- SQLite（better-sqlite3） -- 全文検索（FTS5）とメタデータ管理
- OpenAI Embeddings API -- ベクトル検索用の埋め込みベクトル生成

## プロジェクトのセットアップ

```bash
mkdir mcp-knowledge-base && cd mcp-knowledge-base
npm init -y
npm install @modelcontextprotocol/sdk better-sqlite3 zod glob openai
npm install -D typescript @types/better-sqlite3 @types/node vitest
```

## データベース設計

全文検索にはSQLiteのFTS5拡張を使います。ベクトル検索用の埋め込みはJSON形式で保存します。

```typescript
// src/db.ts
import Database from "better-sqlite3";

export function initializeDatabase(dbPath: string) {
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");

  db.exec(`
    CREATE TABLE IF NOT EXISTS documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      embedding TEXT,
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
      title, content, content=documents, content_rowid=id
    );

    -- FTSインデックスを自動同期するトリガー
    CREATE TRIGGER IF NOT EXISTS documents_ai AFTER INSERT ON documents BEGIN
      INSERT INTO documents_fts(rowid, title, content)
      VALUES (new.id, new.title, new.content);
    END;

    CREATE TRIGGER IF NOT EXISTS documents_ad AFTER DELETE ON documents BEGIN
      INSERT INTO documents_fts(documents_fts, rowid, title, content)
      VALUES ('delete', old.id, old.title, old.content);
    END;

    CREATE TRIGGER IF NOT EXISTS documents_au AFTER UPDATE ON documents BEGIN
      INSERT INTO documents_fts(documents_fts, rowid, title, content)
      VALUES ('delete', old.id, old.title, old.content);
      INSERT INTO documents_fts(rowid, title, content)
      VALUES (new.id, new.title, new.content);
    END;
  `);

  return db;
}
```

## インデックス更新Tool

Markdownファイルを読み込み、データベースに登録するToolを実装します。

```typescript
// src/indexer.ts
import { readFileSync } from "fs";
import { glob } from "glob";
import { basename } from "path";
import type Database from "better-sqlite3";

export async function indexDocuments(
  db: Database.Database,
  docsDir: string
): Promise<{ added: number; updated: number }> {
  const files = await glob("**/*.md", { cwd: docsDir, absolute: true });

  const upsert = db.prepare(`
    INSERT INTO documents (path, title, content, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(path) DO UPDATE SET
      title = excluded.title,
      content = excluded.content,
      updated_at = datetime('now')
  `);

  let added = 0;
  let updated = 0;

  const runBatch = db.transaction(() => {
    for (const filePath of files) {
      const content = readFileSync(filePath, "utf-8");
      const title = extractTitle(content) || basename(filePath, ".md");
      const relativePath = filePath.replace(docsDir, "").replace(/^\//, "");

      const existing = db.prepare(
        "SELECT id FROM documents WHERE path = ?"
      ).get(relativePath);

      upsert.run(relativePath, title, content);

      if (existing) {
        updated++;
      } else {
        added++;
      }
    }
  });

  runBatch();
  return { added, updated };
}

function extractTitle(markdown: string): string | null {
  const match = markdown.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : null;
}
```

## 全文検索Tool

SQLiteのFTS5を使って高速な全文検索を提供します。

```typescript
// src/server.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { initializeDatabase } from "./db.js";
import { indexDocuments } from "./indexer.js";

const DOCS_DIR = process.env.DOCS_DIR || "./docs";
const DB_PATH = process.env.DB_PATH || "./knowledge.db";

const db = initializeDatabase(DB_PATH);

const server = new McpServer({
  name: "knowledge-base",
  version: "1.0.0",
});

// 全文検索
server.tool(
  "kb_search",
  "ナレッジベースをキーワードで全文検索する",
  {
    query: z.string().describe("検索キーワード"),
    limit: z.number().max(20).default(5).describe("取得件数"),
  },
  async ({ query, limit }) => {
    const rows = db.prepare(`
      SELECT d.path, d.title,
             snippet(documents_fts, 1, '**', '**', '...', 32) AS snippet,
             rank
      FROM documents_fts
      JOIN documents d ON d.id = documents_fts.rowid
      WHERE documents_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    `).all(query, limit) as Array<{
      path: string; title: string; snippet: string; rank: number;
    }>;

    if (rows.length === 0) {
      return {
        content: [{
          type: "text",
          text: `「${query}」に一致するドキュメントは見つかりませんでした。`,
        }],
      };
    }

    const results = rows.map((r, i) =>
      `${i + 1}. **${r.title}** (${r.path})\n   ${r.snippet}`
    ).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `## 検索結果（${rows.length}件）\n\n${results}`,
      }],
    };
  }
);
```

## ベクトル検索Tool

自然言語の質問から意味的に近いドキュメントを見つけるベクトル検索を実装します。OpenAI Embeddings APIで埋め込みベクトルを生成し、コサイン類似度で比較します。

```typescript
// src/embeddings.ts
import OpenAI from "openai";
import type Database from "better-sqlite3";

const openai = new OpenAI(); // OPENAI_API_KEY 環境変数を使用

export async function generateEmbedding(text: string): Promise<number[]> {
  const response = await openai.embeddings.create({
    model: "text-embedding-3-small",
    input: text.slice(0, 8000), // トークン制限対策
  });
  return response.data[0].embedding;
}

export async function updateEmbeddings(db: Database.Database) {
  const docs = db.prepare(
    "SELECT id, title, content FROM documents WHERE embedding IS NULL"
  ).all() as Array<{ id: number; title: string; content: string }>;

  for (const doc of docs) {
    const embedding = await generateEmbedding(`${doc.title}\n${doc.content}`);
    db.prepare("UPDATE documents SET embedding = ? WHERE id = ?")
      .run(JSON.stringify(embedding), doc.id);
  }

  return { updated: docs.length };
}

export function cosineSimilarity(a: number[], b: number[]): number {
  let dotProduct = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
}
```

```typescript
// ベクトル検索Tool（server.tsに追加）
import { generateEmbedding, cosineSimilarity, updateEmbeddings } from "./embeddings.js";

server.tool(
  "kb_semantic_search",
  "自然言語の質問でナレッジベースを意味検索する",
  {
    question: z.string().describe("検索したい質問や文章"),
    limit: z.number().max(10).default(3).describe("取得件数"),
  },
  async ({ question, limit }) => {
    const queryEmbedding = await generateEmbedding(question);

    const docs = db.prepare(
      "SELECT id, path, title, content, embedding FROM documents WHERE embedding IS NOT NULL"
    ).all() as Array<{
      id: number; path: string; title: string; content: string; embedding: string;
    }>;

    const scored = docs
      .map((doc) => ({
        ...doc,
        similarity: cosineSimilarity(queryEmbedding, JSON.parse(doc.embedding)),
      }))
      .sort((a, b) => b.similarity - a.similarity)
      .slice(0, limit);

:::message
この実装では全ドキュメントのembeddingをメモリに読み込んで線形走査しています。数百件程度なら問題ありませんが、大規模なドキュメントベースでは`sqlite-vec`や`pgvector`などのベクトルデータベースの利用を検討してください。
:::

    const results = scored.map((r, i) =>
      `${i + 1}. **${r.title}** (類似度: ${(r.similarity * 100).toFixed(1)}%)\n   パス: ${r.path}\n   ${r.content.slice(0, 200)}...`
    ).join("\n\n");

    return {
      content: [{
        type: "text",
        text: `## 意味検索結果（${scored.length}件）\n\n${results}`,
      }],
    };
  }
);
```

## Resources -- ドキュメント一覧とドキュメント読み取り

```typescript
// ドキュメント一覧
server.resource(
  "document-list",
  "kb://documents",
  async (uri) => {
    const docs = db.prepare(
      "SELECT path, title, updated_at FROM documents ORDER BY updated_at DESC"
    ).all();

    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(docs, null, 2),
      }],
    };
  }
);

// 個別ドキュメントの読み取り（Resource Template）
server.resource(
  "document",
  "kb://documents/{path}",
  async (uri) => {
    const path = decodeURIComponent(uri.pathname.replace("/documents/", ""));
    const doc = db.prepare(
      "SELECT title, content, updated_at FROM documents WHERE path = ?"
    ).get(path) as { title: string; content: string; updated_at: string } | undefined;

    if (!doc) {
      return { contents: [{ uri: uri.href, text: "Document not found" }] };
    }

    return {
      contents: [{
        uri: uri.href,
        mimeType: "text/markdown",
        text: doc.content,
      }],
    };
  }
);
```

## Prompts -- Q&Aテンプレート

ナレッジベースに基づいた質問応答のためのプロンプトテンプレートを定義します。

```typescript
server.prompt(
  "kb_qa",
  "ナレッジベースの情報に基づいて質問に回答する",
  { question: z.string().describe("ユーザーの質問") },
  ({ question }) => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text: [
            "以下のナレッジベースの情報を参照し、質問に正確に回答してください。",
            "ナレッジベースに情報がない場合は、その旨を明示してください。",
            "",
            `質問: ${question}`,
            "",
            "まず kb_search または kb_semantic_search ツールで関連ドキュメントを検索し、",
            "その内容を根拠として回答を構成してください。",
          ].join("\n"),
        },
      },
    ],
  })
);
```

## インデックス更新Toolとサーバー起動

```typescript
// インデックス更新Tool
server.tool(
  "kb_reindex",
  "ドキュメントディレクトリを再スキャンしてインデックスを更新する",
  {
    generate_embeddings: z.boolean().default(false)
      .describe("ベクトル埋め込みも生成するか（APIコストがかかります）"),
  },
  async ({ generate_embeddings }) => {
    const indexResult = await indexDocuments(db, DOCS_DIR);

    let embeddingResult = { updated: 0 };
    if (generate_embeddings) {
      embeddingResult = await updateEmbeddings(db);
    }

    return {
      content: [{
        type: "text",
        text: JSON.stringify({
          documents: indexResult,
          embeddings: embeddingResult,
        }, null, 2),
      }],
    };
  }
);

// サーバー起動
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

async function main() {
  // 起動時に自動インデックス
  const result = await indexDocuments(db, DOCS_DIR);
  console.error(`Indexed ${result.added} new, ${result.updated} updated documents`);

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Knowledge Base MCP Server started");
}

main().catch(console.error);
```

## MCP設定とテスト

```json
{
  "mcpServers": {
    "knowledge-base": {
      "command": "npx",
      "args": ["tsx", "/path/to/mcp-knowledge-base/src/server.ts"],
      "env": {
        "DOCS_DIR": "/path/to/your/docs",
        "DB_PATH": "/path/to/knowledge.db",
        "OPENAI_API_KEY": "sk-..."
      }
    }
  }
}
```

設定後、Claude Codeで以下のように使えます。

```
> ドキュメントのインデックスを更新して

> 認証フローの設計について教えて

> APIの利用制限に関するドキュメントを探して
```

## さらなる学習リソースと次のステップ

本書を通じて、MCPサーバーの基礎から実践的な構築・運用までを一通り学びました。ここからさらにスキルを伸ばすためのリソースと方向性を紹介します。

### 公式リソース

- **MCP仕様書**: https://spec.modelcontextprotocol.io -- プロトコルの詳細仕様
- **MCP公式サーバー集**: https://github.com/modelcontextprotocol/servers -- 公式実装例
- **TypeScript SDK**: https://github.com/modelcontextprotocol/typescript-sdk -- 本書で使用したSDK

### 次に取り組むべきテーマ

1. **Streamable HTTP Transport** -- stdioではなくHTTPベースのトランスポートで、リモートサーバーとして公開する
2. **OAuth認証統合** -- MCP仕様に含まれるOAuth 2.0フローを実装し、マルチテナント対応のサーバーを作る
3. **Sampling機能** -- サーバーからクライアント（AI）にリクエストを送り、AI判断をサーバーロジックに組み込む
4. **カスタムTransport** -- WebSocket、gRPCなど独自の通信層を実装する

### MCPサーバーのアイデア集

本書のナレッジベースサーバー以外にも、日常業務で役立つMCPサーバーのアイデアを挙げておきます。

- **CI/CDモニター**: GitHub ActionsやCircleCIのビルド状況をClaude Codeから確認・再実行
- **インフラ管理**: Terraform stateの参照、CloudWatchメトリクスの取得
- **コードレビュー支援**: PRの差分取得、レビューコメントの投稿を自動化
- **議事録管理**: 音声文字起こしの取り込み、要約生成、タスク抽出
- **デザインシステム連携**: Figmaのコンポーネント情報をコード生成に活用

## まとめ

本書の最終章では、社内ナレッジベースMCPサーバーの設計と実装を通じて、これまでの知識を統合しました。

- **設計**: 要件をTools/Resources/Promptsに分解するプロセス
- **データベース**: SQLite FTS5による全文検索、トリガーによるインデックス同期
- **ベクトル検索**: OpenAI Embeddings APIとコサイン類似度による意味検索
- **Resources**: ドキュメント一覧とResource Templateによる個別ドキュメント取得
- **Prompts**: ナレッジベースを活用したQ&Aテンプレート

MCPはまだ若いプロトコルですが、AIと外部システムの接続を標準化する流れは今後加速していきます。本書で身につけた「MCPサーバーを設計・実装・運用できるスキル」は、これからのAIネイティブ開発において大きな武器になるはずです。

ぜひ本書のサンプルコードをベースに、あなた自身の業務に最適化したMCPサーバーを作ってみてください。
