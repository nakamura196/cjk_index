# cjk_index

Dictionary-free full-text search for Chinese, Japanese and Korean text on
static sites. The index is built in Ruby at build time. A small browser
script (no dependencies) queries it.

Why: client-side search in most Ruby static sites uses lunr.js with its
English defaults. lunr's trimmer removes every non-`\w` character, and kanji,
kana and hangul are all non-`\w`, so a Japanese query returns **0 results**,
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

## Ruby

```ruby
require "cjk_index"

builder = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
builder.add("item1.html", "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖")
File.write("search.json", builder.to_json)
File.write("cjk-index.js", CJKIndex::Runtime.source)
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

0.1, early. Not yet on RubyGems. Planned: index sharding for large sites, a
Bridgetown adapter, a CLI, and size and speed benchmarks.

## Development

```sh
bundle install
bundle exec rake test   # the runtime tests need node
```

## License

MIT
