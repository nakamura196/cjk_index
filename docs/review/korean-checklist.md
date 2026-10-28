# Korean review checklist / 한국어 검토 목록

cjk_index folds text before indexing and searching, so that spellings a reader
treats as "the same" find each other. This list asks a reader of Korean to
check the Korean part. It needs no programming. About 30–60 minutes.

cjk_index는 색인과 검색 전에 글자를 하나의 형태로 맞춥니다(접기, folding).
독자가 "같은 글자"로 여기는 표기끼리 서로 찾아지게 하기 위해서입니다. 아래 항목을
한국어를 읽는 분께 확인받고 싶습니다. 프로그래밍 지식은 필요 없습니다.

## How to report / 보고 방법

For each item, answer **OK**, **Wrong** (with the right answer) or **Unsure**.
Open an issue at https://github.com/nakamura196/cjk_index/issues with the title
"Korean review", or send the list to the maintainer by the channel through
which you received it. Korean, English or Japanese are all fine.

각 항목에 **OK / 틀림(올바른 답) / 모르겠음** 으로 답해 주세요. 위 GitHub
이슈("Korean review")나 이 목록을 받으신 경로로 보내 주시면 됩니다. 한국어로 쓰셔도 됩니다.

Please also write your name as you want it credited (or "anonymous").

## A. Modern Hangul / 현대 한글

The same syllable can be stored as one character (precomposed, 한) or as a
sequence of jamo (ᄒ + ᅡ + ᆫ). Both are folded to the precomposed form (Unicode
NFKC). 한 글자를 완성형(한)으로도, 첫가끝 자모 나열(ᄒ+ᅡ+ᆫ)로도 저장할 수 있는데,
둘 다 완성형으로 맞춥니다.

| # | Text | Query | Found? | Check |
|---|---|---|---|---|
| A1 | 한글 (precomposed) | 한글 typed as jamo 한글 | yes | Should these match? |
| A2 | 서울대학교 | 대학 | yes | Searching inside a word without spaces is expected? |
| A3 | ㅎㅏㄴ (compatibility jamo U+314E U+314F U+3134) | 하 | yes: NFKC turns ㅎㅏ into 하, but ㄴ stays a separate initial ᄂ | Is this acceptable for text typed letter by letter? |
| A4 | 서울 대학교 | 서울대학교 | no (see note) | Do Korean users expect 띄어쓰기 differences to match? |

Note for A4: cjk_index splits the query at spaces into phrases that must all
occur; "서울대학교" (no space) does not occur in "서울 대학교" (with a space), so
it is **not** found today. Please tell us whether it should be.

## B. Old Hangul in the Private Use Area / 한양 PUA 옛한글

Older HWP documents and the Hanyang fonts store old Hangul syllables as single
Private Use Area characters (U+E0BC–U+F8F7). Unicode encodes them as jamo
sequences. With the optional table `ko`, cjk_index folds each PUA character to
its jamo sequence (5,660 characters), so a query typed with standard jamo finds
the PUA text and the other way round.

옛 한글 문서(HWP)와 한양 글꼴은 옛한글 음절을 사용자 정의 영역(PUA) 글자 하나로
저장합니다. `ko` 표를 쓰면 이를 표준 첫가끝 자모 나열로 바꿉니다.

These six occur in the demo data (cb-ja-demo, catalog of the University of Tokyo
agricultural library). Please check the reading:

| # | PUA | Folded to | Context in the record | Expected word |
|---|---|---|---|---|
| B1 | U+E97D | ᄉᆞ (U+1109 U+119E) | 가[PUA][歌辭], 계녀[PUA][戒女詞], 어부[PUA][漁父詞] | 가ᄉᆞ, 계녀ᄉᆞ, 어부ᄉᆞ |
| B2 | U+F1FC | ᄌᆞ (U+110C U+119E) | 경[PUA]십이월[庚子十二月] | 경ᄌᆞ |
| B3 | U+E98B | ᄉᆞᆷ (U+1109 U+119E U+11B7) | 이십[PUA]일[二十三日] | 이십ᄉᆞᆷ일 |
| B4 | U+E3A8 | ᄃᆡ (U+1103 U+11A1) | [PUA]셩훈몽젼[大聖訓蒙傳] | ᄃᆡ셩훈몽젼 |
| B5 | U+F212 | ᄌᆡ (U+110C U+11A1) | 셰[PUA]졍[PUA]칠월[歳在丁巳七月] | 셰ᄌᆡ졍ᄉᆞ |
| B6 | U+F537 | ᄒᆞ (U+1112 U+119E) | 두미오활[PUA]라 | 활ᄒᆞ라 |

A random sample of the table (please check that the jamo match the glyph shown
by a Hanyang-PUA font such as 함초롬바탕, if you have one):

| PUA | jamo | code points |
|---|---|---|
| U+E154 | 귀ᇰ | U+ADC0 U+11F0 |
| U+E1A8 | ᄀᆞᆨ | U+1100 U+119E U+11A8 |
| U+E449 | ᄅᆑᆯ | U+1105 U+1191 U+11AF |
| U+EAA1 | ᄯᅦᆯ | U+112F U+1166 U+11AF |
| U+EB8C | ᄲᅵᇂ | U+1132 U+1175 U+11C2 |
| U+EE4D | ᄋᆐᆫ | U+110B U+1190 U+11AB |
| U+F14A | ᅌᅳᆨ | U+114C U+1173 U+11A8 |
| U+F583 | ᅘᅣᆸ | U+1158 U+1163 U+11B8 |
| U+F607 | ᅙᅦ | U+1159 U+1166 |
| U+F7DD | ᅃ | U+1143 |

The whole table is `data/ko-hanyang-pua.tsv` (one line per character, with code
points in the third column).

Note: a modern initial + vowel is stored precomposed even when an old final
follows (귀 + ᇰ, not ᄀ + ᅱ + ᇰ). This is what Unicode normalization (NFC/NFKC)
does; a query typed either way is folded the same way.

## C. Questions of policy / 정책 질문

| # | Question | Today |
|---|---|---|
| C1 | Should ᆞ (arae-a, U+119E) also match ᅡ, so that 가ᄉᆞ is found by 가사? | No. They are different letters; folding them would be a separate, opt-in table. |
| C2 | Should old spellings match modern ones in general (셩 / 성, 젼 / 전)? | No. That is spelling, not character variation. |
| C3 | Hanja: Korean texts use traditional forms (國, 學). The duplicate hanja of KS X 1001 (e.g. U+F914 樂) are folded to the unified character by NFKC. Is anything else needed for Korean hanja? | Nothing else. With the default `ja` table, 國 also matches 国. |
| C4 | Should hanja match their Hangul reading (大學 / 대학)? | No (would need a dictionary). |
| C5 | Other PUA conventions you have seen in Korean data (not Hanyang)? | Only Hanyang is handled. |

Thank you. / 감사합니다.
