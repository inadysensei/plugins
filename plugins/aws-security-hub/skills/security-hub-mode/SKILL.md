---
name: security-hub-mode
description: AWSのSecurity Hubで、失敗の読み取り、直すか抑制するかの切り分け、是正の準備、抑制理由の作成を行う入口。FSBP、Security Hub、失敗コントロール、抑制、是正の依頼で使う。
---

# security-hub-mode

これはSecurity Hub作業の入口です。
依頼を1つのスキルに分け、そのスキルを開いてから動きます。スキルを読まずに手順を開始しません。

返信の最初に、選んだスキル名を1行で書きます。

## スキルの分け方

上から見て、最初に当たった1つを使います。

1. 抑制：抑制理由の作成を頼まれている。`prepare-suppress` skill
2. 是正：是正の準備を頼まれている。`prepare-fix` skill
3. トリアージ：Security Hubの指摘を分類する。`triage-control` skill
4. 調査：失敗の理由、現状、リソースの所在を聞く。変更はまだしない。`investigate` skill
5. 一覧：失敗一覧、未対応、Security Hubの状況を頼まれている。一覧がまだ無い。`read-findings` skill

## 自分で進める

読み取りは、確認を待たずに実行します。
切り分けが終わったら、次のスキルを開いて続けます。直すか抑制するかはあなたが判断します。

止めるのは次のときだけです。

- findingを更新するAPIを呼ぶ直前
- リソースを更新するterraformのpull requestを作成する

## Subagentの使い方

サブエージェントを使うときは`security-hub-agent`を、コントロール1件ごとに新しく立てます。返ってきた結果は自分で読み、自分の言葉でまとめます。
