---
name: prepare-iphone-duo
description: 既存のiPhoneアプリのUIを、折りたたみのiPhone Duoに合わせる。ユーザーが「iPhone Duo対応して」と頼んだときに使う。
---

# prepare-iphone-duo

Cisco Duo、Apple Music Duo、Surface Duoは対象にしません。
画面いっぱいに出すには、Xcode 27.1のiOS 27.1 SDK以上でビルドします。
シーンの大きさは、開閉、半折り、回転、Split Viewで変わります。

## 守ること

- 最低iOSは27へ上げない。新しいAPIはSDK側にある
- ヒンジ角度でレイアウトは変えない

## Step 1: 出典を確認する

作業の前に、文末の出典を開きます。
変わっていたら、このスキルより公式の記述を優先します。

## Step 2: 今の画面の取り方を見る

コードとプロジェクト設定から、次を拾います。

- ビルドに使うSDKと、向きの宣言
- `UIScreen.main`、起動時に一度だけ読む大きさ、固定の幅と高さ、機種ごとの寸法比較
- `UIDevice.current.orientation`、`statusBarOrientation`、`interfaceOrientation`
- `windowScene.effectiveGeometry.interfaceOrientation`
- `userInterfaceIdiom`と、`horizontalSizeClass == .regular`をiPad専用とみなす分岐
- `UIRequiresFullScreen`と、起動画面の有無
- 自前の重ね表示、浮動ボタン、明示的なframe、独自の`Layout`
- 標準のナビゲーション、タブ、シート、分割、アラート
- 文字だけのツールバー項目と、カスタムビューの項目
- 画面がすでに2領域か
- カメラAPIの有無と、複数ウィンドウの要求

特定のアプリの画面名は、このスキルへ書き戻しません。

## Step 3: 今の向きのまま、シミュレータで見る

向きを全方向へ広げるかは、今の宣言のまま見たあとで判断します。
画面いっぱいに出ることは、この確認の達成条件にしません。

本確認には、iPhone Duoシミュレータを使います。
Device Hubで開き、閉じ、回し、折ります。
半折りは、縦折りと横折りを見ます。
置く姿勢と立てる姿勢も見ます。
Split Viewで、シーンが狭くなるかも見ます。
シートとポップオーバーも開きます。

シーンの大きさが変わらない場合は、向きの宣言を見直します。
iOSのリサイズ可能シミュレータも試します。
macOS 27のiPhone Mirroringでは、ウィンドウの幅と高さを、それぞれ極端な大きさにします。
記録の正は、Duoシミュレータの結果です。

TN3192は、リサイズできるシーンの条件に、全方向のサポートを挙げています。
システムは、アプリが宣言した向きと、端末が対応する向きの重なりで、シーンの向きを決めます。
ホームボタンの無いiPhoneでは、宣言に関わらず上下逆さまが外れます。
Preparingの確認項目は、サポートしている各向きと各ポーズでリサイズするかどうかです。
全方向が必須とは書いていません。
縦か横に固定しても、シーンの大きさは変わります。
ゲームの節を、今のアプリの向き固定に当てはめてよいかは、文書が名指ししていません。

## Step 4: 大きさを今の領域から取る

画面の大きさは、今のビューかウィンドウのboundsから取ります。
`UIScreen.main.bounds`からは取りません。
起動時に一度読んだ大きさは、折りたたみの途中で古くなります。
SwiftUIでは`GeometryReader`か`onGeometryChange`を使います。
UIKitでは`layoutSubviews`か`viewDidLayoutSubviews`で取り直します。
変化の開始は`viewWillTransition(to:with:)`で受けます。

スケールは`traitCollection.displayScale`、SwiftUIでは`displayScale`です。
`UIScreen`は保持しません。
必要なときは`view.window?.windowScene?.screen`を、その場で読みます。

固定のiPhone寸法や、`bounds.height == 844`のような機種比較では配置しません。
`.fill`の全面画像は、広い画面で主題が切れます。
サイズクラスか縦横比で、fillとfitを選びます。

レイアウトの判断に、`UIDevice.current.orientation`、`statusBarOrientation`、`interfaceOrientation`は使いません。
`windowScene.effectiveGeometry.interfaceOrientation`も使いません。
縦長か横長かは、今の領域の幅と高さを比べます。
ビューコントローラでは`view.bounds`、ビューでは`superview.bounds`を見ます。

`userInterfaceIdiom`や、`horizontalSizeClass == .regular`をiPad専用とみなす分岐では、レイアウトを選びません。
iPhone Duoと、リサイズするiPhone Mirroringでは、サイズクラスの組み合わせが固定されません。
内側の見え方は、そのアプリのiPadレイアウトの延長です。
サイズの変化は、`horizontalSizeClass`と`verticalSizeClass`を、自動のtrait追跡で見ます。

標準の分割、タブ、`ArrangementView`、ナビゲーションスタックを優先します。
これらは、外側、全開、半折りの各ポーズに合わせて、カメラで隠れる領域を自動で避けます。

## Step 5: 自前の重ねを予約領域から外す

カスタムビューは、予約領域を自分で避けます。
標準の分割、タブ、アラート、シートは、システムが避けるためです。

`occlusion`は、Dynamic Island、カメラ、ウィンドウ操作が内容を隠す領域です。
外側の前面カメラは、常に有効です。
内側の前面カメラは、使用中だけ有効です。

`division`は、折り目です。
半折りのときだけ有効です。
全開では無効なので、既定の問い合わせはdivisionを返しません。
本のように折ると縦に走り、ノートのように折ると横に走ります。

SwiftUIでは、`GeometryReader`の`reservedRegions(kind:options:layoutDirectionBehavior:)`で取ります。
UIKitでは、`UIView`の同名メソッドを使います。
フレームはビュー座標で、余白込みです。
既定では、有効な領域だけが返ります。
`includeInactive`を付けると、無効な折り目も取れます。
`isActive`で、今有効かを見ます。

自分で読むのは、自前の重ね表示、浮動ボタン、明示的なframe、独自の`Layout`です。
スクロールビューは、折り目で行を分けません。
行が折り目を横切って使いにくいときだけ、自分で分けます。
押せない装飾は、折り目を横切って読みにくいときだけずらします。

バーが要らない没入画面は、幅いっぱいにしてよい、とHIGは書いています。
Dynamic Islandとステータスバーには被せません。
`persistentSystemOverlays(.hidden)`が、外側カメラの隠れを消すとは書いていません。
隠してよいのは、システムの重ね表示です。
固定した余白は、隠れの上に残り得ます。
空いた領域は、同じ主題のまま埋めます。
開いた内側で、主な操作を小さく隅へ残しません。

システムのアラートは、先に動かしません。
シミュレータで折り目に乗っていたら、そのとき直します。

## Step 6: 縦のバーに出る操作を残す

閉じた外側では、ナビゲーションバー、ツールバー、タブバーが脇に並びます。
開いた内側の横持ちでも、操作が切れないため、脇のままです。
内側の縦持ちは、従来の横バーです。
Split Viewで2アプリが並ぶとき、各アプリのバーは外側の端に付きます。

標準の`NavigationStack`やタブに`toolbar`を付けると、システムが横と縦を切り替えます。
自前の`UIToolbar`、`UINavigationBar`、`UITabBar`では縦になりません。
標準のバーへ移せるものは、移します。

例外は次のとおりです。

インスペクタのバーは、横のままです。
分割ビューでは、サイドバーと内容が横、詳細が縦です。

外側のシートは、既定で縦です。
横のままにするには、SwiftUIの`toolbarVerticalBehavior(_:)`を使います。
UIKitでは`preferredVerticalBarBehavior`です。

内側のシートは、中央とleadingが横、trailingが縦です。
場所は`presentationPlacement(_:)`で示します。
UIKitでは`preferredPlacement`です。

縦か横かを自前レイアウトが知るには、SwiftUIの`toolbarVerticalEdge`を見ます。
UIKitでは`verticalBarEdge`を見ます。
背景画像を縦バーの下まで延ばすには、`backgroundExtensionEffect()`か`UIBackgroundExtensionView`を使います。

項目の並べ方は次のとおりです。

- 上から、戻るや閉じる、その次に完了のような主要操作を置く。戻るは、ナビゲーションが自動で付ける
- グループは、意味のある`ToolbarItemPlacement`で分ける。手動の固定間隔は付けない
- 縦に出す項目には、アイコンが要る。タイトルだけの項目と、カスタムビューの項目は、縦に出ない。閉じるや完了が文字だけなら、シンボルも付ける
- オーバーフローでは、アイコンとタイトルの両方を使う。頻度の低い操作から、`visibilityPriority`で落とす
- 自前のオーバーフローは、システムの`ToolbarOverflowMenu`へ移す。省略記号は、オーバーフロー専用にする
- ナビゲーションが主の画面ではタブを残し、ツールバーを溢れさせる。作業が主の画面ではタブを最小化し、ツールバーを残す

HIGは、この縦位置をアプリ側で上書きしない、と書いています。
内容の横にある操作は、その内容のそばに残します。
一覧の操作を、本文側の縦バーへ移しません。

iOS 27.1 SDKのビルドを出す前に、バーが縦になることを確認します。
iOS 26以前のSDKでは、開いた内側の中央に空きが残ります。
同じSDKの閉じた外側では、ステータスバーとカメラの左に内容が出ます。

iOS 27のSDKでは、開いた内側の大部分を使い、右端のステータスバーを避けます。
iOS 27の閉じた外側は、根拠のページに記載が無いので、提出の前にそのページで確認します。

iOS 27.1以降のSDKでは、開いた内側が画面いっぱいです。
同じSDKの開いた内側では、ツールバーとタブバーが、ステータスバーの下で縦に並びます。
同じSDKの閉じた外側は画面いっぱいで、縦バーは閉じた外側にも出ます。

## Step 7: 2領域のときだけ分ける

並びがすでに2領域のときだけ、`ArrangementView`を検討します。
UIKitは`UIArrangementViewController`です。
1つの主題を、広いからという理由で2枚にはしません。
折り目の両側に置くとき、領域は自分で読みません。

- splitは、横長なら左右、縦長なら上下に分ける。折り目があれば、その両側へ寄せる。HStackやVStackの並びに対応する
- overlayは、平らなときは重ねる。半折りでは、折り目の両側へ分ける。ZStackの並びに対応する。主が手前、副が奥である
- 軸は`.split.axes(.horizontal)`のように制限できる。縦のとき副を出さない、という指定もできる
- スクロール、リスト、ナビゲーション分割の中には置かない。ナビゲーションは外側に置く

ヒンジの角度は、SwiftUIの`onHingeChange`で受け取ります。
ヒンジの無い端末では、nullが返ります。
UIKit側は`UIHingeInteraction`です。
角度は演出向けです。

## Step 8: リサイズできるシーンの条件を見る

iPad、Mac、またはiPhone Mirroringのリサイズに合わせていれば、土台がある、とPreparingは書いています。
条件はTN3192にあります。

- 起動画面を付ける
- `UIRequiresFullScreen`を、Info.plistとビルド設定に置かない。iOS 27以降、このキーはリサイズ回避にならない
- 古いiOSのため残すなら、`UIRequiresFullScreenIgnoredStartingWithVersion`で、無視を始めるバージョンを指定する

TN3192は、iOS 27以降のApp Store提出に起動画面が必要だと書き、詳細はTN3208を参照、とあります。
起動画面の生成キーだけで、提出条件を満たすとは断定しません。
提出の前にTN3208を読みます。

全アプリがSplit Viewに参加します。
内側では、シーンが画面の一部になります。
複数ウィンドウを要求するなら、失敗を処理します。
外側では、新しいウィンドウは作れません。
要求には`UIWindowSceneActivationAction`を使います。

## Step 9: 各画面で確認する

各画面と、シート、ポップオーバーで次を見ます。

- サポートしている向きとポーズで、ビューがリサイズするか
- 縦バーで、よく使う操作が残り、頻度の低い操作がオーバーフローに入るか
- 開閉で、シートやポップオーバーの位置が不自然でないか
- 操作が折り目に乗って、押しにくくないか

Xcodeの支援に「get my app ready for iPhone Duo」と頼むと、上記のパターンを走査します。
別のエージェントなら、`xcrun agent skills export`で同じ検査を出します。

## Step 10: スクリーンショットを撮影する

全ての作業が完了したら、ストア申請用にiPhone Duoのスクリーンショットを撮影します。

## 出典

- [Prepare - iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
