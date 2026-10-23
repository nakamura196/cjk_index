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

## 2026-10-22: trying 0.2 on cb-ja-demo

Branch `cjk-index-0.2` of cb-ja-demo (from its main at b93088f, not
committed), with the Gemfile pointing at this worktree (`path:`, mounted into
the Docker build). `_config.yml` unchanged: the `collectionbuilder` preset
with its default filters.

- The build passes and writes `cjk_index/3` with filters era (6 values),
  type (2), creator (15) and date (year). Index 176,838 → 178,743 bytes;
  gzipped 44,148 → 44,798 (+650 bytes) for 69 records.
- Year from `date`: 32 of the 36 records with a date. The four without one
  are bracketed era notes (`[明治期]`, `[書写年不明]`). The demo also has a
  `year` column, filled for 12 records that have no `date` (the Veritable
  Records); the default filter does not read it, so those 12 drop out of any
  year range. A site with such a column sets `filters:` itself.
- `;` as separator splits creators as the item pages show them
  (白澤保美編著 ; 丸山宣光,大石榮雄畫 → two values). Commas are not split, so
  `田中芳男, 小野職愨撰` stays one value. Two spellings of one body
  (`農商務省山林局 [編纂]`, `農商務省山林局編纂`) are two values: whole-value
  matching does not hide catalog inconsistencies.
- Search page (the demo's `_includes/js/lunr-js.html`): facet buttons with
  counts for each filter, a year range, and a clear button, built only from
  the index (no item scan). Counts for a field are taken as if nothing were
  chosen in that field, so its other values stay selectable (one extra
  search per field; instant at this size). A blank query with a choice lists
  the matching items; the facets show before any query.
- Checked in headless Chrome (review/tools/cjk-02-facets.mjs, ja and /en/
  built as in the demo's CI): 明治 → 10, 明治 or 大正 → 29, 地図 → 3,
  森林 → 13, 森林 with 1890–1910 → 2; English page, 実録 → 12. No console
  errors.
- Found while building the page: redrawing the whole facet area on each
  change also redrew the year inputs and lost a year being typed. The year
  inputs are now made once and only the value lists are redrawn.

Not tried: the browse page (CollectionBuilder's own script still scans the
items there), and the mobile layout of the facet buttons.

## 2026-10-22: the browse page on the index

Same branch of cb-ja-demo, still not committed. The facet code of the search
page moved to one include (`_includes/js/cjk-facets-js.html`) that both pages
use; the facets it shows are now the value filters of the index itself (in
index order, labels from `config-metadata`), not the list in
`metadata-facets-fields`, so a site that sets `filters:` gets its own.

- Browse page (`_includes/js/browse-js.html`): the same buttons with counts,
  a year range and a clear button. The text box and the advanced search still
  scan the items as before (CollectionBuilder's own code, with
  `CJKIndex.includes`); the facets narrow what they give, and their counts are
  taken over that list. An item is matched to the index by its ref
  (`objectid.html`, or `parent.html#objectid`).
- Links into the browse page (`#era:明治` from an item page, the card tags,
  the home page chips) now choose that value in the index: whole value,
  folded (old/new kanji, width), instead of a substring scan. A single choice
  is written back to the hash, so the page can be linked; more than one
  choice, or a year, clears a facet hash rather than leave a wrong one.
- The browse page now fetches the index (178,743 bytes, 44,798 gzipped) and
  waits for it before the first list, so a facet link is read as one. If the
  fetch fails, the page lists as before and links fall back to the substring
  scan (checked by blocking the request: `#era:明治` → 10, no facets).
- Checked in headless Chrome (review/tools/cjk-02-browse.mjs): all 60 items;
  明治 → 10 (hash `#era:明治`), 明治 or 大正 → 29 (hash cleared); link
  `#creator:農商務省山林局編纂` → 1, the other spelling not included; text
  森林 → 13, with 明治 → 2; year 1890–1910 → 10, kept after sorting by title;
  advanced search type contains 地図 → 3, with 大正 → 1; English page link
  `#era:明治` → 10. The search page test (cjk-02-facets.mjs) gives the same
  numbers as before the move. No console errors.
- On this data the whole-value match gives the same lists as the old
  substring scan: no era or creator here is part of another. The difference
  shows only where one value contains another (明治 and 明治以前).

Not tried: the mobile layout, and the delay on a slow connection before the
first list.

## 2026-10-22: the facets at phone width

Checked in headless Chrome at 375×812, 360×740 and 320×568, ja and en, browse
and search (review/tools/cjk-02-mobile.mjs, screenshots `m-*.png`).

- Nothing runs past the right edge (scroll width = viewport width at all
  three); long creator names wrap onto their own line. No console errors.
- The block is tall: 591–709 px (11–14 rows of buttons, the creator facet
  alone 16 values). On the browse page the first item starts at 987 px at
  375×812 and 1,092 px at 320×568, so the first screen shows only the search
  box and facets.
- The result count (`#numberOf`) sits below the block, so after tapping a
  button on a phone nothing visible changes except the button itself.
- Buttons are 31 px high: above the WCAG 2.2 minimum (24 px), below the
  44 px that Apple's guidelines suggest.

Not done yet: a fix. Candidates are folding the block on narrow screens, or
showing the first few values of a long facet with a "more" button.

## 2026-10-22: folding the facets on a phone

Below Bootstrap's md breakpoint (768 px) the facet block is now closed behind
a "絞り込み / Refine" button (`aria-expanded`), with a badge giving how many
filters are on (values plus the year range as one). Opened, it ends with a
"結果を見る / Show results" button that closes it and scrolls to the count
(browse) or the results (search). From md up nothing changes. All of it is in
the shared include, so both pages get it; one new locale string
(`facet_done`).

Rejected: showing only the first few values of a long facet with a "more"
button. It shortens the block but leaves it in front of the list, and the
count would still be off screen after a tap.

- Phone (cjk-02-mobile.mjs, 375/360/320, ja and en, browse and search):
  closed block 39 px; on the browse page the first item moves from 987 px to
  422 px at 375×812. Open, choose 明治, Show results: count on screen (top 0)
  in all 12 cases, badge 1, block closed; 10 items / 10 results. Opened, the
  block is 642–760 px, nothing past the right edge.
- Desktop (1280): cjk-02-browse.mjs and cjk-02-facets.mjs give the same
  numbers as before. No console errors.
- Rebuilt with `ruby:3.4` in Docker, both configs as in the demo's CI.

Still open: the button height (31 px), and the delay on a slow connection.

## 2026-10-22: the first list on a slow connection

The browse page now waits for the index before its first list. Measured how
much that costs (review/tools/cjk-02-slow.mjs): headless Chrome, 375×812, no
cache, Chrome DevTools network presets, median of 5. The site was served
gzipped, as GitHub Pages does (index 44,786 bytes on the wire), by a small
local server that also serves `browse-nowait.html`: the same page with
`initBrowse()` called at once, as before the change. "First list" is the first
card in `#browseItems`, from navigation start.

| connection | wait for index (now) | list first (before) | index blocked |
|---|---|---|---|
| no throttling | 0.26 s | 0.28 s | 0.29 s |
| Fast 3G | 6.09 s | 6.09 s | 5.87 s |
| Slow 3G | 21.74 s | 21.74 s | 20.86 s |
| Fast 3G, CPU ×4 | 6.16 s | 6.15 s | 5.96 s |

- Waiting for the index costs nothing: the before and after columns are the
  same to 0.01 s. The index arrives before the page's `load` event (Fast 3G:
  5.89 s, list at 6.09 s), and CollectionBuilder has always drawn the list on
  `load`, not on DOMContentLoaded (2.78 s).
- What holds `load` back is the Japanese web font. With the index blocked,
  Fast 3G: the page's own files are in by 1.9 s, the Google Fonts CSS
  (~180 KB) by 2.8 s, then about 20 Noto Sans JP subset files (~460 KB) until
  5.87 s. More font files and the IIIF thumbnails start only after the list.
- The index does cost its download either way: 0.2 s on Fast 3G, 0.9 s on
  Slow 3G (the "index blocked" column), because it shares the connection with
  the fonts. That is the price of fetching it on this page at all, not of
  waiting for it.
- CPU ×4 adds under 0.1 s: building the facets and 60 cards is not the cost.
- All runs: 60 cards, no page errors.

Not tried: drawing the list on DOMContentLoaded instead of `load`, or
loading the font without holding `load`. That is a CollectionBuilder (or
theme) change, not cjk_index's. How much it would gain is not measured: the
index itself is fetched only after DOMContentLoaded and shares the line with
the fonts (it arrived at 5.89 s on Fast 3G), so waiting for it would then
start to matter.

## 2026-10-22: the cb-ja-demo trial committed

The entries above that say "not committed" are now on branch `cjk-index-0.2`
of cb-ja-demo: 3f41aba (search page facets and the shared include), 5bcfd75
(browse page), e5b6b39 (Gemfile pointing at this worktree; trial only, to be
replaced with the released gem before it goes to main).
