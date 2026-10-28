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

  def test_each_token_matches_tokens_with_offsets
    ["東京帝國大學本部構内及農學部建物鳥瞰圖", "第1輯、IIIF「マニフェスト」 abc", "ᄒᆞᆫ글 소학언초", "𠮟る 佐々木\n\t改行",
     "Hello, World! 羣芳圖譜", "a", "", "  ", "。。東。京", "日本語・英語", "ア・イ"].each do |text|
      [true, false].each do |unigrams|
        norm = CJKIndex.normalize(text)
        tokens = []
        CJKIndex::Tokenizer.each_token(norm, unigrams: unigrams) { |tok, offset| tokens << [tok, offset] }
        assert_equal CJKIndex::Tokenizer.tokens_with_offsets(text, unigrams: unigrams), tokens, text
      end
    end
  end
end
