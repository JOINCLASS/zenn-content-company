---
title: "GitHub Copilotのカスタム指示が強すぎる — 失敗を二度と繰り返さないコードレビュー自動化"
emoji: "🛡️"
type: "tech"
topics: ["githubcopilot", "codereview", "automation", "ai", "github"]
published: false
---

「Copilotのコードレビュー、ONにしてるけど汎用的な指摘しか来ないんだよな」

以前の僕もそうだった。普段はTypeScript + Node.jsで自動化スクリプトを書いていて、17個のlaunchdジョブで24時間稼働する基盤を1人で運用している。しかし `.github/copilot-instructions.md` にプロジェクト固有のルールを書き始めた瞬間、Copilotは**プロジェクト専用のシニアレビュアー**に変わった。

この記事では、カスタム指示の書き方、実際のレビューコメント例、そして「本番障害のたびにカスタム指示を育てる」運用パターンを、全てコード付きで公開する。

:::message
**この記事で分かること**
- `copilot-instructions.md` の効果的な書き方（実例付き）
- Copilotが返す実際のレビューコメント3パターン
- 本番障害 → カスタム指示に追加 → 再発防止の運用サイクル
- Copilot CLIでターミナル作業を加速するテクニック
- インライン補完が特に効く場面（openssl、date、jq）

**前提**: GitHub Copilot Free以上。コードレビュー機能はPro以上。Copilot CLIは `gh copilot` 初回実行時に自動インストール。
:::

## カスタム指示を書かないCopilotレビューは半分しか機能していない

GitHub Copilotのコードレビューには `.github/copilot-instructions.md` というカスタム指示ファイルが使える。これを書いていない人が驚くほど多い。

デフォルトのCopilotレビューは、言語の一般的なベストプラクティス（未使用変数、null安全性等）しか指摘しない。しかしカスタム指示を書くと、**プロジェクト固有のルール違反**を自動で検知してくれるようになる。

### 僕が実際に使っているカスタム指示

```markdown
# .github/copilot-instructions.md
# 重要: Copilotはこのファイルの最初の4,000文字だけを読む。短く、具体的に。

## プロジェクト概要
TypeScript + Node.js + シェルスクリプトの自動化基盤。
launchdで17個の定時ジョブが24時間稼働している。

## レビューの重点項目（優先順位順）
1. セキュリティ: シークレットがコードにハードコードされていないか
2. 冪等性: スクリプトを2回実行しても結果が変わらないか
3. エラーハンドリング: 外部APIの失敗時にリトライまたはログ記録があるか
4. 型安全性: anyを使わず、適切な型定義があるか

## レビューしなくていい項目
- コメントの有無（コードの明確さで判断する方針）
- フォーマット（Prettierで自動整形済み）
- テストカバレッジ（別のCIで管理）

## プロジェクト固有のルール（障害から学んだもの）
- launchdスクリプトでは必ず `set -uo pipefail` を使う
- 環境変数は .env から読み込み、ハードコードしない
- curl呼び出しには必ずタイムアウト(-m 30)を設定する
- 全角文字をシェルスクリプトの文字列内で使わない（bashのパース問題の原因）
- git commitの前に変更があるか確認する（空コミット防止）
```

**「プロジェクト固有のルール」セクションに注目してほしい。** これは最初から書いたものではない。本番障害が起きるたびに1行ずつ追加していったものだ。

## Copilotが返す実際のレビューコメント 3パターン

カスタム指示を書くと、Copilotのレビューがどう変わるのか。実際のPRでCopilotが返してきたコメントを要約して3つ紹介する（原文は英語混じりだが、読みやすさのため日本語に整理した）。

### パターン1: シークレット漏洩の防止

```typescript
// PRに含まれていたコード
const SLACK_WEBHOOK = "https://hooks.slack.com/services/T01234/B05678/xyzabc";
```

Copilotのレビューコメント（要約）:

> 🔴 **Security risk**: Slack Webhookのシークレットがソースコードにハードコードされています。`.env`ファイルに移動し、`process.env.SLACK_WEBHOOK_URL`で参照してください。
>
> **Suggested fix**: 環境変数から読み込むように変更し、`.env`を`.gitignore`に追加してください。

これはカスタム指示の「セキュリティ: シークレットがコードにハードコードされていないか」に対応している。デフォルトのCopilotでも検知する可能性はあるが、カスタム指示で最優先に指定することで**見逃しがなくなる**。

### パターン2: 冪等性の欠如

```bash
# 記事を公開するスクリプト
sed -i '' 's/published: false/published: true/' "$ARTICLE_FILE"
git add "$ARTICLE_FILE"
git commit -m "publish: $TITLE"
git push origin main
```

Copilotのレビューコメント（要約）:

> ⚠️ **Idempotency issue**: このスクリプトは冪等ではありません。2回実行すると`sed`は何も変更しませんが、`git commit`が空コミットを試みて失敗します。
>
> **Suggested fix**: 公開前に `grep -q "published: false"` でチェックし、既に `true` なら早期リターンしてください。

「冪等性」はデフォルトのCopilotではまず指摘してこない。カスタム指示に「スクリプトを2回実行しても結果が変わらないか」と書いたからこそ、この観点でレビューが走る。

### パターン3: プロジェクト固有ルールの適用

```bash
RESPONSE=$(curl -sf "$API_URL")
echo "$RESPONSE" | jq '.data'
```

Copilotのレビューコメント（要約）:

> ⚠️ **Missing error handling**: `curl`が失敗した場合、`$RESPONSE`が空になり`jq`がパースエラーを出します。終了コードを確認し、フォールバック処理を追加してください。
>
> また、`-m 30`でタイムアウトを設定してください（`.github/copilot-instructions.md`のプロジェクトルールで必須とされています）。

ここが最も重要なポイントだ。Copilotはカスタム指示の「curl呼び出しには必ずタイムアウト(-m 30)を設定する」というルールを読んで、**指摘の根拠としてプロジェクトルールを引用している**。これはもはやLintではなく、プロジェクトの文脈を理解したレビュアーだ。

## 「失敗駆動カスタム指示」パターン — 障害を二度と繰り返さない仕組み

僕が見つけた最も効果的なCopilot運用は、**本番で障害が起きるたびに、その原因をカスタム指示に1行追加する**サイクルだ。

```
本番障害が発生
    ↓
原因を特定（ポストモーテム）
    ↓
copilot-instructions.md に再発防止ルールを1行追加
    ↓
以降のPRで同じパターンをCopilotが自動検知
    ↓
同じ障害は二度と起きない
```

### 実際の障害 → カスタム指示の進化

**障害1: 全角括弧でbashスクリプトが壊れた**

監視スクリプトのエラーメッセージに全角括弧`（）`を使ったところ、bashの `set -u` で `$EXIT_CODE）` が未定義変数として解釈され、スクリプトが丸1日クラッシュした。

追加した指示: `全角文字をシェルスクリプトの文字列内で使わない（bashのパース問題の原因）`

**障害2: curlのタイムアウト未設定でジョブがハング**

監視スクリプトがZenn APIの応答を待っている最中に、APIが一時的に応答しなくなった。タイムアウト未設定のcurlが待ち続け、その間に後続のQiitaチェック、noteチェック、Slack通知が全てブロックされた。朝の監視が無応答のまま15分以上ハングし、Slackにアラートが届かなかった。

追加した指示: `curl呼び出しには必ずタイムアウト(-m 30)を設定する`

**障害3: 空コミットでデプロイが失敗**

記事公開スクリプトが2回実行され、2回目のgit commitが空コミットになり、CIが失敗した。

追加した指示: `git commitの前に変更があるか確認する（空コミット防止）`

実際にこの運用を始めてから、障害が起きるたびにカスタム指示にルールを追加している。上記の3つの障害対応で、指示は既に5行のプロジェクト固有ルールに育った。**指示が育つほど、同じ失敗は二度と起きなくなる。** これがCopilotコードレビューの本当の価値だ。チームの失敗知識がコードとして蓄積され、全てのPRに自動適用される。

ポストモーテムの結果をWikiに書いて終わりにしていないか？ Wikiは誰も読み返さない。`copilot-instructions.md` に書けば、Copilotが全てのPRで強制的に適用してくれる。

## Copilot CLIでターミナル作業を加速する

Copilotはエディタだけのツールではない。`gh copilot` コマンドでターミナルからも使える。

### suggest: コマンドの提案

「やりたいこと」を自然言語で伝えると、コマンドを提案してくれる。

```bash
# 「10分以上前のgitロックファイルを見つけて削除したい」
$ gh copilot suggest "find git lock files older than 10 minutes and delete them"

# Copilotの提案:
find . -name "index.lock" -path "*/.git/*" -mmin +10 -exec rm -f {} \;
```

`find`の`-mmin`オプション、正確に書ける自信があるだろうか？ 僕はない。これが監視スクリプトにそのまま組み込まれている。

### explain: コマンドの解説

見慣れないコマンドの意味を即座に教えてくれる。

```bash
$ gh copilot explain "openssl s_client -servername \$domain -connect \$domain:443 2>/dev/null | openssl x509 -noout -enddate"

# Copilotの解説:
# 1. openssl s_client: 指定ドメインにTLS接続を確立
# 2. -servername: SNI（Server Name Indication）でドメインを指定
# 3. openssl x509 -noout -enddate: 証明書の有効期限だけを出力
# 結果: "notAfter=Dec 31 23:59:59 2026 GMT" のような文字列が返る
```

Copilot CLIが最も効くのは**「知っているけど構文を覚えていないコマンド」**だ。`openssl`、`date -jf`（macOS）、`jq`のフィルタ構文、`find`のオプション。月に数回しか使わないが、間違えるとバグの原因になるコマンドの補完は、StackOverflowで検索するより圧倒的に速い。

## インライン補完が特に効いた実例

エディタでのインライン補完は誰もが使っている。ここでは「Copilotがなければ確実にハマっていた」具体的な3箇所を紹介する。

### 1. opensslコマンドの構文

SSL証明書の有効期限チェックを書いていた時、`openssl s_client` と入力した時点でCopilotが残りの構文を全て補完してくれた。

```bash
# 「openssl s_client」と書いた時点でCopilotが以下を提案
EXPIRY=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
```

これをmanページから組み立てると、30分はかかる。

### 2. macOSのdateコマンド

macOSの`date`コマンドはLinuxと構文が違う。`date -jf` のフォーマット指定は毎回調べていたが、Copilotは前の行の `EXPIRY` 変数の中身（`Dec 31 23:59:59 2026 GMT` 形式）を読み取って、正しいフォーマット文字列を提案してくれた。

```bash
# Copilotが変数の中身から正しいフォーマットを推測
EXPIRY_EPOCH=$(date -jf "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo "0")
```

### 3. jqでJSONを安全に組み立て

Slack Webhookに送るJSONの組み立てで、変数をエスケープなしで安全に埋め込む方法を提案してくれた。

```bash
# jq -n --arg で変数を安全にJSON文字列に変換（エスケープ不要）
curl -sf -X POST -H "Content-Type: application/json" -m 30 \
  -d "$(jq -n --arg text "監視アラート: $MESSAGE" '{text: $text}')" \
  "$SLACK_WEBHOOK_URL"
```

`jq -n --arg` は知っている人には定石だが、毎回構文を忘れる類のコマンドだ。Copilotはこういう「覚えていないが正確に書く必要がある」場面で最も価値を発揮する。

## 今日から始める3ステップ

### Step 1: カスタム指示を書く（5分）

リポジトリに `.github/copilot-instructions.md` を作る。最初は3行でいい。

```markdown
# .github/copilot-instructions.md

## レビュー重点項目
- エラーハンドリングの漏れを指摘する
- 環境変数のハードコードを警告する
- 型安全性を確認する（any禁止）
```

本番で障害が起きたら、その原因を1行追加する。続けるほど、プロジェクト専用のレビュアーに育っていく。

### Step 2: Copilot CLIを使い始める（1分）

```bash
# GitHub CLI 2.62以降なら、初回実行時に自動インストールされる
gh copilot suggest "find files modified in the last 24 hours"

# 手動インストールが必要な場合
gh extension install github/gh-copilot

# コマンドの解説も即座に
gh copilot explain "awk '{print \$2}'"
```

### Step 3: PRにCopilotレビューを追加する（30秒）

```bash
gh pr create --reviewer "copilot" --title "feat: 新機能追加"
```

この3ステップに追加のインストールは不要。GitHub CLIが入っていれば今日から全て使える。

## まとめ

GitHub Copilotのコードレビューを「ONにしただけ」で終わらせていないか？

1. **カスタム指示を書け。** 3行でいい。プロジェクト固有のルールを書くだけで、Copilotは汎用レビュアー→専用レビュアーに進化する
2. **障害が起きたらカスタム指示に追加しろ。** ポストモーテムの結果をWikiではなく `copilot-instructions.md` に書け。Copilotが全PRで自動適用してくれる
3. **Copilot CLIを使え。** `gh copilot suggest` と `gh copilot explain` は、月に数回しか使わないコマンドの正確な構文を即座に教えてくれる

Copilotは「コード補完ツール」ではない。**育てるレビュアー**だ。

---

この記事は筆者の実務経験に基づいています。カスタム指示の設計パターンやCLAUDE.mdの運用ノウハウは、以下の書籍で体系的にまとめています。

- [CLAUDE.md設計パターン — AIエージェントを正しく動かす技術](https://zenn.dev/joinclass/books/claude-md-design-patterns)
- [全書籍一覧はこちら](https://zenn.dev/joinclass?tab=books)

---

## 付録: コピペで使えるカスタム指示テンプレート

プロジェクトの種類別にテンプレートを用意した。自分のプロジェクトに近いものをコピーして `.github/copilot-instructions.md` に貼り付けてほしい。

### Webアプリ（TypeScript + React）

```markdown
## レビュー重点項目
- XSS脆弱性: dangerouslySetInnerHTML、eval()の使用を警告
- 型安全性: anyの使用を禁止、as型アサーションを警告
- パフォーマンス: useEffectの依存配列漏れを指摘
- アクセシビリティ: img要素のalt属性、button要素のaria-label

## 無視する項目
- CSSのスタイリング（デザインレビューは別途実施）
```

### APIサーバー（Node.js + Express）

```markdown
## レビュー重点項目
- SQLインジェクション: 文字列結合によるクエリ構築を警告
- 認証: ミドルウェアの適用漏れを検知
- バリデーション: リクエストボディの型チェック漏れ
- エラーハンドリング: async/awaitのtry-catch漏れ

## 無視する項目
- ログレベルの選択（運用方針に依存）
```

### シェルスクリプト（CI/CD・自動化）

```markdown
## レビュー重点項目
- set -euo pipefail の漏れ
- 環境変数のハードコード
- curlのタイムアウト未設定
- 全角文字の混入（bashパース問題）
- git操作前の変更有無チェック

## 無視する項目
- ShellCheck警告のうちSC2086（引用符）は無視（意図的な場合が多い）
```
