# Retrieval quality: cjk_index and lunr.js

How often the right records come back, and how often wrong ones do, for
Japanese queries on two real collections. Measured 2026-10-07 on an Apple M4
Max, Ruby 4.0.1, Node 25.6.0.

## What was compared

| engine | what it is |
|---|---|
| cjk_index | this gem: the index is built by the Ruby builder and searched by the browser runtime (`lib/cjk_index/runtime.js`) under Node. `run_cjk_index.rb` also runs the Ruby searcher and stops if the two return different lists; they returned the same lists for all 30 queries. |
| lunr-default | lunr.js 2.3.9 as CollectionBuilder ships it (and as the "default" column of cb-ja-demo's comparison page): English pipeline, `idx.search(query)`. |
| lunr-ja-or, lunr-ja-and | lunr.js 2.3.9 with lunr-languages 1.21.0 `ja` (TinySegmenter, a statistical word segmenter). The query is segmented with the same `lunr.ja.tokenizer` and passed as terms; any term must match (or) or every term (and). |

Without that query segmentation, `idx.search("東京大学")` keeps 東京大学 as one
term, while the records were indexed as 東京 / 大学, so even an exact query
finds nothing. The segmentation of every query is in
`results/*-lunr-segmentation.txt`.

## Collections

- **utokyo**: the 69 records of the cb-ja-demo site (University of Tokyo
  agricultural library and Korean books), with the site's search
  fields and variant tables (`ja`, `zh`). `data/utokyo.jsonl`.
- **aozora**: the 16,951 works of Aozora Bunko
  ([globis-university/aozorabunko-clean](https://huggingface.co/datasets/globis-university/aozorabunko-clean),
  revision 42a9c9c): title, author and the first 200 characters, as in
  `../aozora.rb` catalog mode. Rebuilt by `prepare.py` from the pinned file
  (not committed).

## Queries and judgments

`queries.tsv`: 15 queries per collection. Some are exact (no variant
expected), some need glyph, Simplified/Traditional, kana or iteration-mark
folding, and some are traps built to catch wrong matches:

- **trap-boundary**: the query appears across a word boundary (京都 inside
  東京都; 林学 inside 山林學校)
- **trap-kana**: a katakana word whose hiragana form sits inside other words
  (カメ in 確かめ, カキ in 書き)
- **trap-merge**: 辯 (speech), which the `ja` table folds to 弁 together with
  辨 (distinguish) and 瓣 (petal)

The relevant records were fixed before any engine ran (commit 6153888):

1. `pool.py` collected, for each query, every record containing one of the
   spellings listed by hand in `queries.tsv` (no cjk_index code involved).
2. Each (query, record) pair was judged against the rules in `judging.md`,
   from the contexts in `pools/`, without seeing any engine's output. The
   judging was done by Claude (an LLM; two instances, one per half of the
   pool) and spot-checked by a second reading of 24 random trap pairs.
   1,540 pairs, 1,192 relevant. No judgment was changed after the runs.

A returned record outside the pool counts as a false positive. This
happened once: cjk_index returned aozora 043433 for カキ, through 「聊さかキザ」
(かキ, a spelling the pool did not list), which is not the word カキ.

## Results

Set-based precision (P) and recall (R), summed over the queries
(`results/summary.md` has every query).

| collection | queries | engine | TP | FP | FN | P | R |
|---|---|---|---:|---:|---:|---:|---:|
| utokyo | all 15 | cjk_index | 77 | 4 | 0 | 0.951 | 1.000 |
| | | lunr-default | 0 | 0 | 77 | – | 0.000 |
| | | lunr-ja-or | 48 | 48 | 29 | 0.500 | 0.623 |
| | | lunr-ja-and | 39 | 0 | 38 | 1.000 | 0.506 |
| aozora | all 15 | cjk_index | 1,103 | 345 | 12 | 0.762 | 0.989 |
| | | lunr-default | 0 | 0 | 1,115 | – | 0.000 |
| | | lunr-ja-or | 777 | 7,748 | 338 | 0.091 | 0.697 |
| | | lunr-ja-and | 774 | 10 | 341 | 0.987 | 0.694 |
| aozora | without traps (11) | cjk_index | 792 | 26 | 12 | 0.968 | 0.985 |
| | | lunr-ja-and | 596 | 7 | 208 | 0.988 | 0.741 |
| aozora | exact (2) | cjk_index | 239 | 0 | 0 | 1.000 | 1.000 |
| | | lunr-ja-and | 133 | 3 | 106 | 0.978 | 0.556 |

What this shows:

- **lunr as CollectionBuilder ships it finds nothing** for any Japanese,
  Chinese or Korean query: its trimmer removes every character that is not
  `\w`.
- **Segmentation misses exact matches.** With lunr-ja, 停車場 finds 11 of 116
  records. TinySegmenter splits 停車場 inside sentences (停車 / 場 in 71 of
  the 116 records) but keeps it whole as a query, so the terms differ.
  夏目漱石 and 帝国大学 are split as queries and lose records the same way.
  cjk_index found every exact match.
- **Folding works where the table has the variant**: recall 1.0 for
  鉄道 / 鐵道, 戦争 / 戰爭, 帝国大学 / 帝國大學, 弁当 / 辨當, 实录 / 実録, 农学部 /
  農學部, ぐんぼう / グンボウ, 佐佐木 / 佐々木. lunr-ja finds none of the
  variant-only records.
- **Variants missing from the table are missed.** 證 and 颱 are not in the
  `ja` table, so 証明 missed 3 of 24 (證明) and 台風 missed 9 of 15 (颱風).
  These are the 12 false negatives of cjk_index.
- **Substring matching costs precision on short kana and merged forms.**
  カメ returned 55 records for 4 relevant (確かめ, いかめしい, カメラ); カキ 169
  for 12 (書き, 掻き); ネコ 49 for 29 (ねころぶ, ねんねこ); 辯 216 for 115 (弁当,
  勘弁, 花弁). These 4 queries account for 329 of the 349 false positives.
- **Word boundaries**: 京都 returned the 10 records with 東京都, and 林学 the 4
  with 山林學校 / 農林學校; 気象台風景 matched 台風. lunr-ja, which segments
  東京都 as 東京 / 都, avoided all of these.

## Limits

- The relevant set is defined by the record text (see `judging.md`): a
  record that writes the same word with other characters (猫 for ネコ) is
  outside it, for every engine.
- The judges were an LLM, not people who use these collections, and one
  reading per pair; the notes in `qrels/` say why each 0 was given.
- The queries were chosen by the author of cjk_index, knowing what it folds.
  The trap queries were added to measure its errors, not to be typical.
- Aozora works are literature, not catalog records; only the first 200
  characters are indexed.

## Run it again

```
python3 -I bench/retrieval/prepare.py utokyo <cb-ja-demo>/_data/utokyo-agri.csv
curl -L -o bench/retrieval/cache/aozora.jsonl.gz https://huggingface.co/datasets/globis-university/aozorabunko-clean/resolve/42a9c9c0f1d67e6a5554d9bea4201973dc9b049c/aozorabunko-dedupe-clean.jsonl.gz
python3 -I bench/retrieval/prepare.py aozora bench/retrieval/cache/aozora.jsonl.gz
python3 -I bench/retrieval/pool.py
(cd bench/retrieval && npm ci --ignore-scripts)
ruby -Ilib bench/retrieval/run_cjk_index.rb utokyo
ruby -Ilib bench/retrieval/run_cjk_index.rb aozora
node bench/retrieval/run_lunr.js utokyo > bench/retrieval/results/utokyo-lunr-segmentation.txt
node bench/retrieval/run_lunr.js aozora > bench/retrieval/results/aozora-lunr-segmentation.txt
python3 -I bench/retrieval/evaluate.py
```
