# frozen_string_literal: true

module CJKIndex
  # Splits normalized text into search tokens.
  #
  # Runs of CJK characters (kanji, kana, hangul) have no spaces between words,
  # so they become overlapping character bigrams: 「鳥瞰図」 -> 鳥瞰, 瞰図.
  # Other runs (Latin letters, digits) stay whole words. Each token carries
  # its offset (in characters of the normalized text), so a query can require
  # its bigrams to be adjacent and in order: an exact substring match, found
  # without a dictionary.
  #
  # The character classes are kept as code point ranges so that Runtime can
  # emit exactly the same classes into the browser script, where the same
  # character-by-character loop runs.
  module Tokenizer
    CJK_RANGES = [
      [0x1100, 0x11FF],   # hangul jamo (old hangul is written as jamo sequences)
      [0x3005, 0x3005],   # 々 iteration mark
      [0x3007, 0x3007],   # 〇
      [0x3040, 0x309F],   # hiragana
      [0x30A0, 0x30FF],   # katakana
      [0x3130, 0x318F],   # hangul compatibility jamo
      [0x3400, 0x4DBF],   # CJK extension A
      [0x4E00, 0x9FFF],   # CJK unified ideographs
      [0xA960, 0xA97F],   # hangul jamo extended-A
      [0xAC00, 0xD7AF],   # hangul syllables
      [0xD7B0, 0xD7FF],   # hangul jamo extended-B
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
    SEPARATOR = Regexp.new(char_class(SEPARATOR_RANGES, SEPARATOR_CHARS))

    # Token strings only. unigrams: true adds every single CJK character as
    # well; the index needs them so that one-character queries (「竹」) and
    # CJK characters between digits (「第1輯」) can be found.
    def tokenize(text, unigrams: false, normalizer: Normalizer.default)
      tokens_with_offsets(text, unigrams: unigrams, normalizer: normalizer).map(&:first)
    end

    # [[token, offset], ...] for the whole text. Offsets count characters of
    # the normalized text, so the index and the query agree on them.
    def tokens_with_offsets(text, unigrams: false, normalizer: Normalizer.default)
      phrases(text, unigrams: unigrams, normalizer: normalizer).flatten(1)
    end

    # Splits at separators (spaces, punctuation) into phrases, each a list of
    # [token, offset]. A query matches when every phrase occurs somewhere in
    # the document, with the tokens of each phrase at the same relative offsets.
    def phrases(text, unigrams: false, normalizer: Normalizer.default)
      result = []
      phrase = []
      run = +""
      run_cjk = nil
      run_start = 0
      flush = lambda do
        next if run.empty?

        if run_cjk
          chars = run.chars
          if chars.length == 1 || unigrams
            chars.each_with_index { |c, i| phrase << [c, run_start + i] }
          end
          chars.each_cons(2).with_index { |(a, b), i| phrase << [a + b, run_start + i] }
        else
          phrase << [run.dup, run_start]
        end
        run = +""
      end

      normalizer.normalize(text).each_char.with_index do |ch, offset|
        if ch.match?(SEPARATOR)
          flush.call
          result << phrase unless phrase.empty?
          phrase = []
          run_cjk = nil
          next
        end
        cjk = ch.match?(CJK)
        flush.call if !run_cjk.nil? && cjk != run_cjk
        run_start = offset if run.empty?
        run_cjk = cjk
        run << ch
      end
      flush.call
      result << phrase unless phrase.empty?
      result
    end
  end
end
