---
title: "MCPの3つの機能 -- Tools・Resources・Prompts を理解する"
free: false
---

# MCPの3つの機能 -- Tools・Resources・Prompts を理解する

## この章で学ぶこと

- Tools（ツール）の詳細な実装パターンと設計指針
- Resources（リソース）の仕組みと活用場面
- Prompts（プロンプト）の定義方法と使いどころ
- 3つの機能の使い分けの判断基準

## Tools -- AIが「実行」する機能

Toolsは、MCPの中で最も頻繁に使う機能です。AIモデルが外部システムに対してアクションを実行するためのインターフェースを提供します。

### Toolsの基本構造

第2章で簡単なToolを作りましたが、実践的なToolの実装パターンを見ていきましょう。

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const server = new McpServer({
  name: "advanced-tools-example",
  version: "1.0.0",
});

// 複数のパラメータを持つツール
server.tool(
  "search-users",
  "ユーザーを検索します。名前やメールアドレスで絞り込みが可能です",
  {
    query: z.string().describe("検索キーワード（名前またはメールアドレス）"),
    limit: z.number().min(1).max(100).default(10).describe("取得件数（1-100）"),
    includeInactive: z.boolean().default(false).describe("無効なユーザーも含めるか"),
  },
  async ({ query, limit, includeInactive }) => {
    // 実際にはDB検索などを行う
    const results = await searchUsers(query, limit, includeInactive);

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(results, null, 2),
        },
      ],
    };
  }
);
```

### 説明文の書き方が成果を左右する

Toolsの `description`（説明文）は、AIモデルがそのツールを使うかどうかを判断する材料です。ここの書き方で、ツールの利用精度が大きく変わります。

```typescript
// 悪い例: 曖昧で情報が少ない
server.tool("get-data", "データを取得する", ...);

// 良い例: 何のデータを、どんな条件で取得できるかが明確
server.tool(
  "get-sales-report",
  "指定期間の売上レポートを取得します。日次・週次・月次の集計粒度を選択でき、部門別のフィルタリングも可能です。結果はJSON形式で返されます",
  ...
);
```

**ベストプラクティス:**

- 何ができるかを具体的に書く
- 入力パラメータの制約や期待値を説明に含める
- 出力形式（JSON、テキスト、マークダウンなど）を明記する
- 「いつこのツールを使うべきか」がAIモデルに伝わるように書く

### エラーハンドリング

MCPツールのエラーハンドリングは、`isError` フラグで制御します。

```typescript
server.tool(
  "delete-user",
  "指定したIDのユーザーを削除します",
  {
    userId: z.string().describe("削除するユーザーのID"),
  },
  async ({ userId }) => {
    try {
      await deleteUser(userId);
      return {
        content: [
          {
            type: "text",
            text: `ユーザー ${userId} を削除しました`,
          },
        ],
      };
    } catch (error) {
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `ユーザーの削除に失敗しました: ${error instanceof Error ? error.message : "不明なエラー"}`,
          },
        ],
      };
    }
  }
);
```

`isError: true` を返すと、AIモデルはエラーが発生したことを認識し、ユーザーに適切に報告したりリトライを検討できます。例外をスローするのではなく、必ずエラーレスポンスとして返してください。

## Resources -- AIが「読む」データ

Resourcesは、MCPサーバーが公開する読み取り専用のデータソースです。Toolsとの違いは、**副作用がない**こと。データの参照のみを行います。

### Resourcesの基本実装

```typescript
// 静的なリソース
server.resource(
  "app-config",
  "config://app",
  async (uri) => {
    const config = await loadConfig();
    return {
      contents: [
        {
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify(config, null, 2),
        },
      ],
    };
  }
);
```

`server.resource()` は3つの引数を取ります。

1. **リソース名**: 人間が読むための識別名
2. **URI**: リソースを一意に識別するURI
3. **ハンドラー**: リソースの内容を返す非同期関数

### リソーステンプレート

動的なリソースには、URIテンプレートを使います。

```typescript
// 動的なリソース（URIテンプレート）
server.resource(
  "user-profile",
  "users://{userId}/profile",
  async (uri, { userId }) => {
    const profile = await getUserProfile(userId);
    return {
      contents: [
        {
          uri: uri.href,
          mimeType: "application/json",
          text: JSON.stringify(profile, null, 2),
        },
      ],
    };
  }
);
```

`{userId}` の部分がプレースホルダーとなり、クライアントが具体的な値を指定して呼び出します。

### ToolsとResourcesの使い分け

| 観点 | Tools | Resources |
|------|-------|-----------|
| 副作用 | あり（データの変更、外部への送信） | なし（読み取り専用） |
| 呼び出し主体 | AIモデルが判断して呼ぶ | ユーザーやクライアントが明示的に読む |
| ユースケース | データの作成・更新・削除、API呼び出し | 設定情報の参照、スキーマの取得、ドキュメント表示 |
| 冪等性 | 保証されない | 保証される |

迷ったときの基準は「このアクションでシステムの状態が変わるか」です。変わるならTool、変わらないならResourceです。

## Prompts -- 再利用可能なプロンプトテンプレート

Promptsは、特定のワークフローに最適化されたプロンプトテンプレートを定義する機能です。Toolsほど使用頻度は高くありませんが、チーム内で知見を共有するのに便利です。

### Promptsの基本実装

```typescript
server.prompt(
  "code-review",
  "コードレビューを実行するためのプロンプト",
  {
    language: z.string().describe("プログラミング言語"),
    code: z.string().describe("レビュー対象のコード"),
  },
  ({ language, code }) => {
    return {
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `以下の${language}コードをレビューしてください。

観点:
1. バグや潜在的な問題
2. パフォーマンスの改善点
3. 可読性と保守性
4. セキュリティ上の懸念

\`\`\`${language}
${code}
\`\`\`

各観点について、問題があれば具体的な修正案を示してください。`,
          },
        },
      ],
    };
  }
);
```

### Promptsが活きる場面

- **チーム共通のレビュー基準**を持つプロンプトを標準化したいとき
- **複雑なワークフロー**（多段階の分析など）のテンプレートを共有したいとき
- **ドメイン知識**を含むプロンプトを非エンジニアでも使えるようにしたいとき

```typescript
server.prompt(
  "sql-query-builder",
  "自然言語からSQLクエリを生成するプロンプト",
  {
    description: z.string().describe("取得したいデータの説明"),
    tables: z.string().describe("利用可能なテーブル名（カンマ区切り）"),
  },
  ({ description, tables }) => {
    return {
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `以下のテーブルを使って、指定されたデータを取得するSQLクエリを生成してください。

利用可能なテーブル: ${tables}

取得したいデータ: ${description}

条件:
- PostgreSQL 15の構文を使用
- パフォーマンスを考慮したクエリにする
- 必要に応じてJOINやサブクエリを使用
- 結果にはCOMMENTを付けて各部分の意図を説明する`,
          },
        },
      ],
    };
  }
);
```

## 3つの機能を組み合わせる

実践的なMCPサーバーでは、3つの機能を組み合わせて使います。以下は、タスク管理MCPサーバーの設計例です。

```typescript
const server = new McpServer({
  name: "task-manager",
  version: "1.0.0",
});

// Resource: タスク一覧を参照する（読み取り専用）
server.resource("task-list", "tasks://all", async (uri) => {
  const tasks = await getAllTasks();
  return {
    contents: [{
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(tasks, null, 2),
    }],
  };
});

// Tool: タスクを作成する（副作用あり）
server.tool("create-task", "新しいタスクを作成します", {
  title: z.string().describe("タスクのタイトル"),
  priority: z.enum(["high", "medium", "low"]).describe("優先度"),
}, async ({ title, priority }) => {
  const task = await createTask(title, priority);
  return {
    content: [{
      type: "text",
      text: `タスクを作成しました: ${task.id} - ${task.title}`,
    }],
  };
});

// Prompt: 週次レビュー用のテンプレート
server.prompt("weekly-review", "週次タスクレビューを実行する", {}, () => ({
  messages: [{
    role: "user",
    content: {
      type: "text",
      text: "今週のタスク進捗をレビューしてください。完了タスク、未完了タスク、ブロッカーを整理し、来週の優先事項を提案してください。",
    },
  }],
}));
```

## まとめ

- **Tools** は副作用のあるアクション。MCPで最も使用頻度が高い
- **Resources** は読み取り専用のデータソース。コンテキスト提供に使う
- **Prompts** は再利用可能なテンプレート。チーム知見の標準化に使う
- 判断基準は「状態が変わるか」（Tool）、「読むだけか」（Resource）、「プロンプトのパターン化か」（Prompt）
- 実践的なサーバーでは、3つを組み合わせて使う

次の章では、これらの知識を活かして、実用的なファイルシステムMCPサーバーをゼロから作ります。
