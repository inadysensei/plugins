---
name: read-findings
description: Security Hubの失敗を読む。失敗一覧、未対応、Security Hubの状況を頼まれ、一覧がまだ無いときに使う。
---

# 失敗を読む

Security Hubの指摘事項一覧を読み込みます。

## 手順

検出結果は1件ずつ出す。コントロールIDが同じでもまとめない。
取得の細目は、呼び出しながら足す。

各行に次を書く。

- 検出結果ID
- タイトル
- コントロールID
- `Severity.Label`
- アカウントID
- リソースID

並びは`Severity.Label`の高い順に出す。
同じ深刻度ではコントロールIDの順、その次は検出結果IDの順にする。
