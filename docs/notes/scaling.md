# Scaling: a split index, compact posting lists, build memory

Lab notes for item 3 of the plan ("scaling"). Entries are dated and
appended; earlier entries are not rewritten.

## 2026-10-27: plan and starting point

### Goal

The 0.1 benchmarks showed that query time is not the problem; index size
is. The plan:

- Split the index by token, so that a browser fetches only the parts a
  query needs.
- Write the positions in the posting lists more compactly.
- Use less memory when building.
- Measure each change on the same Aozora Bunko data and on about 1,100
  Japanese blog articles, and publish the numbers.

### Starting point (branch `multi-process`, af5064f)

- Format `cjk_index/3`: one JSON file. Each token maps to a flat array
  `[doc, field, n, pos1, ..., posn, doc, ...]` with absolute numbers.
- The Builder keeps that array per token in memory (one Ruby Integer per
  number) and writes one JSON string.
- bench/README.md (2026-10-01): the 16,951-work catalog index is 19.3 MB
  gzipped; full text adds about 5 bytes gzipped per character; 3,000 full
  texts took 215 s to build, and Ruby used 3 GB at the end of the run.

### Constraints decided before starting

- `filters` must stay in what is loaded first: the browse page lists and
  filters every document with no query.
- `CJKIndex.load(url)` and a synchronous `index.search` keep working for an
  index in one file (cb-ja-demo and `IndexFile` use one file).
- Ruby and the browser must keep returning the same results; Ruby standard
  library only.

## 2026-10-27: how it was measured

- Machine: Apple M4 Max, macOS 27.2. Ruby 4.0.1 (no YJIT unless stated),
  Node 25.6.0, Google Chrome 156.0.8078.73 (headless).
- Aozora: globis-university/aozorabunko-clean, the copy fixed by
  bench/retrieval/prepare.py (16,951 works). "catalog" = title, author and
  the first 200 characters; "fulltext n" = title, author and whole text of
  the first n works. Same records and fields as bench/aozora.rb.
- Blog: the author's own blog, Markdown sources of the Japanese posts
  (`content/ja/posts` of the site repository, 1,187 files, 5.2 M
  characters of body text). Fields title (boost 3), tags (2) and the
  Markdown body as it is (code blocks included). The texts are not in this
  repository; bench/corpus.rb reads any directory of Markdown files.
- Scripts: bench/build.rb (build time; peak memory from `/usr/bin/time -l`,
  "maximum resident set size", which includes the texts read), bench/split.rb
  (bytes a browser fetches per query, from a split index, checked against
  Ruby), bench/layouts.rb (encodings and shard assignments compared),
  bench/aozora.rb and bench/updates.rb (unchanged), bench/browser (Chrome).
- "Before" is af5064f run on the same day on the same machine (its lib
  copied with `git archive`), so that both columns share the machine state.
  Times differ from the 2026-10-01 table for the same code (3,000 full
  texts: 215 s then, 62 s now); compare within one table.

## 2026-10-27: encoding of the posting lists

Tried on the 16,951 catalog, 1,000 full texts and the blog (bench/layouts.rb;
size of the "tokens" object, gzip -9):

| encoding | catalog | fulltext 1000 | blog |
|---|---:|---:|---:|
| A format 3: JSON arrays, absolute numbers | 19.3 MB | 52.3 MB | 9.6 MB |
| B arrays, document gaps and position gaps | 14.2 MB | 37.2 MB | 7.4 MB |
| C arrays, key gaps (doc × fields + field) and position gaps | 14.2 MB | 36.6 MB | 7.3 MB |
| D C as BER integers (pack "w"), base64 | 14.9 MB | 36.7 MB | 7.5 MB |
| E C as variable-length numbers in 90 printable characters | 12.9 MB | 33.2 MB | 6.6 MB |

Kept E (format 4, `CJKIndex::Postings`): each list is one JSON string;
numbers are written with a last digit in base 60 and leading digits in base
30, from the characters `#` to `}` without `\`, so a list needs no escaping.
0–59 take one character, up to 1,799 two, up to 53,999 three.

- Gaps do most of the work (A to B: −26 to −29 %). Writing the gaps as
  characters instead of decimal digits and commas saves another 9–10 %
  after gzip, and halves the size before gzip (catalog: 42.3 MB for C,
  21.5 MB for E), which is what `JSON.parse` and memory see.
- Base64 of binary varints (D) compresses worse than C: base64 cuts bytes
  at 6-bit boundaries, so gzip finds fewer repeats.
- The split of 90 characters into 60 final and 30 leading digits was the
  best of 45/45, 60/30, 70/20 and 32/58, by under 1 %.
- Unigrams (single CJK characters, which the index needs for one-character
  queries) are about 37 % of the gzipped lists (catalog 4.8 of 12.9 MB,
  fulltext 12.2 of 33.2 MB). Their positions are needed only when a single
  CJK character stands next to a Latin word or digit in a query ("IIIF東");
  dropping them would change results, so they stay. A possible later step.
- Decoding: the runtime decodes a list the first time a query uses it, into
  the same flat array as format 3, and keeps it. Format 3 code paths are
  unchanged, so formats 2 and 3 still load.

## 2026-10-27: how to cut the index into shards

Options compared with encoding E (bench/layouts.rb; "per query" is the
gzipped size of the shards holding the tokens of each of the 20 queries,
median and max, manifest not counted):

| assignment | catalog: files, per query | fulltext 1000: files, per query | blog: files, per query |
|---|---|---|---|
| hash of the token, 256 shards | 256, 119 / 357 KB | 256, 252 / 888 KB | 256, 35 / 226 KB |
| hash, 1,024 shards | 1,024, 28 / 158 KB | 1,024, 51 / 389 KB | 1,024, 12 / 59 KB |
| hash, 4,096 shards | 4,096, 7.8 / 62 KB | 4,096, 15 / 123 KB | 4,096, 5.3 / 29 KB |
| sorted tokens cut every 8,000 B | 2,414, 9.9 / 66 KB | 4,887, 11 / 106 KB | 1,199, 5.9 / 30 KB |
| sorted, every 32,000 B | 665, 39 / 120 KB | 1,365, 43 / 170 KB | 317, 22 / 133 KB |
| sorted, every 128,000 B | 178, 151 / 432 KB | 368, 171 / 528 KB | 81, 85 / 491 KB |
| one file per token (lower bound) | 191,019, 0.9 / 48 KB | 273,917, 1.6 / 85 KB | 78,747, 3.1 / 18 KB |

Kept: sort the tokens by code point and cut them into shards of about
`shard_size` bytes (default 32,000), each named after a digest of its
content. The manifest lists the first token and file of each shard.

- For the same number of files, cutting by size fetches less than a hash
  (a hash gives shards of very different sizes) and compresses a little
  better (neighbouring tokens share characters).
- A token larger than the shard size gets a shard of its own. The largest
  list is a common character in the full text (346 KB gzipped at 1,000
  works); a query that needs it fetches it whole. This is the "max" column.
- Sorted shards keep the words a Latin prefix expands to together: they
  are in the shard of the prefix and the next ones that start with it.
- Digest names: a browser can cache shards; a shard whose content changes
  gets a new name, so a cached old manifest never mixes with new shards.
  `write_split` writes shards first, renames the manifest into place, then
  deletes the files the new manifest does not list.
- A hash would keep shard names more stable across updates. It does not
  matter much: adding or removing a document touches the lists of its
  hundreds of tokens, and removing one renumbers all later documents, which
  changes almost every shard (a test checks that removing the last document
  keeps unrelated shards).

Shard size, with the manifest counted (bench/split.rb, first search on a
page = manifest + shards of the query, median):

| shard size | catalog | fulltext 1000 | fulltext 3000 | blog |
|---|---|---|---|---|
| 8,000 B | 2,416 files, 98 + 10 KB | 4,887 files, 80 + 13 KB | 12,071 files, 197 + 14 KB | 1,201 files, 37 + 11 KB |
| 32,000 B | 667 files, 72 + 39 KB | 1,367 files, 28 + 43 KB | 3,821 files, 76 + 44 KB | 319 files, 25 + 22 KB |
| 128,000 B | 180 files, 64 + 151 KB | 370 files, 13 + 171 KB | 1,077 files, 36 + 179 KB | 83 files, 20 + 85 KB |

32,000 B is the default: smaller shards make the shard list in the
manifest grow as fast as they save per query, and multiply the files.

## 2026-10-27: what the manifest holds

The manifest has format, variants, fields, boosts, refs, lengths and
filters (what a blank query, the browse page and facets need), the shard
list, and the name of a file of Latin tokens.

- First version: the sorted Latin tokens (every token without CJK
  characters) inside the manifest, for prefix and typo expansion. On the
  blog this list was 33,129 tokens, 149 KB of the 175 KB gzipped manifest
  (code, URLs, file names). On the Aozora catalog only 1,470 tokens.
- Second version: the list in its own file, fetched when a query had a
  Latin word. The manifest fell to 25 KB, but every query with a Latin word
  then fetched 149 KB: the blog's median per query went from 22 to 103 KB.
- Kept: prefixes are expanded from the shards (see above), so the list is
  fetched only for a Latin word of 5+ letters that is not in the index,
  the case where typo expansion runs. The blog queries fetch 22 KB median.

## 2026-10-27: the API

- Ruby: `Builder#write(path)` writes one file (the same bytes as
  `to_json`, generated piece by piece). `Builder#write_split(dir,
  shard_size:)` writes a split index; `Builder#each_split_file` yields
  [name, content] for other destinations (the Jekyll plugin).
  `Builder.read(path)` reads a file or a split index to update it;
  `Builder.load` still takes JSON or a Hash of one file.
  `Searcher.load(path)` reads a file or a split index, and reads shards as
  queries need them (`Searcher.new(manifest, load_shard: ->(file) { ... })`
  for another source).
- Browser: `CJKIndex.load(url)` reads either. For a split index,
  `await index.searchAsync(query, options)` fetches what the query needs and
  searches; `await index.prepare(query)` only fetches, after which the
  synchronous `index.search(query, options)` works. `searchAsync` also
  works on one file, so a page can use it for both. A synchronous search
  that needs a shard not loaded yet throws an error naming searchAsync.
  `prepare` fetches in rounds until nothing is missing (typo candidates are
  known only after the list of Latin tokens arrives). highlight, excerpt
  and facets are unchanged; a blank query with a filter needs no shard.
- Jekyll: `split: true` (and `shard_size:`) on an index writes
  `<output>/<name>/index.json` and its shards.
- `IndexFile` stays one file.

## 2026-10-27: build memory and time

What changed in the Builder:

- A posting list is kept as the format 4 string, appended to as documents
  are added, instead of an Array of Integers (8 bytes per number plus
  spare capacity). Removing or inserting an entry walks the bytes of the
  list and copies the parts that do not change.
- The tokens of each document (needed to remove it) are no longer kept
  during a build that only adds; the first remove or update scans the
  lists once, as it already did after `Builder.load`.
- `write` and `write_split` do not build the whole JSON in memory.
- Normalizing folds in three passes over the string (tr, gsub, gsub)
  instead of a Ruby loop per character, and the builder normalizes each
  value once instead of twice. `Tokenizer.each_token` yields the tokens of
  normalized text by runs without building phrases. Both are checked against
  the old code: normalizing 706 texts (400 Aozora full texts, 300 blog
  posts, edge cases) and tokenizing 1,487 texts gave identical results.

bench/build.rb, af5064f with `to_json` and `File.write` (before) against
this branch with `write` and `write_split` (after):

| source | characters | before: build, peak memory, gzip | after, one file | after, split |
|---|---:|---|---|---|
| catalog 16,951 | 3.3 M | 8.0 s, 531 MB, 19.3 MB | 5.0 s, 349 MB, 12.9 MB | 5.3 s, 363 MB, 13.2 MB (667 files) |
| fulltext 1,000 | 10.4 M | 17.1 s, 839 MB, 52.3 MB | 10.7 s, 260 MB, 33.2 MB | 10.8 s, 269 MB, 33.4 MB (1,367 files) |
| fulltext 3,000 | 35.6 M | 61.5 s, 2,335 MB, 182.6 MB | 36.8 s, 563 MB, 108.6 MB | 37.0 s, 603 MB, 109.5 MB (3,821 files) |
| blog 1,187 | 5.2 M | 5.6 s, 214 MB, 9.6 MB | 2.4 s, 120 MB, 6.6 MB | 2.4 s, 133 MB, 6.9 MB (319 files) |

Peak memory includes the texts held by the benchmark (65–230 MB after
reading them). `to_json` still makes the whole string: 384 MB peak for the
catalog and 890 MB for 3,000 full texts, against 349 and 563 MB with
`write`.

- Build time is now about linear in the text (1,000 to 3,000 works: 3.4
  times the text, 3.4 times the time); before it grew 3.6 times.
- What is left of the build time is mostly normalizing (NFKC in Ruby's
  standard library is about 60 % of normalizing) and walking the tokens in
  Ruby.

## 2026-10-27: loading and querying

bench/aozora.rb, before and after on the same day (Ruby and Node; query
times median / max of 20 queries, each the median of 5 runs):

| mode | before: gzip, Ruby memory, Ruby load, Node load | after |
|---|---|---|
| catalog 16,951 | 19.3 MB, 655 MB, 0.48 s, 0.29 s | 12.9 MB, 409 MB, 0.08 s, 0.11 s |
| fulltext 1,000 | 52.3 MB, 1,072 MB, 1.18 s, 0.48 s | 33.2 MB, 424 MB, 0.15 s, 0.17 s |
| fulltext 3,000 | 182.6 MB, 3,095 MB, 3.26 s, 1.39 s | 108.6 MB, 1,022 MB, 0.27 s, 0.40 s |

Query times did not change beyond noise (catalog Node 0.06 / 1.01 ms
before, 0.07 / 1.43 ms after; fulltext 3,000 0.13 / 5.12 and 0.19 / 5.31
ms). Loading is faster because a list is decoded only when a query uses it.

Chrome (bench/browser, one file, 5 runs, the same day; results/chrome-v3.json
and chrome-v4.json): 16,951 records, load 275 ms → 142 ms (download 133 →
81, parse 116 → 38, init 22 → 23), JS heap 344 → 136 MB, query median /
max 0.04 / 0.82 → 0.04 / 0.83 ms. All 300 result lists of the format 4 runs
matched the Ruby Searcher.

From a split index (bench/split.rb, 32,000 B shards; each query on a freshly
loaded manifest, so it fetches everything it needs; gzip sizes):

| source | one file (before) | one file (after) | split: manifest | split: per query, median / max | first query in Node, median / max |
|---|---:|---:|---:|---:|---:|
| catalog 16,951 | 19.3 MB | 12.9 MB | 72 KB | 39 / 120 KB | 1.0 / 3.6 ms |
| fulltext 1,000 | 52.3 MB | 33.2 MB | 28 KB | 43 / 170 KB | 0.7 / 4.5 ms |
| fulltext 3,000 | 182.6 MB | 108.6 MB | 76 KB | 44 / 383 KB | 0.8 / 10.8 ms |
| blog 1,187 | 9.6 MB | 6.6 MB | 25 KB | 22 / 133 KB | 0.8 / 2.4 ms |

The first query time covers parsing the fetched shards, decoding lists and
searching; fetching is simulated from disk, so network time is not in it.
Ruby (`Searcher.load` on the directory) returned the same refs, order and
scores as Node for every query.

- The size of a split index no longer depends on the number of documents
  for a query; it depends on the query: 2 requests median, 6 at most.
- The largest fetches are queries with a common bigram (である, ある) in
  full text: its list covers most works with all positions.
- The manifest grows with the number of documents (refs and lengths) and
  of shards: 72 KB at 16,951 records.

## 2026-10-27: updates got slower in places

bench/updates.rb on the 16,951 catalog, before and after, without and with
YJIT (`ruby --yjit`):

| step | before | after | before, YJIT | after, YJIT |
|---|---:|---:|---:|---:|
| `Builder.load` | 0.54 s | 0.10–0.16 s | 1.09 s | 0.09 s |
| first update after load (scans the lists) | 0.79 s | 1.69–1.78 s | 0.58 s | 1.27 s |
| later updates | 81 ms | 242–289 ms | 43 ms | 217 ms |
| update in a builder | 98 ms | 246–250 ms | 64 ms | 181 ms |
| write after updates (`to_json`) | 0.43 s | 0.13–0.24 s | 0.44 s | 0.12 s |
| write after a remove | 0.75 s | 1.65–1.69 s | 0.82 s | 1.36 s |

(Two runs after; ranges show both.)

- One update and its write, in the process that wrote last (`IndexFile`):
  0.51 s before, 0.37–0.53 s after. After another process wrote: load,
  first update and write, 1.76 s before, 1.92–2.18 s after.
- What is slower is walking a list: an entry is now a few characters to
  parse in Ruby instead of Integers in an Array. Removing a document and
  inserting one in place both walk the lists of common characters (の, に),
  which cover most documents. A remove also makes the next write renumber
  every list.
- Tried: counting the positions to skip with String#count (C) when there
  are more than 8. No measurable change on the catalog, where most entries
  have one position.
- Not tried: keeping a skip table per long list, or a binary form in memory
  (`pack("w")` / `unpack("w*")` run in C) converted to format 4 when
  writing. The second would make every write convert every number in Ruby.

## 2026-10-27: tests and what is not checked

Tests (71 runs, 1,560 assertions, all passing): format 4 in one file, format 3 converted from
it and format 2 give the same results, scores and facet counts in Ruby and
in Node; a split index with very small shards (more than 20) gives the same
in Ruby (`Searcher.load`) and in Node (`CJKIndex.load` with a stub fetch,
`searchAsync`), and Builder.read gives back the same index; a synchronous
search before prepare throws; a prefix fetches no list of Latin tokens, a
typo does; tokens beyond U+FFFF and in U+E000–U+FFFF are found (the test
fails if the runtime compares with `<`); rewriting a split index removes
stale shards and keeps unchanged ones; words named like object members
("constructor") score the same in Ruby and Node; the Jekyll option; the existing
rebuild-equality test (random adds, removes and updates equal a fresh
build).

Non-obvious:

- JavaScript compares strings by UTF-16 code unit, Ruby by byte (= code
  point). Characters beyond U+FFFF (CJK extension B, emoji) sort before
  U+E000–U+FFFF in JavaScript and after them in Ruby. The runtime looks
  shards up with its own code point comparison.
- `・` (U+30FB) is in the katakana block, so it is both a CJK character and
  a separator; the tokenizer must test for separators first. The first
  version of `each_token` did not, and the comparison over the blog posts
  found it.
- A lookup on a plain object (`this.tokens[token]`) found
  `Object.prototype` members: in an index with "constructors", the query
  "constructor" counted as an exact word, not a prefix match, and scored
  0.288 in the browser against 0.173 in Ruby. The runtime now uses
  hasOwnProperty and a Set; both give 0.173.

Not checked:

- A real network (latency, HTTP/2 with many small requests) and a real
  site with a split index; Safari, Firefox and phones with format 4.
- Browser caching of shards across page loads.
- Ruby 3.1–3.4 locally (CI runs them).
- Memory of `Searcher` on a split index over a long-running process: it
  keeps every shard and decoded list it has read.
- Thread safety of the lazy caches in `Searcher` beyond the GVL (two
  threads may decode the same list twice; the result is the same).
