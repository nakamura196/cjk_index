# 0.2: filters and index updates

Lab notes for item 1 of the plan ("Filters and index updates", Oct–Nov 2026).
Entries are dated and appended; earlier entries are not rewritten.

## 2026-10-22: plan and design

### Goal

- Filter search results by structured fields (type, creator, date), in Ruby
  and in the browser, so that collection sites can combine CJK search with
  their facets. Filter without a query, for browse pages. Count values for
  facet lists.
- Remove and replace documents in a Ruby index without rebuilding it, and
  update an index file that was written earlier.

### Starting point

- The index (`cjk_index/2`) holds only the postings of the searchable fields.
  It has no field values to filter on.
- cb-ja-demo filters in CollectionBuilder's own browse script, which scans
  every item (`_includes/js/browse-js.html`). The fields come from
  `metadata-facets-fields` in `_data/theme.yml` (era, type, creator in the
  demo); values are separated by `;`.
- `Builder` can only add. `Searcher.new(builder)` copies `builder.to_h`, so it
  does not see later changes.
- Baseline for updates: rebuilding the Aozora Bunko catalog index (16,951
  records) takes 18.9 s, and loading it into `Searcher` 0.92 s
  (bench/README.md, 0.1.1).

### Design

Format `cjk_index/3`: version 2 plus an optional `filters` object. Readers
accept both versions, so existing sites can upgrade the script without
rebuilding their index.

```json
"filters": {
  "type": { "kind": "value", "values": ["地図", "写真"], "docs": [[0], [0, 1], [], [1]] },
  "date": { "kind": "year", "docs": [1900, null, 1923, 1931] }
}
```

- `value`: exact match on the whole value, after the same folding as search
  (old/new kanji, katakana/hiragana, width) and with whitespace collapsed.
  Distinct values are stored once (`values`, in order of first appearance,
  as first written) and documents refer to them by number. A list in the
  condition matches any of its values.
- `year`: the first four-digit number in the value (`1900-01-01` → 1900).
  Conditions are inclusive ranges. Japanese era dates (明治33年) give no year
  in 0.2; converting them is left for later.
- Conditions on different fields must all hold. Scores are computed over the
  whole index, as without a filter, so a filter never changes the order of
  the documents it keeps.
- A blank query with a filter returns every document that passes it, in index
  order (for browse pages). A blank query without a filter still returns
  nothing.

Updates (Ruby only; a browser loads a finished index):

- `Builder#remove(ref)` and `Builder#update(ref, doc)`; `update` keeps the
  document's place. `Builder.load(json)` reads a written index back.
- Test: after any sequence of adds, removes and updates, `to_h` must equal
  the index built from scratch from the final documents in the same order.
  Together with the existing Ruby–JavaScript parity tests, this means an
  updated index answers exactly like a rebuilt one.
- `Searcher.new(builder)` sees later changes to the builder.

Rejected:

- Storing filter values as tokens in the postings: range conditions would
  need one token per year, and filter-only queries would have to merge every
  posting list.
- Marking removed documents as deleted and keeping them in the index: BM25
  counts (number of documents, average length) would drift from a rebuilt
  index, and the parity test above would no longer hold.
- Updates in the browser runtime: no use case; static sites rebuild.

### Schedule

| week | work |
|---|---|
| 10/26–11/1 | 0.1.1 tag on main; design issue for the mentor |
| 11/2–11/8 | filters in Ruby and the browser, parity tests |
| 11/9–11/15 | filter-only queries, year ranges, facet counts; Jekyll options and the CollectionBuilder preset; demo on a branch |
| 11/16–11/22 | remove/update/load and the rebuild-equality test |
| 11/23–11/30 | benchmarks, documentation, release 0.2.0, articles (ja/en) and video |

To measure for the release: time to update one record against the 18.9 s
rebuild; growth of the index file with filters (Aozora by author, demo by
era/type/creator).

## 2026-10-22: first implementation and measurements

Filters, facets, remove/update/load and the Jekyll options are on branch
`v0.2`. Tests: 47 runs, 728 assertions, all passing (Ruby 4.0.1, Node).

Rebuild-equality test: 20 seeds × 60 random adds, removes and updates over
15 refs, with value and year filters; `to_h` equals a fresh build each time.
Checked that the test catches faults by breaking the builder on purpose:
not sorting renumbered postings fails it; keeping empty posting lists fails
it; keeping a removed document's filter values does not (the searcher never
reads removed slots, so results cannot differ).

`bench/updates.rb` on the Aozora catalog records (16,951; title, author,
first 200 characters), MacBook, Ruby 4.0.1:

| step | time |
|---|---:|
| full build | 11.0 s |
| update one record in a builder | 98 ms |
| remove one record | 114 ms |
| `Builder.load` of the written index | 0.70 s |
| first update after load (scans the postings once) | 1.05 s |
| later updates after load | 92 ms |
| write the index again (`to_json`) | 6.39 s |
| first search after an update (searcher refreshes) | 65 ms |
| search without changes (東京) | 2.3 ms |
| filter only (author = 夏目漱石, 112 hits) | 3.7 ms |
| search with filter (東京, year 1900–1920) | 1.3 ms |
| facet counts over all records (author) | 5.2 ms |

- The full build took 18.9 s in the 0.1.1 benchmarks and 11.0 s here; same
  data, so the machine or its load differs. Compare within one run.
- Filters on author (953 values), kana usage (5) and year add 0.2 MB to the
  61.0 MB index, 0.1 MB gzipped.
- Year from 底本初版発行年1 (e.g. 1957（昭和32）年5月20日): found for 16,932
  of 16,951 records.
- Updating in memory is about 100 times faster than rebuilding. Writing the
  file again is not: `to_json` after changes takes 6.4 s, because every
  posting list is renumbered and re-sorted. To look at before 0.2: only
  posting lists that changed need sorting, and renumbering is needed only
  when a document was removed.
- An update costs about 0.1 s mainly because removing a document rewrites
  the posting lists of each of its tokens, including very common unigrams.

Not checked yet: the browser side with a real site (cb-ja-demo on a branch),
memory use of the builder with token lists kept per document.

## 2026-10-22: writing an updated index

`to_json` after changes took 6.4 s, against 0.7 s for a fresh build
(`to_h` 0.5 s, `JSON.generate` 0.2 s). Timing the parts on the Aozora
catalog showed where the time went: the old `to_h` cut every posting list
into entries, renumbered them and sorted them again, even after a single
update.

First attempt: remember which tokens an update touched and sort only those
lists in `to_h`. Renumbering after a remove became a plain pass over the
document numbers (the numbering keeps the order, so sorted lists stay
sorted). `to_h` after a remove went from 3.8 s to 1.3 s, but after one
update it was still 3.1 s: an update touches common unigrams (の, に, …),
whose lists cover most documents, and sorting those is the slow part.
Rejected for that reason.

Kept: `update` inserts the new entries at their place in each list instead of
appending them, so the lists are always in the order a fresh build writes and
`to_h` never sorts entries. Finding the place walks the list once, as
removing the old entries already does.

`bench/updates.rb`, old and new code back to back on the same machine
(16,951 records):

| step | before | after |
|---|---:|---:|
| update one record | 126 ms | 122 ms |
| later updates after load | 110 ms | 115 ms |
| `to_json` after updates | 10.08 s | 0.62 s |
| `to_json` after a remove as well | 11.45 s | 1.23 s |

Times vary between runs (the full build took 8.8 s here, 11.0 s in the
earlier entry, where `to_json` took 6.4 s); compare within one run.

- Writing after updates now costs the same as writing a fresh index. With a
  remove, renumbering still walks every list once (about 0.6 s).
- The rebuild-equality test catches the fault: with insertion turned off
  (always append), it fails.
- Updates cost no more than before; the extra walk is within the noise.
