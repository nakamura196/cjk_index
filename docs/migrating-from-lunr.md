# Migrating from lunr.js

日本語: [ja/migrating-from-lunr.md](ja/migrating-from-lunr.md)

Many Jekyll sites and themes search with [lunr.js](https://lunrjs.com/): the
site writes its records as JSON, and the browser builds a lunr index from
them when the page loads. With lunr's default (English) pipeline, a query
made only of kanji, kana or hangul returns 0 results, because lunr's trimmer
removes every non-`\w` character from both ends of each token. This guide
replaces lunr with cjk_index on such a site, step by step, and lists what
behaves differently.

The steps below are the ones taken on
[cb-ja-demo](https://github.com/nakamura196/cb-ja-demo), a CollectionBuilder
site with Japanese, Chinese and Korean records. Its search page can still run
lunr for comparison: [compare.html](https://nakamura196.github.io/cb-ja-demo/compare.html).

## What changes

| | lunr.js | cjk_index |
|---|---|---|
| Where the index is built | in the browser, on every page load (or prebuilt with Node) | in Ruby, at build time |
| What the browser downloads | the records (a JS or JSON store) and lunr.js (about 8.4 KB gzipped) | the index JSON and `cjk-index.js` (about 6.5 KB gzipped with the Japanese table) |
| CJK text | trimmed to nothing with the default pipeline | overlapping bigrams with positions: a query matches where it occurs as a substring |
| Variants | none (stemming for English) | NFKC, case, katakana/hiragana, old/new kanji forms, optionally Traditional/Simplified Chinese |
| Ranking | BM25 | BM25 per field, with field boosts |
| Result | `{ ref, score, matchData }` | `{ ref, score, fields }` |
| Marking matches | from `matchData` positions, by your own code | `CJKIndex.highlight(text, query)`, `CJKIndex.excerpt(text, query, length)` |
| Filters and facet counts | not built in | `filter:` option and `index.facets(field, results)` |

## Step 1: build the index at build time

Add the gem and say which records and fields to index.

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
      collection: posts            # or data: metadata (rows of _data/metadata.csv) with ref:
      fields: [title, tags, content]
      boosts: { title: 3 }         # lunr: this.field("title", { boost: 3 })
```

Use the same fields and boosts as in the `lunr(function () { ... })` call.
The `ref` of each result is the page URL for a collection, or the `ref:`
column for a data file. Pick the value your results code already uses to
find a record (lunr's `this.ref(...)`).

For CollectionBuilder, one line follows the site's own search settings
(`_data/config-search.csv`, `search-child-objects`, `metadata-facets-fields`):

```yaml
cjk_index:
  indexes:
    - name: search
      preset: collectionbuilder
```

The refs are then the same `id` values as in `assets/js/lunr-store.js`.

Without Jekyll, build the same file in any Ruby program:

```ruby
builder = CJKIndex::Builder.new(fields: %w[title tags content], boosts: { "title" => 3 })
records.each { |r| builder.add(r[:url], r) }
File.write("search.json", builder.to_json)
File.write("cjk-index.js", CJKIndex::Runtime.source)
```

## Step 2: load the index instead of building one

Before:

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

After:

```html
<script src="/assets/js/lunr-store.js"></script>  <!-- keep it if results are drawn from the store -->
<script src="/assets/cjk-index/cjk-index.js"></script>
<script>
  var ready = CJKIndex.load("/assets/cjk-index/search.json");
</script>
```

`CJKIndex.load` fetches the JSON and returns a Promise. Searching is
synchronous once it has resolved.

## Step 3: search and show results

Before:

```js
function search(query) {
  show(idx.search(query));            // [{ ref, score, matchData }]
}
```

After:

```js
function search(query) {
  ready.then(function (index) {
    show(index.search(query));        // [{ ref, score, fields }]
  });
}
```

If the results code looks records up by position in the store (as
CollectionBuilder does, with `store[ref]`), map refs back to positions once:

```js
var position = {};
store.forEach(function (s, i) { position[s.id] = i; });
results.map(function (r) { return { ref: position[r.ref] }; });
```

To mark the matched part of a title or a snippet, use the helpers instead of
`matchData`. They escape HTML and work on the original text, so a query
「帝国大学」 marks 「帝國大學」:

```js
CJKIndex.highlight(record.title, query);   // "東京<mark>帝國大學</mark>…"
CJKIndex.excerpt(record.content, query, 80);
```

## Step 4 (optional): filters and facet counts

lunr has no filters, so a site usually filters its results in its own code.
cjk_index stores the filter values in the index, so the counts in a facet
list come from the same index as the search:

```yaml
      filters:
        type: value
        subject: { kind: value, separator: ";" }
        date: year
```

```js
var results = index.search(query, { filter: { type: "地図", date: { min: 1890, max: 1910 } } });
index.facets("subject", results);   // [{ value: "建物", count: 12 }, ...]
index.search("", { filter: { type: "地図" } });  // no query: everything that passes
```

## Query syntax that does not carry over

lunr parses a small query language. cjk_index does not; a query is plain
text. What each lunr feature becomes:

| lunr | meaning in lunr | in cjk_index |
|---|---|---|
| `foo bar` | either term (OR by default) | **both**: every part separated by spaces or punctuation must occur |
| `+foo -bar` | must / must not | not supported; `+` and `-` are separators |
| `title:foo` | only in one field | not supported in the query; search all fields, then check `fields` of each result |
| `foo*`, `*foo` | wildcards | the last Latin word matches as a prefix automatically; CJK text matches as a substring already |
| `foo~1` | edit distance | Latin words of 5+ letters allow one edit automatically |
| `foo^10` | query-time boost | not supported; boosts are set per field when the index is built |
| stemming, stop words | English pipeline | none; Latin words are matched as written (folded to lowercase and NFKC) |

The change from OR to AND is the one users notice: with lunr, adding words
widens the results; with cjk_index, it narrows them, as on most search
sites.

## Things to check after switching

- Index size. The index is prebuilt and includes positions: about 5 bytes
  per character of indexed text, gzipped. A catalog of titles and short
  fields stays small (the 69 records of cb-ja-demo, with descriptions and
  page transcriptions: 44 KB; 16,951 Aozora Bunko titles, authors and
  openings: 19 MB). Index long full text with care; see
  [bench/README.md](../bench/README.md).
- The browser script and the index must be built with the same variant
  tables. The Jekyll plugin writes both; outside Jekyll, write them together.
  The script refuses an index built with other tables.
- Keep the old path for comparison while you check. cb-ja-demo chooses the
  engine with a theme setting (`search-cjk: true`) and accepts
  `?engine=lunr` on the search page.
