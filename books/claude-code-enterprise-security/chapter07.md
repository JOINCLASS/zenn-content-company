---
title: "第7章 シークレット管理 -- APIキー・認証情報の安全な扱い方"
free: false
---

# 第7章 シークレット管理 -- APIキー・認証情報の安全な扱い方

## この章で学ぶこと

- Claude Code環境でのシークレット漏洩リスクの全体像
- .envファイルの安全な管理方法
- シークレットマネージャーとの連携パターン
- gitへのシークレット混入を防ぐ仕組み
- シークレットローテーションの自動化

---

## 前章の振り返りと本章の位置づけ

前章でHooksによるセキュリティ強制を解説した。Hooksのパターン1で「機密情報を含むコマンドのブロック」を実装したが、シークレット管理の課題はそれだけでは解決しない。

「そもそもシークレットをどこに保存し、どう管理するか」という根本的な設計が必要だ。Claude Code環境では、AIがファイルを読み取りコマンドを実行するため、従来よりも慎重なシークレット管理が求められる。


## シークレット漏洩の経路

Claude Code環境でシークレットが漏洩する経路は大きく5つある。

**経路1: .envファイルの直接読み取り**
→ .env → Claude Code → Anthropic API

**経路2: コマンド実行結果に含まれる**
→ printenv → 出力にAPIキー → Claude Code → Anthropic API

**経路3: ソースコードにハードコード**
→ const API_KEY = "sk-..." → Claude Code → Anthropic API

**経路4: gitの履歴に残存**
→ git log -p → 過去にコミットされた.env → Claude Code → Anthropic API

**経路5: ログファイルに出力**
→ error.log → スタックトレースにDB接続文字列 → Claude Code → Anthropic API

### 経路ごとの対策マップ

| 経路 | 防御レイヤー1 | 防御レイヤー2 | 防御レイヤー3 |
|------|-------------|-------------|-------------|
| .envの読み取り | Permissions deny | Hooks PreToolUse | .gitignore |
| コマンド出力 | Hooks PreToolUse | CLAUDE.md指示 | — |
| ハードコード | CLAUDE.md指示 | ESLintルール | PRレビュー |
| git履歴 | git-secrets | truffleHog | BFG Repo-Cleaner |
| ログファイル | Permissions deny | アプリ側マスキング | — |


## .envファイルの安全な管理

### 原則: .envファイルはClaude Codeの手の届かない場所に置く

最も安全なアプローチは、.envファイルをClaude Codeが読み取れない場所に配置することだ。

```bash
# 方法1: Permissionsでブロック（第4章で解説済み）
# .claude/settings.json
{
  "permissions": {
    "deny": ["Read(*.env)", "Read(*.env.*)"]
  }
}

# 方法2: .envファイルの代わりにシークレットマネージャーを使用
# アプリケーション起動時にシークレットマネージャーから取得する
```

### .envファイルを使い続ける場合のベストプラクティス

現実的には、多くのプロジェクトで.envファイルが使われている。その場合の安全な管理方法を示す。

```bash
# 1. .gitignore に必ず追加
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore
echo "!.env.example" >> .gitignore  # テンプレートはコミット可

# 2. .env.example を用意（値は空またはダミー）
cat > .env.example << 'EOF'
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/mydb

# API Keys (get from team lead)
STRIPE_SECRET_KEY=sk_test_xxx
ANTHROPIC_API_KEY=sk-ant-xxx

# Feature Flags
ENABLE_DEBUG=false
EOF

# 3. 実際の.envファイルには本物の値を入れる
# このファイルはgitにコミットしない、Claude Codeにも読ませない
```

### .env.vault パターン

dotenv-vaultを使ったシークレットの暗号化管理パターンも有効だ。

```bash
# dotenv-vault のセットアップ
npx dotenv-vault new
npx dotenv-vault push

# .env.vault（暗号化されたファイル）はgitにコミット可能
# 復号キーは環境変数 DOTENV_KEY で渡す
# Claude Codeが .env.vault を読んでも暗号化されているため安全
```


## シークレットマネージャーとの連携

企業レベルでは、.envファイルの代わりにシークレットマネージャーを使うのが推奨だ。

### AWS Secrets Manager

```typescript
// src/config/secrets.ts
import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({ region: "ap-northeast-1" });

export async function getSecret(secretName: string): Promise<string> {
  const command = new GetSecretValueCommand({ SecretId: secretName });
  const response = await client.send(command);

  if (response.SecretString) {
    return response.SecretString;
  }
  throw new Error(`Secret ${secretName} not found`);
}

// 使用例
// const dbUrl = await getSecret("production/database-url");
// const stripeKey = await getSecret("production/stripe-secret-key");
```

このパターンのメリット:
- シークレットがファイルシステムに存在しない
- Claude Codeがソースコードを読んでも、シークレットの値は見えない
- IAMロールでアクセス制御が可能
- シークレットのローテーションが自動化できる

### HashiCorp Vault

```typescript
// src/config/vault.ts
import Vault from "node-vault";

const vault = Vault({
  apiVersion: "v1",
  endpoint: process.env.VAULT_ADDR || "http://127.0.0.1:8200",
  token: process.env.VAULT_TOKEN,
});

export async function getSecret(path: string): Promise<Record<string, string>> {
  const result = await vault.read(path);
  return result.data.data;
}

// 使用例
// const secrets = await getSecret("secret/data/production/api-keys");
// const stripeKey = secrets["stripe_secret_key"];
```

### GCP Secret Manager

```typescript
// src/config/gcp-secrets.ts
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";

const client = new SecretManagerServiceClient();

export async function getSecret(
  projectId: string,
  secretName: string
): Promise<string> {
  const [version] = await client.accessSecretVersion({
    name: `projects/${projectId}/secrets/${secretName}/versions/latest`,
  });

  const payload = version.payload?.data;
  if (payload) {
    return typeof payload === "string"
      ? payload
      : Buffer.from(payload).toString("utf-8");
  }
  throw new Error(`Secret ${secretName} not found`);
}
```

### シークレットマネージャーの選定基準

| 要件 | AWS Secrets Manager | HashiCorp Vault | GCP Secret Manager |
|------|--------------------|-----------------|--------------------|
| マネージド | Yes | No（自前運用） | Yes |
| 自動ローテーション | Yes | Plugin必要 | Yes |
| 動的シークレット | 限定的 | Yes | No |
| コスト | $0.40/secret/月 | OSS無料〜Enterprise | $0.06/10K operations |
| クラウド依存 | AWS | クラウド非依存 | GCP |


## gitへのシークレット混入防止

### git-secrets

```bash
# インストール
brew install git-secrets  # macOS
# または
git clone https://github.com/awslabs/git-secrets.git
cd git-secrets && make install

# リポジトリに設定
cd your-project
git secrets --install
git secrets --register-aws  # AWSキーパターンを登録

# カスタムパターンの追加
git secrets --add 'sk-ant-[a-zA-Z0-9]+'       # Anthropic API Key
git secrets --add 'sk-[a-zA-Z0-9]{48}'         # OpenAI API Key
git secrets --add 'ghp_[a-zA-Z0-9]{36}'        # GitHub PAT
git secrets --add 'password\s*=\s*["\x27].+["\x27]'  # パスワードの直書き

# コミット時に自動チェック（pre-commitフック）
# git secrets --installで自動設定される
```

### pre-commitフレームワーク

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: package-lock.json

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: detect-private-key
      - id: check-added-large-files
        args: ['--maxkb=500']
```

```bash
# セットアップ
pip install pre-commit
pre-commit install

# ベースラインの生成（既存の「シークレットに見える文字列」を除外）
detect-secrets scan > .secrets.baseline

# 手動スキャン
detect-secrets scan --all-files
```

### truffleHog（git履歴のスキャン）

```bash
# インストール
brew install trufflehog

# リポジトリ全履歴のスキャン
trufflehog git file://. --only-verified

# GitHub上のリポジトリをスキャン
trufflehog github --org your-org --only-verified

# CI/CDに組み込み
# .github/workflows/secret-scan.yml
```

```yaml
# .github/workflows/secret-scan.yml
name: Secret Scan
on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # 全履歴を取得

      - name: TruffleHog Scan
        uses: trufflesecurity/trufflehog@main
        with:
          extra_args: --only-verified
```


## シークレットがコミットされてしまった場合の対処

万が一シークレットがgitにコミットされてしまった場合の緊急対応手順を示す。

```bash
# 1. 即座にシークレットを無効化（最優先）
# - APIキーの場合: ダッシュボードから即座にrevokeする
# - パスワードの場合: 即座に変更する
# ※ git履歴からの削除より先にシークレットを無効化する

# 2. git履歴からの削除（BFG Repo-Cleaner）
# BFGのインストール
brew install bfg

# シークレットを含むファイルの履歴を削除
bfg --delete-files .env
bfg --replace-text passwords.txt  # passwords.txtに置換パターンを記載

# gc実行
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 3. force push（チーム全員に事前通知必須）
git push --force

# 4. インシデントレポートの作成
# - いつシークレットがコミットされたか
# - どのシークレットが漏洩したか
# - 影響範囲の評価
# - 再発防止策
```

### Claude Codeが読み取った可能性がある場合

Claude Codeがシークレットを含むファイルを読み取った場合、そのデータはAnthropicのAPIに送信されている可能性がある。

**対応手順**:
1. シークレットを即座に無効化・ローテーション
2. Anthropicサポートに連絡（Enterprise契約の場合）
3. 該当データの削除を依頼
4. Permissions/Hooksの設定を見直し、再発を防止


## シークレットローテーションの自動化

定期的なシークレットローテーションは、漏洩リスクを低減する重要な施策だ。

```typescript
// scripts/rotate-secrets.ts
// AWS Secrets Managerでの自動ローテーション設定

import {
  SecretsManagerClient,
  RotateSecretCommand,
} from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({ region: "ap-northeast-1" });

async function enableAutoRotation(
  secretId: string,
  rotationDays: number
): Promise<void> {
  const command = new RotateSecretCommand({
    SecretId: secretId,
    RotationRules: {
      AutomaticallyAfterDays: rotationDays,
    },
  });

  await client.send(command);
  console.log(
    `Auto-rotation enabled for ${secretId}: every ${rotationDays} days`
  );
}

// 90日ごとにローテーション
// enableAutoRotation("production/database-url", 90);
// enableAutoRotation("production/stripe-secret-key", 90);
```


## Claude Code環境でのシークレット管理チェックリスト

```markdown
## シークレット管理チェックリスト

### ファイルシステム
- [ ] .envファイルが.gitignoreに含まれている
- [ ] .env.exampleにはダミー値のみ記載されている
- [ ] Permissionsで.envファイルの読み取りがdenyされている
- [ ] Hooksで機密情報パターンの検出が設定されている

### ソースコード
- [ ] ハードコードされたシークレットがない
- [ ] ESLint等でシークレットのハードコードを検出するルールがある
- [ ] 環境変数の参照はprocess.env経由のみ

### git
- [ ] git-secretsまたはdetect-secretsが設定されている
- [ ] pre-commitフックでシークレットスキャンが実行される
- [ ] CI/CDでtruffleHogによる全履歴スキャンが実行される

### シークレットマネージャー
- [ ] 本番シークレットはシークレットマネージャーに保存されている
- [ ] 開発環境と本番環境でシークレットが分離されている
- [ ] シークレットの自動ローテーションが設定されている
- [ ] シークレットへのアクセスログが記録されている

### インシデント対応
- [ ] シークレット漏洩時の緊急対応手順が文書化されている
- [ ] シークレットの無効化手順が明確である
- [ ] Anthropicサポートへの連絡先が把握されている
```

次の第8章では、ネットワークレベルでのセキュリティ対策を解説する。プロキシサーバーの設置、ファイアウォール設定、VPN環境でのClaude Code利用について具体的に示す。

---

## まとめ

- Claude Code環境でのシークレット漏洩経路は5つ: .env読み取り、コマンド出力、ハードコード、git履歴、ログファイル
- 各経路に対して多層防御（Permissions + Hooks + CLAUDE.md + gitフック）を構築する
- .envファイルよりシークレットマネージャー（AWS Secrets Manager、HashiCorp Vault等）の使用を推奨
- git-secretsやdetect-secretsでコミット前にシークレットを検出する
- シークレットがコミットされた場合は、まずシークレットの無効化を最優先で行う
- 定期的なシークレットローテーションで漏洩リスクを低減する

:::message
**本章の情報はClaude Code 2.x系（v2.1.90）（2026年4月時点）に基づいています。** Claude Codeのメジャーアップデート時に改訂予定です。最新情報は[Anthropic公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)をご確認ください。
:::

> AIエージェントによる業務自動化の全体像を知りたい方は「[Claude Codeで会社を動かす](https://zenn.dev/joinclass/books/claude-code-ai-ceo)」をご覧ください。セキュリティを確保しながらAIエージェントを運用する実践例を解説しています。
