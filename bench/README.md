# Benchmarks

## Aozora Bunko

[aozora.rb](aozora.rb) indexes works from Aozora Bunko (public-domain Japanese
literature) and times queries in Ruby and in the browser script (under Node).
The data is [globis-university/aozorabunko-clean](https://huggingface.co/datasets/globis-university/aozorabunko-clean)
(16,951 works). See the script for how to download it and run it.

- **catalog**: title, author and the first 200 characters of each work, like
  the records of a collection site
- **fulltext**: title, author and the whole text

Measured 2026-10-01 on an Apple M4 Max with Ruby 4.0.1 and Node 25.6.
Query times are the median and the slowest of 20 queries (each the median of
5 runs). Ruby and Node returned the same number of hits for every query.

| mode | works | characters | build | index | gzipped | Ruby memory | Ruby load | Ruby query (median / max) | Node load | Node query (median / max) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| catalog | 100 | 0.02 M | 0.1 s | 0.4 MB | 0.1 MB | 33 MB | 0.01 s | 0.01 / 0.14 ms | 0.01 s | 0.00 / 0.08 ms |
| catalog | 1,000 | 0.2 M | 2.2 s | 3.6 MB | 1.1 MB | 87 MB | 0.07 s | 0.04 / 1.34 ms | 0.06 s | 0.01 / 0.24 ms |
| catalog | 5,000 | 1.0 M | 10.6 s | 17.9 MB | 5.6 MB | 228 MB | 0.22 s | 0.16 / 5.73 ms | 0.26 s | 0.04 / 0.89 ms |
| catalog | 16,951 | 3.3 M | 18.9 s | 61.0 MB | 19.3 MB | 621 MB | 0.92 s | 0.66 / 7.69 ms | 0.69 s | 0.12 / 2.42 ms |
| fulltext | 10 | 0.1 M | 0.4 s | 1.2 MB | 0.5 MB | 45 MB | 0.02 s | 0.01 / 0.06 ms | 0.02 s | 0.01 / 0.05 ms |
| fulltext | 100 | 0.7 M | 1.3 s | 8.6 MB | 3.4 MB | 129 MB | 0.15 s | 0.04 / 0.27 ms | 0.10 s | 0.03 / 1.46 ms |
| fulltext | 300 | 1.9 M | 7.6 s | 23.9 MB | 9.3 MB | 250 MB | 0.27 s | 0.09 / 0.85 ms | 0.27 s | 0.04 / 0.71 ms |
| fulltext | 1,000 | 10.4 M | 25.7 s | 127.6 MB | 52.3 MB | 1,018 MB | 0.92 s | 0.45 / 2.65 ms | 0.87 s | 0.11 / 2.75 ms |
| fulltext | 3,000 | 35.6 M | 214.9 s | 433.9 MB | 182.6 MB | 3,036 MB | 11.13 s | 1.54 / 29.36 ms | 5.15 s | 0.26 / 18.62 ms |

What this shows:

- Queries stay fast at every size: a few milliseconds at most up to 10 M
  characters, in Ruby and in the browser script.
- The limit is the size of the index. A single index file is fine for a
  collection's records (about 1 MB gzipped for 1,000 records), but the
  index grows to roughly 5 bytes gzipped per character of text. A browser
  cannot download one 50 MB file for 1,000 full texts. This is why the index
  needs to be split into shards that a browser loads only as a query needs
  them, with a more compact encoding of positions.
- Building and loading slow down faster than the text grows (3.4 times the
  text from 1,000 to 3,000 works took 8 times as long to build), and Ruby's
  memory reaches 3 GB at 36 M characters. The current builder keeps
  everything in Ruby hashes and writes one JSON document.

## Format 4 and split indexes (2026-10-27)

Index format `cjk_index/4` writes each posting list as a compact string
(gaps, written in printable characters), and `Builder#write_split` cuts the
index into a manifest and shards that the browser fetches as a query needs
them (`searchAsync`). The Builder keeps the lists in that form while it
builds. The table above is kept as measured on 2026-10-01; the tables
below compare the commit before these changes (af5064f, "before") with this
branch ("after"), run on the same day on the same Apple M4 Max (Ruby 4.0.1,
Node 25.6, Chrome 156). Details, rejected options and what is not checked:
[docs/notes/scaling.md](../docs/notes/scaling.md).

Sources ([corpus.rb](corpus.rb)): the Aozora records as above, and a blog:
1,187 Japanese posts of the author's technical blog (Markdown, 5.2 M
characters; title, tags, body). Only the numbers are in this repository.

Build ([build.rb](build.rb); peak memory of the whole process, texts
included; gzip -9):

| source | before: build, peak memory, gzip | after, one file (`write`) | after, split (`write_split`) |
|---|---|---|---|
| catalog 16,951 | 8.0 s, 531 MB, 19.3 MB | 5.0 s, 349 MB, 12.9 MB | 5.3 s, 363 MB, 13.2 MB, 667 files |
| fulltext 1,000 | 17.1 s, 839 MB, 52.3 MB | 10.7 s, 260 MB, 33.2 MB | 10.8 s, 269 MB, 33.4 MB, 1,367 files |
| fulltext 3,000 | 61.5 s, 2,335 MB, 182.6 MB | 36.8 s, 563 MB, 108.6 MB | 37.0 s, 603 MB, 109.5 MB, 3,821 files |
| blog 1,187 | 5.6 s, 214 MB, 9.6 MB | 2.4 s, 120 MB, 6.6 MB | 2.4 s, 133 MB, 6.9 MB, 319 files |

What a browser fetches ([split.rb](split.rb), default 32,000-byte shards;
each of the 20 queries of the source on a freshly loaded page; gzip). Ruby
and the browser script returned the same results for every query.

| source | one file, before | one file, after | split: first load (manifest) | split: per query, median / max | requests per query |
|---|---:|---:|---:|---:|---:|
| catalog 16,951 | 19.3 MB | 12.9 MB | 72 KB | 39 / 120 KB | 2 / 6 |
| fulltext 1,000 | 52.3 MB | 33.2 MB | 28 KB | 43 / 170 KB | 2 / 6 |
| fulltext 3,000 | 182.6 MB | 108.6 MB | 76 KB | 44 / 383 KB | 2 / 6 |
| blog 1,187 | 9.6 MB | 6.6 MB | 25 KB | 22 / 133 KB | 1 / 6 |

Loading and querying one file ([aozora.rb](aozora.rb), before → after):

| mode | gzip | Ruby memory | Ruby load | Ruby query (median / max) | Node load | Node query (median / max) |
|---|---|---|---|---|---|---|
| catalog 16,951 | 19.3 → 12.9 MB | 655 → 409 MB | 0.48 → 0.08 s | 0.30 / 3.55 → 0.29 / 3.38 ms | 0.29 → 0.11 s | 0.06 / 1.01 → 0.07 / 1.43 ms |
| fulltext 1,000 | 52.3 → 33.2 MB | 1,072 → 424 MB | 1.18 → 0.15 s | 0.29 / 1.72 → 0.28 / 1.66 ms | 0.48 → 0.17 s | 0.06 / 1.37 → 0.08 / 1.83 ms |
| fulltext 3,000 | 182.6 → 108.6 MB | 3,095 → 1,022 MB | 3.26 → 0.27 s | 0.81 / 5.49 → 0.82 / 5.85 ms | 1.39 → 0.40 s | 0.13 / 5.12 → 0.19 / 5.31 ms |

In Chrome ([browser/](browser/), 16,951 records, 5 runs): load 275 → 142 ms,
JS heap 344 → 136 MB, queries unchanged (median 0.04 ms, max 0.8 ms).

What this shows:

- The compact encoding alone makes an index about a third smaller gzipped,
  and three times smaller before compression, which is what parsing and
  memory see.
- With a split index, the first load is the manifest (refs, lengths,
  filters: tens of KB), and a query fetches tens of KB whatever the size of
  the collection. A query with a very common bigram in full text fetches
  its whole list (the max column).
- Building uses a quarter of the memory for full text, and its time now
  grows linearly with the text.
- Updating a loaded index got slower in places (removing or inserting a
  document walks the encoded lists in Ruby): see bench/updates.rb in the
  notes. One update and its write in `IndexFile` costs about the same as
  before.

## Puma workers

[puma/](puma/) serves a small Rack app with `puma -w 4` and checks that
`CJKIndex::IndexFile` keeps the workers in step while records are added and
searched at the same time: no add is lost, no worker reads a partly written
file, and how long a worker may answer from the previous index. See
[puma/run.rb](puma/run.rb) for how to run it, and the entry "Puma with four
workers" in [docs/notes/filters-and-updates.md](../docs/notes/filters-and-updates.md)
for the results.
