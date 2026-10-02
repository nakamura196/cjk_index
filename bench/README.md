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
