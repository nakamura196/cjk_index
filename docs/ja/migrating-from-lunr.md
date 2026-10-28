# lunr.js からの移行

English: [../migrating-from-lunr.md](../migrating-from-lunr.md)

Jekyll のサイトやテーマの多くは、[lunr.js](https://lunrjs.com/) で検索している。
サイトは記録を JSON などに書き出し、ページを開くたびにブラウザが lunr の索引を作る。
lunr を初期設定（英語向け）のまま使うと、漢字・かな・ハングルだけの検索語は 0 件になる。
lunr は語の両端から `\w` 以外の文字を削るため、CJK の文字だけの語は空になるからである。
この手引きでは、そうしたサイトの lunr を cjk_index に置き換える手順と、置き換えで変わる点を示す。

手順は、[cb-ja-demo](https://github.com/nakamura196/cb-ja-demo)（日本語・中国語・朝鮮語の資料を載せた CollectionBuilder のサイト）で実際に行ったものである。
このサイトの検索ページは、比べるために lunr でも動かせる:
[compare.html](https://nakamura196.github.io/cb-ja-demo/compare.html)

## 何が変わるか

| | lunr.js | cjk_index |
|---|---|---|
| 索引を作る場所 | ブラウザ（ページを開くたび。Node で事前に作ることもできる） | Ruby（サイトのビルド時） |
| ブラウザが読むもの | 記録（JS か JSON）と lunr.js（gzip で約 8.4 KB） | 索引の JSON と `cjk-index.js`（日本語の表込みで gzip 約 6.5 KB） |
| CJK の文章 | 初期設定では削られて空になる | 位置つきの 2 文字組。検索語がそのまま連続して現れる所に一致する |
| 表記の揺れ | 扱わない（英語の語幹処理はある） | NFKC、大文字小文字、カタカナ／ひらがな、旧字／新字、任意で繁体字／簡体字 |
| 順位付け | BM25 | フィールドごとの BM25 と重み付け |
| 結果 | `{ ref, score, matchData }` | `{ ref, score, fields }` |
| 一致箇所の強調 | `matchData` の位置から自分で書く | `CJKIndex.highlight(text, query)`、`CJKIndex.excerpt(text, query, length)` |
| 絞り込みと件数 | なし | `filter:` と `index.facets(field, results)` |

## 手順 1: ビルド時に索引を作る

gem を足し、どの記録のどのフィールドを索引にするかを書く。

```ruby
# Gemfile
group :jekyll_plugins do
  gem "cjk_index", require: "cjk_index/jekyll"
end
```

```yaml
# _config.yml
cjk_index:
  indexes:
    - name: search                 # -> assets/cjk-index/search.json
      collection: posts            # データファイルなら data: metadata（_data/metadata.csv の各行）と ref:
      fields: [title, tags, content]
      boosts: { title: 3 }         # lunr の this.field("title", { boost: 3 }) にあたる
```

フィールドと重みは、`lunr(function () { ... })` の中と同じにする。
結果の `ref` は、コレクションならページの URL、データファイルなら `ref:` に指定した列の値になる。
結果を表示するコードが記録を探すのに使っている値（lunr の `this.ref(...)`）を選ぶ。

CollectionBuilder なら、次の 1 行でサイト自身の検索設定
（`_data/config-search.csv`、`search-child-objects`、`metadata-facets-fields`）に従う。

```yaml
cjk_index:
  indexes:
    - name: search
      preset: collectionbuilder
```

このとき ref は、`assets/js/lunr-store.js` の `id` と同じ値になる。

Jekyll を使わない場合も、Ruby のプログラムから同じファイルを作れる。

```ruby
builder = CJKIndex::Builder.new(fields: %w[title tags content], boosts: { "title" => 3 })
records.each { |r| builder.add(r[:url], r) }
File.write("search.json", builder.to_json)
File.write("cjk-index.js", CJKIndex::Runtime.source)
```

## 手順 2: 索引を作る代わりに読み込む

変更前:

```html
<script src="/assets/lib/lunr.min.js"></script>
<script src="/assets/js/lunr-store.js"></script>
<script>
  var idx = lunr(function () {
    this.ref("id");
    this.field("title", { boost: 3 });
    this.field("content");
    store.forEach(function (doc) { this.add(doc); }, this);
  });
</script>
```

変更後:

```html
<script src="/assets/js/lunr-store.js"></script>  <!-- 結果を store から描くなら残す -->
<script src="/assets/cjk-index/cjk-index.js"></script>
<script>
  var ready = CJKIndex.load("/assets/cjk-index/search.json");
</script>
```

`CJKIndex.load` は JSON を取得し、Promise を返す。読み込みが済めば、検索は同期で動く。

## 手順 3: 検索して結果を表示する

変更前:

```js
function search(query) {
  show(idx.search(query));            // [{ ref, score, matchData }]
}
```

変更後:

```js
function search(query) {
  ready.then(function (index) {
    show(index.search(query));        // [{ ref, score, fields }]
  });
}
```

結果を表示するコードが、store の中の位置で記録を探す場合（CollectionBuilder の `store[ref]` がそう）は、ref から位置への対応を一度作っておく。

```js
var position = {};
store.forEach(function (s, i) { position[s.id] = i; });
results.map(function (r) { return { ref: position[r.ref] }; });
```

題名や抜粋の一致箇所に印を付けるには、`matchData` の代わりに次の関数を使う。
HTML のエスケープも行い、元の文章の上に印を付ける。検索語「帝国大学」で「帝國大學」に印が付く。

```js
CJKIndex.highlight(record.title, query);   // "東京<mark>帝國大學</mark>…"
CJKIndex.excerpt(record.content, query, 80);
```

## 手順 4（任意）: 絞り込みと件数

lunr には絞り込みがないので、サイトが自分のコードで結果を絞ることが多い。
cjk_index は絞り込みの値を索引に持つので、絞り込み一覧の件数を検索と同じ索引から出せる。

```yaml
      filters:
        type: value
        subject: { kind: value, separator: ";" }
        date: year
```

```js
var results = index.search(query, { filter: { type: "地図", date: { min: 1890, max: 1910 } } });
index.facets("subject", results);   // [{ value: "建物", count: 12 }, ...]
index.search("", { filter: { type: "地図" } });  // 検索語なし: 条件に合うものすべて
```

## 引き継がれない検索の書き方

lunr は検索語を小さな検索言語として解釈する。cjk_index は解釈せず、検索語はただの文字列として扱う。
lunr の書き方がどうなるかを次に示す。

| lunr | lunr での意味 | cjk_index では |
|---|---|---|
| `foo bar` | どちらかを含む（既定は OR） | **両方**を含む。空白や句読点で区切った部分は、すべて現れる必要がある |
| `+foo -bar` | 必ず含む／含まない | 使えない。`+` と `-` は区切りとして扱う |
| `title:foo` | 1 つのフィールドだけ | 検索語では指定できない。全フィールドを検索し、結果の `fields` を見る |
| `foo*`、`*foo` | ワイルドカード | 最後のラテン文字の語は自動で前方一致。CJK の文章はもともと部分一致 |
| `foo~1` | 編集距離 | 5 文字以上のラテン文字の語は、自動で 1 文字の違いを許す |
| `foo^10` | 検索時の重み | 使えない。重みは索引を作るときにフィールドごとに決める |
| 語幹処理・ストップワード | 英語向けの処理 | なし。ラテン文字の語は書かれたとおりに照合する（小文字化と NFKC はする） |

利用者が気づくのは、OR から AND への変化である。lunr では語を足すと結果が増え、cjk_index では減る。多くの検索サイトと同じ動きである。

## 置き換えたあとに確かめること

- 索引の大きさ。索引は事前に作り、位置の情報も持つ。索引にした文章 1 文字あたり、gzip 後で約 5 バイトになる。
  題名と短い項目の目録なら小さい（cb-ja-demo の 69 件は、解説とページごとの翻刻を含めて 44 KB。
  青空文庫 16,951 作品の題名・著者・冒頭は 19 MB）。長い本文を入れるときは
  [bench/README.md](../../bench/README.md) を見てから決める。
- ブラウザ用のスクリプトと索引は、同じ異体字の表で作る。Jekyll のプラグインは両方を書き出す。
  Jekyll を使わないときは、両方を一緒に作る。違う表で作った索引は、スクリプトが読み込みを断る。
- 確認が済むまで、元の検索も比べられるように残しておく。cb-ja-demo は、テーマの設定
  （`search-cjk: true`）で使う検索を選び、検索ページで `?engine=lunr` を付けると lunr で動く。
