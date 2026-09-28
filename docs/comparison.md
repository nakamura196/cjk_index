# Comparison with existing search tools for static sites

Surveyed on 2026-09-28. Star counts, release dates and archive status were
read from GitHub and RubyGems on that date. Feature descriptions come from
each project's documentation and source unless marked otherwise; we have not
benchmarked the other tools.

## Summary

- The core idea of cjk_index, positional CJK bigrams, is **not new**.
  [kensaku](https://github.com/whispcat/kensaku) (Rust compiled to
  WebAssembly, first published 2026-09-25) does the same, and full-text
  engines such as Lucene have long offered CJK bigram analyzers. cjk_index
  adopted kensaku's positional matching, BM25 ranking, highlighting, Latin
  prefix matching and one-typo tolerance.
- Most other tools either segment CJK text into words (so matching depends on
  where a segmenter puts word boundaries), split it into single characters,
  or do not handle it at all.
- None of the tools below folds the spelling variants that matter for East
  Asian texts: old and new kanji forms, Traditional and Simplified Chinese,
  katakana and hiragana.
- None of them builds its index in Ruby. The Ruby integrations keep lunr's
  English pipeline, call a non-Ruby binary, or send data to a hosted service.

## Search libraries

| Tool | Build needs / browser runtime | CJK handling | Matches inside a word | Variant folding | Ranking | Status (2026-09-28) |
|---|---|---|---|---|---|---|
| **cjk_index** 0.1 | Ruby only / JS, 6.5 KB gzipped (24 KB with the `zh` table) | Positional bigrams; single characters for 1-char queries | Yes, exact substring | NFKC, case, katakana → hiragana, 291 old kanji forms, 々, optional Traditional → Simplified (OpenCC) | BM25 per field, field boosts | Published 2026-09-28 |
| [kensaku](https://github.com/whispcat/kensaku) | Rust CLI / WASM 147 KB + JS 5 KB gzipped | Positional bigrams | Yes, exact substring (tested exhaustively) | Not documented | BM25, title ×3 | Published 2026-09-25, 0 stars |
| [Pagefind](https://github.com/Pagefind/pagefind) | Rust binary (via npx) / WASM | Word segmentation at indexing; at query time with `Intl.Segmenter` since v1.5.0 | Only where query and text segment the same way (see note 1) | None | BM25-style, title boost | 5,485 stars, active |
| [FlexSearch](https://github.com/nextapps-de/flexsearch) | JS | `Charset.CJK`: one token per character | Yes | None | Own scoring | 13.8k stars, active |
| [lunr.js](https://github.com/olivernn/lunr.js) + [lunr-languages](https://github.com/MihaiValentin/lunr-languages) `ja` | JS | TinySegmenter (statistical word segmentation) | No | None | TF-IDF | lunr: last release 2.3.9 (2020) |
| [MiniSearch](https://github.com/lucaong/minisearch) | JS | None built in (bring your own tokenizer) | No | None | BM25+ | 6.15k stars |
| [Orama](https://github.com/oramasearch/orama) | JS + tokenizer packages | Dictionary-based segmentation | No | None | BM25 | 10.6k stars, active |
| [Fuse.js](https://github.com/krisk/Fuse) | JS | None; fuzzy scan of every record | Yes (fuzzy) | None | Edit distance (Bitap) | 20.5k stars, active |
| [tinysearch](https://github.com/tinysearch/tinysearch) | Rust / WASM | Whitespace tokens only | No | None | Prefix match | 2,975 stars |
| [Simple-Jekyll-Search](https://github.com/christian-fei/Simple-Jekyll-Search) | JS | None; substring scan with `indexOf` | Yes (literal only) | None | None | Archived (2022) |
| [jekyll-algolia](https://github.com/algolia/jekyll-algolia) | Hosted service (paid tiers) | Server-side, dictionary-based | Not documented | Not documented | Algolia's | Deprecated by Algolia; last release 1.7.1 (2021) |

**Note 1 (Pagefind).** [Issue #987](https://github.com/Pagefind/pagefind/issues/987)
asked for substring search for CJK instead of word-based segmentation. It was
closed in April 2026 by
[v1.5.0](https://github.com/Pagefind/pagefind/releases/tag/v1.5.0), which
segments the *query* with `Intl.Segmenter` so that it is split "the same way
the sentence was indexed". Matching is still word-based: it works when the
browser's segmenter and the indexer agree on word boundaries. We have not
measured how often they disagree on Japanese titles.

## Ruby and Jekyll components

| Gem | What it does | Last release |
|---|---|---|
| [itaiji](https://github.com/camelmasa/itaiji) | Variant kanji conversion (`seijitai`: old → new form) | 1.0.0, 2018-01 |
| [moji](http://gimite.net/gimite/rubymess/moji.html) | Full-width/half-width, katakana/hiragana. No old/new kanji | 1.6, 2013-01 |
| [tiny_segmenter](https://github.com/6/tiny_segmenter) | Ruby port of TinySegmenter | 0.0.6, 2015-10 |
| [suika](https://github.com/yoshoku/suika) | Pure-Ruby morphological analyzer (bundled dictionary) | 0.3.3, 2024-12 |
| [jekyll-lunr-js-search](https://github.com/slashdotdash/jekyll-lunr-js-search) | lunr index for Jekyll, English pipeline | 3.3.0, 2017-01 (archived) |
| [bridgetown-quick-search](https://github.com/bridgetownrb/bridgetown-quick-search) | lunr search for Bridgetown; CJK not mentioned | 3.0.3, 2024-07 |
| [jekyll-pagefind](https://github.com/phothinmg/jekykll-pagefind) | Runs the Pagefind binary after a Jekyll build | 0.3.3, 2026-06 (1 star) |

The pieces for Japanese normalization exist in Ruby, but as separate,
mostly unmaintained gems, and none of them reaches the browser side of a
static site. Stock Jekyll search (lunr.js with English defaults) returns zero
results for any CJK query, because lunr's trimmer strips non-`\w`
characters from both ends of each token; see the [README](../README.md).

## What cjk_index does differently

- **Pure Ruby at build time.** No Node, Rust, native extension or hosted
  service is needed to build the index.
- **The same variant tables on both sides.** The browser runtime is generated
  from the Ruby tables, the test suite compares Ruby and JavaScript output
  under Node, and the runtime refuses an index built with other tables.
  Highlighting maps matches back to the original text across variants
  (「帝国大学」 marks 「帝國大學」).
- **Traditional and Simplified Chinese.** Optional table derived from OpenCC.
  We found no other tool in this survey that folds them.
- **Jekyll and CollectionBuilder integration.** A Jekyll generator, with a
  preset that reads CollectionBuilder's own search configuration. Working
  example: https://nakamura196.github.io/cb-ja-demo/compare.html (stock
  search vs. cjk_index on the same data).

## What cjk_index does not have yet

- Index sharding for large sites (Pagefind loads index fragments on demand).
- Filters and facets (Pagefind has filters; CollectionBuilder has its own).
- Benchmarks on large corpora. The runtime size above is measured; index size
  and query time on large sites are not.
- A release on RubyGems.

We do not claim to be the smallest or the fastest. kensaku's runtime is about
23 times larger than ours, but it is a compiled engine and we have not
compared index sizes or query times.
