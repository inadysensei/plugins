# 効果

画像を、このページのために作ったものへ変える、コードの扱いです。任意です。方向の性格に合うときだけ、主なビジュアルにだけ使います。他の要素の装飾にはしません。

## 字形

画像を文字の格子として描きます。明るさが文字を選びます。文字が製品自身の材料から来るとき、最もうまくいきます。画像が、製品の扱うもので文字どおりできています。

- お金、請求、金融: `. : 1 7 4 0 8 ¥ %`。ドル建ての製品は`¥`の代わりに`$`を使う
- コード、開発ツール: `. : / { } < > = #`
- 音楽: `c d e g a`のような音名と、`♭ ♯`
- 書くこと、読むこと: 製品から来た語の、小文字の字母か仮名
- データ、監視: `. · : | + ▪`

セルは6pxから10pxに保ちます。書体は、文字のパスで選んだ等幅を使います。字形の色は、画像からか、ランプから取ります。少数のセルを時間とともにゆっくり変え、絵が生きて見えるようにします。

下の見本の既定は、原文のまま`Geist Mono`と`$`です。呼び出すときは、選んだ等幅と、製品の通貨記号を渡します。

### 実装

```js
function glyphs(canvas, image, { cell = 8, chars = ". :1740$%", font = "Geist Mono", fps = 8 } = {}) {
  const ctx = canvas.getContext("2d");
  const columns = Math.floor(canvas.width / cell);
  const rows = Math.floor(canvas.height / cell);

  const sample = document.createElement("canvas");
  sample.width = columns;
  sample.height = rows;
  const sampler = sample.getContext("2d", { willReadFrequently: true });
  sampler.drawImage(image, 0, 0, columns, rows);
  const pixels = sampler.getImageData(0, 0, columns, rows).data;

  const atlas = document.createElement("canvas");
  atlas.width = cell * chars.length;
  atlas.height = cell;
  const pen = atlas.getContext("2d");
  pen.font = `500 ${cell + 1}px ${font}`;
  pen.textAlign = "center";
  pen.textBaseline = "middle";
  pen.fillStyle = "#fff";
  [...chars].forEach((char, index) => pen.fillText(char, index * cell + cell / 2, cell / 2));

  const cells = [];
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < columns; x++) {
      const i = (y * columns + x) * 4;
      const light = (0.2126 * pixels[i] + 0.7152 * pixels[i + 1] + 0.0722 * pixels[i + 2]) / 255;
      cells.push({ x, y, light, color: `rgb(${pixels[i]},${pixels[i + 1]},${pixels[i + 2]})`, seed: Math.random() });
    }
  }

  const tinted = document.createElement("canvas");
  tinted.width = cell;
  tinted.height = cell;
  const tint = tinted.getContext("2d");

  const draw = (step) => {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const c of cells) {
      if (c.light < 0.06) continue;
      const jitter = Math.sin(c.seed * 999 + step) > 0.92 ? 1 : 0;
      const pick = Math.min(chars.length - 1, Math.floor(c.light * chars.length) + jitter);
      tint.globalCompositeOperation = "copy";
      tint.drawImage(atlas, pick * cell, 0, cell, cell, 0, 0, cell, cell);
      tint.globalCompositeOperation = "source-in";
      tint.fillStyle = c.color;
      tint.fillRect(0, 0, cell, cell);
      ctx.drawImage(tinted, c.x * cell, c.y * cell);
    }
  };

  let frame = 0;
  let last = 0;
  let step = 0;
  let visible = true;
  new IntersectionObserver(([entry]) => (visible = entry.isIntersecting)).observe(canvas);
  const loop = (now) => {
    frame = requestAnimationFrame(loop);
    if (!visible || now - last < 1000 / fps) return;
    last = now;
    draw(step++);
  };
  frame = requestAnimationFrame(loop);
  return () => cancelAnimationFrame(frame);
}
```

大きいキャンバスでは、各セルの色付き字形を一度オフスクリーンのキャンバスへ焼き、段階で変わるセルだけを描き直します。

## ハーフトーンの点

明るさに従って大きさが変わる、格子の上の点です。編集、印刷、手仕事の性格に合います。採取は字形と同じです。半径`light * cell / 2`の`arc`の円を、ページの色の上に1つのインク色で描きます。

## ディザ

ランプから取った2色か3色への、順序ディザか誤差拡散です。レトロ、技術的、遊びのある性格に合います。画像を読み込んだときに1回行い、毎フレームでは行いません。

## 2色

画像の明るさを2色へ写像します。ランプの最も暗い面と、アクセントか主の文字色です。生成画像をパレットに属させる、最も単純な方法です。CSSでは、アクセントの`mix-blend-mode: color`の層の下にグレースケール画像を置くか、SVGの`feColorMatrix`フィルタを使います。

## 性能

これらの効果は、性能の低いノートPCで以前おかしくなりました。次の規則に従います。

- 画素は、画像を読み込んだときに1回だけ読む。アニメーションのループの中で`getImageData`を呼ばない。GPUが止まり、フレームが1桁まで落ちる。
- 字形のアトラスと色付きセルは先に用意し、`drawImage`で描く。
- アニメーションは毎秒8から12段階にする。60にはしない。1段階で変えるセルは、少ない割合だけにする。
- キャンバスが画面の外にあるときは止める。
- キャンバスの大きさはデバイスの画素比に合わせる。上限は2にする。
