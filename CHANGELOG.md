# Changelog

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
