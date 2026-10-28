# cjk_index（日本語の説明）

English: [../../README.md](../../README.md)

中国語・日本語・朝鮮語の文章を、辞書なしで全文検索するための Ruby のライブラリである。
Ruby だけで書かれており、ネイティブ拡張を必要としない。
索引は Ruby で作り、検索は Ruby（`CJKIndex::Searcher`）でも、依存のない小さなブラウザ用スクリプトでもできる。
どちらで検索しても同じ結果を返す。

紹介動画（2 分）: [日本語](https://www.youtube.com/watch?v=B1PO2l3iPHo) ·
[English](https://www.youtube.com/watch?v=me46kC3JU8Q)。
試す: [デモサイト](https://nakamura196.github.io/cb-ja-demo/) ·
[同じデータで、元の検索と cjk_index を比べる](https://nakamura196.github.io/cb-ja-demo/compare.html)。

## なぜ作ったか

Ruby で作る静的サイトの多くは、ブラウザ内の検索に lunr.js を英語向けの初期設定のまま使っている。
lunr は語の両端から `\w` 以外の文字を削る。漢字・かな・ハングルはどれも `\w` ではないので、
これらだけの語は空になり、日本語で検索すると、題名をそのまま入れても **0 件** になる。

cjk_index は次のようにする。

- CJK の文字の並びを、1 文字ずつずらした 2 文字組に分け（「鳥瞰図」→ 鳥瞰、瞰図）、位置も記録する。
  検索語の 2 文字組が、その順に隣り合って現れる所だけに一致する。
  つまり、辞書もネイティブ拡張も使わずに、部分文字列としての一致になる
  （[kensaku](https://github.com/whispcat/kensaku) と同じ考え方）。
- 表記の揺れを、索引と検索語の両方で同じようにそろえる。
  NFKC（全角・半角など）、大文字小文字、異体字セレクタの除去、カタカナ → ひらがな、旧字 → 新字（「圖」→「図」）、
  「々」の展開（「佐々木」→「佐佐木」）。
  任意で、繁体字 ↔ 簡体字（OpenCC による）と、私用領域に書かれた古いハングルもそろえる。
- フィールドごとの BM25 で順位を付け、フィールドに重みを付けられる。
- 一致した箇所に、元の文章の上で印を付ける（`highlight`、`excerpt`）。
  検索語と本文が上の揺れだけ違う場合も印が付く。
- 最後のラテン文字の語は前方一致にし、5 文字以上のラテン文字の語は 1 文字の違いを許す。
- ブラウザ用のスクリプトは、Ruby 側と同じ表から作る。そのため索引を作る側と検索する側がずれない
  （テストで Node を使って確かめている。違う表で作った索引は、スクリプトが読み込みを断る）。
- 大きな索引は、小さな目次と分割したファイルに分けて書き出せる。ブラウザは検索に要るファイルだけを取りに行く。

ブラウザ用のスクリプトは、日本語の表込みで gzip 後約 9 KB、中国語の表も入れると約 24 KB である。
索引は Ruby のプログラム、Jekyll、Bridgetown、Rake、コマンドラインのどれからでも作れる。

他の方法（Pagefind、kensaku、lunr.js、rroonga、tantiny など）との比較:
[docs/comparison.md](../comparison.md)（英語）。
索引の大きさと検索時間: [bench/README.md](../../bench/README.md)。
lunr.js と比べた検索の質: [bench/retrieval/](../../bench/retrieval/)。

### 向いている場合と、向いていない場合

- **向いている:** 目録・資料のメタデータ・ブログ記事・本文を、静的サイト、コマンドラインの道具、
  スクリプト、小さなアプリで検索する場合。Ruby の外に何も入れたくない場合や、
  Ruby とブラウザで同じ結果がほしい場合。
  青空文庫の目録 16,951 件は、1 ファイルで gzip 後 12.9 MB になる。
  [分割した索引](#大きな資料群-索引の分割)にすると、ブラウザは最初に 72 KB の目次を読み、
  1 回の検索で約 40 KB を取りに行く。本文 1,000 作品（1 ファイルなら gzip 後 33 MB）でもほぼ同じである。
- **向いていない:** 大きな索引を頻繁に更新する場合や、サーバーで常に検索を受け付ける場合。
  更新のたびに索引全体を書き直し、索引はメモリに載せる。本文 3,000 作品（3,560 万字）の索引作りに
  37 秒、0.56 GB を使う。そうした用途には、ネイティブの検索エンジン（rroonga、tantiny）や
  データベースの機能（pg_bigm）のほうが向いている。

## Ruby で使う

```console
$ gem install cjk_index
```

```ruby
require "cjk_index"

builder = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
builder.add("item1.html", "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖")
File.write("search.json", builder.to_json)
File.write("cjk-index.js", CJKIndex::Runtime.source)
```

`add` の 1 つ目の引数（ref）が、検索結果で記録を指す値になる。
`fields` は索引にするフィールド、`boosts` はその重みである。

### Ruby で検索する

```ruby
searcher = CJKIndex::Searcher.new(builder)   # または CJKIndex::Searcher.load("search.json")
searcher.search("鳥瞰図")
# => [{ ref: "item1.html", score: 0.86, fields: ["title"] }]
searcher.highlight("東京帝國大學", "帝国大学")   # => "東京<mark>帝國大學</mark>"
searcher.excerpt(long_text, "鳥瞰図", 80)
```

一致の判定、順位付け、印の付け方、抜粋は、ブラウザ用のスクリプトと一つずつ同じ手順で行う。
テストでは同じ索引を両方で検索し、ref・点数・一致したフィールド・印・抜粋が同じことを確かめている。

### 絞り込み

絞り込みに使うフィールドは、索引を作るときに指定する。

- `value`: 値の全体で一致させる。値は検索語と同じようにそろえる（「地圖」で「地図」に一致する）。
- `year`: 値の中の最初の 4 桁の数字を年とする（`1900-01-01`、`１９３１年`）。
  「明治33年」のような和暦からは年を取らない。

```ruby
builder = CJKIndex::Builder.new(fields: %w[title], filters: {
  "type" => "value", "subject" => { "kind" => "value", "separator" => ";" }, "date" => "year"
})
builder.add("item1.html", "title" => "…鳥瞰圖", "type" => "地図", "subject" => "建物;農学部", "date" => "1900")

searcher.search("鳥瞰図", filter: { "type" => "地図", "date" => 1890..1910 })
searcher.search("", filter: { "subject" => %w[建物 植物] })  # 検索語なし: 条件に合うものすべて
searcher.facets("type", results)  # => [{ value: "地図", count: 12 }, ...]
```

違うフィールドの条件は、すべて満たす必要がある。値を配列で渡すと、どれか一つに合えばよい。
絞り込みは結果を減らすだけで、残った結果の点数は変わらない。

### 索引を更新する

```ruby
builder.update("item1.html", "title" => "…", "type" => "写真")  # 置き換え。無ければ追加
builder.remove("item2.html")

builder = CJKIndex::Builder.read("search.json")   # 書き出した索引を読み込んで変える
```

何度変えても、結果は残った記録を同じ順で一から作った索引と同じになる（テストで確かめている）。

### 複数のプロセスで 1 つの索引ファイルを使う

Rails のアプリは、ふつう複数のワーカープロセスで動き、それぞれが索引をメモリに持つ。
`IndexFile` は、1 つのファイルを通してそれらをそろえる。

```ruby
# config/initializers/cjk_index.rb
SEARCH = CJKIndex::IndexFile.new(Rails.root.join("db/search-index.json"))

SEARCH.write(builder)                                   # 全件を作り直す（Rake タスクなど）
SEARCH.update { |b| b.update(item.id, item.to_doc) }    # 記録が変わったら。どのプロセスからでもよい
SEARCH.searcher.search("鳥瞰図")                        # ファイルが変わっていれば読み直す
```

`update` はロックを取り、ファイルを読み、ブロックを実行して書き出す。
そのため、別々のプロセスからの更新も一つずつ順に反映される。
新しい索引は一時ファイルに書いてから名前を付け替えるので、読む側が書きかけのファイルを見ることはない。
書く途中でプロセスが止まっても、前の索引がそのまま残る。
ロックは `flock` を使うので、NFS ではなく手元のディスクに置く。

## 大きな資料群: 索引の分割

索引は形式 `cjk_index/4` で書き出す。各語の出現位置の一覧を短い文字列に詰めたもので、
gzip 後で形式 3 の約 3 分の 2、圧縮前で約 3 分の 1 の大きさになる。
Ruby もブラウザ用のスクリプトも、形式 2 と 3 の索引を引き続き読める。

本文や数万件の記録を入れるときは、索引を分割して書き出す。
小さな目次（ref・長さ・絞り込みの値）と、約 32 KB ずつのファイルに分かれ、
ブラウザは検索に要るファイルだけを取りに行く。

```ruby
builder.write_split("assets/search")   # index.json（目次）と分割したファイル
```

```js
const index = await CJKIndex.load("/assets/search/index.json");
const results = await index.searchAsync("銀河鉄道", { filter: { type: "小説" } });
// または: await index.prepare(query); index.search(query, options)
```

`searchAsync` は 1 ファイルの索引でも動くので、ページの側はどちらにも同じ書き方で対応できる。
検索語なしの絞り込み、`facets`、`highlight`、`excerpt` は、分割したファイルを読まない。
青空文庫の本文 1,000 作品（1 ファイルなら gzip 後 33 MB）では、目次が 28 KB、
1 回の検索で取りに行くのは中央値で 43 KB だった。

Ruby では、`CJKIndex::Searcher.load("assets/search")` が検索に要るファイルだけを読み、
`CJKIndex::Builder.read("assets/search")` が分割した索引を読み込んで変更できるようにする。
分割したファイルの名前は中身から作るので、長くキャッシュしてよい。
`write_split` は、新しい目次に載っていない古いファイルを消す。`IndexFile` は常に 1 ファイルで書く。

## ブラウザで使う

```html
<script src="cjk-index.js"></script>
<script>
  CJKIndex.load("search.json").then(function (index) {
    index.search("鳥瞰図");  // => [{ ref: "item1.html", score: ..., fields: ["title"] }]
    CJKIndex.highlight("東京帝國大學", "帝国大学"); // => "東京<mark>帝國大學</mark>"
    CJKIndex.excerpt(longText, "鳥瞰図", 80);    // 最初の一致の周りを、印を付けて切り出す

    var results = index.search("鳥瞰図", { filter: { type: "地図", date: { min: 1890, max: 1910 } } });
    index.facets("type", results);              // => [{ value: "地図", count: 12 }, ...]
  });
  // 分割した索引では await index.searchAsync(query, options) を使う（上を参照）
</script>
```

## Jekyll

```ruby
# Gemfile
group :jekyll_plugins do
  gem "cjk_index", require: "cjk_index/jekyll"
end
```

```yaml
# _config.yml
cjk_index:
  output: assets/cjk-index        # 既定
  variants: [ja]                  # 既定。[ja, zh-safe] で繁体字・簡体字もそろえる
  indexes:
    - name: posts                 # -> assets/cjk-index/posts.json
      collection: posts
      fields: [title, tags, content]
      boosts: { title: 3 }
    - name: items
      data: metadata              # _data/metadata.csv の各行
      ref: objectid
      fields: [title, creator, subject]
      filters:                    # 任意
        type: value
        subject: { kind: value, separator: ";" }
        date: year
    - name: texts
      collection: texts
      fields: [title, content]
      split: true                 # -> assets/cjk-index/texts/index.json と分割したファイル
```

ブラウザ用のスクリプトは `assets/cjk-index/cjk-index.js` に書き出される。
lunr.js からの移行の手順: [migrating-from-lunr.md](migrating-from-lunr.md)。

### CollectionBuilder

```yaml
cjk_index:
  indexes:
    - name: search
      preset: collectionbuilder
```

この設定は、CollectionBuilder 自身の検索の設定に従う。
`_data/config-search.csv` で `index` が `true` のフィールドを索引にし、
子の資料は `search-child-objects` が有効なときだけ入れる。
結果の ref は、`assets/js/lunr-store.js` の `id` と同じ値になる。
絞り込みは、既定でテーマの `metadata-facets-fields`（値は `;` 区切り）と、`date` 列の年になる。
変えるときは `filters:` を書く。
動いている例: https://github.com/nakamura196/cb-ja-demo

## Bridgetown

Bridgetown 2.2.2 で確かめている。Node は要らない。

```ruby
# config/initializers.rb
require "cjk_index/bridgetown"

Bridgetown.configure do |config|
  init :cjk_index, indexes: [
    { name: "posts", collection: "posts", fields: %w[title content], boosts: { title: 3 },
      filters: { category: "value", date: "year" } }
  ]
end
```

`output/cjk-index/posts.json` と `output/cjk-index/cjk-index.js` が書き出される。
`src/_data/*.csv` の各行を入れるときは、`collection:` の代わりに `data:` と `ref:` を書く。
例: [examples/bridgetown](../../examples/bridgetown)

## コマンドラインと Rake

```console
$ cjk_index build items.csv --ref id --fields title,creator --boost title=3 --filter type --filter date=year -o index.json --runtime cjk-index.js
$ cjk_index search index.json 鳥瞰図 --filter type=地図 --filter date=1890..1910
$ cjk_index runtime --variants ja,zh-safe -o cjk-index.js
```

`build` は CSV、JSON の配列、JSON Lines を、ファイルか標準入力（`-`）から読む。
`--filter subject=value:";"` とすると、値を `;` で分ける。
`search` に `--json` を付けると、結果を JSON で出す。
CSV を読むには `csv` gem が要る（Ruby 3.4 から標準では入らない）。

```ruby
# Rakefile
require "cjk_index/rake_task"

CJKIndex::RakeTask.new(:search_index) do |t|
  t.source  = "data/items.csv"            # または t.records = -> { Item.all.map(&:to_search) }
  t.output  = "public/search/items.json"
  t.runtime = "public/search/cjk-index.js"
  t.fields  = %w[title creator]
  t.boosts  = { "title" => 3 }
  t.filters = { "type" => "value", "date" => "year" }
end
```

[examples/search_csv.rb](../../examples/search_csv.rb) は、CSV の目録をコマンドラインで検索する、
約 40 行の Ruby だけのスクリプトである。

## Rails

[examples/rails](../../examples/rails)（Rails 8.1.4。Puma の 4 ワーカーで確かめた）は、
`IndexFile` で 1 つの索引をすべてのワーカーで共有する例である。
初期化のファイル、記録の保存のあとに索引を更新するモデルの部品、絞り込みつきの検索の画面、
索引を作り直す Rake タスクを含む。
各方式の覚え書き: [docs/notes/adapters.md](../notes/adapters.md)（英語）

## 異体字の表

| 名前 | そろえるもの | 出典 |
|---|---|---|
| `ja`（既定） | 日本語の旧字・異体字 409 組を 1 つの形に（圖→図、證→証、禱/祷、剝/剥） | 常用漢字表（2010）、人名用漢字、kZVariant（Unihan 18.0 経由、Unicode License v3） |
| `zh-safe` | 繁体字 → 簡体字のうち、どちら向きにも 1 対 1 の 2,767 組 | OpenCC（Apache-2.0） |
| `zh` | 繁体字 → 簡体字 3,202 組（0.1 と同じ） | OpenCC の `TSCharacters.txt`（Apache-2.0）。あいまいな項目は除く |
| `ko` | 私用領域に書かれた古いハングル 5,660 字 → 標準の字母 | hypua の表（Unlicense）。元は KTUG の Hanyang PUA Table Project |

複数の表を指定すると、どれかの表でつながる字はすべて 1 つの形にそろい、
先に書いた表の形を優先する（`[ja, zh-safe]` なら 圖・図・图 → 図）。

`zh` は、日本語や繁体字では別の字も 1 つにまとめる。後と后、發と髮（どちらも 发）、機と机などである。
`ja` と合わせると、常用漢字・人名用漢字の 45 組がまとまってしまう。
`zh-safe` はこうした組を除くので、簡体字の「发展」で「發展」は見つからない。
日本語のサイトで簡体字の検索語にも応えたいときは `zh-safe`、中国語のサイトでは `zh` を使う。

ハングルには表が要らない。合成済みの音節と、字母を並べた書き方は、Unicode の正規化でそろう。
`ko` は、HWP やハニャン（漢陽）のフォントが私用領域に書いた古いハングルのための表である。
標準の字母で入力した検索語で、それらを見つけ、印を付けられるようになる。

### 自分の表を使う

`variants` に上の名前以外を書くと、自分で用意した表のファイルとして読む。
場所は、サイトのフォルダ（Jekyll、Bridgetown）か、いまいるフォルダ（CLI、Rake、Ruby）から見た相対パスで書く。
ファイルは 1 行に 1 グループで、タブで区切る。先頭がそろえる先の形、その後ろに異体字を 1 字ずつ並べる。
資料のデータベースがすでに持っている異体字の一覧は、たいていこの形である。

```text
# itaiji.tsv
与	與
宴	醼	讌
嶋	嶌
```

```yaml
cjk_index:
  variants: [ja, _data/itaiji.tsv]
```

各欄は、先に NFKC・小文字・異体字セレクタの除去・カタカナ → ひらがなを通してから読む。
そのため、異体字シーケンス（「珊」＋ U+E0100）で書いた欄は、その字そのものとして扱う。
グループをどの形にそろえるかは、ここでも先に書いた表が優先する。
索引には、書いたとおりの名前（`_data/itaiji.tsv`）が入り、手元の絶対パスは入らない。
digest はファイルの中身から作るので、ファイルを直したら索引を作り直す。
別のフォルダから Ruby でその索引を読むときは、normalizer を渡す:
`Builder.load(json, normalizer: CJKIndex::Normalizer.new(tables: [...], base: dir))`。
範囲の広い一覧は、表記の違いを越えて字をまとめる。「宴」に「燕」が入った一覧では、「燕」で「宴会」が見つかる。
自分の資料で確かめてから使う。

ブラウザ用スクリプトの大きさ（gzip 後）: 表なし 6.3 KB、`ja` 9.0 KB、`ja, zh-safe` 24.1 KB、
`ja, zh` 25.9 KB、`ja, ko` 36.1 KB。

表は `data/` にある UTF-8 の TSV ファイルである（「異体字<TAB>そろえた形」、任意で注記の列、`#` で注記）。
`script/variant_tables.rb` が出典から作り直す。出典・規則・件数:
[docs/notes/variant-tables.md](../notes/variant-tables.md)（英語）。
索引には、表がそろえる中身から作った値（digest）が入る。
Ruby もブラウザ用のスクリプトも、違う中身の表で作った索引は読み込みを断る。
表を変えたときや 0.x から上げたときは、索引を作り直す。

## 状態

1.0。RubyGems で公開している: `gem install cjk_index`
（https://rubygems.org/gems/cjk_index）。変更点: [CHANGELOG.md](../../CHANGELOG.md)（英語）。
開発は Ruby Association Grant 2026 の支援を受けている。

`ko` の表と朝鮮語の例は、朝鮮語を読む人による確認がまだである
（確認用の一覧: [docs/review/](../review/)）。気づいた点を知らせていただけるとありがたい。

## 開発

```sh
bundle install
bundle exec rake test   # ブラウザ用スクリプトのテストには node が要る
```

不具合の報告とプルリクエスト: [CONTRIBUTING.md](../../CONTRIBUTING.md)。
セキュリティの問題: [SECURITY.md](../../SECURITY.md)。

## ライセンス

MIT。異体字の表のライセンスは [NOTICE](../../NOTICE) を参照。
