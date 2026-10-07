## TDD（Red / Green / Refactor）

このリポジトリでは、機能追加・バグ修正・リファクタのすべてを Red → Green → Refactor で進める。テストを先に書かずに実装しない。

### 手順

1. **Red** — 失敗するテストを先に書く。実行して失敗することを確認してから実装に入る。
2. **Green** — そのテストを通す最小の実装だけを足す。先回りして別機能を足さない。
3. **Refactor** — テストが緑のまま、重複や不要なコードの削除、リーダブルな命名、構造を整える。挙動は変えない。

ステップごとにTestsを実行して、成功or失敗することを確認します。

テストの実行:

```bash
bash plugins/motoki/skills/textlint-ja/scripts/lint.test.sh
```
