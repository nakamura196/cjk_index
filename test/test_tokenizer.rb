# frozen_string_literal: true

require "test_helper"

class TestTokenizer < Minitest::Test
  def t(text, **opts) = CJKIndex.tokenize(text, **opts)

  def test_cjk_runs_become_bigrams
    assert_equal %w[鳥瞰 瞰図], t("鳥瞰圖")
  end

  def test_single_cjk_character_is_kept
    assert_equal %w[竹], t("竹")
  end

  def test_unigrams_for_indexing
    assert_equal %w[鳥 瞰 図 鳥瞰 瞰図], t("鳥瞰圖", unigrams: true)
  end

  def test_mixed_scripts_and_separators
    assert_equal %w[第 1 輯 iiif まに にふ ふぇ ぇす すと], t("第1輯、IIIF「マニフェスト」")
  end

  def test_hangul_is_cjk
    assert_equal %w[서울 울대 대학], t("서울대학")
  end
end
