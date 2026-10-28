# 0.2: variant tables

Lab notes for item 2 of the plan ("Variant tables checked against expert
sources"). Entries are dated and appended; earlier entries are not rewritten.

## 2026-10-27: sources, rules and counts

### Goal

- Extend the Japanese table beyond the 291 hand-written pairs of 0.1, from
  official or scholarly sources whose terms allow redistribution in an MIT gem.
- Review the Chinese table (OpenCC-derived) for merges that are wrong in some
  contexts (後/后).
- Hangul: check precomposed vs. conjoining jamo; handle old Hangul written in
  the Private Use Area, which occurs in the demo data.
- Keep the tables as plain TSV that other programs can read, and regenerable.

### Sources (as verified on 2026-10-27)

| Source | Version | Where | Terms (checked at the primary source) |
|---|---|---|---|
| 常用漢字表 (Joyo Kanji Table), Cabinet Notice No. 2 | 2010-11-30 | https://www.bunka.go.jp/kokugo_nihongo/sisaku/joho/joho/kijun/naikaku/kanji/ | Official notice; not subject to copyright (Copyright Act art. 13) |
| 人名用漢字, 戸籍法施行規則 (Family Register Act Enforcement Regulations) appended table 3 (別表第三; was 別表第二) | 2010, amended 2015, 2017, 2026 | e-Gov law 322M40000010094 | Ministerial ordinance; art. 13. The kanji lists are images in e-Gov, not text |
| Unicode Han Database (Unihan), UAX #38 rev. 41 | Unicode 18.0.0 (files dated 2026-07-31) | https://www.unicode.org/Public/18.0.0/ucd/Unihan.zip, SHA-256 4c93ea9c… | Unicode License v3 (https://www.unicode.org/license.txt), OSI-approved; notice in LICENSE-Unicode |
| OpenCC TSCharacters.txt, STCharacters.txt | commit 2939943b | https://github.com/BYVoid/OpenCC | Apache-2.0 (LICENSE-OpenCC, as in 0.1) |
| hypua crate table, by kiwiyou | commit 7e47655 (2020-03-29), crate 0.2.0 | https://github.com/kiwiyou/hypua | Unlicense (public domain dedication) |
| hypua2jamo, by mete0r (used only to cross-check) | 0.7 (PyPI) | https://github.com/mete0r/hypua2jamo | LGPL-3.0-or-later; "based on KTUG Hanyang PUA Table Project" |
| KTUG Hanyang PUA Table Project | completed c. 2006–2008; page archived 2024-10-12 | http://faq.ktug.org/faq/HanyangPuaTableProject (server down since 2024-12-07; read via web.archive.org) | No license stated on the page |
| 文字情報基盤 MJ縮退マップ (IPA / 文字情報技術促進協議会) | Ver. 1.2.0 | https://moji.or.jp/mojikiban/map/ | CC BY-SA 2.1 JP — **not used** (see below) |

Unihan carries the official lists as machine-readable fields, which is why it
is used for them: `kJapaneseOldVariant` (the bracketed old forms of the Joyo
Kanji Table, 364 pairs), `kJoyoKanji` with a code point (the JIS X 0208 form of
the 4 kanji whose Joyo form is JIS X 0213-only: 剝, 𠮟, 塡, 頰), and
`kJinmeiyoKanji` with a code point (230 variant links of the Jinmeiyo list:
part 2 "old forms of Joyo kanji" plus the pairs joined by "―" in part 1, which
the regulation glosses as "相互の漢字が同一の字種"). `kZVariant` (180 directed
links; "the same abstract shape encoded multiple times ... identical
semantics", UAX #38) covers characters outside both lists.

### Rules

Japanese (`ja`, default): fold when a source says the two are one character
(字種): Joyo brackets, Joyo two forms, Jinmeiyo links, kZVariant, and 19
hand-written glyph variants kept from 0.1 (`data/src/ja-extra.tsv`).
Each class folds to one member, preferring: the JIS X 0208 form of a Joyo
kanji (剥 over 剝) > a Joyo kanji > a 0.1 target > a Jinmeiyo kanji that is
not itself a variant > a JIS X 0208 character > the rest; ties by code point.
So the folded form of every 0.1 pair is unchanged. Entries whose source is a
compatibility ideograph are left out: NFKC runs first and they never reach
the table.

Dropped from 0.1: 籐→藤 (rattan vs. wisteria: two words), 聯→連 and 彎→湾
(substitutions of the 1956 list 同音の漢字による書きかえ, not variants; 聯
and 連 are also distinct in Chinese, which the default table meets too).

Chinese: `zh` is unchanged from 0.1 (backward compatible: indexes stored with
`zh` keep working). New `zh-safe` keeps a pair 繁→简 only if
1. the Simplified form converts back (STCharacters) to that Traditional
   character and no other — this drops 發/髮→发, 歷/曆→历;
2. the Simplified form is not itself a Traditional character — drops
   後→后, 幹→干, 麵→面, 裡→里, 鬆→松, 隻→只, 範→范, 製→制;
3. the Traditional character has a single Simplified form;
4. not both sides are Japanese kanji (Joyo/Jinmeiyo, after `ja`) that
   Japanese keeps apart — drops 機→机, 憐→怜, 棲→栖, 莊→庄. Pairs such as
   貓→猫, 腳→脚 stay: there the Simplified form is also the Japanese form.

Korean: Hangul syllables and conjoining jamo need no table: NFKC composes
modern L+V(+T) into syllables, in Ruby and in JavaScript alike. Compatibility
jamo (ㅎㅏㄴ) become conjoining jamo and an initial+vowel pair composes (하);
a following compatibility consonant stays an initial (ᄂ), not a final.
The KS X 1001 duplicate hanja (U+F900..) fold to unified ideographs by NFKC.
Korean-specific hanja variants are therefore not added: Korean uses the
traditional forms that `ja` and `zh` already link, and the duplicates are
handled by NFKC. Old Hangul in the Hanyang PUA: new opt-in table `ko`.

### Counts

| Table | Pairs | Notes |
|---|---|---|
| `ja` | 409 (0.1: 291) | by source of the variant: joyo 302, jinmei 21, joyo-jis 4, zvariant 68, extra 14; 395 classes; no class holds two Joyo kanji |
| `zh` | 3,202 | identical to 0.1 (regenerated byte for byte) |
| `zh-safe` | 2,767 | dropped from zh: 209 several Traditional, 181 Simplified is also Traditional, 20 same with no ST entry, 21 several Simplified, 4 both Japanese kanji |
| `ko` | 5,660 | U+E0BC..U+F8F7 → 1 to 3 jamo (361 / 2,753 / 2,546 by length); 1,342 contain a precomposed syllable after NFKC |

Groups of Joyo/Jinmeiyo kanji that `ja` keeps apart but a combination merges:
`[ja, zh]` 45 (丑醜 並併 云雲 后後 発髪 机機 暦歴 面麺 裏裡里 …), `[ja, zh-safe]` 0.

Gzipped browser script (`Zlib.gzip` level 9, this branch):

| Tables | gzip | raw |
|---|---|---|
| none | 6.3 KB | 18.6 KB |
| ja (0.1 table) | 7.8 KB | 21.0 KB |
| ja | 9.0 KB | 23.5 KB |
| ja, zh-safe | 24.1 KB | 55.8 KB |
| ja, zh | 25.9 KB | 60.6 KB |
| ko | 33.3 KB | 110.0 KB |
| ja, ko | 36.1 KB | 115.0 KB |
| ja, zh-safe, ko | 50.4 KB | 147.3 KB |

`ko` is opt-in for size and because other projects use the PUA for other
things (Japanese gaiji).

### Old Hangul in the demo data

cb-ja-demo `_data/utokyo-agri.csv` has 11 PUA characters, 6 distinct:
U+E97D ᄉᆞ (5×: 가ᄉᆞ[歌辭], 계녀ᄉᆞ[戒女詞], 어부ᄉᆞ[漁父詞], …), U+E3A8 ᄃᆡ (2×,
ᄃᆡ셩훈몽젼[大聖訓蒙傳]), U+E98B ᄉᆞᆷ (이십ᄉᆞᆷ일[二十三日]), U+F1FC ᄌᆞ (경ᄌᆞ[庚子]),
U+F212 ᄌᆡ (셰ᄌᆡ[歳在]), U+F537 ᄒᆞ. Every reading fits the hanja gloss next to
it, which identifies the convention as the Hanyang PUA (HWP / Hanyang fonts).

### 1→many folding

A PUA character folds to up to three jamo. In Ruby the table value is simply a
longer string; offsets count characters of the folded text in both Ruby and
the browser, so tokens line up. The browser's highlighter (`matchRanges`) used
to assume one folded character per original character; it now records, for
each folded code point, the range of original characters it came from, so a
query in standard jamo marks the PUA character and the other way round.

Found on the way: the highlighter normalized each character alone, so text
stored as conjoining jamo (ᄒ+ᅡ+ᆫ) or half-width kana with a sound mark (ｶﾞ)
was not highlighted for 한 or が, although search found it. It now normalizes
a base character together with the following vowel/final jamo or combining
marks. Tests: `test_highlight_*` in test/test_runtime.rb (two of them fail on
0.1's runtime).

### Rejected options

- MJ縮退マップ (IPA): the best source for variants beyond JIS, but CC BY-SA
  2.1 JP. A derived table would have to be share-alike, which does not fit an
  MIT gem's data directory. Could be an external, user-supplied table.
- Unihan `kSemanticVariant` / `kSpecializedSemanticVariant`: "similar or
  identical meaning", "only in certain contexts" — would merge distinct words.
- Changing `zh` to the safe subset: an index stored with `zh` and searched
  with the new table would silently miss matches (the index records only
  table names). Added `zh-safe` instead.
- hypua2jamo's packed tables (LGPL) as the shipped source: share-alike-like
  terms for the data file. Used only to cross-check: its composed table
  (p2jc) equals the hypua crate table for all 5,660 entries; hypua2jamo has
  one extra code point, U+F86A, mapped to the empty string.
- Choosing old forms as the folded form (圖 rather than 図): changes every 0.1
  index for no gain in recall.

### Non-obvious facts

- e-Gov's text of the regulation renumbered the kanji table from 別表第二 to
  別表第三 and gives the kanji only as images.
- Unihan `kJoyoKanji` holds a code point (not a year) on the JIS X 0208 form of
  the 4 Joyo kanji whose official form is JIS X 0213-only; UAX #38 describes
  this as "the code point of the JIS X 0208 variant".
- The KTUG wiki server has been down since 2024-12-07 (notice on the site);
  the table project page survives on web.archive.org (EUC-KR).
- NFKC composes a modern initial+vowel even when an old final follows
  (ᄀ+ᅱ+ᇰ → 귀+ᇰ). The `ko` table stores values in this form so that they match
  queries typed either way.

### Not checked

- No native-speaker review yet: docs/review/korean-checklist.md and
  docs/review/japanese-chinese-checklist.md are prepared.
- The 230 Jinmeiyo links were not compared one by one with the images of the
  regulation; Unihan's transcription is trusted.
- The provenance of the KTUG table: written by volunteers (DohyunKim, Karnes,
  JungshikShin, 원신, moosoy, MadToad per the archived page) with no license.
  The hypua author's public-domain dedication covers the author's own rights
  only. A mapping of code points to jamo is largely factual, but whether it
  is protected (e.g. as a database) in Korea is not checked. Asking KTUG or
  the volunteers for an explicit license would settle it.
- A PUA character followed by a stored standard jamo that would compose with
  its last jamo (rare) is not recomposed after folding.
- Ruby and Node may use different Unicode versions for NFKC; characters new in
  Unicode 16–18 are not tested.
- Index files do not record a digest of the tables, so an index built with the
  0.1 `ja` table and searched with this one can miss the 121 new pairs and
  still match the 3 dropped ones until it is rebuilt.
