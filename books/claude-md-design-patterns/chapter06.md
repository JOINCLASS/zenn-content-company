---
title: "Hooks — イベント駆動の自動化"
---

# Hooks — イベント駆動の自動化

Claude Code Hooksは、特定のイベントが発生したときにシェルコマンドを自動実行する機能です。CLAUDE.mdに書くルールが「こうしてほしい」というお願いだとすると、Hooksは「必ずこうなる」という強制です。

## Hooksとは

Hooksは、Claude Codeのライフサイクルイベントに対してシェルコマンドをバインドする仕組みです。

例えば、「ファイルを保存するたびにリントを実行する」「コミット前にテストを実行する」といった自動化ができます。

CLAUDE.mdが「ルール」なら、Hooksは「ガードレール」です。ルールはAIが「忘れる」可能性がありますが、Hooksは忘れません。

## 設定ファイルの場所

Hooksは`.claude/settings.json`で設定します（CLAUDE.mdではありません）。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "echo 'ファイル変更をチェック中...'"
      }
    ]
  }
}
```

## Hookイベントの種類

Claude Codeには以下のHookイベントがあります。

### PreToolUse

ツール（Edit, Write, Bash等）が実行される**前**に発火します。

用途：ツール実行の事前チェック、危険な操作の防止

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "/path/to/check-command.sh \"$TOOL_INPUT\""
      }
    ]
  }
}
```

### PostToolUse

ツールが実行された**後**に発火します。

用途：実行結果の検証、自動整形、ログ記録

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "command": "npx prettier --write \"$TOOL_INPUT_FILE_PATH\""
      }
    ]
  }
}
```

### Notification

Claude Codeがユーザーに通知を送るタイミングで発火します。

用途：Slack通知、サウンド再生

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "command": "afplay /System/Library/Sounds/Glass.aiff"
      }
    ]
  }
}
```

### Stop

Claude Codeがタスクを完了してターンを終了するときに発火します。

用途：完了通知、後処理

## 実用的なHookパターン

### パターン1: 自動フォーマット

ファイルを書き込むたびにPrettierで整形します。

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "command": "npx prettier --write \"$TOOL_INPUT_FILE_PATH\" 2>/dev/null || true"
      }
    ]
  }
}
```

これにより、Claude Codeが生成するコードが常にフォーマット済みになります。CLAUDE.mdに「Prettierのフォーマットに従って」と書く必要がなくなります。

### パターン2: 危険なコマンドの防止

本番データベースへの直接アクセスを防止します。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "if echo \"$TOOL_INPUT\" | grep -q 'DATABASE_URL.*production'; then echo 'BLOCKED: 本番DBへの直接アクセスは禁止です' >&2; exit 1; fi"
      }
    ]
  }
}
```

Hookが`exit 1`を返すと、そのツール実行はブロックされます。

### パターン3: テスト自動実行

ソースコードを変更したら、関連テストを自動実行します。

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "bash -c 'FILE=\"$TOOL_INPUT_FILE_PATH\"; if [[ \"$FILE\" == *.ts ]] && [[ \"$FILE\" != *.test.ts ]]; then TEST=\"${FILE%.ts}.test.ts\"; if [ -f \"$TEST\" ]; then npx vitest run \"$TEST\" --reporter=dot 2>&1 | tail -5; fi; fi'"
      }
    ]
  }
}
```

### パターン4: コミットメッセージ検証

コミットメッセージがConventional Commits形式に従っているかチェックします。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "bash -c 'if echo \"$TOOL_INPUT\" | grep -q \"git commit\"; then MSG=$(echo \"$TOOL_INPUT\" | grep -oP \"(?<=-m \\\").*?(?=\\\")\"); if [ -n \"$MSG\" ] && ! echo \"$MSG\" | grep -qE \"^(feat|fix|refactor|docs|test|chore):\"; then echo \"BLOCKED: コミットメッセージはConventional Commits形式にしてください\" >&2; exit 1; fi; fi'"
      }
    ]
  }
}
```

### パターン5: 完了サウンド

タスクが完了したらサウンドを鳴らします（macOS）。

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "command": "afplay /System/Library/Sounds/Glass.aiff"
      }
    ]
  }
}
```

## Hooksの設定場所

Hooksは2つのレベルで設定できます。

### プロジェクト設定

`.claude/settings.json`に書きます。チームで共有可能です。

### ユーザー設定

`~/.claude/settings.json`に書きます。全プロジェクトに適用されます。

プロジェクト設定とユーザー設定が両方ある場合は、両方のHooksが実行されます。

## CLAUDE.mdとHooksの使い分け

| 用途 | CLAUDE.md | Hooks |
|------|-----------|-------|
| コーディング規約 | 向いている | 向いていない |
| 自動フォーマット | 忘れる可能性あり | 確実に実行 |
| 危険操作の防止 | お願いベース | 強制ブロック |
| テスト実行 | 指示として書ける | 自動で実行される |
| ビルドコマンド | 情報として記載 | 実行には不要 |

原則として：
- **ルールや方針** → CLAUDE.md
- **自動実行・強制** → Hooks
- **両方必要なもの** → CLAUDE.mdに理由を書き、Hooksで実行

## Hookスクリプトの管理

複雑なHookは外部スクリプトに切り出して管理します。

```
.claude/
├── settings.json
└── hooks/
    ├── pre-edit-check.sh
    ├── post-write-format.sh
    └── pre-bash-guard.sh
```

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": ".claude/hooks/pre-bash-guard.sh"
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "command": ".claude/hooks/post-write-format.sh \"$TOOL_INPUT_FILE_PATH\""
      }
    ]
  }
}
```

## まとめ

- Hooksはイベント駆動でシェルコマンドを自動実行する仕組み
- CLAUDE.mdが「お願い」ならHooksは「強制」
- PreToolUseで危険操作を防止、PostToolUseで自動整形
- 複雑なロジックは外部スクリプトに切り出す
- CLAUDE.mdとHooksを組み合わせて堅牢な開発環境を作る
