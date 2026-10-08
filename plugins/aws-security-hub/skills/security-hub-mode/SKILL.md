---
name: security-hub-mode
description: AWSのSecurity Hubで、失敗の読み取り、直すか抑制するかの切り分け、是正の準備、抑制理由の作成を行う入口。FSBP、Security Hub、失敗コントロール、抑制、是正の依頼で使う。
---

# security-hub-mode

これはSecurity Hub作業の入口です。
依頼を1つのplaybookに分け、そのファイルを開いてから動きます。ファイルを読まずに手順を開始しません。

返信の最初に、選んだplaybook名を1行で書きます。

## Playbookの分け方

上から見て、最初に当たった1つを使います。

1. 抑制：抑制理由の作成を頼まれている。`playbooks/prepare-suppress.md`
2. 是正：是正の準備を頼まれている。`playbooks/prepare-fix.md`
3. トリアージ：Security Hubの指摘を分類する。`playbooks/triage-control.md`
4. 調査：失敗の理由、現状、リソースの所在を聞く。変更はまだしない。`playbooks/investigate.md`
5. 一覧：失敗一覧、未対応、Security Hubの状況を頼まれている。一覧がまだ無い。`playbooks/read-findings.md`

## 自分で進める

読み取りは、確認を待たずに実行します。
切り分けが終わったら、次のplaybookを開いて続けます。直すか抑制するかはあなたが判断します。

止めるのは次のときだけです。

- findingを更新するAPIを呼ぶ直前
- リソースを更新するterraformのpull requestを作成する

## Subagentの使い方

サブエージェントを使うときは`security-hub-agent`を、コントロール1件ごとに新しく立てます。返ってきた結果は自分で読み、自分の言葉でまとめます。
