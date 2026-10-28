# frozen_string_literal: true

require "test_helper"

class TestNormalizer < Minitest::Test
  def n(text) = CJKIndex.normalize(text)

  def test_old_form_kanji_become_modern
    assert_equal "東京帝国大学", n("東京帝國大學")
    assert_equal "鳥瞰図", n("鳥瞰圖")
  end

  def test_katakana_become_hiragana
    assert_equal "さくら", n("サクラ")
  end

  def test_nfkc_and_lowercase
    assert_equal "iiif 2024", n("ＩＩＩＦ　２０２４")
  end

  def test_iteration_mark_is_expanded
    assert_equal "佐佐木", n("佐々木")
  end

  def test_japanese_table_is_the_default
    assert_equal %w[ja], CJKIndex::Normalizer.default.tables
    assert_equal "图书馆", n("图书馆"), "Simplified Chinese is left alone by default"
  end

  def test_chinese_table_folds_traditional_and_simplified
    zh = CJKIndex::Normalizer.new(tables: %w[zh])
    assert_equal zh.normalize("图书馆"), zh.normalize("圖書館")
    assert_equal "干", zh.normalize("幹")
    assert_equal "乾", zh.normalize("乾"), "ambiguous entries are not folded"
  end

  def test_tables_combine_with_the_first_one_preferred
    both = CJKIndex::Normalizer.new(tables: %w[ja zh])
    assert_equal %w[図 図 図], %w[圖 図 图].map { |c| both.normalize(c) }
  end

  def test_japanese_table_covers_the_official_lists
    assert_equal "証明", n("證明"), "Joyo Kanji Table, bracketed old form"
    assert_equal n("剝"), n("剥"), "Joyo Kanji Table, two accepted forms"
    assert_equal n("頰"), n("頬")
    assert_equal n("𠮟"), n("叱")
    assert_equal n("禱"), n("祷"), "Jinmeiyo Kanji"
    assert_equal n("塡"), n("填"), "Unihan kZVariant"
    assert_equal "槙", n("槇"), "the folded form of a 0.1 pair is unchanged"
  end

  def test_japanese_table_does_not_merge_distinct_characters
    assert_equal "籐", n("籐"), "rattan, not wisteria (藤)"
    assert_equal "聯", n("聯"), "a substitution (書きかえ), not a variant of 連"
    assert_equal "彎", n("彎")
  end

  def test_safe_chinese_table_folds_only_one_to_one_pairs
    safe = CJKIndex::Normalizer.new(tables: %w[zh-safe])
    assert_equal safe.normalize("图书馆"), safe.normalize("圖書館")
    assert_equal "後", safe.normalize("後"), "后 is also a Traditional character"
    assert_equal "發", safe.normalize("發"), "发 stands for 發 and 髮"
    assert_equal "麵", safe.normalize("麵")
    full = CJKIndex::Normalizer.new(tables: %w[zh])
    assert_equal "后", full.normalize("後"), "zh keeps the 0.1 behaviour"
  end

  def test_safe_chinese_table_keeps_japanese_characters_apart
    assert_equal %w[発 髪], %w[發 髮].map { |c| CJKIndex::Normalizer.new(tables: %w[ja zh-safe]).normalize(c) }
    both = CJKIndex::Normalizer.new(tables: %w[ja zh])
    assert_equal both.normalize("発"), both.normalize("髪"), "known: the full table merges them through 发"
  end

  def test_hangul_syllables_and_jamo_fold_to_one_form
    precomposed = "한글"
    conjoining = "\u1112\u1161\u11AB\u1100\u1173\u11AF"
    compatibility = "ㅎㅏㄴ" # U+314E U+314F U+3134
    assert_equal precomposed, n(conjoining)
    assert_equal "하ᄂ", n(compatibility), "NFKC joins a compatibility consonant and vowel, not a final"
    assert_equal "樂", CJKIndex::Normalizer.new(tables: []).normalize("\uF914"), "KS X 1001 duplicate hanja (compatibility ideographs) fold by NFKC"
  end

  def test_old_hangul_in_the_private_use_area
    ko = CJKIndex::Normalizer.new(tables: %w[ja ko])
    assert_equal "가\u1109\u119E", ko.normalize("가\uE97D"), "U+E97D is ᄉᆞ in the Hanyang PUA"
    assert_equal ko.normalize("\u1109\u119E\u11B7"), ko.normalize("\uE98B")
    assert_equal "가\uE97D", n("가\uE97D"), "not folded without ko"
    tokens = CJKIndex::Tokenizer.tokens_with_offsets("\uE97D이", unigrams: true, normalizer: ko)
    assert_includes tokens, ["\u119E이", 1], "offsets count characters of the folded text"
  end

  def test_tables_are_plain_data
    CJKIndex::Normalizer::TABLES.each_key do |name|
      pairs = CJKIndex::Normalizer.read_table(name)
      refute_empty pairs, name
      assert_equal pairs.size, pairs.map(&:first).uniq.size, "#{name}: one line per variant"
      pairs.each do |from, to|
        assert_equal 1, from.length, "#{name}: #{from}"
        refute_equal from, to, name
        assert_equal from, from.unicode_normalize(:nfkc), "#{name}: #{from} never reaches the table"
        assert_equal to, to.unicode_normalize(:nfkc), "#{name}: #{from} -> #{to}"
      end
    end
    assert_equal ["\uE97D", "\u1109\u119E"], CJKIndex::Normalizer.read_table("ko").assoc("\uE97D")
  end

  def test_unknown_table
    assert_raises(ArgumentError) { CJKIndex::Normalizer.new(tables: %w[xx]) }
  end

  FIXTURES = File.expand_path("fixtures/variants", __dir__)

  def test_table_file_of_your_own
    custom = CJKIndex::Normalizer.new(tables: %w[itaiji.tsv], base: FIXTURES)
    assert_equal "与 宴宴 嶋嶋嶋", custom.normalize("與 醼讌 嶌島嶋")
    assert_equal "株式会社", custom.normalize("㍿") # NFKC already did it; the line adds nothing
    assert_equal %w[itaiji.tsv], custom.tables
  end

  def test_table_file_combines_with_built_in_tables
    # 嶋 and 島 are linked by ja too; the table listed first picks the form
    assert_equal "島 与", CJKIndex::Normalizer.new(tables: %w[ja itaiji.tsv], base: FIXTURES).normalize("嶌 與")
    assert_equal "嶋 与", CJKIndex::Normalizer.new(tables: %w[itaiji.tsv ja], base: FIXTURES).normalize("嶌 與")
  end

  def test_table_file_digest_follows_its_contents
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "t.tsv"), "与\t與\n")
      before = CJKIndex::Normalizer.new(tables: %w[t.tsv], base: dir).digest
      File.write(File.join(dir, "t.tsv"), "与\t與\n宴\t醼\n")
      refute_equal before, CJKIndex::Normalizer.new(tables: %w[t.tsv], base: dir).digest
    end
  end

  def test_table_file_cells_after_the_first_are_one_character
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "t.tsv"), "# comment\n与\t與\n宴\t醼讌\n")
      error = assert_raises(ArgumentError) { CJKIndex::Normalizer.new(tables: %w[t.tsv], base: dir) }
      assert_match(/t\.tsv:3: "醼讌"/, error.message)
    end
  end

  def test_missing_table_file
    error = assert_raises(ArgumentError) { CJKIndex::Normalizer.new(tables: %w[nothing.tsv], base: FIXTURES) }
    assert_match(/no file at .*nothing\.tsv/, error.message)
  end

  def test_nil_is_empty
    assert_equal "", n(nil)
  end
end
