---
title: "第9章 コンプライアンス対応 -- SOC2/ISO27001/GDPR/個人情報保護法"
free: false
---

# 第9章 コンプライアンス対応 -- SOC2/ISO27001/GDPR/個人情報保護法

> 本章の内容は情報提供を目的としており、法的助言ではありません。具体的なコンプライアンス対応は、必ず法務部門や専門家にご相談ください。

## この章で学ぶこと

- AIツール利用に関連するコンプライアンス要件の全体像
- SOC2監査でのClaude Code利用の説明方法
- ISO27001の管理策とClaude Codeの対応関係
- GDPR/個人情報保護法における注意点
- コンプライアンス証跡の収集・管理方法

---

## 前章の振り返りと本章の位置づけ

第4章から第8章にかけて、Permissions、CLAUDE.md、Hooks、シークレット管理、ネットワークセキュリティという5つのレイヤーでセキュリティ設計を行った。

本章では、これらの設計が各種コンプライアンス要件を満たしていることを「証明する」方法を解説する。セキュリティを設計するだけでは不十分で、**監査人に対して「適切に管理している」ことを示す証跡**が必要だ。

筆者は受託開発4社とNDAを締結している。うち2社からは契約時に「AIツールの利用方針」の提出を求められた。本章で解説するコンプライアンス対応は、その際に実際に整理した内容をベースにしている。

コンプライアンスは机上の空論ではなく、実際のビジネスで「今すぐ求められるもの」だ。


## AIツール利用に関するコンプライアンスの全体像

企業がClaude Codeを導入する際に考慮すべきコンプライアンスフレームワークを整理する。

| フレームワーク | 対象 | 関連する章 |
|--------------|------|----------|
| SOC2 | クラウドサービス全般 | 第2章（データフロー）、第4-8章（セキュリティ設計） |
| ISO27001 | 情報セキュリティ全般 | 全章 |
| GDPR | EU市民の個人データ | 第2章（データフロー）、第7章（シークレット管理） |
| 個人情報保護法 | 日本国内の個人情報 | 第2章（データフロー）、第7章（シークレット管理） |
| PCI DSS | クレジットカード情報 | 第7章（シークレット管理）、第8章（ネットワーク） |
| HIPAA | 医療情報（米国） | 第2章（データフロー）、第3章（プラン選定） |


## SOC2対応

SOC2（Service Organization Control 2）は、クラウドサービスのセキュリティ、可用性、処理のインテグリティ、機密性、プライバシーに関する監査フレームワークだ。

### Trust Services Criteriaとの対応

| カテゴリ | 基準 | Claude Code対応 |
|---------|------|----------------|
| **セキュリティ** | CC6.1: 論理アクセス制御 | Permissions設計（第4章）、SSO/SCIM（第3章） |
| | CC6.6: 外部脅威からの保護 | ファイアウォール（第8章）、Hooks（第6章） |
| | CC6.7: 送信データの保護 | TLS 1.2+通信（第2章）、プロキシ（第8章） |
| | CC6.8: 不正アクセスの検知 | 監査ログ（第6章）、ネットワーク監視（第8章） |
| **機密性** | CC6.5: 機密データの保護 | シークレット管理（第7章）、データフロー制御（第2章） |
| **可用性** | A1.2: 環境の監視 | ネットワーク監視（第8章） |
| **処理のインテグリティ** | PI1.4: 出力の完全性 | Hooks PostToolUse（第6章） |

### SOC2監査で聞かれる質問と回答テンプレート

```markdown
## Q: AIコーディングツールを使用していますか？
A: はい。Claude Code（Anthropic社）を使用しています。

## Q: どのようなデータがAIプロバイダーに送信されますか？
A: ユーザーのプロンプト、タスク遂行に必要なファイルの内容、
コマンド実行結果のみが送信されます。
機密情報（.envファイル、認証情報等）はPermissionsとHooksにより
送信前にブロックされます。
（詳細はデータフロー図を参照: [第2章の図を添付]）

## Q: 送信されたデータはAIのトレーニングに使用されますか？
A: いいえ。Business/Enterprise/APIプランを使用しており、
データはモデルのトレーニングに使用されません。
（Anthropicの利用規約/DPAを添付）

## Q: アクセス制御はどのように設計されていますか？
A: 以下の3層で制御しています。
1. Permissions: ツール（操作）ごとのallow/deny設定
2. CLAUDE.md: セキュリティポリシーの行動規範
3. Hooks: コマンド実行前後の動的チェック
（設定ファイルのコピーを添付）

## Q: 監査ログはありますか？
A: はい。全てのツール実行がJSONL形式で記録されます。
ログには実行時刻、ユーザー、プロジェクト、ツール名、
入力（機密情報はマスキング済み）が含まれます。
ログの保持期間は[X]日間で、[保管先]に保存されます。
（ログのサンプルを添付）
```


## ISO27001対応

ISO27001は情報セキュリティマネジメントシステム（ISMS）の国際規格だ。Annex Aの管理策とClaude Codeの対応関係を整理する。

### 関連する管理策

| 管理策ID | 管理策名 | Claude Code対応 | 証跡 |
|---------|---------|----------------|------|
| A.5.1 | 情報セキュリティポリシー | CLAUDE.md（第5章） | CLAUDE.mdファイル |
| A.6.1 | 内部組織 | ロール別Permissions（第4章） | settings.json |
| A.8.1 | 資産管理 | データ分類（第2章） | データフロー図 |
| A.9.1 | アクセス制御方針 | Permissions（第4章） | settings.json + CI検証ログ |
| A.9.2 | 利用者アクセス管理 | SSO/SCIM（第3章） | 管理コンソールのログ |
| A.9.4 | システムおよびアプリのアクセス制御 | Permissions + Hooks（第4,6章） | 監査ログ |
| A.10.1 | 暗号による管理策 | TLS通信（第8章）、シークレット暗号化（第7章） | 設定ファイル |
| A.12.4 | ログ取得及び監視 | 監査ログ（第6章） | ログファイル |
| A.13.1 | ネットワークセキュリティ管理 | ファイアウォール/プロキシ（第8章） | ネットワーク設定 |
| A.14.2 | 開発プロセスのセキュリティ | CLAUDE.md + Hooks（第5,6章） | CI/CDログ |
| A.18.1 | 法的及び契約上の要求事項の順守 | 本章全体 | コンプライアンス証跡 |

### ISMS文書にClaude Code利用を追加する

既存のISMS文書に、AIツール利用に関するセクションを追加する。

```markdown
## 6.3 AIコーディングツールの管理

### 6.3.1 利用ポリシー
- 承認されたAIコーディングツール: Claude Code（Anthropic社）
- 利用可能なプラン: Business/Enterprise/API
- 個人アカウントでの利用: 禁止

### 6.3.2 データ分類とAIツール
- 機密度: 高 のデータ: AIツールへの送信禁止
- 機密度: 中 のデータ: Permissions/Hooksでフィルタリング後に送信可
- 機密度: 低 のデータ: 送信可

### 6.3.3 アクセス制御
- ロール別のPermissions設定を適用する
- 設定の変更はセキュリティチームの承認を必要とする
- 設定ファイルの変更はCIで検知する

### 6.3.4 監査ログ
- 全てのAIツール操作を監査ログに記録する
- ログの保持期間: [X]日間
- ログは月次でセキュリティチームがレビューする

### 6.3.5 インシデント対応
- AIツール経由でのデータ漏洩が疑われる場合の対応手順
- Anthropicサポートへのエスカレーション手順
```


## GDPR対応

GDPR（General Data Protection Regulation）は、EU市民の個人データ保護に関する規則だ。Claude Codeを使用する際のGDPR対応を整理する。

### データ処理の根拠

GDPRでは、個人データの処理には法的根拠が必要だ。Claude Codeの利用における根拠は以下の通り。

**処理の目的**: ソフトウェア開発の効率化

**法的根拠**: 正当な利益（第6条1項(f)）
→ AIコーディングツールの利用は開発生産性の向上という正当な利益に基づく
→ ただし、個人データを含むファイルをAIに送信しない措置を講じる

### DPIA（データ保護影響評価）

GDPRでは、新しい技術を使って大規模な個人データ処理を行う場合、DPIA（Data Protection Impact Assessment）が必要になる場合がある。

```markdown
## DPIA: Claude Code導入

### 1. 処理の概要
- 目的: ソフトウェア開発の効率化
- 処理されるデータ: ソースコード、設定ファイル、コマンド実行結果
- データ主体: なし（個人データは処理対象外）
- 処理者: Anthropic PBC（米国）

### 2. 個人データの取り扱い
- ソースコード内に個人データが含まれる可能性がある
  （例: テストデータ、コメント、ログメッセージ）
- 対策: Permissions/Hooksで個人データを含むファイルの
  送信をブロック

### 3. リスク評価
- リスク: ソースコード内の個人データがAnthropicに送信される
- 発生可能性: 中（対策を講じた上でのリスク）
- 影響度: 中（個人データの量は限定的）
- 総合リスク: 中
- 軽減策: Permissions + Hooks + 社内プロキシでのフィルタリング

### 4. 国際データ移転
- Anthropicは米国の企業であるため、EUから米国へのデータ移転が発生
- 対策: Anthropicとの契約にSCC（Standard Contractual Clauses）を含める
- Enterprise契約でDPAを締結する

### 5. 結論
- 適切な技術的・組織的措置を講じた上で、
  Claude Codeの利用はGDPRに準拠可能
```

### データ主体の権利への対応

```
Q: 個人データが Claude Code 経由で処理された場合、
   データ主体のアクセス権（第15条）にどう対応するか？

A: Claude Code経由でAnthropicに送信されたデータは、
   Business/Enterprise/APIプランではトレーニングに使用されず、
   一定期間後に削除される。
   データ主体からのアクセス請求があった場合:
   1. 監査ログで該当するデータの送信有無を確認
   2. Anthropicに対して保持データの開示を依頼（Enterprise契約）
   3. データの削除を依頼
```


## 日本の個人情報保護法への対応

### 第三者提供の制限

個人情報保護法では、本人の同意なく個人データを第三者に提供することが制限されている（第27条）。

```
Q: Claude Code経由でAnthropicに個人データが送信されることは
   「第三者提供」に該当するか？

A: 以下の解釈が考えられる:
   1. 「委託」に該当する場合（第27条5項1号）:
      - Anthropicへのデータ送信が「業務委託」の範囲内であれば、
        本人同意は不要
      - ただし、委託先の監督義務がある（第25条）
   2. 個人データを送信しない場合:
      - Permissions/Hooksで個人データの送信をブロックしていれば、
        第三者提供の問題は生じない（推奨）

推奨対策:
- Claude Codeで個人データを含むファイルを処理しない設計とする
- 万が一送信される場合に備え、プライバシーポリシーに記載する
- Anthropicとの契約に委託先管理の条項を含める
```

### 安全管理措置

個人情報保護法第23条で求められる安全管理措置とClaude Codeの対応。

| 安全管理措置 | Claude Code対応 |
|-------------|----------------|
| 組織的安全管理措置 | セキュリティポリシー（CLAUDE.md）、責任者の明確化 |
| 人的安全管理措置 | 利用ガイドライン、研修の実施 |
| 物理的安全管理措置 | ネットワークセキュリティ（第8章）|
| 技術的安全管理措置 | Permissions（第4章）、Hooks（第6章）、暗号化通信 |


## コンプライアンス証跡の収集・管理

### 証跡の一覧

| 証跡 | 保管場所 | 保持期間 | 更新頻度 |
|------|---------|---------|---------|
| Permissions設定ファイル | git（.claude/settings.json） | gitの履歴期間 | 変更時 |
| CLAUDE.mdファイル | git（CLAUDE.md） | gitの履歴期間 | 変更時 |
| Hookスクリプト | git（scripts/claude-hooks/） | gitの履歴期間 | 変更時 |
| 監査ログ | ログサーバー | 3年間 | リアルタイム |
| 設定変更のCI検証ログ | CI/CDサービス | 1年間 | PRごと |
| DPA（データ処理契約） | 法務部門 | 契約期間+5年 | 契約更新時 |
| DPIA | 法務部門 | 最新版+変更履歴 | 年次レビュー |
| セキュリティレビュー記録 | セキュリティチーム | 3年間 | 四半期 |
| インシデントレポート | セキュリティチーム | 5年間 | インシデント発生時 |

### 証跡の自動収集スクリプト

```bash
#!/bin/bash
# /scripts/compliance/collect-evidence.sh
# 四半期ごとの監査証跡収集スクリプト

QUARTER=$(date +%Y-Q$(( ($(date +%-m) - 1) / 3 + 1 )))
EVIDENCE_DIR="/var/compliance/claude-code/${QUARTER}"
mkdir -p "$EVIDENCE_DIR"

echo "=== Collecting compliance evidence for ${QUARTER} ==="

# 1. 現在のPermissions設定
echo "Collecting Permissions settings..."
for repo_dir in /repos/*/; do
  repo_name=$(basename "$repo_dir")
  if [ -f "${repo_dir}.claude/settings.json" ]; then
    cp "${repo_dir}.claude/settings.json" \
       "$EVIDENCE_DIR/permissions-${repo_name}.json"
  fi
done

# 2. CLAUDE.mdファイル
echo "Collecting CLAUDE.md files..."
for repo_dir in /repos/*/; do
  repo_name=$(basename "$repo_dir")
  if [ -f "${repo_dir}CLAUDE.md" ]; then
    cp "${repo_dir}CLAUDE.md" \
       "$EVIDENCE_DIR/claude-md-${repo_name}.md"
  fi
done

# 3. 監査ログのサマリー
echo "Generating audit log summary..."
python3 /scripts/compliance/summarize-audit-logs.py \
  --quarter "$QUARTER" \
  --output "$EVIDENCE_DIR/audit-summary.json"

# 4. 設定変更の履歴
echo "Collecting settings change history..."
for repo_dir in /repos/*/; do
  repo_name=$(basename "$repo_dir")
  cd "$repo_dir"
  git log --all --oneline -- ".claude/" "CLAUDE.md" > \
    "$EVIDENCE_DIR/settings-changes-${repo_name}.txt" 2>/dev/null
done

# 5. ブロックされた操作のレポート
echo "Generating blocked operations report..."
grep "BLOCKED" /var/log/claude-code-audit/*.jsonl 2>/dev/null | \
  python3 /scripts/compliance/analyze-blocked.py > \
  "$EVIDENCE_DIR/blocked-operations-report.json"

echo "=== Evidence collection complete: ${EVIDENCE_DIR} ==="
```


## コンプライアンスチェックリスト

```markdown
## Claude Code導入 コンプライアンスチェックリスト

### 契約・法務
- [ ] Anthropicとの利用規約を確認した
- [ ] DPA（データ処理契約）を締結した（Business/Enterprise）
- [ ] SCC（標準契約条項）を確認した（EU向け）
- [ ] 自社のプライバシーポリシーにAIツール利用を記載した

### データ保護
- [ ] データフロー図を作成した
- [ ] 個人データがAIに送信されない設計を実装した
- [ ] DPIA（データ保護影響評価）を実施した（必要な場合）

### アクセス制御
- [ ] ロール別のPermissionsを設計・適用した
- [ ] Permissions設定の変更はCIで検知される
- [ ] CLAUDE.mdにセキュリティポリシーを記載した

### 監査・ログ
- [ ] 全操作が監査ログに記録される
- [ ] ログの保持期間が定義されている
- [ ] ログの定期レビューのプロセスがある
- [ ] 証跡の収集・保管のプロセスがある

### インシデント対応
- [ ] AIツール関連のインシデント対応手順がある
- [ ] Anthropicサポートへのエスカレーション手順がある
- [ ] データ漏洩時の72時間通知体制がある（GDPR）

### 教育・啓発
- [ ] AIツール利用ガイドラインを全社員に周知した
- [ ] セキュリティ研修にAIツールの項目を追加した
- [ ] 定期的な利用状況のレビューを実施している
```

次の最終章では、これまでの全章の内容を統合し、すぐに使える「企業導入テンプレート集」を提供する。

---

## まとめ

- SOC2監査ではClaude Codeのデータフロー、アクセス制御、監査ログの説明が求められる
- ISO27001ではAnnex Aの管理策とClaude Codeの対応関係を文書化する
- GDPRでは個人データをAIに送信しない設計が最も安全。送信する場合はDPIAとDPAが必要
- 日本の個人情報保護法では、個人データの第三者提供の問題を回避する設計が推奨
- コンプライアンス証跡は自動収集し、定期的にレビュー・保管する

:::message
**本章の情報はClaude Code 2.x系（v2.1.90）（2026年4月時点）に基づいています。** Claude Codeのメジャーアップデート時に改訂予定です。最新情報は[Anthropic公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)をご確認ください。
:::

> コンプライアンスを含む企業全体のAI導入戦略を知りたい方は「[月5万円で会社が回る](https://zenn.dev/joinclass/books/claude-code-automation-bible)」をご覧ください。コスト管理とガバナンスの両立方法を実例で解説しています。
