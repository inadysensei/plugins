# inady agent plugins

## IMPORTANT

このリポジトリはPublicです。認証情報、秘密、顧客データ、アカウント識別子はcommitしません。remoteへのpushは、ユーザーが確認してから行います。

## Skillの更新手順

### Step 1: Skillの更新

ユーザーの要求した内容を踏まえ、`Skill.md`を修正します。
ユーザーに修正内容を確認します。OKならcommitします。

### Step 2: textlintの実行

`textlint-ja` Skillを実行します。

### Step 3: Pluginバージョンアップ

`bump-plugin-version` Skillを実行します。

### Step 4: Commit

変更をcommitします。
remoteへは、ユーザーが確認してからpushします。確認の前にpushしません。
