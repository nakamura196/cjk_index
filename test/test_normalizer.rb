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

  def test_unknown_table
    assert_raises(ArgumentError) { CJKIndex::Normalizer.new(tables: %w[xx]) }
  end

  def test_nil_is_empty
    assert_equal "", n(nil)
  end
end
