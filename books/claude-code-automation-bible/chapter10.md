---
title: "SNS・コンテンツの全自動配信パイプライン"
---

## この章で学ぶこと

- Autonomos（Sales Cruise）を使ったSNS自動配信の全体像
- 9プロダクト x 3チャネルで1日27件を配信する設計
- スパム回避のための時間帯分散戦略
- Zenn/Qiita毎日1記事自動公開の実装（launchd + git push）
- note自動投稿の仕組み（Playwright + bot検知対策）
- コンテンツストック管理と品質スコアリング

---

## 10.1 Autonomos（Sales Cruise）によるSNS自動配信

マーケティングの全自動化において、最も効果が大きかったのがSNS配信の自動化だ。筆者の会社では、**Autonomos（Sales Cruise）** というSaaS型のSNS自動配信ツールを使っている。

### なぜ自前で作らなかったのか

SNS自動投稿は自前で実装することもできる。実際、初期はLinkedIn APIとcronで自作していた。しかし、以下の理由でSaaSに移行した。

1. **API仕様の変更への追従コスト** — X（Twitter）のAPIは頻繁に仕様が変わる。自前で追従し続けるのは非効率
2. **スパム検知の回避** — 各プラットフォームのbot検知は年々高度化している。SaaSはこの対策を専門にやっている
3. **スケジュール管理のUI** — 461件のスケジュール済み投稿をCLIだけで管理するのは現実的ではない

月額コストはかかるが、自前メンテナンスの工数を考えれば十分にペイする判断だった。

### 9プロダクト x 3チャネル = 27件/日

筆者の会社には9つのプロダクト（コア3事業 + 保守5プロダクト + 会社ブランド）がある。それぞれについて、X（Twitter）、LinkedIn、Threadsの3チャネルに投稿する。

```
プロダクト一覧（投稿対象）:
1. DX支援・受託開発
2. AI業務自動化コンサルティング
3. Zenn有料書籍・技術記事
4. Focalize（保守モードだがブランド維持）
5. ShareToku（同上）
6. MochiQ（同上）
7. 元気ボタン（同上）
8. スキル管理SaaS（同上）
9. 合同会社ジョインクラス（コーポレート）

チャネル: X / LinkedIn / Threads
→ 9 x 3 = 27件/日（最大稼働時）
```

実際の運用では、コア3事業とコーポレートに集中しているため、1日の投稿件数は10-15件程度だ。保守モードのプロダクトは週1-2回に絞っている。

---

## 10.2 スパム回避の時間帯分散戦略

27件を一気に投稿すると、各プラットフォームのスパムフィルタに引っかかる。これを回避するための設計が重要だ。

### 30分間隔のスケジューリング

```
# Autonomosでの投稿スケジュール設計
# プロダクトごとに30分間隔で配信し、同一アカウントの連続投稿を避ける

08:00  DX支援 → X
08:30  DX支援 → LinkedIn
09:00  AIコンサル → X
09:30  AIコンサル → LinkedIn
10:00  Zenn書籍 → X
10:30  Zenn書籍 → LinkedIn
11:00  コーポレート → X
11:30  コーポレート → LinkedIn
12:00  DX支援 → Threads
12:30  AIコンサル → Threads
...
```

### チャネル別の投稿特性

```yaml
# 各チャネルの投稿設計
# プラットフォームごとに文体・長さ・ハッシュタグを最適化する

x_twitter:
  max_length: 280         # 文字数制限
  hashtags: 3-5           # ハッシュタグ数
  tone: "カジュアル・技術寄り"
  best_time: "8:00-10:00, 12:00-13:00, 20:00-22:00"
  # Xはリアルタイム性が重要。朝・昼・夜に分散

linkedin:
  max_length: 3000        # 長文OK
  hashtags: 3-5
  tone: "ビジネス・プロフェッショナル"
  best_time: "8:00-10:00, 17:00-18:00"
  # LinkedInはビジネスアワーに集中

threads:
  max_length: 500
  hashtags: 0-3           # ハッシュタグ控えめ
  tone: "カジュアル・親しみやすい"
  best_time: "12:00-14:00, 19:00-21:00"
  # Threadsはカジュアルな時間帯
```

### 461件をどう作ったか

461件のSNS投稿コンテンツは、Claude Codeで一括生成した。手順は以下の通り。

1. `sns-content-calendar.md` にカテゴリ配分と投稿テーマを定義
2. Claude Codeに「カレンダーに基づいて、3ヶ月分の投稿テキストを生成してください」と指示
3. 生成されたテキストをCSVに整形
4. AutonomosにCSVインポート

生成から投稿スケジュール設定まで、所要時間は約2時間だった。手動で461件を書いていたら、1件5分としても38時間かかる計算だ。

---

## 10.3 Zenn毎日1記事自動公開

Zennの記事公開は、launchdとgit pushの組み合わせで完全自動化している。

### 仕組みの全体像

```
[ストック記事]                    [launchd]              [Zenn]
articles/                        毎日 8:00 JST          GitHub連携で
  article-001.md (published: false)  ↓                  自動デプロイ
  article-002.md (published: false)  auto-publish.sh     ↓
  article-003.md (published: false)  ↓                  記事が公開される
                                 1本だけ
                                 published: true に変更
                                 → git commit & push
```

### auto-publish.sh の実装

```bash
#!/bin/bash
# Zenn記事を1日1本ずつ自動公開するスクリプト
# launchd: 毎日 8:00 JST
set -euo pipefail

export PATH="/Users/kyoagun/.nvm/versions/node/v22.17.0/bin:/usr/bin:/bin"

REPO_DIR="/Users/kyoagun/workspace/zenn-content-company"
cd "$REPO_DIR"

# 未公開記事を1本見つける（ファイル名順で最初のもの）
# published: false を grep で検索し、最初の1件だけ取得する
TARGET=$(grep -rl "^published: false" articles/*.md 2>/dev/null | head -1)

if [ -z "$TARGET" ]; then
  echo "$(date): No unpublished articles found. Skipping."
  exit 0
fi

FILENAME=$(basename "$TARGET")
echo "$(date): Publishing $FILENAME"

# published: false → true に変更（これだけでZennが公開する）
sed -i '' 's/^published: false/published: true/' "$TARGET"

# git commit & push → ZennのGitHub連携が自動デプロイ
git add "$TARGET"
git commit -m "publish: $(head -3 "$TARGET" | grep 'title:' | sed 's/title: *"*//;s/"*$//')"
git push
```

ポイントは、Zennの「GitHub連携」機能を活用していることだ。Zennはリポジトリの `articles/` ディレクトリを監視しており、`published: true` に変わったファイルがpushされると、自動的に記事を公開する。つまり、`sed` で1行書き換えて `git push` するだけで公開が完了する。

### launchd の設定

```xml
<!-- com.joinclass.zenn-publish.plist -->
<!-- ~/Library/LaunchAgents/ に配置 -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.joinclass.zenn-publish</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/kyoagun/workspace/zenn-content-company/scripts/auto-publish.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <!-- launchdはシェル環境を引き継がないので、PATHを明示する -->
    <key>PATH</key>
    <string>/Users/kyoagun/.nvm/versions/node/v22.17.0/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/kyoagun</string>
  </dict>
  <!-- 毎日 8:00 に実行 -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>8</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
</dict>
</plist>
```

### Qiita自動公開（8:30 JST）

Qiitaも同様の仕組みで、30分後の8:30に自動公開している。QiitaはGitHub連携（`qiita-content` リポジトリ）を使っており、Zennと全く同じパターンだ。

```
08:00  Zenn記事公開（auto-publish.sh）
08:30  Qiita記事公開（同様のスクリプト）
08:43  note記事投稿（別の仕組み、後述）
```

1日の朝に3つのプラットフォームで記事が公開される。読者から見ると「毎日発信している人」に見えるが、実際にはストックを事前に用意して自動配信しているだけだ。

---

## 10.4 note自動投稿（Playwright + bot検知対策）

noteにはGitHub連携のようなAPIがない。そこで、Playwright（ブラウザ自動化ツール）を使ってUIを直接操作する方式で自動投稿している。

### なぜnoteが必要なのか

Zenn/Qiitaはエンジニア向けプラットフォームだ。しかし、AIコンサルティングのターゲットは「中小企業の経営者」であり、エンジニアではない。noteは非エンジニア層へのリーチに優れているため、別途パイプラインを構築した。

### Playwrightによる投稿フロー

```typescript
// note投稿の概要（実装のポイント）
// Playwrightでnoteのエディタを操作し、記事を投稿する

import { chromium } from 'playwright';

async function postToNote(article: {
  title: string;
  body: string;
  tags: string[];
}) {
  // ヘッドレスブラウザを起動
  // user-data-dirを指定してCookieを永続化する（毎回ログインしなくて済む）
  const browser = await chromium.launchPersistentContext(
    '/path/to/note-profile',
    {
      headless: true,
      // bot検知対策: 実際のブラウザに近いUser-Agentを使う
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ...',
    }
  );

  const page = await browser.newPage();
  await page.goto('https://note.com/notes/new');

  // タイトル入力
  await page.fill('[placeholder="タイトル"]', article.title);

  // 本文入力（noteのリッチエディタにMarkdownを貼り付ける）
  await page.click('.note-body-editor');
  await page.keyboard.type(article.body, { delay: 50 });
  // delay: 50 で人間らしい入力速度を模倣する

  // 公開ボタンをクリック
  await page.click('button:has-text("公開")');

  await browser.close();
}
```

### bot検知対策のポイント

noteのbot検知を回避するために、以下の対策を講じている。

```yaml
# bot検知対策の設計
anti_bot_measures:
  # 1. 入力速度を人間に近づける
  typing_delay: 50ms  # 1文字50msの遅延

  # 2. ランダムな待機時間を挟む
  random_wait:
    min: 2000ms
    max: 5000ms

  # 3. Cookie永続化でログイン頻度を減らす
  persistent_context: true

  # 4. 投稿頻度を1日1回に制限
  max_posts_per_day: 1

  # 5. 投稿時刻をランダムにずらす（8:30-8:55の間）
  time_jitter: 25min
```

### launchd設定

```xml
<!-- com.joinclass.note-publish.plist -->
<key>StartCalendarInterval</key>
<dict>
  <!-- 8:43に実行（Zenn 8:00、Qiita 8:30と時間をずらす） -->
  <key>Hour</key>
  <integer>8</integer>
  <key>Minute</key>
  <integer>43</integer>
</dict>
```

---

## 10.5 コンテンツストック管理

自動公開パイプラインが安定稼働するためには、**ストックが切れないこと**が絶対条件だ。ストックがゼロになると、翌日の自動公開が空振りに終わる。

### 3本常時ストックルール

```yaml
# コンテンツストック管理ポリシー
stock_policy:
  # 最低ストック数（これを下回ったらSlack警告）
  minimum_stock:
    zenn_articles: 3    # Zenn記事は最低3本
    qiita_articles: 3   # Qiita記事は最低3本
    note_articles: 3    # note記事は最低3本
    sns_posts: 30       # SNS投稿は最低30件（約3日分）

  # 警告レベル
  warning_threshold: 3  # 残り3本でSlack警告
  critical_threshold: 1 # 残り1本で緊急警告
```

### ストック残数の自動チェック

```bash
#!/bin/bash
# ストック残数を毎朝チェックし、少なければSlack通知
# auto-morning.sh の一部として実行

ZENN_DIR="/Users/kyoagun/workspace/zenn-content-company"

# 未公開記事の数をカウント
# published: false の記事 = まだ公開されていないストック
zenn_stock=$(grep -rl "^published: false" "$ZENN_DIR/articles/"*.md 2>/dev/null | wc -l | tr -d ' ')

if [ "$zenn_stock" -le 3 ]; then
  notify_slack ":warning: [AI-CEO] Zennストック残り${zenn_stock}本。記事の追加生成が必要です。"
fi

if [ "$zenn_stock" -le 1 ]; then
  notify_slack ":rotating_light: [AI-CEO] Zennストック残り${zenn_stock}本！明日の公開に支障が出ます。"
fi
```

### 実績値

筆者の環境での実績は以下の通り。

| プラットフォーム | 初期ストック数 | 消費ペース | 補充頻度 |
|---|---|---|---|
| Zenn | 7本 | 1本/日 | 週1回（Claude Codeで5本一括生成） |
| Qiita | 7本 | 1本/日 | 週1回（同上） |
| note | 5本 | 1本/日 | 週1回（同上） |
| SNS（Autonomos） | 461件 | 10-15件/日 | 月1回（3ヶ月分を一括生成） |

記事の補充もClaude Codeで自動化している。「SEOキーワードリストに基づいて、Zenn記事を5本生成してください」と指示すれば、30分程度で5本のドラフトが完成する。

---

## 10.6 記事品質スコアリングの自動適用

ストックを増やすだけでは不十分だ。品質の低い記事を公開してしまうと、ブランドイメージの毀損やSEOペナルティのリスクがある。

### 100点満点のスコアリングフレームワーク

```yaml
# 記事品質スコアリング基準
# 70点以上で公開可。70点未満は修正後に再スコアリング

scoring:
  seo: 30           # SEO最適化（30点満点）
    title_keyword: 10     # タイトルにターゲットキーワードが含まれるか
    meta_description: 5   # メタディスクリプションの品質
    heading_structure: 10  # 見出し構造（H2/H3の適切な使用）
    internal_links: 5     # 内部リンクの有無

  quality: 30        # コンテンツ品質（30点満点）
    originality: 10       # オリジナリティ（実体験・独自データ）
    depth: 10             # 深さ（表面的でないか）
    readability: 10       # 読みやすさ（段落長、専門用語の説明）

  conversion: 20     # コンバージョン誘導（20点満点）
    cta_presence: 10      # CTAの有無と適切さ
    funnel_alignment: 10  # ファネルとの整合性

  engagement: 20     # エンゲージメント要素（20点満点）
    code_examples: 10     # コード例の有無
    visual_elements: 5    # 図表・スクリーンショット
    actionable: 5         # 読者がすぐ試せる内容か

  # 公開判定
  publish_threshold: 70   # 70点以上で公開可
```

### スコアリングの自動実行

記事がストックに追加されたタイミングで、Claude Codeが自動的にスコアリングを実行する。70点未満の記事は修正ポイントと共にフィードバックされ、修正後に再スコアリングされる。

実際の運用では、初回スコアリングで70点を超える記事は約60%だ。残りの40%は1回の修正で合格ラインに達する。2回以上の修正が必要になったケースは、これまでに1件だけだった。

---

## まとめ

- SNS自動配信はAutonomos（Sales Cruise）に一本化。461件をスケジュール済みで、手動運用ゼロ
- 9プロダクト x 3チャネルの投稿は30分間隔で分散し、スパム検知を回避する
- Zenn/Qiita記事は `published: false` → `true` の書き換え + git pushだけで公開完了
- noteはPlaywrightでUI操作。bot検知対策として入力遅延・ランダム待機・Cookie永続化を実装
- 「3本常時ストック」ルールとSlack警告で、パイプラインの空振りを防止
- 100点満点の品質スコアリングを自動適用し、70点未満の記事は公開前に修正する
