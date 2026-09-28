# frozen_string_literal: true

module CJKIndex
  # Splits normalized text into search tokens.
  #
  # Runs of CJK characters (kanji, kana, hangul) have no spaces between words,
  # so they become overlapping character bigrams: 「鳥瞰図」 -> 鳥瞰, 瞰図.
  # Other runs (Latin letters, digits) stay whole words. Requiring every bigram
  # of a query to be present behaves like a substring search without a
  # dictionary.
  #
  # The character classes are kept as code point ranges so that Runtime can
  # emit exactly the same classes into the browser script.
  module Tokenizer
    CJK_RANGES = [
      [0x3005, 0x3005],   # 々 iteration mark
      [0x3007, 0x3007],   # 〇
      [0x3040, 0x309F],   # hiragana
      [0x30A0, 0x30FF],   # katakana
      [0x3400, 0x4DBF],   # CJK extension A
      [0x4E00, 0x9FFF],   # CJK unified ideographs
      [0xAC00, 0xD7AF],   # hangul syllables
      [0xF900, 0xFAFF],   # CJK compatibility ideographs
      [0x20000, 0x2FA1F]  # CJK extensions B- and compatibility supplement
    ].freeze

    SEPARATOR_RANGES = [
      [0x09, 0x0D], [0x20, 0x20], [0xA0, 0xA0], [0x1680, 0x1680],
      [0x2000, 0x200A], [0x2028, 0x2029], [0x202F, 0x202F], [0x205F, 0x205F],
      [0x3000, 0x3000], [0xFEFF, 0xFEFF]
    ].freeze
    SEPARATOR_CHARS = "、。，．・：；！？「」『』（）()［］[]【】〈〉《》〔〕｛｝{}\"'`,.:;!?/\\|-‐―－~〜=+*&%$#@^<>"

    module_function

    # "[...]" character class usable in both Ruby and JavaScript (with /u).
    def char_class(ranges, chars = "")
      body = ranges.map do |from, to|
        from == to ? escape(from) : "#{escape(from)}-#{escape(to)}"
      end
      body += chars.each_char.map { |c| escape(c.ord) }
      "[#{body.join}]"
    end

    def escape(code)
      format("\\u{%x}", code)
    end

    CJK = Regexp.new(char_class(CJK_RANGES))
    SEPARATOR = Regexp.new("#{char_class(SEPARATOR_RANGES, SEPARATOR_CHARS)}+")

    # unigrams: true adds every single CJK character as well. Use it when
    # indexing, so that one-character queries (「竹」) and short CJK runs
    # between digits (「第1輯」) still match. Queries use unigrams: false.
    def tokenize(text, unigrams: false)
      tokens = []
      Normalizer.normalize(text).split(SEPARATOR).each do |chunk|
        next if chunk.empty?

        chunk.scan(/#{CJK}+|(?:(?!#{CJK}).)+/o) do |run|
          if run.match?(CJK)
            chars = run.chars
            tokens.concat(chars) if chars.length == 1 || unigrams
            chars.each_cons(2) { |a, b| tokens << (a + b) }
          else
            tokens << run
          end
        end
      end
      tokens
    end
  end
end
