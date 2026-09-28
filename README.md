# cjk_index

Dictionary-free full-text search for Chinese, Japanese and Korean text on
static sites. The index is built in Ruby at build time. A small browser
script (no dependencies) queries it.

Why: client-side search in most Ruby static sites uses lunr.js with its
English defaults. lunr's trimmer removes every non-`\w` character, and kanji,
kana and hangul are all non-`\w`, so a Japanese query returns **0 results**,
even when it is an exact title. cjk_index instead:

- splits CJK runs into overlapping character bigrams (「鳥瞰図」→ 鳥瞰, 瞰図) and
  requires all of them, which behaves like substring search, with no dictionary
  or native extension;
- folds variants on both sides: NFKC, lowercase, katakana → hiragana,
  old-form kanji → modern form (「圖」→「図」), 々 expanded (「佐々木」→「佐佐木」);
- generates the browser script from the same tables as the Ruby code, so
  indexing and querying cannot drift apart (checked by the test suite under Node).

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
    index.search("鳥瞰図"); // => [{ ref: "item1.html", score: ... }]
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

## Status

0.1, early. Not yet on RubyGems. Planned: Traditional/Simplified Chinese
variant tables, index sharding for large sites, a Bridgetown adapter, and
size and speed benchmarks.

## Development

```sh
bundle install
bundle exec rake test   # the runtime tests need node
```

## License

MIT
