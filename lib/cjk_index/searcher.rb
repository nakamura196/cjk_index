# frozen_string_literal: true

require "json"
require "set"

module CJKIndex
  # Queries an index in Ruby, with the same matching, ranking, highlighting
  # and excerpts as the browser runtime (runtime.js). The test suite runs
  # both on the same index and checks that they agree.
  #
  #   searcher = CJKIndex::Searcher.new(builder)            # or a parsed JSON index
  #   searcher.search("鳥瞰図")  # => [{ ref: "item1.html", score: 1.2, fields: ["title"] }]
  #   searcher.highlight("東京帝國大學", "帝国大学")  # => "東京<mark>帝國大學</mark>"
  #
  # The normalizer is taken from the tables the index was built with, so a
  # query folds exactly like the indexed text.
  class Searcher
    # BM25 parameters (the usual defaults, as in Lucene and Pagefind).
    K1 = 1.2
    B = 0.75
    # Score multiplier for matches found by prefix or typo expansion.
    EXPANDED = 0.6

    attr_reader :fields, :refs, :normalizer

    # index is a Builder, its to_h, or the JSON it wrote (String or parsed).
    # prefix: the last Latin word of a query also matches longer words.
    # typos: Latin words of 5+ letters also match words one edit away.
    def self.load(path, **options)
      new(File.read(path, encoding: "UTF-8"), **options)
    end

    def initialize(index, prefix: true, typos: true, normalizer: nil)
      data = case index
             when Builder then index.to_h
             when String then JSON.parse(index)
             else index
             end
      unless data.is_a?(Hash) && data["format"] == Builder::FORMAT
        raise ArgumentError, "cjk_index: unsupported index format #{data.is_a?(Hash) ? data['format'].inspect : data.class}"
      end

      @normalizer = normalizer || Normalizer.new(tables: data["variants"])
      if @normalizer.tables != data["variants"]
        raise ArgumentError, "cjk_index: index built with variant tables #{data['variants'].inspect} " \
                             "but this normalizer folds with #{@normalizer.tables.inspect}; rebuild both together"
      end

      @prefix = prefix
      @typos = typos
      @fields = data["fields"]
      @boosts = data["boosts"]
      @refs = data["refs"]
      @lengths = data["lengths"]
      @tokens = data["tokens"]
      nf = @fields.length
      avg = Array.new(nf, 0.0)
      @lengths.each_with_index { |len, i| avg[i % nf] += len }
      @avg_length = avg.map { |s| (v = s / [1, @refs.length].max).zero? ? 1 : v }
      @latin_tokens = @tokens.keys.select { |t| latin?(t) }.sort
    end

    # Every phrase of the query must occur in the document (in any field),
    # with its tokens adjacent and in order. Returns [{ ref:, score:, fields: }]
    # with the best match first; fields lists the fields that matched.
    def search(query)
      nf = @fields.length
      n = @refs.length
      qp = Tokenizer.phrases(query, normalizer: @normalizer)
      return [] if qp.empty?

      scores = Hash.new(0.0)
      matched_fields = Hash.new { |h, k| h[k] = [] }
      docs_so_far = nil

      qp.each_with_index do |phrase, q|
        expanded = false
        parts = phrase.each_with_index.map do |(token, offset), i|
          tokens, exp = alternatives(token, q == qp.length - 1 && i == phrase.length - 1)
          expanded ||= exp
          [offset, positions(tokens)]
        end
        return [] if parts.any? { |_, pos| pos.empty? }

        parts = parts.sort_by.with_index { |(_, pos), i| [pos.size, i] }
        rare_offset, rare = parts.first
        hits = {}
        rare.each do |key, set|
          tf = set.count do |pos|
            start = pos - rare_offset
            parts.drop(1).all? { |offset, other| other[key]&.include?(start + offset) }
          end
          hits[key] = tf if tf.positive?
        end
        docs = hits.keys.map { |key| key / nf }.to_set
        docs &= docs_so_far if docs_so_far
        return [] if docs.empty?

        docs_so_far = docs
        idf = Math.log(1 + ((n - docs.size + 0.5) / (docs.size + 0.5)))
        weight = expanded ? EXPANDED : 1
        hits.each do |key, tf|
          doc = key / nf
          field = key % nf
          norm = 1 - B + (B * @lengths[key] / @avg_length[field])
          scores[doc] += weight * @boosts[field] * idf * (tf * (K1 + 1)) / (tf + (K1 * norm))
          matched_fields[doc] |= [@fields[field]]
        end
      end

      docs_so_far.sort_by { |doc| [-scores[doc], doc] }
                 .map { |doc| { ref: @refs[doc], score: scores[doc], fields: matched_fields[doc] } }
    end

    def highlight(text, query) = CJKIndex.highlight(text, query, normalizer: @normalizer)

    def excerpt(text, query, length = 80) = CJKIndex.excerpt(text, query, length, normalizer: @normalizer)

    private

    def latin?(token) = !token.match?(Tokenizer::CJK)

    # "doc * nf + field" => Set of positions, merged over the alternatives.
    def positions(tokens)
      nf = @fields.length
      map = {}
      tokens.each do |token|
        postings = @tokens[token] or next
        i = 0
        while i < postings.length
          count = postings[i + 2]
          (map[(postings[i] * nf) + postings[i + 1]] ||= Set.new).merge(postings[i + 3, count])
          i += 3 + count
        end
      end
      map
    end

    # Alternatives for one query token: itself, and for Latin words the index
    # words it is a prefix of (last word only) or one edit away from.
    def alternatives(token, last)
      return [[token], false] unless latin?(token)

      out = @tokens.key?(token) ? [token] : []
      if @prefix && last
        from = @latin_tokens.bsearch_index { |k| k >= token } || @latin_tokens.length
        @latin_tokens[from..].each do |k|
          break unless k.start_with?(token)

          out << k unless k == token
        end
      end
      out.concat(@latin_tokens.select { |k| one_edit?(token, k) }) if @typos && !@tokens.key?(token) && token.length >= 5
      [out, !out.empty? && out.first != token]
    end

    # true when a and b differ by exactly one insertion, deletion or substitution.
    def one_edit?(a, b)
      return false if a == b || (a.length - b.length).abs > 1

      i = 0
      i += 1 while i < a.length && i < b.length && a[i] == b[i]
      if a.length == b.length then a[(i + 1)..] == b[(i + 1)..]
      elsif a.length > b.length then a[(i + 1)..] == b[i..]
      else a[i..] == b[(i + 1)..]
      end
    end
  end

  HTML_ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&#39;" }.freeze

  def self.escape_html(text) = text.gsub(/[&<>"']/, HTML_ESCAPES)

  # [start, end) ranges, in characters of the original text, where a phrase
  # of the query occurs after normalization.
  def self.match_ranges(text, query, normalizer: Normalizer.default)
    chars = text.to_s.chars
    norm = +""
    origin = []
    chars.each_with_index do |ch, i|
      folded = normalizer.normalize(ch)
      # 々 depends on the previous character, so fold it in context.
      folded = norm[-1] if folded == Normalizer::ITERATION_MARK && !norm.empty?
      norm << folded
      folded.length.times { origin << i }
    end
    needles = normalizer.normalize(query).split(Tokenizer::SEPARATOR).reject(&:empty?)
    ranges = needles.flat_map do |needle|
      found = []
      from = 0
      while (at = norm.index(needle, from))
        found << [origin[at], origin[at + needle.length - 1] + 1]
        from = at + needle.length
      end
      found
    end
    merged = ranges.sort_by(&:first).each_with_object([]) do |r, acc|
      if acc.last && r[0] <= acc.last[1] then acc.last[1] = [acc.last[1], r[1]].max
      else acc << r.dup
      end
    end
    [chars, merged]
  end

  # HTML-escaped text with every match of the query wrapped in <mark>.
  # 「東京帝國大學」 is marked for the query 「帝国大学」.
  def self.highlight(text, query, normalizer: Normalizer.default)
    chars, ranges = match_ranges(text, query, normalizer: normalizer)
    at = 0
    out = +""
    ranges.each do |from, to|
      out << escape_html(chars[at...from].join) << "<mark>" << escape_html(chars[from...to].join) << "</mark>"
      at = to
    end
    out << escape_html(chars[at..].join)
  end

  # A highlighted window of about `length` characters around the first match.
  def self.excerpt(text, query, length = 80, normalizer: Normalizer.default)
    chars, ranges = match_ranges(text, query, normalizer: normalizer)
    if ranges.empty?
      return chars.length > length ? "#{escape_html(chars[0, length].join)}…" : escape_html(chars.join)
    end

    start = [0, ranges[0][0] - (length / 3)].max
    stop = [chars.length, start + length].min
    "#{start.positive? ? '…' : ''}#{highlight(chars[start...stop].join, query, normalizer: normalizer)}" \
      "#{stop < chars.length ? '…' : ''}"
  end

  # Substring test on normalized text, ignoring whitespace.
  def self.includes?(haystack, needle, normalizer: Normalizer.default)
    strip = ->(s) { normalizer.normalize(s).gsub(/\s+/, "") }
    strip.call(haystack).include?(strip.call(needle))
  end
end
