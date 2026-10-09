---
name: prepare-fix
description: 是正と判断したSecurity Hubの指摘について、IaCのPull Requestを準備する。是正の準備を頼まれたときに使う。
---

# 是正を準備する

是正と判断したものについてIaCのPull Requestを作成します。

## 手順

1. リソースIDに対応するIaCのファイルパスを書く。見つからなければ、未発見と書く。
2. 実装のSubagentを立てる。
3. IaCリポジトリの手順に従って実装を開始する。
