---
title: "第8章 ネットワークセキュリティ -- プロキシ・ファイアウォール・VPN設定"
free: false
---

# 第8章 ネットワークセキュリティ -- プロキシ・ファイアウォール・VPN設定

## この章で学ぶこと

- Claude Codeのネットワーク通信要件
- 企業プロキシ環境でのClaude Code設定
- ファイアウォールの許可ルール設計
- VPN環境での利用時の注意点
- 社内プロキシサーバーによる通信の監視・制御

---

## 前章の振り返りと本章の位置づけ

前章ではシークレット管理を解説し、Claude Codeがアクセスする「データ」の保護を設計した。

本章では、Claude Codeの「通信」を保護する。企業ネットワークでは、プロキシサーバー、ファイアウォール、VPNが標準的に導入されている。Claude Codeをこれらの環境で正しく動作させつつ、セキュリティを確保する設定を示す。


## Claude Codeのネットワーク通信要件

Claude Codeが正常に動作するために必要な通信先を整理する。

### 必須の通信先

| 通信先 | ポート | 用途 | 必須度 |
|--------|-------|------|--------|
| api.anthropic.com | 443 | Claude API（推論） | 必須 |
| statsig.anthropic.com | 443 | Feature Flags | 必須 |
| sentry.io | 443 | エラーレポート | 推奨 |

### オプションの通信先

| 通信先 | ポート | 用途 | 必須度 |
|--------|-------|------|--------|
| registry.npmjs.org | 443 | npm install | Claude Codeがnpmを実行する場合 |
| github.com | 443 | git操作 | Claude Codeがgitを実行する場合 |
| MCPサーバーのホスト | 設定による | MCP連携 | MCP使用時 |

### テレメトリの通信先

テレメトリを無効化している場合は不要。

```bash
# テレメトリの無効化
claude config set --global telemetry disabled
```

> コマンドの構文はClaude Codeのバージョンにより異なる場合があります。`claude config --help` で最新の構文を確認してください。


## 企業プロキシ環境での設定

### HTTPプロキシの設定

多くの企業ではHTTPプロキシサーバーを経由してインターネットにアクセスする。Claude Codeは標準的な環境変数でプロキシを設定できる。

```bash
# 環境変数でプロキシを設定
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080
export NO_PROXY=localhost,127.0.0.1,.company.com

# 認証が必要なプロキシの場合
export HTTPS_PROXY=http://username:password@proxy.company.com:8080
```

注意: プロキシの認証情報を.bashrcや.zshrcに直接書くことは推奨しない。認証情報はシークレットマネージャーや暗号化されたファイルから読み取るスクリプトを用意する。

```bash
# プロキシ設定スクリプト（推奨）
#!/bin/bash
# /usr/local/bin/setup-proxy.sh

# 認証情報を安全な場所から取得
PROXY_PASS=$(security find-generic-password -s "corporate-proxy" -w 2>/dev/null)

if [ -n "$PROXY_PASS" ]; then
  export HTTPS_PROXY="http://$(whoami):${PROXY_PASS}@proxy.company.com:8080"
  export HTTP_PROXY="$HTTPS_PROXY"
  export NO_PROXY="localhost,127.0.0.1,.company.com"
fi
```

### SSL/TLS検査プロキシへの対応

企業プロキシの中には、SSL/TLS通信を傍受・検査するものがある（Man-in-the-Middle型プロキシ）。この場合、企業の証明書をClaude Codeの信頼証明書ストアに追加する必要がある。

```bash
# Node.jsのCA証明書設定
export NODE_EXTRA_CA_CERTS=/path/to/corporate-ca.pem

# または、システム全体の証明書ストアに追加（macOS）
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /path/to/corporate-ca.pem
```

SSL検査プロキシを使用する場合のセキュリティ上の注意点:

**注意**:
- SSL検査プロキシは、Claude CodeとAnthropic API間の通信を復号する
- つまり、プロキシサーバーの管理者はコンテキスト（ソースコード含む）を閲覧可能
- これは意図的な設計（企業が通信を監視するため）だが、リスクとして認識すべき
- 特に機密性の高いプロジェクトでは、SSL検査の除外リストにapi.anthropic.comを追加することを検討する


## ファイアウォール設計

### 最小権限のファイアウォールルール

Claude Codeに必要な通信のみを許可するファイアウォールルールを設計する。

| 分類 | ルール | ポート |
|------|--------|--------|
| **必須** | ALLOW api.anthropic.com | 443 |
| **必須** | ALLOW statsig.anthropic.com | 443 |
| オプション | ALLOW sentry.io（エラーレポート） | 443 |
| 開発用 | ALLOW registry.npmjs.org | 443 |
| 開発用 | ALLOW github.com（HTTPS） | 443 |
| 開発用 | ALLOW github.com（SSH git） | 22 |
| **その他** | **DENY *（全て拒否）** | * |

### iptablesの設定例（Linux）

```bash
#!/bin/bash
# /etc/iptables/claude-code-rules.sh

# Claude Code用の通信を許可するiptablesルール

# Anthropic API
iptables -A OUTPUT -p tcp -d api.anthropic.com --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp -d statsig.anthropic.com --dport 443 -j ACCEPT

# パッケージマネージャー
iptables -A OUTPUT -p tcp -d registry.npmjs.org --dport 443 -j ACCEPT

# git
iptables -A OUTPUT -p tcp -d github.com --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp -d github.com --dport 22 -j ACCEPT

# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# ローカル通信
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# エラーレポート（オプション）
# iptables -A OUTPUT -p tcp -d sentry.io --dport 443 -j ACCEPT

# その他の通信を拒否
iptables -A OUTPUT -j DROP
```

### macOSのpfルール

```
# /etc/pf.conf に追加
# Claude Code用のアウトバウンドルール

# テーブル定義
table <claude_allowed> { api.anthropic.com, statsig.anthropic.com, \
  registry.npmjs.org, github.com }

# 許可ルール
pass out quick proto tcp to <claude_allowed> port 443
pass out quick proto tcp to github.com port 22

# ローカルネットワーク許可
pass out quick to 127.0.0.0/8
pass out quick to 10.0.0.0/8

# その他のアウトバウンド通信をブロック（開発マシン用）
# block out proto tcp to any port 443  # 必要に応じて
```


## VPN環境での利用

### スプリットトンネルの設計

VPNを使用する企業では、Claude Codeの通信をVPN経由にするかどうかを判断する必要がある。

**パターン1: フルトンネル**（全通信がVPN経由）
→ 開発者 → VPN → 企業ネットワーク → インターネット → Anthropic API
→ メリット: 企業のファイアウォール/プロキシで制御可能
→ デメリット: レイテンシ増加、VPN帯域の消費

**パターン2: スプリットトンネル**（Claude Codeの通信はVPN外）
→ 開発者 → インターネット → Anthropic API
→ 開発者 → VPN → 企業内部サービス
→ メリット: 低レイテンシ、VPN帯域の節約
→ デメリット: 企業のプロキシで通信を監視できない

**パターン3: ハイブリッド**（プロキシ経由でVPN外）
→ 開発者 → 社内プロキシ（ローカル） → インターネット → Anthropic API
→ 開発者 → VPN → 企業内部サービス
→ メリット: 通信の監視とパフォーマンスの両立
→ デメリット: 設定が複雑

### 推奨: パターン3（ハイブリッド）

セキュリティとパフォーマンスを両立するため、パターン3を推奨する。

```bash
# VPNクライアントのスプリットトンネル設定例
# api.anthropic.comはVPNを経由しないが、ローカルプロキシ経由

# ルーティングテーブルの設定
# Anthropic APIの通信はデフォルトゲートウェイ（VPN外）を使用
sudo route add -host api.anthropic.com -interface en0  # macOS
```


## 社内プロキシサーバーの構築

API経由でClaude Codeを利用する場合、社内にプロキシサーバーを設置することで、高度なセキュリティ制御が可能になる。

### アーキテクチャ

```mermaid
graph TD
    A["👨‍💻 開発者のマシン\nAPI_KEY=dummy"] -->|"HTTPS"| B["社内プロキシサーバー"]
    B --> B1["✅ 認証（社員ID）"]
    B1 --> B2["🔍 コンテンツフィルタ"]
    B2 --> B3["📝 ログ記録"]
    B3 --> B4["⏱️ 利用量制限"]
    B4 --> B5["🔑 本物のAPIキー付与"]
    B5 -->|"HTTPS"| C["Anthropic API"]
    style A fill:#2d3748,color:#fff
    style B fill:#d69e2e,color:#000
    style C fill:#1a365d,color:#fff
```

### プロキシサーバーの実装例（Node.js）

```typescript
// proxy-server/src/index.ts
import express from "express";
import { createProxyMiddleware } from "http-proxy-middleware";
import { filterSensitiveData } from "./filters/sensitive-data";
import { logRequest } from "./logging/audit";
import { checkRateLimit } from "./rate-limit";
import { authenticateUser } from "./auth";

const app = express();

// JSON bodyの解析
app.use(express.json({ limit: "10mb" }));

// 認証
app.use(authenticateUser);

// レート制限
app.use(checkRateLimit);

// コンテンツフィルタリング
app.use("/v1/messages", async (req, res, next) => {
  if (req.method === "POST" && req.body) {
    const filtered = await filterSensitiveData(req.body);
    if (filtered.blocked) {
      // 機密情報を検出した場合はブロック
      await logRequest(req, "BLOCKED", filtered.reason);
      return res.status(403).json({
        error: {
          type: "security_filter",
          message: `Request blocked: ${filtered.reason}`,
        },
      });
    }
    req.body = filtered.data;
  }
  next();
});

// ログ記録
app.use(async (req, res, next) => {
  await logRequest(req, "ALLOWED");
  next();
});

// Anthropic APIへのプロキシ
app.use(
  "/v1",
  createProxyMiddleware({
    target: "https://api.anthropic.com",
    changeOrigin: true,
    onProxyReq: (proxyReq) => {
      // 本物のAPIキーを付与（開発者のキーは使わない）
      proxyReq.setHeader(
        "x-api-key",
        process.env.ANTHROPIC_API_KEY_REAL || ""
      );
      proxyReq.setHeader("anthropic-version", "2023-06-01");
    },
  })
);

const PORT = process.env.PORT || 3100;
app.listen(PORT, () => {
  console.log(`Claude Code proxy running on port ${PORT}`);
});
```

### コンテンツフィルタリングの実装

```typescript
// proxy-server/src/filters/sensitive-data.ts

interface FilterResult {
  blocked: boolean;
  reason?: string;
  data?: unknown;
}

const SENSITIVE_PATTERNS = [
  // APIキー
  /sk-[a-zA-Z0-9]{20,}/g,
  /AKIA[A-Z0-9]{16}/g,
  /ghp_[a-zA-Z0-9]{36}/g,

  // 日本の個人情報
  /\d{3}-\d{4}-\d{4}/g, // 電話番号
  /\d{3}-\d{4}/g, // 郵便番号（コンテキストで判断）
  /[A-Z0-9]{2}\d{6}/g, // パスポート番号パターン

  // データベース接続文字列
  /postgresql:\/\/[^:]+:[^@]+@[^\/]+\/\S+/g,
  /mysql:\/\/[^:]+:[^@]+@[^\/]+\/\S+/g,
  /mongodb(\+srv)?:\/\/[^:]+:[^@]+@[^\/]+/g,

  // IPアドレス（プライベート除外）
  /(?!10\.)(?!172\.(1[6-9]|2\d|3[01])\.)(?!192\.168\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/g,
];

export async function filterSensitiveData(
  body: Record<string, unknown>
): Promise<FilterResult> {
  const bodyStr = JSON.stringify(body);

  for (const pattern of SENSITIVE_PATTERNS) {
    const match = bodyStr.match(pattern);
    if (match) {
      return {
        blocked: true,
        reason: `Sensitive data detected: ${pattern.source} (matched: ${match[0].substring(0, 10)}...)`,
      };
    }
  }

  return {
    blocked: false,
    data: body,
  };
}
```

### 開発者側の設定

```bash
# 開発者は社内プロキシを向く設定にする
export ANTHROPIC_BASE_URL=http://claude-proxy.internal.company.com:3100
export ANTHROPIC_API_KEY=internal-user-token  # プロキシの認証トークン

# Claude Codeは通常通り使用可能
# 通信は全て社内プロキシを経由する
```


## ネットワーク監視

### 監視すべきメトリクス

1. APIリクエスト数（ユーザー別、時間帯別）
2. リクエストサイズ（異常に大きいリクエストの検知）
3. ブロックされたリクエスト数（機密情報フィルタの動作状況）
4. レスポンスタイム（パフォーマンスの監視）
5. エラーレート（API側の問題検知）

### 異常検知のルール

**アラート条件**:
- 1ユーザーが1時間に100リクエスト以上: 異常利用の可能性
- リクエストサイズが5MB以上: 大量データ送信の可能性
- 機密情報フィルタが5分間に3回以上ブロック: 意図的な漏洩の可能性
- 深夜帯（23:00-06:00）のリクエスト: 不正利用の可能性

次の第9章では、これまで設計してきたセキュリティ対策を、コンプライアンスの観点から整理する。SOC2、ISO27001、GDPR、日本の個人情報保護法への対応方法を解説する。

---

## まとめ

- Claude Codeの必須通信先はapi.anthropic.comとstatsig.anthropic.comの2つ
- 企業プロキシ環境ではHTTPS_PROXY環境変数とCA証明書の設定が必要
- ファイアウォールは最小権限の原則で、必要な通信先のみ許可する
- VPN環境ではハイブリッド構成（プロキシ経由でVPN外通信）を推奨
- 社内プロキシサーバーでコンテンツフィルタリング、ログ記録、利用量制限が可能
- ネットワーク監視で異常な利用パターンを検知する体制を構築する

:::message
**本章の情報はClaude Code 2.x系（v2.1.90）（2026年4月時点）に基づいています。** Claude Codeのメジャーアップデート時に改訂予定です。最新情報は[Anthropic公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)をご確認ください。
:::

> 企業のAI業務自動化の全体設計を知りたい方は「[中小企業AI業務自動化 実践ガイド](https://zenn.dev/joinclass/books/sme-ai-automation-guide)」をご覧ください。ネットワーク設計を含むインフラ全体の自動化パターンを解説しています。
