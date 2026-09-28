# frozen_string_literal: true

require "json"

module CJKIndex
  # Builds a prebuilt inverted index that the browser runtime loads as JSON.
  #
  #   builder = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
  #   builder.add("item1.html", "title" => "東京帝國大學", "creator" => "…")
  #   File.write("search-index.json", builder.to_json)
  #
  # Format (version 2):
  #   {
  #     "format":  "cjk_index/2",
  #     "fields":  ["title", "creator"],
  #     "boosts":  [3, 1],
  #     "refs":    ["item1.html", ...],
  #     "lengths": [len(doc0.title), len(doc0.creator), len(doc1.title), ...],
  #     "tokens":  { "東京": [doc, field, n, pos1, ..., posn, doc, field, n, ...], ... }
  #   }
  # doc and field are positions in "refs" and "fields"; n is the number of
  # occurrences and pos are character offsets in the normalized field text.
  # Offsets let the runtime require the bigrams of a query to be adjacent
  # (exact substring match); lengths feed BM25 ranking.
  class Builder
    FORMAT = "cjk_index/2"

    # Gap between the values of a multi-valued field, so that a phrase cannot
    # match across two values.
    VALUE_GAP = 1

    attr_reader :fields, :refs

    def initialize(fields:, boosts: {})
      raise ArgumentError, "fields must not be empty" if fields.empty?

      @fields = fields.map(&:to_s)
      @boosts = @fields.map { |f| (boosts[f] || boosts[f.to_sym] || 1).to_f }
      @refs = []
      @lengths = []
      @postings = Hash.new { |h, k| h[k] = [] }
    end

    # doc is a Hash of field name => value. Array values are indexed as
    # separate strings (e.g. multi-valued subject fields).
    def add(ref, doc)
      doc_index = @refs.length
      @refs << ref.to_s
      @fields.each_with_index do |field, field_index|
        value = doc[field] || doc[field.to_sym]
        positions = Hash.new { |h, k| h[k] = [] }
        base = 0
        Array(value).each do |v|
          text = v.to_s
          Tokenizer.tokens_with_offsets(text, unigrams: true).each { |t, offset| positions[t] << (base + offset) }
          base += Normalizer.normalize(text).length + VALUE_GAP
        end
        @lengths << [base - VALUE_GAP, 0].max
        positions.each { |token, offsets| @postings[token].push(doc_index, field_index, offsets.length, *offsets) }
      end
      self
    end

    def to_h
      {
        "format" => FORMAT,
        "fields" => @fields,
        "boosts" => @boosts.map { |b| b == b.to_i ? b.to_i : b },
        "refs" => @refs,
        "lengths" => @lengths,
        "tokens" => @postings.sort.to_h
      }
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end
  end
end
