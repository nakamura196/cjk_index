# Changelog

## 1.0.0 (2026-10-28)

Indexes built with 0.x should be rebuilt: the `ja` table changed, and the
index now records a digest of its tables (see below). Formats 2 and 3 are
still read.

Large collections:

- Index format `cjk_index/4`: posting lists as compact strings (about a third
  smaller gzipped, three times smaller before compression).
- Split indexes: `Builder#write_split(dir, shard_size:)` and
  `Builder#each_split_file` write a manifest and shards of about 32 KB; the
  browser fetches shards as queries need them (`index.searchAsync`,
  `index.prepare`). `CJKIndex.load` and `Searcher.load` read a split index;
  Jekyll: `split: true`.
- `Builder#write(path)` writes one file without building the JSON in memory;
  `Builder.read(path)` reads a file or a split index.
- Building keeps posting lists encoded and normalizes faster: 3,000 full
  texts take 0.56 GB instead of 2.3 GB at peak, and 37 s instead of 62 s.
- Updating a loaded index is slower without YJIT (one update about 0.25 s at
  17,000 records); one update and its write in `IndexFile` cost about the
  same as before.

Variant tables:

- `ja`: 409 pairs (was 291), generated from the Jōyō Kanji Table, the
  Jinmeiyō kanji list and Unihan kZVariant. 籐/藤, 聯/連 and 彎/湾 no longer
  fold.
- New opt-in tables: `zh-safe` (Traditional/Simplified pairs that are
  one-to-one both ways, so 後/后 and 發/髮 stay apart) and `ko` (old Hangul
  in the Hanyang Private Use Area to standard jamo). `zh` is unchanged.
- `script/variant_tables.rb` generates the tables from their sources.
- The index records `variant_digest`, a digest of what its tables fold; Ruby
  and the browser script refuse an index whose digest differs.
- The browser highlights matches in conjoining jamo, half-width kana with
  sound marks and old Hangul in the Private Use Area.

More ways to build an index:

- `cjk_index` command: `build` (CSV, JSON or JSON Lines), `search`, `runtime`.
- `CJKIndex::RakeTask`.
- Bridgetown 2 plugin (`require "cjk_index/bridgetown"`).
- Examples for Bridgetown and Rails (`examples/`), notes in
  `docs/notes/adapters.md`.
- Migration guide from lunr.js, in English and Japanese
  (`docs/migrating-from-lunr.md`).

Filters:

- A `value` filter compares value ids instead of folded strings, in Ruby
  and in the browser (#14): filtering 17,000 records by one author takes
  1.7 ms instead of 2.7 ms.

Fixes:

- A `year` filter on a Time or Date (Jekyll gives a post's `date` as a Time)
  gave no year.
- The Jekyll plugin gave the builder only the index fields of a collection
  document, so a filter on another front-matter field was empty.
- A query word named like a JavaScript object member ("constructor") scored
  differently in the browser than in Ruby.

## 0.2.0 (2026-10-28)

- Filters: `Builder.new(filters:)` with `value` and `year` filters;
  `search(query, filter:)` in Ruby and `search(query, { filter })` in the
  browser; a blank query with a filter lists every document that passes;
  `facets(field, results)` counts values. Ruby and the browser give the same
  results and counts.
- Index updates: `Builder#remove`, `Builder#update`, `Builder.load`. The
  changed index is the same as one rebuilt from scratch.
- `Searcher.new(builder)` follows later changes to the builder (it used to
  copy the index).
- `IndexFile`: an index file shared by several processes (e.g. Rails
  workers). Updates take a lock and are written with a rename, so none is
  lost and readers never see a partly written file; readers load the file
  again when it changes. A killed writer leaves the old index intact;
  `lock_timeout:` bounds the wait for another writer.
- Index format `cjk_index/3` (adds `filters`). The browser script and
  `Searcher` still read `cjk_index/2`.
- Jekyll: `filters:` for an index; the CollectionBuilder preset filters on
  `metadata-facets-fields` and the year of `date`.

## 0.1.1 (2026-10-18)

No change to the library. This release fixes the state of the repository
cited in a paper.

- Retrieval quality on two real datasets (69 catalog records from cb-ja-demo,
  16,951 Aozora Bunko works; 15 queries each), against lunr.js with its
  default and Japanese settings: [bench/retrieval/](bench/retrieval/).
  Queries, relevance judgments (committed before the runs), judging rules,
  scripts and raw outputs are included.
- Load and query times in Chrome and Safari for 1,000, 5,000 and 16,951
  records: [bench/browser/](bench/browser/).
- README and docs/comparison.md: the recommended size is now the range we
  measured (up to 16,951 records), not "about 20,000".
- CITATION.cff for citing the software.
- CODE_OF_CONDUCT.md (Contributor Covenant 2.1), CONTRIBUTING.md, SECURITY.md,
  issue forms and a pull request template.

## 0.1.0 (2026-10-02)

First release on RubyGems.

- Normalizer in pure Ruby: NFKC, lowercase, katakana → hiragana, 291 old-form
  kanji → modern forms, the iteration mark 々. Optional Traditional → Simplified
  Chinese table (3,202 characters, from OpenCC, Apache-2.0). `CJKIndex.normalize`.
- Tokenizer: positional bigrams for CJK runs, including hangul and old-hangul
  jamo; Latin words as whole tokens.
- `CJKIndex::Builder`: BM25 index with field boosts, written as JSON.
- `CJKIndex::Searcher`: exact substring matching, BM25 ranking, highlighting and
  excerpts in pure Ruby; prefix matching and one-typo tolerance for Latin words.
- Browser runtime with no dependencies (`CJKIndex::Runtime.source`), generated
  from the same tables; the test suite requires identical results in Ruby and
  under Node.
- Jekyll plugin (`cjk_index/jekyll`) with a CollectionBuilder preset.

In the repository (not packaged in the gem):

- `examples/search_csv.rb`: search a CSV catalog from the command line, without Jekyll.
- Benchmarks on Aozora Bunko (up to 16,951 works): [bench/README.md](bench/README.md).
- Comparison with other search tools: [docs/comparison.md](docs/comparison.md).
