---
title: "認証とセキュリティ"
free: false
---

# 認証とセキュリティ — OAuth・APIキー管理・サンドボックス設計

MCPサーバーは外部サービスやローカルリソースへのアクセスゲートウェイです。セキュリティ設計を怠ると、意図しないデータ漏洩や不正操作のリスクが生じます。この章では、MCPサーバーを安全に運用するための実践的なセキュリティパターンを学びます。

**この章で学ぶこと:**

- 環境変数でのAPIキー管理のベストプラクティス
- OAuth 2.0フローをMCPサーバーに組み込む方法
- Zodスキーマによる入力バリデーション
- ファイルアクセスのサンドボックス化
- MCPサーバー開発のセキュリティチェックリスト

## 環境変数でのAPIキー管理

前章でSlackやGitHubのトークンを`.mcp.json`に直接記述しましたが、本番運用ではこれは避けるべきです。

### 基本原則

1. **トークンをコードやconfigにハードコードしない**
2. **`.env`ファイルはgitignoreに追加する**
3. **必須の環境変数はサーバー起動時にバリデーションする**

### 環境変数バリデーションの実装

```typescript
// src/config.ts
import { z } from "zod";

const envSchema = z.object({
  SLACK_BOT_TOKEN: z.string().startsWith("xoxb-", {
    message: "SLACK_BOT_TOKENはxoxb-で始まる必要があります",
  }),
  GITHUB_TOKEN: z.string().min(1, {
    message: "GITHUB_TOKENが設定されていません",
  }),
  ALLOWED_PATHS: z.string().optional().default("/tmp"),
});

export function loadConfig() {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    const errors = result.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");
    console.error(`環境変数の設定エラー:\n${errors}`);
    process.exit(1);
  }

  return result.data;
}
```

起動時にバリデーションを行うことで、設定ミスによる実行時エラーを未然に防げます。Zodを使えば型安全にconfigオブジェクトを扱えるのも利点です。

### .mcp.jsonでの環境変数参照

`.mcp.json`では`env`フィールドで環境変数を渡せます。シェルの環境変数をそのまま参照する場合は、起動スクリプトを経由させるのが安全です。

```json
{
  "mcpServers": {
    "secure-server": {
      "command": "bash",
      "args": ["-c", "source ~/.secrets/mcp-tokens.sh && npx tsx /path/to/server.ts"]
    }
  }
}
```

`~/.secrets/mcp-tokens.sh`には以下のようにトークンを記述します。

```bash
# ~/.secrets/mcp-tokens.sh（パーミッション: 600）
export SLACK_BOT_TOKEN="xoxb-..."
export GITHUB_TOKEN="ghp_..."
```

## OAuth 2.0フロー対応

APIキーではなくOAuth 2.0トークンが必要なサービスもあります。MCPサーバーにOAuthフローを組み込む方法を見てみましょう。

### トークンの保存と更新

```typescript
// src/oauth-manager.ts
import fs from "fs";
import path from "path";

interface TokenData {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

const TOKEN_PATH = path.join(
  process.env.HOME || "",
  ".config",
  "mcp-server",
  "oauth-token.json"
);

export function loadToken(): TokenData | null {
  try {
    const data = fs.readFileSync(TOKEN_PATH, "utf-8");
    return JSON.parse(data) as TokenData;
  } catch {
    return null;
  }
}

export function saveToken(token: TokenData): void {
  const dir = path.dirname(TOKEN_PATH);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(TOKEN_PATH, JSON.stringify(token, null, 2), {
    mode: 0o600, // オーナーのみ読み書き可能
  });
}

export async function refreshAccessToken(
  clientId: string,
  clientSecret: string,
  refreshToken: string,
  tokenUrl: string
): Promise<TokenData> {
  const response = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });

  if (!response.ok) {
    throw new Error(`Token refresh failed: ${response.status}`);
  }

  const data = await response.json() as {
    access_token: string;
    refresh_token: string;
    expires_in: number;
  };

  const token: TokenData = {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  };

  saveToken(token);
  return token;
}
```

### 自動トークン更新の組み込み

```typescript
export async function getValidToken(
  clientId: string,
  clientSecret: string,
  tokenUrl: string
): Promise<string> {
  const token = loadToken();
  if (!token) {
    throw new Error(
      "OAuthトークンが未設定です。初回認証を実行してください。"
    );
  }

  // 有効期限の5分前にリフレッシュ
  if (Date.now() > token.expiresAt - 5 * 60 * 1000) {
    const newToken = await refreshAccessToken(
      clientId,
      clientSecret,
      token.refreshToken,
      tokenUrl
    );
    return newToken.accessToken;
  }

  return token.accessToken;
}
```

トークンの有効期限を5分前に切ることで、リクエスト中にトークンが切れるリスクを減らしています。

## Zodスキーマによる入力バリデーション

MCPのTool定義ではZodスキーマでパラメータを定義しますが、これはバリデーションとしても機能します。セキュリティの観点から、より厳密なバリデーションを設計しましょう。

```typescript
// 危険な入力をブロックするバリデーション例
server.tool(
  "query_database",
  "データベースを検索する",
  {
    // SQLインジェクション対策: テーブル名をホワイトリストで制限
    table: z.enum(["users", "orders", "products"])
      .describe("検索対象のテーブル"),

    // パスの制限: ディレクトリトラバーサル防止
    filePath: z.string()
      .refine((p) => !p.includes(".."), {
        message: "パスに'..'を含めることはできません",
      })
      .refine((p) => p.startsWith("/allowed/"), {
        message: "許可されたディレクトリ外のパスです",
      })
      .optional(),

    // 文字数制限: 過大な入力の防止
    searchQuery: z.string().max(500)
      .describe("検索キーワード"),

    // 件数制限: DoS対策
    limit: z.number().min(1).max(100).default(10)
      .describe("取得件数"),
  },
  async ({ table, searchQuery, limit }) => {
    // バリデーション済みの安全な値のみがここに到達する
    // ...
  }
);
```

特にファイルパスを扱うToolでは、ディレクトリトラバーサル（`../../etc/passwd`のような攻撃パス）への対策が重要です。

## ファイルアクセスのサンドボックス化

第4章で基本的なパストラバーサル対策を実装しましたが、ここではさらに堅牢なサンドボックスクラスに発展させます。

ファイル操作を提供するMCPサーバーでは、アクセス可能なディレクトリを制限するサンドボックスの実装が不可欠です。

```typescript
// src/sandbox.ts
import path from "path";
import fs from "fs";

export class FileAccessSandbox {
  private allowedRoots: string[];

  constructor(allowedPaths: string[]) {
    // 全てのパスを正規化して保持
    this.allowedRoots = allowedPaths.map((p) => path.resolve(p));
  }

  /**
   * パスがサンドボックス内かどうかを検証する
   * @throws アクセス禁止のパスの場合にエラーをスロー
   */
  async validatePath(targetPath: string): Promise<string> {
    const resolved = path.resolve(targetPath);

    // シンボリックリンク経由の脱出を防ぐ
    const real = await fs.promises.realpath(resolved).catch(() => resolved);

    const isAllowed = this.allowedRoots.some((root) =>
      real.startsWith(root + path.sep) || real === root
    );

    if (!isAllowed) {
      throw new Error(
        `アクセス拒否: ${real} は許可されたディレクトリ外です。` +
        `許可: ${this.allowedRoots.join(", ")}`
      );
    }

    return real;
  }
}
```

### サンドボックスの利用

```typescript
const sandbox = new FileAccessSandbox(
  (process.env.ALLOWED_PATHS || "/tmp").split(",")
);

server.tool(
  "read_file",
  "ファイルの内容を読み取る",
  {
    path: z.string().describe("読み取るファイルのパス"),
  },
  async ({ path: filePath }) => {
    try {
      const safePath = sandbox.validatePath(filePath);
      const content = await fs.promises.readFile(safePath, "utf-8");
      return {
        content: [{ type: "text", text: content }],
      };
    } catch (error) {
      return {
        content: [{ type: "text", text: `エラー: ${(error as Error).message}` }],
        isError: true,
      };
    }
  }
);
```

`ALLOWED_PATHS`環境変数でサンドボックスの範囲を制御できるため、プロジェクトごとに柔軟に設定できます。

## ログとモニタリング

セキュリティ上重要な操作はログに記録しましょう。

```typescript
// src/audit-logger.ts
import fs from "fs";

export function auditLog(
  tool: string,
  params: Record<string, unknown>,
  result: "success" | "error" | "denied",
  detail?: string
): void {
  const entry = {
    timestamp: new Date().toISOString(),
    tool,
    params,
    result,
    detail,
  };
  const logLine = JSON.stringify(entry) + "\n";

  // ログファイルに追記
  fs.appendFileSync(
    process.env.AUDIT_LOG_PATH || "/tmp/mcp-audit.log",
    logLine
  );

  // エラーや拒否はstderrにも出力（Claude Codeのログで確認できる）
  if (result !== "success") {
    console.error(`[AUDIT] ${result}: ${tool} - ${detail}`);
  }
}
```

## セキュリティチェックリスト

MCPサーバーを公開・運用する前に、以下の項目を確認しましょう。

### 認証・認可

- [ ] APIトークンはコードやconfigにハードコードされていないか
- [ ] トークンファイルのパーミッションは600（オーナーのみ）か
- [ ] `.env`や秘密鍵ファイルは`.gitignore`に追加されているか
- [ ] OAuthトークンの自動リフレッシュが実装されているか

### 入力バリデーション

- [ ] 全てのToolパラメータにZodスキーマが定義されているか
- [ ] SQLクエリにバインドパラメータを使っているか（文字列結合でないか）
- [ ] ファイルパスにディレクトリトラバーサル対策があるか
- [ ] 入力の長さ・件数に上限を設けているか

### アクセス制御

- [ ] ファイル操作にサンドボックスが適用されているか
- [ ] データベース操作に適切な権限制限があるか（SELECT onlyなど）
- [ ] 破壊的操作（DELETE、DROP）に追加の確認ステップがあるか

### 監査とログ

- [ ] セキュリティ上重要な操作がログに記録されているか
- [ ] エラーメッセージに内部情報（パス、トークンの一部等）が含まれていないか

## まとめ

この章では、MCPサーバーのセキュリティ設計について体系的に学びました。

- **APIキー管理**: 環境変数 + Zodバリデーションで安全に管理
- **OAuth 2.0**: トークンの保存・自動リフレッシュの実装パターン
- **入力バリデーション**: Zodスキーマによる厳密な検証（ホワイトリスト、パス制限、長さ制限）
- **サンドボックス**: ファイルアクセスの範囲を制限するクラス設計
- **監査ログ**: セキュリティイベントの記録

セキュリティは「後から追加」ではなく「最初から組み込む」ものです。ここで紹介したパターンをベースに、安全なMCPサーバーを構築してください。

次章では、Claude CodeでのMCP活用実践として、設定ファイルの設計パターンやMCPサーバーの選定基準について解説します。
