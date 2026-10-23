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

    attr_reader :fields, :normalizer

    # index is a Builder, its to_h, or the JSON it wrote (String or parsed).
    # A Searcher made from a Builder answers for the builder's current
    # documents, also after later add, remove and update.
    # prefix: the last Latin word of a query also matches longer words.
    # typos: Latin words of 5+ letters also match words one edit away.
    def self.load(path, **options)
      new(File.read(path, encoding: "UTF-8"), **options)
    end

    def initialize(index, prefix: true, typos: true, normalizer: nil)
      @prefix = prefix
      @typos = typos
      if index.is_a?(Builder)
        @builder = index
        data = index.live_data
      else
        data = index.is_a?(String) ? JSON.parse(index) : index
        unless data.is_a?(Hash) && Builder::FORMATS.include?(data["format"])
          raise ArgumentError, "cjk_index: unsupported index format #{data.is_a?(Hash) ? data['format'].inspect : data.class}"
        end
      end

      @normalizer = normalizer || Normalizer.new(tables: data["variants"])
      if @normalizer.tables != data["variants"]
        raise ArgumentError, "cjk_index: index built with variant tables #{data['variants'].inspect} " \
                             "but this normalizer folds with #{@normalizer.tables.inspect}; rebuild both together"
      end

      setup(data)
    end

    # Refs of the documents in the index, in index order.
    def refs
      refresh
      @refs.compact
    end

    # Names of the filters the index was built with.
    def filters
      refresh
      @filters.keys
    end

    # Every phrase of the query must occur in the document (in any field),
    # with its tokens adjacent and in order. Returns [{ ref:, score:, fields: }]
    # with the best match first; fields lists the fields that matched.
    #
    # filter: { "type" => "地図", "subject" => ["植物", "動物"], "date" => 1900..1950 }
    # keeps the documents that meet every condition: a value filter matches
    # any of the given values (folded like the query), a year filter takes a
    # Range, { "min" => 1900, "max" => 1950 } or one year. Scores do not
    # depend on the filter. With a filter, a blank query returns every
    # document that passes it, in index order, with score 0.
    def search(query, filter: nil)
      refresh
      nf = @fields.length
      n = @count
      conditions = filter && compile_filter(filter)
      qp = Tokenizer.phrases(query, normalizer: @normalizer)
      if qp.empty?
        return [] unless conditions

        return @refs.each_index.select { |doc| @refs[doc] && pass?(doc, conditions) }
                    .map { |doc| { ref: @refs[doc], score: 0.0, fields: [] } }
      end

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

      docs_so_far = docs_so_far.select { |doc| pass?(doc, conditions) } if conditions
      docs_so_far.sort_by { |doc| [-scores[doc], doc] }
                 .map { |doc| { ref: @refs[doc], score: scores[doc], fields: matched_fields[doc] } }
    end

    # Counts of the values of a filter, for a facet list: over results (as
    # returned by search, or refs) or over the whole index. Returns
    # [{ value:, count: }], the most frequent first, ties in index order.
    # Year filters count each year.
    def facets(field, results = nil)
      refresh
      filter = @filters.fetch(field.to_s) { raise ArgumentError, "cjk_index: no filter #{field}" }
      docs = if results
               results.filter_map { |r| @slot_of[r.is_a?(Hash) ? (r[:ref] || r["ref"]) : r.to_s] }
             else
               @refs.each_index.select { |doc| @refs[doc] }
             end
      counts = Hash.new(0)
      docs.each do |doc|
        value = filter[:docs][doc]
        if filter[:kind] == "year" then counts[value] += 1 unless value.nil?
        else value.each { |key| counts[key] += 1 }
        end
      end
      counts.sort_by { |key, count| [-count, filter[:rank][key]] }
            .map { |key, count| { value: filter[:display][key], count: count } }
    end

    def highlight(text, query) = CJKIndex.highlight(text, query, normalizer: @normalizer)

    def excerpt(text, query, length = 80) = CJKIndex.excerpt(text, query, length, normalizer: @normalizer)

    private

    def setup(data)
      @version = @builder&.version
      @fields = data["fields"]
      @boosts = data["boosts"]
      @refs = data["refs"]
      @lengths = data["lengths"]
      @tokens = data["tokens"]
      @count = data["count"] || @refs.length
      nf = @fields.length
      avg = Array.new(nf, 0.0)
      @lengths.each_with_index { |len, i| avg[i % nf] += len if len }
      @avg_length = avg.map { |s| (v = s / [1, @count].max).zero? ? 1 : v }
      @latin_tokens = @tokens.keys.select { |t| latin?(t) }.sort
      @slot_of = {}
      @refs.each_with_index { |ref, doc| @slot_of[ref] ||= doc if ref }
      @filters = (data["filters"] || {}).to_h { |name, f| [name, setup_filter(f)] }
    end

    # Filter values by document: keys (value filters) or a year, with the
    # form to show for each key and its rank of first appearance.
    def setup_filter(f)
      docs = if f["kind"] == "year" then f["docs"]
             elsif f["values"]
               keys = f["values"].map { |v| Builder.filter_key(v, @normalizer) }
               f["docs"].map { |ids| ids.map { |id| keys[id] } }
             else
               f["docs"].map { |pairs| pairs&.map(&:first) }
             end
      display = {}
      if f["values"] then f["values"].each { |v| display[Builder.filter_key(v, @normalizer)] ||= v }
      elsif f["kind"] == "value" then f["docs"].each { |pairs| pairs&.each { |key, v| display[key] ||= v } }
      end
      rank = {}
      docs.each_with_index do |value, doc|
        next unless @refs[doc]

        Array(value).each { |key| rank[key] ||= rank.size }
      end
      display = rank.keys.to_h { |year| [year, year] } if f["kind"] == "year"
      { kind: f["kind"], docs: docs, display: display, rank: rank }
    end

    def refresh
      setup(@builder.live_data) if @builder && @builder.version != @version
    end

    # [[filter, test], ...] from a filter argument of search.
    def compile_filter(filter)
      filter.filter_map do |name, condition|
        f = @filters.fetch(name.to_s) { raise ArgumentError, "cjk_index: no filter #{name}" }
        next if condition.nil? || (condition.is_a?(Array) && condition.empty?)

        if f[:kind] == "year"
          range = case condition
                  when Range then condition
                  when Hash then (condition["min"] || condition[:min])..(condition["max"] || condition[:max])
                  else Integer(condition)..Integer(condition)
                  end
          [f, ->(year) { !year.nil? && range.cover?(year) }]
        else
          keys = Array(condition).map { |v| Builder.filter_key(v, @normalizer) }.to_set
          [f, ->(values) { values.any? { |key| keys.include?(key) } }]
        end
      end
    end

    def pass?(doc, conditions) = conditions.all? { |f, test| test.call(f[:docs][doc]) }

    def latin?(token) = !token.match?(Tokenizer::CJK)

    # "doc * nf + field" => Set of positions, merged over the alternatives.
    def positions(tokens)
      nf = @fields.length
      map = {}
      tokens.each do |token|
        postings = @tokens.fetch(token, nil) or next
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
