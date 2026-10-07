# Relevance judgments: rules

The judgments in `qrels/` were made from `pools/*.tsv` before any search
engine was run on the collections. The assessor saw only the query, the
description in `queries.tsv` and the contexts in the pool, never the output
of cjk_index or lunr.

## What counts as relevant

A record is relevant to a query when one of its indexed fields contains the
word the query denotes, written in any of these forms:

- old or new character forms and other glyph variants (圖 / 図, 帝國大學 / 帝国大学)
- Traditional, Simplified or Japanese forms of a Chinese character (實錄 / 实录 / 実録)
- katakana or hiragana (ランプ / らんぷ)
- full-width or half-width forms, and the iteration mark 々 (佐々木 / 佐佐木)

A compound that contains the word as one of its parts is relevant
(京都府, 京都大学, 鉄道省, 日露戦争, 帝国大学総長).

These are **not** relevant:

- a match that crosses a word boundary: 東京都 is 東京 + 都 and contains no
  京都; 山林学校 is 山林 + 学校 and contains no 林学
- the same characters used as part of another word: かめ in 確かめ, かき in
  書き, ねこ in 寝ころぶ
- a different word that only shares a character form: 辨 (distinguish) and
  瓣 (petal) are not 辯 (speech), even though all three are written 弁 today
- the same meaning written with other characters or in kanji instead of kana
  (猫 for ネコ, 柿 for カキ, 鉄路 for 鉄道); these are outside what any of the
  compared engines tries to do, and leaving them out keeps the definition
  checkable from the record text

## Per-query notes

- a02 夏目漱石: the author field 夏目漱石 counts, as does the name in the text.
- a07 台風: 颶風 counts only where the context means a typhoon.
- a10 ネコ, a11 カメ, a12 カキ: the kana must spell the word itself, alone or
  as a part of a compound. Relevant: ネコ / ねこ = cat (also 三毛ねこ, ねこじゃらし);
  カメ / かめ = turtle or jar (亀, 甕); カキ / かき = persimmon, oyster or fence
  (柿, 牡蠣, 垣; かきね = 垣根 counts). Not relevant: verb forms and other words
  (寝ころぶ, 確かめる, かめば = 噛めば, カメラ, カメレオン, 書き, 掻き, 描き,
  かき集める, カキツバタ = 杜若). A character's name counts only when it is the
  animal's name for that animal (a turtle called カメ); a person's name that
  contains the kana does not.
- a13 京都: the place (city, prefecture, the old capital). 東京都 does not count.
- a14 辯: relevant when the character means speech or argument: 辯 / 弁 in
  辯論, 辯解, 辯護, 雄辯, 答辯, 詭辯, 弁士, 弁舌, 弁明, 弁天 (辯才天), 能弁, 駄弁,
  関西弁 and other dialect 弁 (from 辯). Not relevant: 辨 / 弁 meaning
  distinguish or manage (辨別, 弁える, 勘弁, 弁償, 弁当, 支弁, 弁慶 written 辨慶),
  瓣 / 弁 meaning petal or valve (花弁, 安全弁). When the record writes 弁 and
  the word does not decide it, mark it 0 and say why.
- u13 林学: 林学 / 林學 itself, including 林学科 or 森林学. 山林學校 / 農林学校
  do not count.

## Format

`qrels/<corpus>.tsv`: qid, doc, rel (1 or 0), note. Every record in the pool
is judged. A record that is not in the pool is not relevant (it contains none
of the spellings). The note says why for every 0 and for any 1 that needed a
decision.
