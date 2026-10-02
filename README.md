# cjk_index

Dictionary-free full-text search for Chinese, Japanese and Korean text, in
pure Ruby. Build the index in Ruby, then query it in Ruby (`CJKIndex::Searcher`)
or in the browser with a small script that has no dependencies. Both return
the same results.

[![Demo video: CJK search in CollectionBuilder, before and after cjk_index](https://img.youtube.com/vi/me46kC3JU8Q/hqdefault.jpg)](https://www.youtube.com/watch?v=me46kC3JU8Q)

Demo video (2 min): [English](https://www.youtube.com/watch?v=me46kC3JU8Q) ·
[日本語](https://www.youtube.com/watch?v=B1PO2l3iPHo).
Try it: [demo site](https://nakamura196.github.io/cb-ja-demo/) ·
[stock search vs. cjk_index on the same data](https://nakamura196.github.io/cb-ja-demo/compare.html).

Why: client-side search in many Ruby static sites uses lunr.js with its
English defaults. lunr's trimmer strips non-`\w` characters from both ends of
each token, and kanji, kana and hangul are all non-`\w`, so a token made only
of them becomes empty and a Japanese query returns **0 results**,
even when it is an exact title. cjk_index instead:

- splits CJK runs into overlapping character bigrams (「鳥瞰図」→ 鳥瞰, 瞰図) and
  stores their positions, so a query matches only where its bigrams are
  adjacent and in order: an exact substring match, with no dictionary or
  native extension (the same idea as [kensaku](https://github.com/whispcat/kensaku));
- folds variants on both sides: NFKC, lowercase, katakana → hiragana,
  old-form kanji → modern form (「圖」→「図」), 々 expanded (「佐々木」→「佐佐木」),
  and optionally Traditional ↔ Simplified Chinese (from OpenCC);
- ranks with BM25 per field, with field boosts;
- marks matches in the original text (`highlight`, `excerpt`), even when the
  query and the text differ only by these variants;
- matches the last Latin word as a prefix, and Latin words of 5+ letters with
  one typo;
- generates the browser script from the same tables as the Ruby code, so
  indexing and querying cannot drift apart (checked by the test suite under
  Node; the script also refuses an index built with other tables).

The browser script is about 6.5 KB gzipped with the Japanese table, 24 KB
with the Chinese table as well.

How this compares with Pagefind, kensaku, lunr.js and others:
[docs/comparison.md](docs/comparison.md).
Index size and query time on up to 16,951 works of Aozora Bunko:
[bench/README.md](bench/README.md).

## Ruby

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

### Search in Ruby

No search server or native extension is needed. `Searcher` takes a
`Builder`, its `to_h`, or the JSON it wrote, and folds queries with the
variant tables the index was built with.

```ruby
searcher = CJKIndex::Searcher.new(builder)   # or CJKIndex::Searcher.load("search.json")
searcher.search("鳥瞰図")
# => [{ ref: "item1.html", score: 0.86, fields: ["title"] }]
searcher.highlight("東京帝國大學", "帝国大学")   # => "東京<mark>帝國大學</mark>"
searcher.excerpt(long_text, "鳥瞰図", 80)
```

Matching, BM25 ranking, highlighting and excerpts follow the browser script
step for step. The test suite runs both on the same index and checks that
refs, scores, matched fields, highlights and excerpts are identical.

### Without Jekyll

[examples/search_csv.rb](examples/search_csv.rb) searches a CSV catalogue from
the command line, in about 40 lines of plain Ruby:

```console
$ ruby examples/search_csv.rb items.csv 实录 --ref objectid --variants ja,zh
12 results for 实录
jitsu_51ed985b       宣祖[実録] 第1帙 第1冊 巻2戊辰元年(1568)
...
$ ruby examples/search_csv.rb items.csv 帝国大学 --ref objectid
3 results for 帝国大学
agri_6d032fb5        東京[帝國大學]農學部建物位置圖
...
```

## Browser

```html
<script src="cjk-index.js"></script>
<script>
  CJKIndex.load("search.json").then(function (index) {
    index.search("鳥瞰図");  // => [{ ref: "item1.html", score: ..., fields: ["title"] }]
    CJKIndex.highlight("東京帝國大學", "帝国大学"); // => "東京<mark>帝國大學</mark>"
    CJKIndex.excerpt(longText, "鳥瞰図", 80);    // highlighted window around the first match
  });
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
  output: assets/cjk-index        # default
  variants: [ja]                  # default; [ja, zh] adds Traditional/Simplified Chinese
  indexes:
    - name: posts                 # -> assets/cjk-index/posts.json
      collection: posts
      fields: [title, tags, content]
      boosts: { title: 3 }
    - name: items
      data: metadata              # rows of _data/metadata.csv
      ref: objectid
      fields: [title, creator, subject]
```

The runtime is written to `assets/cjk-index/cjk-index.js`.

### CollectionBuilder

```yaml
cjk_index:
  indexes:
    - name: search
      preset: collectionbuilder
```

The preset follows CollectionBuilder's own search settings: fields with
`index: true` in `_data/config-search.csv`, and child objects only when
`search-child-objects` is on. Result refs are the same `id` values as in
`assets/js/lunr-store.js`. A working example:
https://github.com/nakamura196/cb-ja-demo

## Variant tables

| name | folds | source |
|---|---|---|
| `ja` (default) | 291 Japanese old forms → modern forms | written for cjk_index |
| `zh` | 3,202 Traditional → Simplified Chinese | OpenCC `TSCharacters.txt` (Apache-2.0); ambiguous entries dropped |

With several tables, characters linked by any of them fold to one form,
preferring the table listed first (`[ja, zh]`: 圖, 図, 图 → 図). The `zh`
table also merges characters that are distinct in Japanese (後 and 后), so
it is opt-in.

## Status

0.1, early. On RubyGems: `gem install cjk_index`
(https://rubygems.org/gems/cjk_index). Planned: filters and incremental index
updates, index sharding for large sites (see the [benchmarks](bench/README.md)),
a Bridgetown adapter and a CLI.

## Development

```sh
bundle install
bundle exec rake test   # the runtime tests need node
```

## License

MIT
