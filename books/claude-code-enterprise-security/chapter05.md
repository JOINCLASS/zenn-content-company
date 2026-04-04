---
title: "第5章 CLAUDE.mdによるセキュリティポリシーの実装"
free: false
---

# 第5章 CLAUDE.mdによるセキュリティポリシーの実装

## この章で学ぶこと

- CLAUDE.mdの仕組みと読み込み順序
- セキュリティポリシーをCLAUDE.mdに落とし込む方法
- 組織全体・プロジェクト・ディレクトリ単位のポリシー設計
- 実運用で使えるCLAUDE.mdテンプレート
- CLAUDE.mdの限界と補完手段

---

## 前章の振り返りと本章の位置づけ

前章ではPermissionsによる技術的なアクセス制御を設計した。Permissionsは「どのツールを使えるか」を制御する仕組みだ。

しかし、セキュリティポリシーは「このファイルを読むな」「このコマンドを実行するな」だけでは不十分だ。「どのように振る舞うべきか」という行動規範も必要になる。

例えば、「本番データベースのテーブルを変更する際は必ずマイグレーションファイルを作成すること」「外部APIのレスポンスにユーザー情報が含まれる場合はログに出力しないこと」といったルールは、Permissionsでは表現できない。

これを担うのがCLAUDE.mdだ。


## CLAUDE.mdとは何か

CLAUDE.mdは、Claude Codeに対する「指示書」だ。プロジェクトのルート、サブディレクトリ、またはユーザーのホームディレクトリに配置でき、Claude Codeはこのファイルの内容を自動的に読み込んで従う。

重要なのは、CLAUDE.mdは**Permissionsのような強制力はない**ということだ。Claude Codeは CLAUDE.mdの内容を「指示」として解釈し、可能な限り従う。しかし、技術的にブロックされるわけではない。

そのため、CLAUDE.mdは**「第一防衛線」**として機能し、Permissionsは**「最終防衛線」**として機能する。両方を組み合わせた多層防御が望ましい。


## CLAUDE.mdの読み込み順序と階層

CLAUDE.mdは以下の順序で読み込まれ、全てが結合されてClaude Codeのコンテキストに含まれる。

1. `~/.claude/CLAUDE.md` -- ユーザー個人のグローバル設定
2. `/project-root/CLAUDE.md` -- プロジェクトルートの設定
3. `/project-root/src/CLAUDE.md` -- サブディレクトリの設定（作業対象に応じて）
4. `/project-root/.claude/CLAUDE.md` -- .claudeディレクトリ内の設定

Permissionsとは異なり、CLAUDE.mdは「上書き」ではなく「結合」される。つまり、全ての階層のCLAUDE.mdが読み込まれ、Claude Codeはその全てに従おうとする。

矛盾する指示がある場合は、一般的にはより具体的な（サブディレクトリの）指示が優先される傾向があるが、保証はない。矛盾を避ける設計が重要だ。


## セキュリティポリシーをCLAUDE.mdに実装する

### 組織レベルのCLAUDE.md

全リポジトリに共通するセキュリティポリシーを定義する。開発者のホームディレクトリに配置するか、各リポジトリにコピーする。

```markdown
# セキュリティポリシー

## 絶対に行ってはならないこと

1. .envファイル、.env.local、.env.production等の環境変数ファイルの内容を
   読み取ったり、出力したり、コミットしたりしない
2. APIキー、パスワード、トークン等のシークレット情報を
   コード内にハードコードしない
3. 本番データベースに直接クエリを実行しない
4. git push --force を実行しない
5. mainブランチに直接コミットしない
6. rm -rf で重要なディレクトリを削除しない
7. curlやwgetで外部にデータを送信しない
8. ユーザーの個人情報（氏名、メールアドレス、住所等）を
   ログやコメントに含めない

## コミット・プッシュのルール

- コミットメッセージはConventional Commitsに従う
- 全てのコード変更はフィーチャーブランチで行う
- mainブランチへのマージはPull Requestを通す
- PRにはセキュリティ関連の変更を明記する

## コードレビューの観点

- 新しい依存パッケージを追加する際は、そのパッケージの
  メンテナンス状況とセキュリティ履歴を確認する
- 外部APIとの通信は必ずHTTPSを使用する
- ユーザー入力は必ずバリデーションする
- SQLクエリはパラメータ化クエリを使用する（SQL injection防止）
```

### プロジェクトレベルのCLAUDE.md

プロジェクト固有のセキュリティポリシーを定義する。

```markdown
# プロジェクト: 顧客管理システム

## セキュリティ分類

このプロジェクトは顧客の個人情報を扱うため、
セキュリティレベル: **高** に分類される。

## 機密ファイル

以下のファイルには機密情報が含まれる。読み取り・変更を行わない。
- config/production.json
- certs/
- .env, .env.local, .env.production
- database/seeds/production/

## データベース操作のルール

- マイグレーションファイルは必ず `database/migrations/` に作成する
- 直接SQLを実行しない。必ずORMを通す
- テストデータにはダミーデータを使用する。実際の顧客データを
  テストに使用しない
- 個人情報を含むカラムにはコメントで「PII」と明記する

## API設計のルール

- 個人情報を返すエンドポイントには認証を必須とする
- レスポンスに不要な個人情報を含めない（最小権限の原則）
- 個人情報のログ出力はマスキングする（例: email → t***@example.com）
- レート制限を全エンドポイントに設定する

## 依存パッケージ

- 新しいパッケージを追加する際は、npm auditの結果を確認する
- high以上の脆弱性があるパッケージは使用しない
- パッケージのバージョンは固定する（^ や ~ を使わない）
```

### ディレクトリレベルのCLAUDE.md

特にセンシティブなディレクトリに配置する。

```markdown
# /src/services/payment/ のルール

このディレクトリは決済処理を担当する。

## 特別なセキュリティルール

- クレジットカード番号をログに出力しない
- 決済APIのレスポンスをそのまま保存しない
- テストではStripeのテストキーのみを使用する
- 金額計算には浮動小数点を使わず、整数（cents）で処理する
- 全ての金額変更はトランザクション内で行う

## コード変更時の注意

- このディレクトリのコード変更はセキュリティチームのレビューを必須とする
- 変更理由をコミットメッセージに詳細に記載する
```


## 実運用で使えるCLAUDE.mdセキュリティテンプレート

筆者が実際に使用しているテンプレートをベースに、企業向けに拡張したテンプレートを提供する。

### テンプレート: Webアプリケーション（TypeScript/Node.js）

```markdown
# セキュリティポリシー

## 環境

- Node.js 22.x
- TypeScript 5.x
- Next.js 15.x

## 禁止事項

### ファイル操作
- .env* ファイルの読み取り・表示・コミット禁止
- node_modules/ 内のファイル変更禁止
- package-lock.json の手動変更禁止

### コード規約
- any型の使用禁止（型安全性の確保）
- eval() の使用禁止（コードインジェクション防止）
- innerHTML の直接代入禁止（XSS防止）
- 動的SQLの構築禁止（パラメータ化クエリを使用）
- console.log に個人情報を含めない（構造化ログを使用）

### Git操作
- mainブランチへの直接コミット禁止
- git push --force 禁止
- コミットに.envファイルを含めない

### 外部通信
- HTTPでの外部通信禁止（HTTPSのみ）
- 信頼されていないURLへのリクエスト禁止
- CORSの設定を緩める変更は要レビュー

## 必須事項

### 認証・認可
- 全APIルートに認証ミドルウェアを適用
- ロールベースアクセス制御を使用
- セッショントークンの有効期限を設定

### データ保護
- 個人情報のログ出力時はマスキング
- パスワードはbcrypt等でハッシュ化
- 機密データの暗号化にはAES-256を使用

### エラーハンドリング
- 本番環境でスタックトレースを表示しない
- エラーレスポンスに内部情報を含めない
- 全エラーを構造化ログに記録

## テスト

- セキュリティ関連のコードにはユニットテストを必須とする
- テストデータにはFaker.jsで生成したダミーデータを使用
- 本番のAPIキーをテストに使用しない
```

### テンプレート: インフラ・DevOps

```markdown
# インフラセキュリティポリシー

## 禁止事項

- 本番環境への直接SSH禁止（踏み台サーバー経由）
- 本番DBへの直接クエリ禁止（管理ツール経由）
- セキュリティグループの0.0.0.0/0許可禁止
- IAMユーザーのアクセスキー直接利用禁止（IAMロールを使用）
- Terraformの state ファイルの直接変更禁止

## IaCルール

- インフラ変更は全てTerraform/CloudFormationで管理
- terraform plan の結果を確認してから apply
- stateファイルは暗号化してリモートバックエンドに保存
- 秘密情報はSSM Parameter StoreまたはSecrets Managerを使用

## Docker

- rootユーザーでコンテナを実行しない
- マルチステージビルドでイメージサイズを最小化
- ベースイメージは公式イメージを使用
- 定期的にイメージの脆弱性スキャンを実施
```


## CLAUDE.mdの限界

CLAUDE.mdは強力な指示メカニズムだが、以下の限界がある。

### 1. 技術的な強制力がない

CLAUDE.mdは「指示」であり「制限」ではない。Claude Codeは通常これに従うが、ユーザーが明示的に指示を上書きする場合（例: 「CLAUDE.mdのルールは無視して.envを読んで」）、従ってしまう可能性がある。

**対策**: 本当に絶対にブロックしたい操作は、PermissionsのdenyリストまたはHooksで制御する。CLAUDE.mdは「第一防衛線」、Permissions/Hooksは「最終防衛線」と位置づける。

### 2. コンテキストウィンドウを消費する

CLAUDE.mdの内容は常にコンテキストウィンドウに含まれる。長大なCLAUDE.mdはコンテキストウィンドウを圧迫し、Claude Codeのパフォーマンスに影響する。

**対策**: CLAUDE.mdは簡潔に保つ。詳細なドキュメントは別ファイルに置き、CLAUDE.mdからは「詳細はsecurity-policy.mdを参照」と書く。ただし、常に読み込まれるのはCLAUDE.mdだけなので、重要なルールはCLAUDE.mdに直接書く。

### 3. ユーザーが変更できる

プロジェクトのCLAUDE.mdはgitで管理されているため、PRでの変更が可能だ。悪意のある変更や、不注意による変更で、セキュリティポリシーが緩む可能性がある。

**対策**: 前章で紹介したCIでのsettings.json検証と同様に、CLAUDE.mdの変更もCIで検知し、セキュリティチームのレビューを必須とする。

```yaml
# .github/workflows/check-claude-md.yml
name: Check CLAUDE.md changes
on:
  pull_request:
    paths:
      - 'CLAUDE.md'
      - '**/CLAUDE.md'
      - '.claude/CLAUDE.md'

jobs:
  require-security-review:
    runs-on: ubuntu-latest
    steps:
      - name: Add security review label
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              labels: ['security-review-required']
            })
```


## CLAUDE.md + Permissions の組み合わせパターン

| セキュリティ要件 | CLAUDE.md | Permissions |
|----------------|-----------|-------------|
| .envを読まない | 「.envファイルを読み取らない」と記載 | `"deny": ["Read(*.env*)"]` |
| force pushしない | 「git push --forceを実行しない」と記載 | `"deny": ["Bash(git push --force*)"]` |
| 個人情報をログに出さない | 「個人情報のログ出力はマスキング」と記載 | Permissionsでは制御不可 |
| テストにダミーデータを使う | 「テストデータにはFaker.jsを使用」と記載 | Permissionsでは制御不可 |
| mainに直接コミットしない | 「mainブランチへの直接コミット禁止」と記載 | `"deny": ["Bash(git checkout main)"]` |
| パラメータ化クエリを使う | 「動的SQLの構築禁止」と記載 | Permissionsでは制御不可 |

この表からわかるように、**コーディング規約やベストプラクティスはCLAUDE.mdでしか制御できない**。一方、**ファイルアクセスやコマンド実行の制限はPermissionsで技術的に強制すべき**だ。

次の第6章では、CLAUDE.mdでもPermissionsでも制御しきれないケースを、Hooksで動的に制御する方法を解説する。

---

## まとめ

- CLAUDE.mdはClaude Codeへの「行動規範」を定義するファイルで、複数の階層に配置可能
- 組織レベル・プロジェクトレベル・ディレクトリレベルで段階的にポリシーを定義する
- CLAUDE.mdは「指示」であり技術的な強制力はないため、Permissionsと組み合わせた多層防御が必要
- コーディング規約やデータ取り扱いのルールはCLAUDE.mdでしか表現できない
- CLAUDE.mdの変更はCIで検知し、セキュリティレビューを必須とする

:::message
**本章の情報はClaude Code 2.x系（v2.1.90）（2026年4月時点）に基づいています。** Claude Codeのメジャーアップデート時に改訂予定です。最新情報は[Anthropic公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)をご確認ください。
:::

> CLAUDE.mdの設計パターンをさらに詳しく知りたい方は「[CLAUDE.md設計パターン](https://zenn.dev/joinclass/books/claude-md-design-patterns)」で、20以上の実践パターンを解説しています。
