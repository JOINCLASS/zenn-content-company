---
title: "Playwrightでブラウザ操作を自動化する"
---

# Playwrightでブラウザ操作を自動化する

## この章で学ぶこと

- PlaywrightでAPI非対応サービスを自動化する考え方
- bot検知対策（UserAgent、ランダム遅延、WebDriver検出回避）
- 実装例1: noteへの記事自動投稿
- 実装例2: KDPへの書籍登録支援
- セッション管理（storageStateの保存・復元）
- エラー時のスクリーンショット保存
- 実際の運用での注意点（利用規約、レート制限）

## なぜPlaywrightが必要なのか

ここまでの章で、API経由の自動化を解説してきました。Slack通知はWebhook API、Zenn公開はGit push、Qiita投稿はAPI経由。しかし、すべてのサービスがAPIを提供しているわけではありません。

**noteにはパブリックな投稿APIがありません。** KDP（Kindle Direct Publishing）も、書籍登録のAPIを公開していません。

こうしたAPI非対応サービスを自動化する最終手段が、Playwrightによるブラウザ操作です。人間がブラウザで行う操作——ログイン、フォーム入力、ボタンクリック——をプログラムで再現します。

```
API自動化（推奨）:
  スクリプト → API → サービス

ブラウザ自動化（APIがない場合の最終手段）:
  スクリプト → Playwright → ブラウザ → サービス
```

筆者の環境では、noteへの毎日の記事投稿をPlaywrightで自動化しています。月間約30本の記事を、人間の操作なしで投稿しています。

## bot検知対策

ブラウザ自動化で最初にぶつかる壁がbot検知です。多くのWebサービスは、自動操作を検知してブロックする仕組みを持っています。Playwrightをデフォルト設定で使うと、高確率で検知されます。

### 対策1: UserAgentの設定

Playwrightのデフォルトは `HeadlessChrome` を含むUserAgentです。これは即座にbot判定されます。

```javascript
// デフォルト（bot検知される）
const context = await browser.newContext();

// 対策: 実際のChromeと同じUserAgentを設定
const context = await browser.newContext({
  userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  viewport: { width: 1280, height: 800 },
  locale: "ja-JP",
  timezoneId: "Asia/Tokyo",
});
```

### 対策2: WebDriver検出の回避

ブラウザの `navigator.webdriver` プロパティは、Playwrightで操作されている場合に `true` を返します。多くのサービスがこれをチェックしています。

```javascript
// WebDriver検出を回避する
await context.addInitScript(() => {
  // navigator.webdriverをfalseに上書き
  Object.defineProperty(navigator, "webdriver", { get: () => false });
});
```

### 対策3: ランダム遅延（人間らしい操作速度）

人間は一定のリズムで操作しません。クリック間隔、タイピング速度、スクロール量にばらつきがあります。

```javascript
// 人間らしいランダム遅延
function humanDelay(minMs = 500, maxMs = 2000) {
  const delay = Math.floor(Math.random() * (maxMs - minMs)) + minMs;
  return new Promise((resolve) => setTimeout(resolve, delay));
}

// 人間のタイピング速度: 1文字あたり30-80ms
function humanTypingDelay() {
  return Math.floor(Math.random() * 50) + 30;
}

// 人間らしいスクロール
async function humanScroll(page) {
  const scrollAmount = Math.floor(Math.random() * 300) + 100;
  await page.mouse.wheel(0, scrollAmount);
  await humanDelay(300, 800);
}

// 人間らしいマウス移動（直線ではなく複数ステップで移動）
async function humanMouseMove(page) {
  const x = Math.floor(Math.random() * 800) + 100;
  const y = Math.floor(Math.random() * 400) + 100;
  await page.mouse.move(x, y, {
    steps: Math.floor(Math.random() * 5) + 3, // 3-7ステップで移動
  });
  await humanDelay(200, 500);
}
```

### 対策4: headless: false

ヘッドレスモード（画面なし）は検知されやすいです。自動化スクリプトでも `headless: false` で起動し、実際のブラウザウィンドウを表示します。

```javascript
const browser = await chromium.launch({
  headless: false, // 画面を表示する（検知回避のため）
  args: [
    "--disable-blink-features=AutomationControlled", // 自動化フラグを無効化
  ],
});
```

macOSのlaunchdから起動する場合、画面表示が必要です。GUIセッション内で実行されることが前提となるため、MacBookのスリープ解除後に実行するスケジュールにするのが確実です。

## 実装例1: noteへの記事自動投稿

筆者が毎日運用しているスクリプトの実装です。Markdownファイルからタイトル・本文・ハッシュタグを読み取り、noteに自動投稿します。

### ファイル構成

```
.company/scripts/note/
  post-to-note.mjs      # 投稿スクリプト本体
  note-session.json      # ログインセッション（自動保存）
  auto-post-note.sh      # launchdから呼ばれるラッパー

.company/departments/marketing/note/
  standalone/            # 投稿待ち記事
    article-001.md
    article-002.md
  published/             # 投稿済み記事（自動移動）
```

### 記事ファイルのフォーマット

```markdown
# AI時代の経営者に必要な3つのスキル

近年、AIの進化により経営の在り方が大きく変わりつつあります。
（本文...）

**ハッシュタグ:** #AI #経営 #DX #生成AI #業務効率化
```

### 投稿スクリプトの核心部分

```javascript
#!/usr/bin/env node
import { chromium } from "playwright";
import { readFileSync, readdirSync, renameSync, existsSync, mkdirSync } from "fs";
import { join, basename, dirname } from "path";

const SESSION_FILE = join(__dirname, "note-session.json");

// ── 記事のパース ──
function parseArticle(filePath) {
  const content = readFileSync(filePath, "utf-8");
  const lines = content.split("\n");

  // 最初の # 見出しをタイトルとして取得
  let title = "";
  let bodyStart = 0;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith("# ")) {
      title = lines[i].replace(/^# /, "").trim();
      bodyStart = i + 1;
      break;
    }
  }

  // ハッシュタグ行からタグを抽出
  let hashtags = [];
  const hashtagLine = lines.find((l) => l.includes("ハッシュタグ:"));
  if (hashtagLine) {
    hashtags = hashtagLine
      .replace(/.*ハッシュタグ:\s*\**\s*/, "")
      .split(/\s+/)
      .filter((t) => t.startsWith("#"))
      .map((t) => t.replace(/^#/, ""));
  }

  // 本文（ハッシュタグ行やメタ情報行を除外）
  const bodyLines = lines.slice(bodyStart).filter((l) => {
    if (l.includes("ハッシュタグ:")) return false;
    if (l.includes("投稿時間:")) return false;
    return true;
  });

  return { title, body: bodyLines.join("\n").trim(), hashtags };
}

// ── メイン処理 ──
async function postToNote(articlePath) {
  const { title, body, hashtags } = parseArticle(articlePath);
  console.log(`Title: ${title}`);
  console.log(`Body: ${body.length} chars`);

  const browser = await chromium.launch({
    headless: false,
    args: ["--disable-blink-features=AutomationControlled"],
  });

  // セッションファイルがあれば復元（毎回ログインを避ける）
  const context = existsSync(SESSION_FILE)
    ? await browser.newContext({
        storageState: SESSION_FILE,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ...",
        viewport: { width: 1280, height: 800 },
        locale: "ja-JP",
        timezoneId: "Asia/Tokyo",
      })
    : await browser.newContext({
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ...",
        viewport: { width: 1280, height: 800 },
        locale: "ja-JP",
        timezoneId: "Asia/Tokyo",
      });

  // WebDriver検出回避
  await context.addInitScript(() => {
    Object.defineProperty(navigator, "webdriver", { get: () => false });
  });

  const page = await context.newPage();

  try {
    // ログイン処理
    await page.goto("https://note.com/login", { waitUntil: "networkidle" });
    await humanDelay(1500, 3000);

    // セッションが有効ならログイン画面をスキップ
    const emailInput = page.locator('input[type="email"], input[name="login"]');
    if (await emailInput.isVisible().catch(() => false)) {
      console.log("Logging in...");
      await humanMouseMove(page);
      await emailInput.click();
      await humanDelay(300, 700);
      // 1文字ずつ人間のスピードで入力（一括入力はbot判定される）
      await emailInput.type(process.env.NOTE_EMAIL, {
        delay: humanTypingDelay(),
      });
      await humanDelay(500, 1000);

      const passInput = page.locator('input[type="password"]');
      await passInput.click();
      await passInput.type(process.env.NOTE_PASSWORD, {
        delay: humanTypingDelay(),
      });
      await humanDelay(800, 1500);

      await page.locator('button:has-text("ログイン")').click();
      await humanDelay(3000, 6000);
    }

    // セッション保存（次回ログインをスキップするため）
    await context.storageState({ path: SESSION_FILE });

    // 記事作成ページに遷移
    await page.goto("https://note.com/notes/new", {
      waitUntil: "networkidle",
    });
    await humanDelay(2000, 4000);

    // タイトル入力
    const titleEl = page.locator('[placeholder="記事タイトル"]');
    await titleEl.click();
    await page.keyboard.type(title, { delay: humanTypingDelay() });
    await humanDelay(500, 1000);

    // 本文入力（段落ごとに入力し、時々スクロール）
    await page.keyboard.press("Enter");
    for (const para of body.split("\n")) {
      if (para.trim() === "") {
        await page.keyboard.press("Enter");
        continue;
      }
      await page.keyboard.type(para, { delay: humanTypingDelay() });
      await page.keyboard.press("Enter");
      // 数段落ごとにスクロール（人間らしい動作）
      if (Math.random() < 0.2) {
        await humanScroll(page);
      }
    }

    // 投稿設定 → ハッシュタグ追加 → 公開
    // （省略: セレクタの探索とクリック処理）

    // 投稿完了を確認
    await humanDelay(5000, 8000);
    console.log(`Published: ${page.url()}`);

    // セッションを再保存
    await context.storageState({ path: SESSION_FILE });

    // 投稿済みディレクトリに移動
    moveToPublished(articlePath);
  } catch (error) {
    // エラー時はスクリーンショットを保存（デバッグ用）
    const ssPath = join(__dirname, `error-${Date.now()}.png`);
    await page.screenshot({ path: ssPath, fullPage: true });
    console.error(`Screenshot saved: ${ssPath}`);
    throw error;
  } finally {
    await browser.close();
  }
}
```

### 投稿済みファイルの管理

```javascript
function moveToPublished(filePath) {
  const publishedDir = join(__dirname, "../../departments/marketing/note/published");
  if (!existsSync(publishedDir)) mkdirSync(publishedDir, { recursive: true });
  const dest = join(publishedDir, basename(filePath));
  renameSync(filePath, dest);
  console.log(`Moved to published: ${dest}`);
}
```

投稿待ちの `standalone/` ディレクトリから、投稿済みの `published/` ディレクトリにファイルを移動します。これにより、同じ記事が二重投稿されることを防ぎます。

## 実装例2: KDPへの書籍登録支援

Amazon KDPの書籍登録画面は、多数のフォーム入力が必要です。Playwrightで入力を支援（完全自動化ではなく半自動化）します。

### なぜ「支援」なのか

KDPの登録画面には、以下の特殊な事情があります。

1. **reCAPTCHAが存在する** — 完全自動化は困難
2. **ファイルアップロードがある** — EPUBと表紙画像
3. **プレビュー確認が必要** — 人間の目視チェックが不可欠

そのため、フォーム入力の自動化に絞り、最終的な送信は人間が行う設計にしています。

```javascript
async function fillKdpForm(page, metadata) {
  // 書籍タイトル入力
  const titleInput = page.locator('#data-print-book-title input, #title-input');
  await titleInput.fill("");
  await humanDelay(300, 500);
  await titleInput.type(metadata.title, { delay: humanTypingDelay() });

  // サブタイトル
  const subtitleInput = page.locator('#data-print-book-subtitle input');
  if (await subtitleInput.isVisible().catch(() => false)) {
    await subtitleInput.type(metadata.subtitle, { delay: humanTypingDelay() });
  }

  // 内容紹介（HTML対応のリッチテキストエディタ）
  const descEditor = page.locator('#data-print-book-description textarea, [contenteditable]');
  if (await descEditor.isVisible().catch(() => false)) {
    await descEditor.click();
    await humanDelay(500, 1000);
    // HTMLをクリップボード経由で貼り付け
    await page.evaluate((html) => {
      navigator.clipboard.writeText(html);
    }, metadata.description);
    await page.keyboard.press("Meta+v"); // macOSの貼り付け
  }

  // キーワード（最大7個）
  for (let i = 0; i < Math.min(metadata.keywords.length, 7); i++) {
    const kwInput = page.locator(`#data-print-book-keywords-${i} input`);
    if (await kwInput.isVisible().catch(() => false)) {
      await kwInput.type(metadata.keywords[i], { delay: humanTypingDelay() });
      await humanDelay(200, 400);
    }
  }

  console.log("Form filled. Please review and submit manually.");
  // ここで一時停止し、人間がレビューして送信する
  await page.pause();
}
```

`page.pause()` でPlaywright Inspectorが開き、人間がフォームの内容を確認してから操作を続行できます。

## セッション管理

ブラウザ自動化で最も面倒なのがログイン管理です。毎回ログインすると、以下の問題が発生します。

- 不審なログイン検知でアカウントがロックされる
- 二段階認証を毎回要求される
- ログイン処理に20-30秒かかり、全体の実行時間が伸びる

### storageStateによるセッション永続化

Playwrightの `storageState` 機能を使うと、Cookie・LocalStorageの状態をJSONファイルに保存し、次回起動時に復元できます。

```javascript
// セッション保存（ログイン後に実行）
await context.storageState({ path: "note-session.json" });

// セッション復元（次回起動時）
const context = await browser.newContext({
  storageState: "note-session.json",
});
```

`note-session.json` にはCookieが平文で保存されるため、`.gitignore` に追加してリポジトリにコミットしないことが重要です。

### セッションの有効期限

サービスによってセッションの有効期限は異なります。

| サービス | 有効期限の目安 | 対策 |
|---------|-------------|------|
| note | 約2週間 | 期限切れ時は自動でログイン処理にフォールバック |
| KDP | 約1時間 | 毎回ログインが必要。2段階認証はSMS |
| 一般的なWebアプリ | 数時間-30日 | Remember Meにチェックを入れる |

スクリプト内で「セッションが有効か」を判定し、無効なら再ログインする分岐を入れておくのがベストプラクティスです。

```javascript
// ログインページに遷移
await page.goto("https://note.com/login");
await humanDelay(1500, 3000);

// ログインフォームが表示されるか確認（表示されなければログイン済み）
const loginForm = page.locator('input[type="email"]');
if (await loginForm.isVisible().catch(() => false)) {
  // セッション切れ → 再ログイン
  console.log("Session expired, logging in...");
  // ログイン処理...
} else {
  console.log("Session valid, skipping login");
}
```

## エラー時のスクリーンショット保存

ブラウザ自動化は、UIの変更で突然動かなくなることがあります。原因調査のために、エラー時のスクリーンショットを自動保存します。

```javascript
try {
  // メイン処理
  await postToNote(articlePath);
} catch (error) {
  console.error("Error:", error.message);

  // スクリーンショット保存（タイムスタンプ付きで一意なファイル名）
  const ssPath = join(__dirname, `error-${Date.now()}.png`);
  await page.screenshot({ path: ssPath, fullPage: true });
  console.error(`Screenshot saved: ${ssPath}`);

  // Slack通知（スクリーンショットのパスも添える）
  if (process.env.SLACK_WEBHOOK_URL) {
    await fetch(process.env.SLACK_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: `[note投稿] エラー: ${error.message}\nスクリーンショット: ${ssPath}`,
      }),
    });
  }

  throw error;
}
```

筆者の経験では、noteのUI変更で月に1-2回はセレクタが壊れます。スクリーンショットがあれば、「どのボタンが見つからなかったか」を即座に特定できます。エラー発生からセレクタ修正まで、通常10分以内で復旧しています。

## 実際の運用での注意点

### 利用規約の確認

ブラウザ自動化は、多くのサービスの利用規約でグレーゾーンです。以下の原則を守ってください。

1. **サービスに過負荷をかけない** — 適切な遅延を入れ、1日の操作回数を制限する
2. **スクレイピング目的ではない** — 自分のコンテンツを投稿・管理する用途に限定する
3. **APIがあればAPIを使う** — ブラウザ自動化はAPIが存在しない場合の最終手段
4. **アカウント共有しない** — 自分のアカウントを自分で操作する範囲に留める

### レート制限

サービスにレート制限がなくても、常識的な頻度で操作しましょう。

```javascript
// 良い例: 1日1回、人間らしいスピードで
// 1記事あたり3-5分（人間がフォーム入力するのと同程度）

// 悪い例: 1時間に50記事を秒速で投稿
// → アカウントBANのリスクが極めて高い
```

筆者の環境では、noteへの投稿を1日1回に制限しています。これは人間が手動で投稿する場合と同じ頻度です。

### macOSでの実行環境

Playwrightは `headless: false` で実行するため、GUIセッションが必要です。launchdから実行する場合の注意点:

1. **MacBookの蓋を開けた状態で実行する** — 画面がないとブラウザが起動しない
2. **スケジュールを適切に設定** — 通常の作業時間帯（9:00-18:00）に設定
3. **ディスプレイスリープの設定を確認** — システム設定でディスプレイのスリープ時間を調整

```xml
<!-- launchd plistの例: 毎日10:30に実行（確実に蓋を開けている時間帯） -->
<key>StartCalendarInterval</key>
<dict>
  <key>Hour</key>
  <integer>10</integer>
  <key>Minute</key>
  <integer>30</integer>
</dict>
```

## まとめ

- **Playwright**はAPI非対応サービスの自動化における最終手段。APIがあるなら必ずAPIを使う
- **bot検知対策**は4つのレイヤー: UserAgent設定、WebDriver検出回避、ランダム遅延、headless: false
- **セッション管理**は `storageState` で永続化。毎回ログインを避けることで、検知リスクとセッション管理の手間を軽減
- **エラー時のスクリーンショット保存**が運用の生命線。UIが変更されたときの原因特定が格段に早くなる
- **利用規約を遵守**し、人間と同じ頻度・速度で操作する。1日1回・人間らしいスピードが基本
- 筆者の環境では、noteへの毎日の記事投稿をPlaywrightで自動化し、月間約30本を人間の操作なしで投稿している
- 次章以降では、ここまで解説した全技術（Hooks、Skills、MCP、launchd、Playwright）を組み合わせた統合パイプラインの構築に進む
