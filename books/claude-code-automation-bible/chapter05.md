---
title: "Skillsで「コマンド型」自動化を作る"
---

# Skillsで「コマンド型」自動化を作る

## この章で学ぶこと

- Claude Code Skillsの概念と、Hooksとの使い分け
- スキル定義ファイル（Markdownフロントマター+本文）の書き方
- 実装例1: `/write-zenn` — 品質スコアリング内蔵のZenn記事作成スキル
- 実装例2: `/publish-kindle` — EPUB品質チェックからKDP登録まで一貫実行するスキル
- 実装例3: `/deploy` — FTPデプロイスキル
- スキル間の連携パターンと設計指針

## Skillsとは何か

第3章・第4章でHooksを使ったイベント駆動型の自動化を学びました。Hooksは「何かが起きたら自動で実行する」仕組みでした。

Skillsは、それとは対照的な「コマンド型」の自動化です。ユーザーが `/スキル名` と入力することで、定義済みのワークフローが起動します。

```
Hooks = イベント駆動（自動発火）
  → コミット時のlint、ファイル保存時のフォーマット

Skills = コマンド駆動（手動起動）
  → 記事作成、デプロイ、書籍出版
```

Hooksが「裏方の自動化」なら、Skillsは「表舞台のワークフロー」です。チームで共有する定型作業、品質基準つきのコンテンツ作成、複数ステップの手順をスキルにまとめることで、毎回同じクオリティの成果物を出せるようになります。

筆者の環境では、15個のスキルが稼働しており、記事作成からデプロイまでの日常業務をカバーしています。

## スキル定義ファイルの書き方

スキルは `.claude/skills/` ディレクトリにMarkdownファイルとして配置します。

### 配置場所

```
.claude/
  skills/
    write-zenn.md       # /write-zenn で呼び出せる
    publish-kindle.md   # /publish-kindle で呼び出せる
    deploy.md           # /deploy で呼び出せる
```

### フロントマターの構造

```yaml
---
name: write-zenn                    # スキル名（/で呼び出す際の名前）
description: "Zenn記事を作成する"     # 説明文（スキル一覧で表示される）
user_invocable: true                # trueにすると /name で呼び出し可能
---
```

`user_invocable: true` が重要です。これが `false` の場合、他のスキルやエージェントからしか呼び出せません。ユーザーが直接 `/スキル名` で起動したいスキルは、必ず `true` にします。

### 本文の書き方

フロントマターの後に、Markdown形式でスキルの動作を記述します。本文はClaude Codeへの「指示書」になります。

```markdown
---
name: my-skill
description: "説明"
user_invocable: true
---

# /my-skill — スキルの正式名

あなたは○○の専門家です。

## ワークフロー
1. ステップ1: 何を確認するか
2. ステップ2: 何を生成するか
3. ステップ3: 何を出力するか

## ルール
- 守るべき品質基準
- 出力フォーマット
- 禁止事項
```

ポイントは3つです。

1. **ペルソナを与える** — 「あなたは○○の専門家です」と冒頭で役割を定義する
2. **ステップを明示する** — 曖昧さを排除し、実行順序を固定する
3. **品質基準を数値化する** — 「良い記事を書いて」ではなく「100点満点で75点以上」

## 実装例1: /write-zenn — Zenn記事作成スキル

筆者が最も頻繁に使うスキルです。Zenn向け技術記事を品質スコアリング基準つきで生成します。週に5本以上の記事をこのスキルで量産しています。

### スキル定義の全体像

`.claude/skills/write-zenn.md`:

```markdown
---
name: write-zenn
description: Zenn記事を作成する。SEOスコアリング基準（100点満点）に基づき、
  75点以上の記事のみ出力。使い方 /write-zenn "テーマ"
user_invocable: true
---

# /write-zenn — Zenn記事作成スキル

あなたはZenn向け技術記事の専門ライターです。
**記事を書く前にスコアリング基準を確認し、75点以上の記事のみ出力します。**

## スコアリング基準（100点満点）

### 1. SEO（30点）
| 項目 | 配点 | 基準 |
|------|------|------|
| キーワード競合度 | 10 | 低競合=10, 中=7, 高=4 |
| タイトルにメインキーワード含む | 5 | 含む=5, 部分的=3, なし=0 |
| H2/H3が検索クエリに対応 | 5 | 3つ以上=5, 2つ=3, 1つ以下=1 |
| メタディスクリプション最適化 | 5 | 120字以内で訴求=5, 長すぎ/短すぎ=2 |
| 記事長（3,000-7,000字） | 5 | 適正=5, やや外れ=3, 大幅に外れ=1 |

### 2. コンテンツ品質（30点）
| 項目 | 配点 | 基準 |
|------|------|------|
| オリジナリティ | 10 | 独自視点/比較/実体験=10, 一般的=5 |
| 実用性（コード例+手順） | 10 | コピペで使える=10, 概念のみ=5 |
| 構成の論理性 | 5 | 導入→課題→解決→実践→まとめ=5 |
| コードブロック・図表 | 5 | 3つ以上=5, 1-2=3, なし=1 |

### 3. コンバージョン（20点）
| 項目 | 配点 | 基準 |
|------|------|------|
| 書籍CTAの自然な配置 | 10 | 文脈に沿った誘導=10, 末尾のみ=5 |
| 内部リンク（他記事・書籍） | 5 | 2つ以上=5, 1つ=3, なし=0 |
| AIコンサルCTA | 5 | 対象読者に関連=5, 無関係=0 |

### 4. エンゲージメント（20点）
| 項目 | 配点 | 基準 |
|------|------|------|
| フック（冒頭の引き） | 5 | 数字/問題提起=5, 普通=2 |
| 比較表・フローチャート | 5 | あり=5, なし=0 |
| トピックタグの最適化 | 5 | 関連性高い5つ=5, 3つ以下=2 |
| シェアしたくなる要素 | 5 | 独自フレームワーク=5, なし=0 |

## 出力フォーマット
Zennのフロントマター形式で出力:
（省略）

## ルール
1. 読者はエンジニア（中級-上級）
2. コード例は必ずコピペで動くものを含める
3. published: false で保存。公開は自動公開スクリプトが行う
4. 記事末尾にスコアリング結果を表形式で添付する
```

### なぜスコアリング基準を入れるのか

スコアリングなしで「良い記事を書いて」と指示すると、品質にばらつきが出ます。ある日は具体例が豊富な実践的記事、翌日は概念説明だけの薄い記事、といった具合です。

100点満点のルーブリックを定義することで、以下の効果が得られます。

1. **品質の下限を保証** — 75点未満は自動的にリジェクトされる
2. **弱点が可視化される** — スコアリング結果の表で、どの観点が弱いか一目でわかる
3. **改善指示が具体的になる** — 「SEOが弱い」ではなく「H2/H3が検索クエリに対応していない（1/5点）」と指摘できる

実際の運用では、初回生成で70点台だった記事に「コンバージョン項目を改善して」と追加指示するだけで、85点以上に引き上がることがほとんどです。

### 使い方

```
> /write-zenn "Claude CodeのHooksで開発体験を変える方法"
```

Claude Codeがスコアリング基準を読み込み、テーマに沿った記事を生成します。出力先は自動的に `articles/` ディレクトリになり、`published: false` の状態で保存されます。公開は第7章で解説するlaunchd定期実行が担当します。

## 実装例2: /publish-kindle — Kindle出版スキル

Zenn書籍をAmazon Kindleに出版するワークフローをスキル化したものです。EPUB品質チェック、ソース修正、再生成、KDP登録プロンプト作成までを一貫実行します。

### なぜスキル化するのか

Kindle出版には以下の手順が必要です。

1. ZennのMarkdownソースからEPUBを生成（pandoc）
2. EPUBを展開して品質チェック（リスト崩れ、テーブル変換漏れ、Zenn固有記法の残留）
3. 問題があればソースMarkdownを修正
4. EPUB再生成
5. 修正確認
6. KDP登録用の情報をまとめる

これを毎回手動でやると、30分以上かかり、チェック漏れも発生します。スキルにすれば5分です。

### スキル定義

`.claude/skills/publish-kindle.md`:

```markdown
---
name: publish-kindle
description: Zenn書籍をAmazon Kindle向けに出版する。
  EPUB品質チェック→修正→再生成→KDP登録プロンプト作成まで一貫実行。
  使い方 /publish-kindle "書籍名"
user_invocable: true
---

# /publish-kindle — Amazon Kindle出版スキル

Zenn書籍をAmazon Kindleに出版するための一貫ワークフロー。

## ワークフロー

### Step 1: 書籍の特定と確認
書籍ソースの場所: books/{book-slug}/
必要ファイル:
- config.yaml — 書籍メタデータ
- chapter*.md — 各章のMarkdown
- kindle/metadata.yaml — Kindle用メタデータ
- kindle/cover-kindle.jpg — 表紙画像（1600×2560px推奨）

### Step 2: EPUB品質チェック
# EPUBを展開して問題を検出するコマンド
cd /tmp && rm -rf epub_check && mkdir epub_check
unzip -q {epub-path} -d epub_check
# パラグラフに潰れたリストを検出
grep -r '<p><strong>[^<]*:</strong> - ' epub_check/EPUB/text/ | wc -l

### Step 3: 問題があればMarkdownソース修正
# **ラベル:** 直後のリストに空行を追加
perl -i -0777 -pe \
  's/(\*\*[^*]+[:：]\*\*)\n(- |\d+\. )/$1\n\n$2/g' \
  chapter*.md

### Step 4: EPUB再生成
pandoc \
  --metadata-file=kindle/metadata.yaml \
  --epub-cover-image=kindle/cover-kindle.jpg \
  --toc --toc-depth=3 --split-level=1 \
  -f markdown+pipe_tables+grid_tables \
  -o kindle/{book-slug}.epub \
  kindle/title-page.md chapter*.md

### Step 5: 修正確認（問題ゼロを確認）

### Step 6: KDP登録プロンプト生成
出力: kindle/kdp-registration.md
```

### 実行例

```
> /publish-kindle "claude-code-mcp-development"

Step 1: 書籍確認
  - 12章 検出
  - metadata.yaml OK
  - 表紙画像 OK

Step 2: EPUB品質チェック
  - リスト崩れ: 23箇所 検出
  - テーブル変換漏れ: 0箇所
  - Zenn固有記法: 0箇所

Step 3: ソース修正
  - 23箇所修正完了

Step 4: EPUB再生成
  - kindle/claude-code-mcp-development.epub (2.1MB)

Step 5: 修正確認
  - リスト崩れ: 0箇所 ✓

Step 6: KDP登録プロンプト生成完了
  - kindle/kdp-registration.md
```

7冊をこのスキルで出版しました。手動だと1冊あたり30分以上かかっていた作業が、品質チェック込みで5分に短縮されています。

## 実装例3: /deploy — FTPデプロイスキル

レガシーなレンタルサーバーにFTPでデプロイするスキルです。SSH非対応のサーバーを使っているクライアント案件で活躍します。

### スキル定義

`.claude/skills/deploy.md`:

```markdown
---
name: deploy
description: FTPでレンタルサーバーにデプロイする。
  差分のみアップロード。使い方 /deploy "サイト名"
user_invocable: true
---

# /deploy — FTPデプロイスキル

## 前提条件
- .env にFTP接続情報が設定されていること
- lftp がインストールされていること

## ワークフロー

### Step 1: 対象サイトの確認
.company/products/{site-name}/deploy.yaml から接続情報を読み取る:
  host: ftp.example.com
  user: ftpuser
  remote_dir: /public_html
  local_dir: ./dist

### Step 2: ビルド実行
npm run build（対象プロジェクトのビルドコマンドを実行）

### Step 3: 差分デプロイ
# lftpのmirrorコマンドで差分のみアップロード（帯域と時間を節約）
lftp -c "
  set ftp:ssl-allow yes;
  open -u $FTP_USER,$FTP_PASS $FTP_HOST;
  mirror --reverse --delete --verbose \
    --exclude .git/ --exclude node_modules/ \
    $LOCAL_DIR $REMOTE_DIR;
  quit
"

### Step 4: 動作確認
- curl でステータスコード200を確認
- Lighthouse スコアの簡易チェック（オプション）

## ルール
1. デプロイ前に必ずビルドを実行
2. FTPパスワードは.envから読み取り、ログに出力しない
3. --deleteフラグでリモートの不要ファイルも削除
4. 結果をSlack通知（MCP経由）
```

### ポイント: lftpのmirrorコマンド

FTPデプロイで重要なのは差分転送です。毎回全ファイルをアップロードすると、数百ファイルのサイトで10分以上かかります。lftpの `mirror --reverse` は、ローカルとリモートのタイムスタンプ・サイズを比較し、変更されたファイルだけを転送します。

```bash
# --reverse: ローカル→リモートの方向（通常のmirrorはリモート→ローカル）
# --delete: リモートにあってローカルにないファイルを削除
# --verbose: 転送ファイル一覧を表示（ログ用）
lftp -c "
  set ftp:ssl-allow yes;
  open -u $FTP_USER,$FTP_PASS $FTP_HOST;
  mirror --reverse --delete --verbose \
    --exclude .git/ --exclude node_modules/ \
    ./dist /public_html;
  quit
"
```

## スキル間の連携パターン

複数のスキルを組み合わせることで、より大きなワークフローを構築できます。

### パターン1: チェーン実行

あるスキルの出力を、次のスキルの入力にする。

```
/write-zenn "テーマ" → 記事Markdownが生成される
                   ↓
/write-note "同じテーマ" → note向けに再構成
```

筆者の環境では、1つのテーマからZenn・Qiita・noteの3プラットフォーム向けに記事を生成しています。各スキルがプラットフォームの特性（文字数、読者層、フォーマット）に最適化した出力を行います。

### パターン2: 親スキルからの委任

大きなワークフローを1つの親スキルにまとめ、個別のスキルに委任する。

```markdown
---
name: publish-all
description: 全プラットフォームに一括公開
user_invocable: true
---

# /publish-all — 一括公開スキル

## ワークフロー
1. /write-zenn でZenn記事を生成
2. /write-note でnote記事を生成
3. git commit & push でZenn自動公開
4. note投稿はPlaywrightスクリプトで実行
5. 結果をSlackに通知
```

### パターン3: エージェントとスキルの組み合わせ

`.claude/agents/` のエージェント定義から、スキルを呼び出す。

```
エージェント（ai-ceo-cmo.md）
  → コンテンツ戦略を決定
  → /write-zenn を呼び出して記事を生成
  → /write-note を呼び出してnote記事を生成
```

エージェントが「何を書くか」を判断し、スキルが「どう書くか」を実行する。この分離により、戦略変更時にはエージェント定義だけを更新すればよく、実行ロジックに触る必要がありません。

### 設計指針: スキルの粒度

スキルを設計するときに迷うのが粒度です。以下の基準で判断しています。

| 粒度 | 例 | 適切な場面 |
|------|-----|-----------|
| 小さすぎ | `/add-frontmatter` | 単純すぎてスキルにする意味がない。Hooksで十分 |
| ちょうどいい | `/write-zenn` | 1つの成果物を生成する単位 |
| 大きすぎ | `/run-everything` | 何をしているか分からない。分割すべき |

**1スキル = 1成果物** が基本です。記事1本、EPUB1冊、デプロイ1回。複数の成果物をまとめたい場合は、パターン2の親スキルを使います。

## まとめ

- **Skillsは `/コマンド名` で起動するコマンド型の自動化**。`.claude/skills/` にMarkdownで定義する
- **フロントマター**で名前・説明・呼び出し可否を設定し、**本文**でワークフローとルールを記述する
- **品質スコアリング**を組み込むことで、成果物の品質の下限を保証できる
- **スキル間連携**はチェーン実行、親スキルからの委任、エージェントとの組み合わせの3パターン
- **1スキル = 1成果物**の粒度を基本とし、複合ワークフローは親スキルで束ねる
- 次章では、スキルの中から外部サービスを呼び出すための仕組み——MCPサーバーについて解説する
