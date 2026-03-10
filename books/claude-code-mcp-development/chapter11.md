---
title: "本番運用"
free: false
---

# 本番運用 -- Docker化・モニタリング・バージョニング

## この章で学ぶこと

- MCPサーバーをDockerコンテナ化する方法
- docker-composeで複数サーバーをまとめて管理する構成
- ヘルスチェックとモニタリングの仕組み
- セマンティックバージョニングの運用ルール
- npmパッケージとしての公開手順
- GitHub Actionsを使ったCI/CDパイプライン

## なぜ本番運用を考える必要があるのか

MCPサーバーは「ローカルで動けばOK」と思いがちですが、チームで共有したり、CI環境で使ったりする場面が増えてきます。環境差異でサーバーが動かない、依存パッケージのバージョン不整合でエラーが出る。こうした問題をDocker化で解決し、安定した運用基盤を作りましょう。

## Dockerfileの作成

MCPサーバーのDockerイメージは、マルチステージビルドで軽量に仕上げます。

```dockerfile
# ---- ビルドステージ ----
FROM node:22-slim AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/

RUN npm run build

# ---- 実行ステージ ----
FROM node:22-slim AS runner

WORKDIR /app

# 本番依存のみインストール
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=builder /app/dist ./dist

# MCPサーバーはstdioで通信するので、ポートは不要
# ENTRYPOINTでサーバーを起動
ENTRYPOINT ["node", "dist/index.js"]
```

ビルドと実行を試してみましょう。

```bash
# ビルド
docker build -t mcp-database-server .

# 実行テスト（stdioモードなので対話的に確認）
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}' | \
  docker run -i --rm mcp-database-server
```

### .dockerignore

不要なファイルをイメージに含めないように設定します。

```
node_modules
dist
*.md
.git
.env
.mcp.json
src/__tests__
```

## docker-composeでの複数サーバー管理

第9章のMonorepo構成を前提に、複数のMCPサーバーをdocker-composeで定義します。

```yaml
# docker-compose.yml
services:
  mcp-database:
    build:
      context: .
      dockerfile: servers/database/Dockerfile
    environment:
      - DB_PATH=/data/app.db
    volumes:
      - db-data:/data

  mcp-slack:
    build:
      context: .
      dockerfile: servers/slack/Dockerfile
    environment:
      - SLACK_TOKEN=${SLACK_TOKEN}

  mcp-github:
    build:
      context: .
      dockerfile: servers/github/Dockerfile
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}

volumes:
  db-data:
```

```bash
# 全サーバーをビルド
docker compose build

# 個別にテスト起動
docker compose run --rm mcp-database
```

Claude Codeから Docker化したMCPサーバーを使うには、`.mcp.json`でdockerコマンドを指定します。

```json
{
  "mcpServers": {
    "database": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-v", "./data:/data",
        "mcp-database-server"
      ]
    }
  }
}
```

ポイントは`-i`フラグです。MCPはstdin/stdoutで通信するため、コンテナの標準入力を開いておく必要があります。

## ヘルスチェックとモニタリング

MCPサーバーはstdioで通信するプロセスなので、HTTPのヘルスチェックエンドポイントは使えません。代わりに、プロセスの生存確認とログベースのモニタリングを組み合わせます。

### プロセスの生存確認

```typescript
// src/health.ts
import { writeFileSync } from "fs";

const HEARTBEAT_FILE = process.env.HEARTBEAT_FILE || "/tmp/mcp-heartbeat";

export function startHeartbeat(intervalMs = 10000) {
  setInterval(() => {
    writeFileSync(HEARTBEAT_FILE, new Date().toISOString());
  }, intervalMs);
}
```

```dockerfile
# Dockerfile にヘルスチェックを追加
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD test $(( $(date +%s) - $(date -r /tmp/mcp-heartbeat +%s) )) -lt 60
```

### メトリクス収集

ツールの呼び出し回数、レスポンス時間、エラー率を記録しましょう。

```typescript
// src/metrics.ts
interface ToolMetrics {
  callCount: number;
  errorCount: number;
  totalDurationMs: number;
}

const metrics = new Map<string, ToolMetrics>();

export function recordToolCall(
  toolName: string,
  durationMs: number,
  isError: boolean
) {
  const current = metrics.get(toolName) || {
    callCount: 0,
    errorCount: 0,
    totalDurationMs: 0,
  };

  current.callCount++;
  if (isError) current.errorCount++;
  current.totalDurationMs += durationMs;

  metrics.set(toolName, current);
}

export function getMetricsSummary() {
  const summary: Record<string, ToolMetrics & { avgDurationMs: number }> = {};
  for (const [name, m] of metrics) {
    summary[name] = {
      ...m,
      avgDurationMs: Math.round(m.totalDurationMs / m.callCount),
    };
  }
  return summary;
}
```

メトリクス情報自体をMCPのResourceとして公開すると、Claude Codeから「サーバーの調子はどう？」と聞けるようになります。

```typescript
server.resource(
  "metrics",
  "mcp://metrics/summary",
  async (uri) => ({
    contents: [{
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(getMetricsSummary(), null, 2),
    }],
  })
);
```

## セマンティックバージョニング

MCPサーバーのバージョン管理には、セマンティックバージョニング（SemVer）を採用しましょう。

```
MAJOR.MINOR.PATCH
  │     │     └── バグ修正（後方互換あり）
  │     └──────── 機能追加（後方互換あり）
  └────────────── 破壊的変更（後方互換なし）
```

MCPサーバーの文脈での具体例を整理します。

| 変更内容 | バージョン変更 |
|---------|-------------|
| エラーメッセージの改善 | PATCH (1.0.0 → 1.0.1) |
| 新しいToolの追加 | MINOR (1.0.1 → 1.1.0) |
| 既存Toolのパラメータ変更 | MAJOR (1.1.0 → 2.0.0) |
| Toolの削除・リネーム | MAJOR (1.1.0 → 2.0.0) |

`McpServer`のコンストラクタに渡す`version`と`package.json`の`version`を一致させましょう。

```typescript
import { readFileSync } from "fs";

const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf-8"));

const server = new McpServer({
  name: pkg.name,
  version: pkg.version, // package.json から読み取る
});
```

## npmパッケージとしての公開

MCPサーバーをnpmパッケージとして公開すれば、`npx`で誰でも即座に利用できます。

### package.json の設定

```json
{
  "name": "@myorg/mcp-database-server",
  "version": "1.0.0",
  "bin": {
    "mcp-database-server": "./dist/index.js"
  },
  "files": ["dist"],
  "type": "module",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "build": "tsc",
    "prepublishOnly": "npm run build && npm test"
  }
}
```

`dist/index.js`の先頭にシバンを追加します。

```typescript
#!/usr/bin/env node
// src/index.ts の先頭に追加
```

### 公開

```bash
# ビルド & テスト
npm run build
npm test

# npm に公開
npm publish --access public
```

公開後は`npx`で実行できるようになります。

```json
{
  "mcpServers": {
    "database": {
      "command": "npx",
      "args": ["-y", "@myorg/mcp-database-server"],
      "env": { "DB_PATH": "./data.db" }
    }
  }
}
```

## CI/CDパイプライン

GitHub Actionsでテスト・ビルド・公開を自動化しましょう。

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run build
      - run: npm test

  publish:
    needs: test
    if: github.ref == 'refs/heads/main' && startsWith(github.event.head_commit.message, 'release:')
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          registry-url: https://registry.npmjs.org
      - run: npm ci
      - run: npm run build
      - run: npm publish --provenance --access public
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

リリースの流れは以下のようになります。

```bash
# 1. バージョンを更新
npm version minor

# 2. コミット & プッシュ
git push origin main --follow-tags

# 3. CIが自動でテスト → 公開
```

## まとめ

- **Docker化**: マルチステージビルドで軽量イメージを作り、`-i`フラグでstdio通信を確保する
- **docker-compose**: 複数サーバーの構成管理に使い、`.mcp.json`からdockerコマンドで接続
- **モニタリング**: ハートビートファイルでプロセス生存確認、メトリクスをResourceとして公開
- **バージョニング**: Tool追加はMINOR、Tool変更・削除はMAJORとしてSemVerを運用
- **npm公開**: `bin`フィールドを設定して`npx`で即利用可能にする
- **CI/CD**: GitHub Actionsでテスト・ビルド・公開を自動化

次章では、本書の集大成として「社内ナレッジベースMCPサーバー」を設計・実装します。これまでの全知識を統合した実践プロジェクトです。
