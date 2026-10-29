# Browser measurement

Load and query times of the browser runtime (`runtime.js`) in real browsers,
on the catalog-scale Aozora Bunko indexes of `bench/aozora.rb` (title, author
and the first 200 characters of the text; 1,000, 5,000 and 16,951 works),
both as one index file and as a split index (`Builder#write_split`).
The 16,951-work index is the one in the benchmark table of
`../RESULTS-1.1.1.md` (21.8 MB, 12.9 MB gzip).

## Steps

From the repository root, with the Aozora data at
`bench/retrieval/cache/aozora.jsonl.gz` (the fixed revision and sha256 given in
`bench/retrieval/prepare.py`):

```
ruby -Ilib bench/browser/build.rb bench/retrieval/cache/aozora.jsonl.gz 1000 5000 16951
zsh bench/browser/run.zsh 5
python3 bench/browser/summarize.py
```

- `build.rb` builds the indexes with the Ruby Builder, writes each one also
  as a split index (`split-<n>/`, and gzipped in `split-<n>-gz/`), and records
  the refs the Ruby Searcher returns for each query (`cache/expected-<n>.json`).
- `serve.mjs` serves the page and the index on 127.0.0.1. The index files are
  sent pre-compressed with `Content-Encoding: gzip` and `Cache-Control:
  no-store`, so each run downloads the gzip size and decodes it like a
  deployed site. With `--split` it serves the split index instead.
- `page.html` measures one load per page: download, `JSON.parse`, and building
  the `Index` (for the split index, of the manifest only). It then runs the
  20 queries of `queries.json` (the same as `bench/aozora.rb`): 5 trials of
  10 searches each, median of the trials. For the split index, each query
  first runs `searchAsync` on a fresh `Index`, so it fetches the shards it
  needs as the first search on a page does; that first search is timed, and
  the bytes and requests it fetched are counted. Every result list is
  compared with the Ruby Searcher, order included. The page reloads itself
  for the next run.
- `run.zsh` runs Google Chrome (headless, fresh profile) and Safari (a normal
  window; Safari has no headless mode), each with one index file and then
  with the split index. `zsh bench/browser/run.zsh 5 chrome` runs Chrome only.

## Results

`results/summary.md`; raw results per run in `results/<browser>.json` (one
index file) and `results/<browser>-split.json` (split index).

Measured 2026-10-28 with cjk_index 1.1.1 on an Apple M4 Max (macOS 27.2),
Google Chrome 156.0.8078.73 (headless) and Safari 27.2, 5 runs per size.
All 1,200 result lists (2 browsers × 2 layouts × 3 sizes × 5 runs × 20
queries) matched the Ruby Searcher. At 16,951 records:

- one file (12.9 MB gzip): load 127 ms in Chrome, 122 ms in Safari; query
  max 0.8 ms (Chrome) and 0.5 ms (Safari); JS heap 173 MB (Chrome)
- split: manifest 72 KB, load 3–4 ms; first search of a query, shards
  included, median 1.2 / max 2.8 ms (Chrome) and 2.0 / 5.0 ms (Safari);
  fetched per query median 37 KB, max 120 KB, in 2 to 6 requests

Earlier measurements, kept for comparison:

- 2026-10-07, 0.1.x, Chrome 154.0.8037.98 and Safari 27.0.1, one
  file only: at 16,951 records the index was 19.3 MB gzip, load 545 ms
  (Chrome) and 335 ms (Safari), JS heap 338 MB. The results files of that
  run are in the git history of `results/`.
- 2026-10-28, format 4: `results/chrome-v3.json` and `results/chrome-v4.json`
  are the same measurement in Google Chrome 156.0.8078.73 (headless, 5 runs
  per size), with indexes built by the commit before format 4 (af5064f) and
  by format 4. Run with `node bench/browser/serve.mjs chrome-v4 5 1000 5000
  16951` and Chrome opened on the page as in run.zsh. At 16,951 records:
  load 275 → 142 ms (download 133 → 81, parse 116 → 38), JS heap 344 → 136
  MB, query median / max 0.04 / 0.82 → 0.04 / 0.83 ms; every result list
  matched the Ruby Searcher. summarize.py does not read these two files.

## Limits

- The download is from a local server, so it shows the browser's cost of
  receiving and decoding the gzip, not network time. Over a network, add the
  transfer: 12.9 MB for one file at 16,951 works, tens of KB per query for
  the split index.
- Safari rounds `performance.now()` coarsely; with 10 searches per trial,
  query times below 0.1 ms show as 0.
- The JS heap is reported by Chrome only (`performance.memory`, with
  `--enable-precise-memory-info`).
- One machine. Firefox and mobile browsers were not measured.
