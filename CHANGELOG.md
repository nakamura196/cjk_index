# Changelog

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
