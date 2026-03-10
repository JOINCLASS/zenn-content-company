---
title: "Claude CodeでのMCP活用実践"
free: false
---

# Claude CodeでのMCP活用実践 — 設定ファイルの設計パターン

これまでの章でMCPサーバーの作り方を学んできました。この章では視点を変えて、Claude CodeユーザーとしてMCPサーバーをどう活用するかに焦点を当てます。設定ファイルの書き方、MCPサーバーの選び方、公式サーバーとカスタムサーバーの使い分けを解説します。

**この章で学ぶこと:**

- `.mcp.json`の構造と設定パターン
- プロジェクト別MCP設定のベストプラクティス
- MCPサーバーの選定基準
- 公式MCPサーバーの活用方法
- カスタムMCPサーバーとの使い分け

## 設定ファイルの種類と使い分け

Claude CodeでMCPサーバーを利用するには、設定ファイルにサーバー情報を記述します。設定ファイルは3つのスコープがあり、用途に応じて使い分けます。

| スコープ | ファイル | 用途 |
|---------|---------|------|
| プロジェクト | `.mcp.json`（プロジェクトルート） | そのリポジトリ専用のMCPサーバー |
| ユーザー | `~/.claude/settings.json` | 個人の全プロジェクト共通 |
| デスクトップ | `claude_desktop_config.json` | Claude Desktop App用 |

### .mcp.json の構造

プロジェクトルートに配置する`.mcp.json`が最も使用頻度の高い設定ファイルです。

```json
{
  "mcpServers": {
    "server-name": {
      "command": "実行コマンド",
      "args": ["引数1", "引数2"],
      "env": {
        "ENV_VAR": "値"
      }
    }
  }
}
```

各フィールドの意味を確認しましょう。

- **`command`**: MCPサーバーを起動するコマンド（`node`, `npx`, `python`など）
- **`args`**: コマンドに渡す引数の配列
- **`env`**: サーバープロセスに渡す環境変数

### 実践的な.mcp.json の例

Webアプリケーション開発プロジェクトの設定例を見てみましょう。

```json
{
  "mcpServers": {
    "database": {
      "command": "npx",
      "args": ["tsx", "./tools/mcp-servers/database.ts"],
      "env": {
        "DATABASE_URL": "postgresql://localhost:5432/myapp_dev"
      }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": ""
      }
    },
    "filesystem": {
      "command": "npx",
      "args": [
        "-y", "@modelcontextprotocol/server-filesystem",
        "/Users/you/project/docs",
        "/Users/you/project/config"
      ]
    }
  }
}
```

この例では、3つのMCPサーバーを使い分けています。

1. **database**: プロジェクト内に自作したデータベース連携サーバー
2. **github**: npmパッケージとして公開されている公式GitHubサーバー
3. **filesystem**: 公式ファイルシステムサーバー（特定ディレクトリのみ許可）

## プロジェクト別MCP設定のベストプラクティス

### 1. リポジトリにコミットする設定とシークレットを分離する

`.mcp.json`はリポジトリにコミットして、チームで共有できます。ただし、APIトークンなどのシークレットはコミットしてはいけません。

```json
{
  "mcpServers": {
    "slack": {
      "command": "bash",
      "args": [
        "-c",
        "source .env.local && npx tsx ./tools/mcp-servers/slack.ts"
      ]
    }
  }
}
```

`.env.local`をgitignoreに追加し、チームメンバーには`.env.local.example`を提供するパターンが有効です。

```bash
# .env.local.example（コミットする）
SLACK_BOT_TOKEN=xoxb-your-token-here
NOTION_API_KEY=ntn_your-key-here
```

### 2. MCPサーバーのコードをプロジェクト内に配置する

カスタムMCPサーバーは`tools/mcp-servers/`のようなディレクトリにまとめて配置すると管理しやすいです。

```
my-project/
  .mcp.json
  tools/
    mcp-servers/
      database.ts      # DB連携
      deploy.ts         # デプロイ操作
      test-runner.ts    # テスト実行
  src/
    ...
```

### 3. 開発環境と本番環境の設定を分ける

MCPサーバーから本番データベースに接続するのは危険です。環境変数で接続先を切り替えましょう。

```typescript
// tools/mcp-servers/database.ts
const DB_URL = process.env.DATABASE_URL;
const IS_PRODUCTION = DB_URL?.includes("production");

if (IS_PRODUCTION) {
  console.error("本番データベースへの接続は許可されていません");
  process.exit(1);
}
```

## MCPサーバーの選定基準

MCPサーバーを導入する際の判断フレームワークを紹介します。

### 公式/コミュニティサーバーを選ぶか、自作するか

```
その機能は既存のMCPサーバーでカバーされているか？
├── はい → 公式/コミュニティサーバーを使う
│   ├── メンテナンスされているか？ → 採用
│   └── 放置されている？ → フォークして自作
└── いいえ → カスタムMCPサーバーを自作する
    ├── 汎用的な機能か → npmパッケージとして公開を検討
    └── プロジェクト固有か → リポジトリ内に配置
```

### 選定時のチェックポイント

| 観点 | 確認事項 |
|------|---------|
| 信頼性 | メンテナが誰か。公式（@modelcontextprotocol）か |
| セキュリティ | どんな権限を要求しているか。過剰なスコープはないか |
| 依存関係 | 依存パッケージの数と品質。脆弱性はないか |
| ドキュメント | 設定方法が明確に記載されているか |
| 更新頻度 | 直近のコミットはいつか。Issueは放置されていないか |

## 公式MCPサーバーの活用

Anthropicが公開している公式MCPサーバーは、品質とセキュリティの面で信頼できます。主要なサーバーを紹介します。

### @modelcontextprotocol/server-filesystem

ファイルの読み書き、ディレクトリ一覧、検索機能を提供します。

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y", "@modelcontextprotocol/server-filesystem",
        "/path/to/allowed/dir1",
        "/path/to/allowed/dir2"
      ]
    }
  }
}
```

引数で指定したディレクトリのみにアクセスが制限されるため、安全に利用できます。ドキュメントフォルダや設定ファイルのディレクトリを指定するケースが多いです。

### @modelcontextprotocol/server-github

GitHubのIssue、PR、リポジトリ操作をClaude Codeから行えます。

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": ""
      }
    }
  }
}
```

Claude Code自体にもGitHub連携機能がありますが、MCPサーバー経由ではより細かい操作（ラベル管理、マイルストーン操作など）が可能です。

### @modelcontextprotocol/server-slack

Slackのメッセージ送信、チャンネル操作を提供します。

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "",
        "SLACK_TEAM_ID": ""
      }
    }
  }
}
```

### @modelcontextprotocol/server-postgres

PostgreSQLに直接クエリを発行できます。開発データベースの確認やデバッグに便利です。

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": [
        "-y", "@modelcontextprotocol/server-postgres",
        "postgresql://user:pass@localhost:5432/mydb"
      ]
    }
  }
}
```

## カスタムMCPサーバーとの使い分け

### 公式サーバーが適しているケース

- 汎用的なサービス連携（GitHub、Slack、ファイル操作）
- 標準的なCRUD操作
- すぐに使い始めたいとき

### カスタムサーバーが適しているケース

- プロジェクト固有のビジネスロジックを含む操作
- 複数のAPIを組み合わせたワークフロー
- 独自のバリデーションやアクセス制御が必要なとき
- 社内システムとの連携

### 組み合わせの実例

実際のプロジェクトでは、公式サーバーとカスタムサーバーを組み合わせて使うのが一般的です。

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "" }
    },
    "project-db": {
      "command": "npx",
      "args": ["tsx", "./tools/mcp-servers/project-db.ts"],
      "env": { "DATABASE_URL": "postgresql://localhost:5432/myapp_dev" }
    },
    "deploy": {
      "command": "npx",
      "args": ["tsx", "./tools/mcp-servers/deploy.ts"],
      "env": { "DEPLOY_ENV": "staging" }
    }
  }
}
```

この構成では、GitHub連携は公式サーバーに任せつつ、プロジェクト固有のデータベース操作とデプロイ操作はカスタムサーバーで実装しています。

## MCPサーバーの管理コマンド

Claude Codeには、MCPサーバーを管理するためのCLIコマンドが用意されています。

```bash
# MCPサーバーの一覧を表示
claude mcp list

# MCPサーバーを追加
claude mcp add server-name npx -y @modelcontextprotocol/server-github

# MCPサーバーを削除
claude mcp remove server-name
```

`claude mcp add`を使うと、`.mcp.json`を手動で編集せずにサーバーを追加できます。チームメンバーへのセットアップ手順を共有する際に便利です。

## まとめ

この章では、Claude CodeでのMCP活用について実践的な視点から解説しました。

- **設定ファイル**: `.mcp.json`のスコープ（プロジェクト、ユーザー、デスクトップ）と使い分け
- **ベストプラクティス**: シークレットの分離、ディレクトリ構成、環境の分離
- **選定基準**: 公式サーバー vs カスタムサーバーの判断フレームワーク
- **公式サーバー**: filesystem, github, slack, postgresの設定例
- **組み合わせ**: 公式とカスタムのハイブリッド構成パターン

MCPの真価は、複数のサーバーを組み合わせてClaude Codeの能力を拡張することにあります。まずは公式サーバーで基本的な連携を構築し、プロジェクト固有のニーズに合わせてカスタムサーバーを追加していく、というアプローチがおすすめです。

次の章では、複数のMCPサーバーを組み合わせてマイクロサービス的なアーキテクチャを構築する方法を解説します。
