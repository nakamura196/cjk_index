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

  def test_nil_is_empty
    assert_equal "", n(nil)
  end
end
