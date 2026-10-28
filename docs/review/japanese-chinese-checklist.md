# Japanese and Chinese spot-check list

For a reader of Japanese or Chinese. Each line is a fold that cjk_index makes
(or deliberately does not make). Answer **OK**, **Wrong** (and why) or
**Unsure**, in an issue titled "Variant review" at
https://github.com/nakamura196/cjk_index/issues. About 20 minutes.
The full tables are `data/ja-kyujitai.tsv`, `data/zh-hant-hans-safe.tsv` and
`data/zh-hant-hans.tsv`; the third column of the Japanese table says where
each pair comes from.

## Japanese (`ja`, the default)

Folded (searching one finds the other):

| # | Pair | Source | Question |
|---|---|---|---|
| J1 | 證 → 証, 辯/辨/瓣 → 弁, 藝 → 芸, 缺 → 欠 | Joyo Kanji Table brackets | OK although the old forms are distinct characters in Chinese? |
| J2 | 剝 / 剥, 𠮟 / 叱, 塡 / 填, 頰 / 頬 | Joyo Kanji Table, two accepted forms | OK? |
| J3 | 禱 / 祷, 遙 / 遥, 檜 / 桧, 盃 → 杯, 埜 → 野, 冨 → 富, 駈 → 駆 | Jinmeiyo Kanji (人名用漢字) | Especially 盃/杯, 埜/野, 冨/富: does a reader treat them as the same character in names? |
| J4 | 吳 / 吴 / 呉, 戶 / 户 / 戸, 說 → 説, 搖 / 摇 / 揺, 值 → 値 | Unihan kZVariant | OK that Chinese forms (吴, 户, 摇) also fold in Japanese text? |
| J5 | 內 → 内, 靑 → 青, 淸 → 清, 舍 → 舎, 邉 → 辺, 甞 → 嘗, 牀 → 床 | written for cjk_index | OK? |

Not folded any more (they were in 0.1):

| # | Pair | Why | Question |
|---|---|---|---|
| J6 | 籐 / 藤 | rattan and wisteria are different words | Agree? |
| J7 | 聯 / 連, 彎 / 湾 | substitutions of 1956 (同音の漢字による書きかえ), not variants | Should a search for 連合 find 聯合? |

## Chinese

`zh-safe` keeps only Traditional→Simplified pairs that are one-to-one both
ways. `zh` (unchanged from 0.1) keeps the first Simplified form of every
character.

| # | Pair | zh-safe | zh | Question |
|---|---|---|---|---|
| C1 | 圖 / 图, 書 / 书, 國 / 国 | folded | folded | — |
| C2 | 後 / 后 | no | folded | In which kind of collection would you want 皇后 and 以後 apart? |
| C3 | 發 / 髮 / 发 | no | folded | A Simplified query 发展 does not find 發展 with zh-safe. Acceptable for a Japanese site? |
| C4 | 乾 / 幹 / 干, 麵 / 面, 裡 / 里, 鬆 / 松, 隻 / 只, 範 / 范, 製 / 制 | no | folded (except 乾) | — |
| C5 | 機 / 机, 憐 / 怜, 棲 / 栖, 莊 / 庄 | no | folded | Left out of zh-safe because both are Japanese kanji. Right call? |
| C6 | 貓 / 猫, 腳 / 脚, 羣 / 群 | folded | folded | The Simplified form is also the Japanese form. OK? |

With `[ja, zh]`, 45 groups of Joyo/Jinmeiyo kanji that Japanese keeps apart
fall together (e.g. 発 and 髪, 机 and 機, 暦 and 歴, 面 and 麺). With
`[ja, zh-safe]` there are none. Do you know of a pair we missed?
