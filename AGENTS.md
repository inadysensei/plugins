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

## TDD（Red / Green / Refactor）

このリポジトリでは、機能追加・バグ修正・リファクタのすべてをRed → Green → Refactorで進める。テストを書く前に実装しない。

### 手順

1. Red: 失敗するテストを先に書く。実行して失敗することを確認してから実装に入る。
2. Green: そのテストを通す最小の実装だけを足す。先回りして別機能を足さない。
3. Refactor: テストが緑のまま、重複や不要なコードの削除、リーダブルな命名、構造を整える。挙動は変えない。

ステップごとにTestsを実行して、成功or失敗することを確認します。

テストは次のコマンドで実行します。

```bash
bash plugins/motoki/skills/textlint-ja/scripts/lint.test.sh
```
