# frozen_string_literal: true

module CJKIndex
  # Folds text so that spelling variants a reader treats as "the same" compare
  # equal: NFKC (full-width -> half-width etc.), lowercase, katakana ->
  # hiragana, old-form kanji (kyujitai) -> modern form (shinjitai), and the
  # iteration mark 々 expanded to the preceding character.
  #
  # The same rules run in the browser (see Runtime), so an index built here
  # and a query typed there are folded identically.
  module Normalizer
    VARIANTS_PATH = File.expand_path("../../data/variants.tsv", __dir__)

    # Katakana ァ (U+30A1) .. ヶ (U+30F6) map to hiragana by subtracting 0x60.
    KATAKANA_FIRST = 0x30A1
    KATAKANA_LAST = 0x30F6
    KANA_OFFSET = 0x60
    ITERATION_MARK = "々"

    module_function

    # Hash of single-character old form => modern form.
    def variants
      @variants ||= File.readlines(VARIANTS_PATH, chomp: true, encoding: "UTF-8")
                        .reject { |line| line.empty? || line.start_with?("#") }
                        .to_h { |line| line.split("\t", 2) }
                        .freeze
    end

    def normalize(text)
      return "" if text.nil?

      map = variants
      prev = nil
      text.to_s.unicode_normalize(:nfkc).downcase.each_char.map do |ch|
        code = ch.ord
        ch = (code - KANA_OFFSET).chr(Encoding::UTF_8) if code.between?(KATAKANA_FIRST, KATAKANA_LAST)
        ch = map.fetch(ch, ch)
        ch = prev if ch == ITERATION_MARK && prev
        prev = ch
      end.join
    end
  end
end
