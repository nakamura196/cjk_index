# Benchmarks re-measured on v1.1.1 (5db18f4)

Measured 2026-10-28 on an Apple M4 Max, Ruby 4.0.1 (Homebrew, arm64-darwin25),
Node 25.6.0. Same machine, Ruby and Node as the 2026-10-01 / 2026-10-07
measurements, so the comparison is like for like. Each cell is a single run
of the script (as before); query times are the median and the slowest of 20
queries, each the median of 5 runs. Other processes were running on the
machine, so treat the times as +-10-20 %.

Sections: the Aozora Bunko benchmark (`aozora.rb`, compared with
[README.md](README.md), 2026-10-01), retrieval quality (`retrieval/`), and
the browser measurement, re-run the same day with one index file and the
split index (`browser/README.md`, `browser/results/summary.md`).

## 5.1 Aozora Bunko (bench/aozora.rb, single index file, `to_json`)

Data: aozora.jsonl.gz, sha256 3f41359c...d278 (revision 42a9c9c), the same
file as before. Ruby and Node returned the same hit counts for every query.
Format: previous (2026-10-01, v0.1.x) -> v1.1.1.

| mode | works | characters | build | index | gzipped | Ruby memory | Ruby load | Ruby query median / max | Node load | Node query median / max |
|---|---:|---:|---|---|---|---|---|---|---|---|
| catalog | 100 | 0.02 M | 0.1 -> 0.1 s | 0.4 -> 0.2 MB | 0.1 -> 0.1 MB | 33 -> 39 MB | 0.01 -> 0.00 s | 0.01 / 0.14 -> 0.02 / 0.09 ms | 0.01 -> 0.00 s | 0.00 / 0.08 -> 0.00 / 0.05 ms |
| catalog | 1,000 | 0.2 M | 2.2 -> 0.4 s | 3.6 -> 1.6 MB | 1.1 -> 0.9 MB | 87 -> 90 MB | 0.07 -> 0.02 s | 0.04 / 1.34 -> 0.03 / 0.67 ms | 0.06 -> 0.02 s | 0.01 / 0.24 -> 0.01 / 0.12 ms |
| catalog | 5,000 | 1.0 M | 10.6 -> 1.8 s | 17.9 -> 7.0 MB | 5.6 -> 4.0 MB | 228 -> 213 MB | 0.22 -> 0.03 s | 0.16 / 5.73 -> 0.12 / 1.09 ms | 0.26 -> 0.04 s | 0.04 / 0.89 -> 0.02 / 0.44 ms |
| catalog | 16,951 | 3.3 M | 18.9 -> 6.0 s | 61.0 -> 21.8 MB | 19.3 -> 12.9 MB | 621 -> 407 MB | 0.92 -> 0.09 s | 0.66 / 7.69 -> 0.30 / 3.63 ms | 0.69 -> 0.11 s | 0.12 / 2.42 -> 0.07 / 1.23 ms |
| fulltext | 10 | 0.1 M | 0.4 -> 0.1 s | 1.2 -> 0.6 MB | 0.5 -> 0.4 MB | 45 -> 41 MB | 0.02 -> 0.01 s | 0.01 / 0.06 -> 0.02 / 0.04 ms | 0.02 -> 0.01 s | 0.01 / 0.05 -> 0.00 / 0.03 ms |
| fulltext | 100 | 0.7 M | 1.3 -> 0.8 s | 8.6 -> 3.7 MB | 3.4 -> 2.4 MB | 129 -> 82 MB | 0.15 -> 0.02 s | 0.04 / 0.27 -> 0.03 / 0.14 ms | 0.10 -> 0.03 s | 0.03 / 1.46 -> 0.01 / 0.11 ms |
| fulltext | 300 | 1.9 M | 7.6 -> 2.2 s | 23.9 -> 9.5 MB | 9.3 -> 6.4 MB | 250 -> 130 MB | 0.27 -> 0.04 s | 0.09 / 0.85 -> 0.06 / 0.52 ms | 0.27 -> 0.05 s | 0.04 / 0.71 -> 0.02 / 0.43 ms |
| fulltext | 1,000 | 10.4 M | 25.7 -> 12.1 s | 127.6 -> 46.6 MB | 52.3 -> 33.2 MB | 1,018 -> 415 MB | 0.92 -> 0.16 s | 0.45 / 2.65 -> 0.29 / 1.63 ms | 0.87 -> 0.15 s | 0.11 / 2.75 -> 0.07 / 1.75 ms |
| fulltext | 3,000 | 35.6 M | 214.9 -> 43.4 s | 433.9 -> 149.0 MB | 182.6 -> 108.6 MB | 3,036 -> 1,053 MB | 11.13 -> 0.73 s | 1.54 / 29.36 -> 1.02 / 20.74 ms | 5.15 -> 0.95 s | 0.26 / 18.62 -> 0.23 / 7.37 ms |

Raw rows as printed by the script (v1.1.1 only; the script prints the
character count with one decimal, hence 0.0 M for the small rows):

```
| catalog | 100 | 0.0 M | 0.1 s | 0.2 MB | 0.1 MB | 39 MB | 0.00 s | 0.02 / 0.09 ms | 0.00 s | 0.00 / 0.05 ms |
| catalog | 1000 | 0.2 M | 0.4 s | 1.6 MB | 0.9 MB | 90 MB | 0.02 s | 0.03 / 0.67 ms | 0.02 s | 0.01 / 0.12 ms |
| catalog | 5000 | 1.0 M | 1.8 s | 7.0 MB | 4.0 MB | 213 MB | 0.03 s | 0.12 / 1.09 ms | 0.04 s | 0.02 / 0.44 ms |
| catalog | 16951 | 3.3 M | 6.0 s | 21.8 MB | 12.9 MB | 407 MB | 0.09 s | 0.30 / 3.63 ms | 0.11 s | 0.07 / 1.23 ms |
| fulltext | 10 | 0.1 M | 0.1 s | 0.6 MB | 0.4 MB | 41 MB | 0.01 s | 0.02 / 0.04 ms | 0.01 s | 0.00 / 0.03 ms |
| fulltext | 100 | 0.7 M | 0.8 s | 3.7 MB | 2.4 MB | 82 MB | 0.02 s | 0.03 / 0.14 ms | 0.03 s | 0.01 / 0.11 ms |
| fulltext | 300 | 1.9 M | 2.2 s | 9.5 MB | 6.4 MB | 130 MB | 0.04 s | 0.06 / 0.52 ms | 0.05 s | 0.02 / 0.43 ms |
| fulltext | 1000 | 10.4 M | 12.1 s | 46.6 MB | 33.2 MB | 415 MB | 0.16 s | 0.29 / 1.63 ms | 0.15 s | 0.07 / 1.75 ms |
| fulltext | 3000 | 35.6 M | 43.4 s | 149.0 MB | 108.6 MB | 1053 MB | 0.73 s | 1.02 / 20.74 ms | 0.95 s | 0.23 / 7.37 ms |
```

Notes:

- The old "build" (2026-10-01) was the Ruby builder before format 4; the
  "index" size is the JSON text (`json.bytesize`), now format 4 (compact
  posting lists). The old README also lists a "before" build of 8.0 s for
  catalog 16,951 measured on 2026-10-27 with `build.rb` (af5064f); that is a
  different harness (and warm), so the 18.9 s above vs 6.0 s now is not a
  pure code effect. `bench/README.md` shows the 2026-10-27 comparison of the
  same commits.
- Hit counts (stderr, `hits:` lines) are unchanged in kind: Ruby and Node
  agree for all 20 queries at every size (the script aborts otherwise).
- Split index (`write_split`), already measured on 2026-10-27 in
  bench/README.md "Format 4 and split indexes" (not re-measured; Apple M4
  Max, Ruby 4.0.1, Node 25.6, Chrome 156; same code as v1.1.1 for this
  part): one file after format 4 / split with 32,000-byte shards:

  | source | one file, gzip | split: first load (manifest) | split: per query, median / max | requests per query |
  |---|---:|---:|---:|---:|
  | catalog 16,951 | 12.9 MB | 72 KB | 39 / 120 KB | 2 / 6 |
  | fulltext 1,000 | 33.2 MB | 28 KB | 43 / 170 KB | 2 / 6 |
  | fulltext 3,000 | 108.6 MB | 76 KB | 44 / 383 KB | 2 / 6 |
  | blog 1,187 | 6.6 MB | 25 KB | 22 / 133 KB | 1 / 6 |

  The gzipped sizes above agree with this run (12.9, 33.2, 108.6 MB).
  Build with `write_split` (same file): catalog 16,951 5.3 s / 363 MB peak /
  667 files; fulltext 1,000 10.8 s / 269 MB / 1,367 files; fulltext 3,000
  37.0 s / 603 MB / 3,821 files.

## 5.3 Retrieval quality (bench/retrieval/)

Only cjk_index was re-run (utokyo and aozora). `run_cjk_index.rb` reports
that Ruby and runtime.js return the same lists. The lunr runs were also
re-run (`run_lunr.js`): the segmentation output is byte-identical to the
committed `results/*-lunr-segmentation.txt`, so the earlier lunr results
stand. utokyo cjk_index results are identical to before (no diff in
`results/utokyo-cjk_index.tsv`). Only aozora changed.

Previous (v0.1.x, 2026-10-07) -> v1.1.1:

| collection | subset | TP | FP | FN | P | R |
|---|---|---|---|---|---|---|
| utokyo | all 15 | 77 -> 77 | 4 -> 4 | 0 -> 0 | 0.951 -> 0.951 | 1.000 -> 1.000 |
| aozora | all 15 | 1,103 -> 1,106 | 345 -> 345 | 12 -> 9 | 0.762 -> 0.762 | 0.989 -> 0.992 |
| aozora | without traps (11) | 792 -> 795 | 26 -> 26 | 12 -> 9 | 0.968 -> 0.968 | 0.985 -> 0.989 |
| aozora | glyph (6) | 465 -> 468 | 1 -> 1 | 12 -> 9 | 0.998 -> 0.998 | 0.975 -> 0.981 |
| aozora | exact (2) | 239 -> 239 | 0 -> 0 | 0 -> 0 | 1.000 | 1.000 |

The only change: query a06 証明 now returns 24 of the 24 relevant records
(was 21): 043529, 043668, 048215 (證明) are found, because the larger `ja`
table (409 pairs, was 291) folds 證 to 証. a07 台風 still misses the same 9
records (颱風; 颱 is not in the table). The 4 trap queries (カメ, カキ, ネコ,
辯 plus 京都 etc.) return exactly the same lists as before. Per-query
numbers: `bench/retrieval/results/summary.md` (regenerated by
`evaluate.py`; its diff against the committed one is only a06 and the
all/glyph rows above).

### Unjudged pairs (returned by v1.1.1, not in qrels)

Total: **1** pair, in all 30 queries. Per query: utokyo 0; aozora a12 カキ 1;
all others 0. This pair is not new: it was already unjudged in the
2026-10-07 run and is the one the README mentions.

| query | doc | field | context (30 chars before / hit / after) | criterion in judging.md |
|---|---|---|---|---|
| a12 カキ | 043433 | text | たのだ。 　私が、自分から「親友」などと呼びかけるのは、聊さ【かキ】ザだけれど、でも、彼には、あの変屈な金持黒住箒吉には、友だち | "the kana must spell the word itself": かキ here is the tail of 聊さかキザ (an adjective, "somewhat affected"), not 柿 / 牡蠣 / 垣. Looks like rel 0 (a different word), the same call as other kana-inside-word cases (書き, 確かめ). The pool lists カキ|かき only, so this mixed-script spelling (かキ) was not in it. |

Removed (in the previous results, not in v1.1.1): **0**. Added judged pairs
(in qrels, newly returned): 3, all rel=1 (a06: 043668, 048215, 043529).

The many other hits of 台風/ネコ/カメ/カキ/辯 that are false positives
(345) are all judged 0 in qrels; none are new.

Both ways of counting the one unjudged pair (the figures differ in 1 FP):

| subset | counting unjudged as false positive (evaluate.py default) | excluding unjudged |
|---|---|---|
| aozora all 15 | TP 1,106, FP 345, FN 9; P 0.762, R 0.992 | TP 1,106, FP 344, FN 9; P 0.763, R 0.992 |
| aozora without traps (11) | P 0.968, R 0.989 (no unjudged here) | same |

(The 043433 pair belongs to the カキ query, a trap query.) So the choice
does not change the reported figures at three decimals, except 0.762 vs
0.763 for the all-15 precision. If 043433 is judged 0 (as expected), the
default figures stand.

## Commands run

```
git checkout v1.1.1                                # a checkout of the tag
# bench/retrieval/cache/aozora.jsonl{,.gz} as in bench/retrieval/README.md
(cd bench/retrieval && npm ci --ignore-scripts)
export PATH=/opt/homebrew/opt/ruby/bin:$PATH      # Ruby 4.0.1 (system Ruby is 2.6)
for each of: catalog 100|1000|5000|16951, fulltext 10|100|300|1000|3000:
  ruby -Ilib bench/aozora.rb bench/retrieval/cache/aozora.jsonl.gz <mode> <count>
ruby -Ilib bench/retrieval/run_cjk_index.rb utokyo
ruby -Ilib bench/retrieval/run_cjk_index.rb aozora
node bench/retrieval/run_lunr.js {utokyo,aozora} > <elsewhere>   # identical to the committed segmentation txt
python3 -I bench/retrieval/evaluate.py
ruby -Ilib bench/browser/build.rb bench/retrieval/cache/aozora.jsonl.gz 1000 5000 16951
zsh bench/browser/run.zsh 5
python3 bench/browser/summarize.py
```

The unjudged / removed lists and the two-way P/R were computed with a
throwaway script (not in the repo) from `results/*.tsv` and `qrels/*.tsv`;
contexts are located with the gem's own normalizer (so folded matches are
found), 30 characters either side.
