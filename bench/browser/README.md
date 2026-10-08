# Browser measurement

Load and query times of the browser runtime (`runtime.js`) in real browsers,
on the catalog-scale Aozora Bunko indexes of `bench/aozora.rb` (title, author
and the first 200 characters of the text; 1,000, 5,000 and 16,951 works).
The 16,951-work index is the one in the README benchmark table
(61.0 MB, 19.3 MB gzip).

## Steps

From the repository root, with the Aozora data at
`bench/retrieval/cache/aozora.jsonl.gz` (the fixed revision and sha256 given in
`bench/retrieval/prepare.py`):

```
ruby -Ilib bench/browser/build.rb bench/retrieval/cache/aozora.jsonl.gz 1000 5000 16951
zsh bench/browser/run.zsh 5
python3 bench/browser/summarize.py
```

- `build.rb` builds the indexes with the Ruby Builder and records the refs the
  Ruby Searcher returns for each query (`cache/expected-<n>.json`).
- `serve.mjs` serves the page and the index on 127.0.0.1. The index is sent
  pre-compressed with `Content-Encoding: gzip` and `Cache-Control: no-store`,
  so each run downloads the gzip size and decodes it like a deployed site.
- `page.html` measures one load per page: download, `JSON.parse`, and building
  the `Index`. It then runs the 20 queries of `queries.json` (the same as
  `bench/aozora.rb`): 5 trials of 10 searches each, median of the trials.
  Every result list is compared with the Ruby Searcher, order included.
  The page reloads itself for the next run.
- `run.zsh` runs Google Chrome (headless, fresh profile) and Safari (a normal
  window; Safari has no headless mode).

## Results

`results/summary.md`; raw results per run in `results/chrome.json` and
`results/safari.json`.

Measured 2026-10-07 on an Apple M4 Max (macOS 27.0.1), Google Chrome
154.0.8037.98 (headless) and Safari 27.0.1, 5 runs per size. All 600 result
lists (2 browsers × 3 sizes × 5 runs × 20 queries) matched the Ruby Searcher.

## Limits

- The download is from a local server, so it shows the browser's cost of
  receiving and decoding the gzip, not network time. Over a network, add the
  transfer of the gzip size (19.3 MB at 16,951 works).
- Safari rounds `performance.now()` coarsely; with 10 searches per trial,
  query times below 0.1 ms show as 0.
- The JS heap is reported by Chrome only (`performance.memory`, with
  `--enable-precise-memory-info`).
- One machine. Firefox and mobile browsers were not measured.
