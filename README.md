# cjk_index

日本語の説明: [docs/ja/README.md](docs/ja/README.md)

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
- folds variants on both sides: NFKC, lowercase, variation selectors
  dropped, katakana → hiragana, old-form kanji → modern form (「圖」→「図」), 々 expanded (「佐々木」→「佐佐木」),
  and optionally Traditional ↔ Simplified Chinese (from OpenCC) and old
  Hangul in the Private Use Area;
- ranks with BM25 per field, with field boosts;
- marks matches in the original text (`highlight`, `excerpt`), even when the
  query and the text differ only by these variants;
- matches the last Latin word as a prefix, and Latin words of 5+ letters with
  one typo;
- generates the browser script from the same tables as the Ruby code, so
  indexing and querying cannot drift apart (checked by the test suite under
  Node; the script also refuses an index built with other tables);
- splits a large index into a small manifest and shards that the browser
  fetches only when a query needs them.

The browser script is about 9 KB gzipped with the Japanese table, 24 KB
with the Chinese table as well. Index it from Ruby, Jekyll, Bridgetown, a
Rake task or the command line.

How this compares with Pagefind, kensaku, lunr.js, rroonga, tantiny and others:
[docs/comparison.md](docs/comparison.md).
Index size and query time on up to 16,951 works of Aozora Bunko:
[bench/README.md](bench/README.md). Retrieval quality against lunr.js:
[bench/retrieval/](bench/retrieval/). Load and query times in Chrome and
Safari: [bench/browser/](bench/browser/).

When to use it, and when not to:

- **Good fit:** catalogs, collection records, blog posts and full texts on
  static sites, command-line tools, scripts and small apps; anywhere you want
  nothing to install outside Ruby, or the same results in Ruby and the
  browser. In one file, the 16,951-record Aozora Bunko catalog is 12.9 MB
  gzipped; as a [split index](#large-collections-split-indexes), the browser
  loads a 72 KB manifest and fetches about 40 KB per query, and 1,000 full
  texts (33 MB gzipped in one file) need about the same.
- **Not a good fit:** frequent updates to a large index, or search served
  continuously by a server. An update rewrites the whole index, and the index
  is held in memory: building 3,000 full texts (35.6 million characters) takes
  37 s and 0.56 GB. A native engine (rroonga, tantiny) or a database feature
  (pg_bigm) is the better choice there.

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

### Filters

Fields to filter on are given when the index is built. A `value` filter
matches whole values, folded like the query (地圖 matches 地図); a `year`
filter keeps the first four-digit number of a value (`1900-01-01`,
`１９３１年`; era dates such as 明治33年 give no year).

```ruby
builder = CJKIndex::Builder.new(fields: %w[title], filters: {
  "type" => "value", "subject" => { "kind" => "value", "separator" => ";" }, "date" => "year"
})
builder.add("item1.html", "title" => "…鳥瞰圖", "type" => "地図", "subject" => "建物;農学部", "date" => "1900")

searcher.search("鳥瞰図", filter: { "type" => "地図", "date" => 1890..1910 })
searcher.search("", filter: { "subject" => %w[建物 植物] })  # no query: every item that passes
searcher.facets("type", results)  # => [{ value: "地図", count: 12 }, ...]
```

Conditions on different fields must all hold; a list matches any of its
values. A filter only removes results: the scores of the others do not change.

### Updating an index

```ruby
builder.update("item1.html", "title" => "…", "type" => "写真")  # in place, or added if new
builder.remove("item2.html")

builder = CJKIndex::Builder.load(File.read("search.json"))    # change a written index
```

After any changes, `to_h` is the same as for an index built from scratch
with the remaining documents in the same order (the test suite checks this
on random sequences of changes). A `Searcher` made from a `Builder` answers
for its current documents.

### Sharing an index file between processes

A Rails app usually runs several worker processes, and each holds its own
copy of the index in memory. `IndexFile` keeps them in step through one file:

```ruby
# config/initializers/cjk_index.rb
SEARCH = CJKIndex::IndexFile.new(Rails.root.join("db/search-index.json"))

SEARCH.write(builder)                                   # a full build, e.g. in a Rake task
SEARCH.update { |b| b.update(item.id, item.to_doc) }    # after a record changes, in any process
SEARCH.searcher.search("鳥瞰図")                        # loads the file again if it has changed
```

`update` takes a lock, reads the file, runs the block and writes the result,
so updates from different processes are applied one after another. The new
index is written to a temporary file and renamed over the old one: a reader
gets the old index or the new one, never a partly written file. A reader
keeps the index it loaded until the file changes; `interval:` limits how
often it checks. Put several changes in one block to write once.

On the Aozora Bunko catalog (16,951 records), a check of an unchanged file
takes 0.09 ms, and an update about 0.5 s (about 2 s when another process
wrote last, as the file is read again).
[bench/index_file.rb](bench/index_file.rb). The lock is `flock`: use a local
disk, not NFS.

The file is never changed in place, so a writer that is killed leaves the
previous index intact and nothing to repair. A writer waits at most
`lock_timeout:` seconds (default 60) for another one, then raises
`CJKIndex::IndexFile::LockTimeout`.

An update rewrites the whole file, so its cost grows with the index: 0.08 s
for 1,000 records, 0.24 s for 5,000, 0.7 s for 16,951. A record edited now
and then needs nothing special; put a few changes in one block; for an
import, build the index again and `write` it (11 s for 16,951 records).

## Large collections: split indexes

Indexes are written in format `cjk_index/4`: each posting list is a compact
string, about a third smaller gzipped than format 3 and three times smaller
before compression. Ruby and the browser script still read formats 2 and 3.

For full text or tens of thousands of records, write a split index: a small
manifest (refs, lengths, filters) and shards of about 32 KB that the browser
fetches only when a query needs them.

```ruby
builder.write_split("assets/search")   # index.json and the shards
```

```js
const index = await CJKIndex.load("/assets/search/index.json");
const results = await index.searchAsync("銀河鉄道", { filter: { type: "小説" } });
// or: await index.prepare(query); index.search(query, options)
```

`searchAsync` also works on an index in one file, so a page can use it for
both. A blank query with a filter, `facets`, `highlight` and `excerpt` need
no shard. On 1,000 Aozora Bunko full texts (33 MB gzipped as one file), the
manifest is 28 KB and a query fetches 43 KB (median).

In Ruby, `CJKIndex::Searcher.load("assets/search")` reads shards as queries
need them, and `CJKIndex::Builder.read("assets/search")` loads a split index
to change it. Shard names are digests of their content, so they can be cached
for long; `write_split` removes the shards the new manifest no longer lists.
`IndexFile` always writes one file. Measurements: [bench/README.md](bench/README.md).

## Browser

```html
<script src="cjk-index.js"></script>
<script>
  CJKIndex.load("search.json").then(function (index) {
    index.search("鳥瞰図");  // => [{ ref: "item1.html", score: ..., fields: ["title"] }]
    CJKIndex.highlight("東京帝國大學", "帝国大学"); // => "東京<mark>帝國大學</mark>"
    CJKIndex.excerpt(longText, "鳥瞰図", 80);    // highlighted window around the first match

    var results = index.search("鳥瞰図", { filter: { type: "地図", date: { min: 1890, max: 1910 } } });
    index.facets("type", results);              // => [{ value: "地図", count: 12 }, ...]
  });
  // a split index: await index.searchAsync(query, options), see above
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
      filters:                    # optional
        type: value
        subject: { kind: value, separator: ";" }
        date: year
    - name: texts
      collection: texts
      fields: [title, content]
      split: true                 # -> assets/cjk-index/texts/index.json and shards
```

The runtime is written to `assets/cjk-index/cjk-index.js`. Moving a site from
lunr.js: [docs/migrating-from-lunr.md](docs/migrating-from-lunr.md).

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
`assets/js/lunr-store.js`. Filters default to the theme's
`metadata-facets-fields` (values separated by `;`) and a year from the `date`
column; set `filters:` to change them. A working example:
https://github.com/nakamura196/cb-ja-demo

## Bridgetown

Tested with Bridgetown 2.2.2. Node is not needed.

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

This writes `output/cjk-index/posts.json` and `output/cjk-index/cjk-index.js`.
Use `data:` and `ref:` instead of `collection:` for rows of
`src/_data/*.csv`. See [examples/bridgetown](examples/bridgetown).

## Command line and Rake

```console
$ cjk_index build items.csv --ref id --fields title,creator --boost title=3 --filter type --filter date=year -o index.json --runtime cjk-index.js
$ cjk_index search index.json 鳥瞰図 --filter type=地図 --filter date=1890..1910
$ cjk_index runtime --variants ja,zh-safe -o cjk-index.js
```

`build` reads CSV, a JSON array or JSON Lines, from a file or from standard
input (`-`). `--filter subject=value:";"` splits values on `;`. Add `--json`
to `search` for machine-readable results. CSV needs the `csv` gem, which is
no longer a default gem from Ruby 3.4.

```ruby
# Rakefile
require "cjk_index/rake_task"

CJKIndex::RakeTask.new(:search_index) do |t|
  t.source  = "data/items.csv"            # or t.records = -> { Item.all.map(&:to_search) }
  t.output  = "public/search/items.json"
  t.runtime = "public/search/cjk-index.js"
  t.fields  = %w[title creator]
  t.boosts  = { "title" => 3 }
  t.filters = { "type" => "value", "date" => "year" }
end
```

### A script with no dependencies

[examples/search_csv.rb](examples/search_csv.rb) searches a CSV catalog from
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

## Rails

[examples/rails](examples/rails) (Rails 8.1.4, tested with Puma and four
workers) keeps one index for all worker processes with `IndexFile`: an
initializer, a model concern that updates the index after each commit, a
search action with filters, and a Rake task that rebuilds the index.
Notes on all the adapters: [docs/notes/adapters.md](docs/notes/adapters.md).

## Variant tables

| name | folds | source |
|---|---|---|
| `ja` (default) | 409 Japanese old forms and glyph variants → one form (圖→図, 證→証, 禱/祷, 剝/剥) | Jōyō Kanji Table (2010), Jinmeiyō kanji list and kZVariant, via Unihan 18.0 (Unicode License v3) |
| `zh-safe` | 2,767 Traditional → Simplified pairs that are one-to-one both ways | OpenCC (Apache-2.0) |
| `zh` | 3,202 Traditional → Simplified (as in 0.1) | OpenCC `TSCharacters.txt` (Apache-2.0); ambiguous entries dropped |
| `ko` | 5,660 old Hangul characters in the Hanyang Private Use Area → standard jamo | hypua table (Unlicense), from the KTUG Hanyang PUA Table Project |

With several tables, characters linked by any of them fold to one form,
preferring the table listed first (`[ja, zh-safe]`: 圖, 図, 图 → 図).

`zh` also merges characters that are distinct in Japanese and in
Traditional Chinese: 後 and 后, 發 and 髮 (both 发), 機 and 机. Combined with
`ja`, it merges 45 such groups of Jōyō and Jinmeiyō kanji. `zh-safe` leaves
those pairs out, so a Simplified query 发展 does not find 發展. Use `zh-safe`
for Japanese sites that should also match Simplified queries, and `zh` for
Chinese sites.

Hangul needs no table: precomposed syllables and conjoining jamo are folded
by Unicode normalization. `ko` is for old Hangul stored in the Private Use
Area by HWP and the Hanyang fonts; a query typed in standard jamo then finds
and highlights it.

### A table of your own

Any entry of `variants` that is not one of the names above is a table file
of your own, relative to the site's folder (Jekyll, Bridgetown) or the
current folder (CLI, Rake, Ruby). One group per line, tab-separated: the
form to fold to, then its variants, one character each. This is the format
of the itaiji lists that collection databases often keep already.

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

Each cell is folded first (NFKC, lowercase, variation selectors dropped,
katakana → hiragana), so a cell written as an ideographic variation sequence
(珊 + U+E0100) is the character itself, and the table listed first still
picks the form a group folds to. The index records
the entry as written (`_data/itaiji.tsv`), not the full path, and its digest
covers the file's contents, so editing the file means rebuilding the index.
To read such an index from another folder in Ruby, pass the normalizer:
`Builder.load(json, normalizer: CJKIndex::Normalizer.new(tables: [...], base: dir))`.
Wide lists merge more than spelling: a list that puts 燕 with 宴 makes
a search for 燕 (swallow) find 宴 (banquet). Check a list against your own material first.

Browser script size, gzipped: no table 6.3 KB, `ja` 9.0 KB, `ja, zh-safe`
24.1 KB, `ja, zh` 25.9 KB, `ja, ko` 36.1 KB.

The tables are UTF-8 TSV files in `data/` ("variant<TAB>folded", an optional
comment column, `#` comments); `script/variant_tables.rb` generates them from
their sources. Sources, rules and counts:
[docs/notes/variant-tables.md](docs/notes/variant-tables.md). An index
records a digest of what its tables fold, and Ruby and the browser script
refuse an index built with other table contents: rebuild the index after
changing tables or upgrading from 0.x.

## Status

1.0. On RubyGems: `gem install cjk_index`
(https://rubygems.org/gems/cjk_index). Changes: [CHANGELOG.md](CHANGELOG.md).
Development is supported by the Ruby Association Grant 2026.

Not yet checked by a native reader: the `ko` table and the Korean examples
([docs/review/](docs/review/)). Reports are welcome.

## Development

```sh
bundle install
bundle exec rake test   # the runtime tests need node
```

Bug reports and pull requests: see [CONTRIBUTING.md](CONTRIBUTING.md).
Security problems: [SECURITY.md](SECURITY.md).

## License

MIT
