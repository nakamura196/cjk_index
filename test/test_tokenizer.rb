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

  def test_offsets_and_phrases
    assert_equal [[["鳥瞰", 0], ["瞰図", 1]], [["iiif", 4]]], CJKIndex::Tokenizer.phrases("鳥瞰圖 IIIF")
    assert_equal [["第", 0], ["1", 1], ["輯", 2]], CJKIndex::Tokenizer.tokens_with_offsets("第1輯")
  end

  def test_hangul_is_cjk
    assert_equal %w[서울 울대 대학], t("서울대학")
  end

  def test_old_hangul_jamo_are_cjk
    # ᄒᆞᆫ (arae-a, no precomposed syllable): three jamo, kept in one run
    assert_equal ["ᄒᆞ", "ᆞᆫ", "ᆫ글"], t("ᄒᆞᆫ글")
  end
end
