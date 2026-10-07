---
name: textlint-ja
description: >-
  日本語の文章を textlint で検査し、指摘を直す。
---

# textlint-ja

日本語を textlint で検査し、指摘を直す。
意味は変えない。言い回しは stop-ai-slop、技術文書の構成は technical-writing に従う。

## Step 1: 対象

ユーザーが指定したファイルを検査する。文章を貼られたときは、一時ファイルに書いてから検査する。
指定が無いときは、今編集している日本語の文章を対象にする。

## Step 2: 実行

このスキルの `scripts/lint.sh` を実行する。

- プロジェクトに textlint の設定があるときは、その設定で実行する。ルールは足さない。依存もプロジェクトには入れない
- 設定が無いときは、同梱の設定を使う
  - 通常: オプションなし
  - マニュアル、README、仕様、提案、設計文書: `--technical`

```bash
scripts/lint.sh path/to/file.md
scripts/lint.sh --technical path/to/manual.md
```

通常は次の3つを使う。

- `preset-japanese` — 誤検知の少ない一般向け
- `preset-ja-spacing` — 全角と半角、かっこのスペース
- `@textlint-ja/preset-ai-writing` — リスト、誇張、強調、コロン続き

`--technical` では `preset-japanese` の代わりに `preset-ja-technical-writing` を使う。このプリセットは `preset-japanese` の検査を含む。同時には有効にしない。康煕部首だけ `no-kangxi-radicals` を足す。

`ai-tech-writing-guideline` は切ってある。指摘がエラーになり、数値や能動態への書き換えを求めるため。
`preset-JTF-style` は入れない。スペースと記号が `preset-ja-spacing` と重なる。

## Step 3: 修正

1. 指摘を読む
2. 同じオプションのまま `--fix` を付けて、機械的に直るものだけ直す。`--technical` を付けた検査なら、修正のときも付ける
3. 残ったエラーは本文を直す。意味、言い切りの強さは変えない
4. `--fix` なしで、同じオプションでもう一度実行し、エラーが残っていないことを確認する

固有名詞や引用で指摘が残るときは、ルールを消さない。残すかをユーザーに確認する。
同意があるときだけ `<!-- textlint-disable -->` を使う。
プロジェクトの設定ファイルは、頼まれたときだけ作る。

## Step 4: 結果の出力

```markdown
## 指摘

- ルール名: 元 → 後

## 残したところ（必要なときだけ）

- 残した文と理由

## 質問（必要なときだけ）

- 判断がつかなかった点
```
