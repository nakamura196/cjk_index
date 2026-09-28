# frozen_string_literal: true

require "json"

module CJKIndex
  # Builds a prebuilt inverted index that the browser runtime loads as JSON.
  #
  #   builder = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
  #   builder.add("item1.html", "title" => "東京帝國大學", "creator" => "…")
  #   File.write("search-index.json", builder.to_json)
  #
  # Format (version 1):
  #   {
  #     "format": "cjk_index/1",
  #     "fields": ["title", "creator"],
  #     "boosts": [3, 1],
  #     "refs":   ["item1.html", ...],
  #     "tokens": { "東京": [doc, field, tf, doc, field, tf, ...], ... }
  #   }
  # doc and field are positions in "refs" and "fields". Postings are flat
  # integer triples because that is the smallest plain-JSON form.
  class Builder
    FORMAT = "cjk_index/1"

    attr_reader :fields, :refs

    def initialize(fields:, boosts: {})
      raise ArgumentError, "fields must not be empty" if fields.empty?

      @fields = fields.map(&:to_s)
      @boosts = @fields.map { |f| (boosts[f] || boosts[f.to_sym] || 1).to_f }
      @refs = []
      @postings = Hash.new { |h, k| h[k] = [] }
    end

    # doc is a Hash of field name => value. Array values are indexed as
    # separate strings (e.g. multi-valued subject fields).
    def add(ref, doc)
      doc_index = @refs.length
      @refs << ref.to_s
      @fields.each_with_index do |field, field_index|
        value = doc[field] || doc[field.to_sym]
        next if value.nil?

        counts = Hash.new(0)
        Array(value).each do |v|
          Tokenizer.tokenize(v.to_s, unigrams: true).each { |t| counts[t] += 1 }
        end
        counts.each { |token, tf| @postings[token].push(doc_index, field_index, tf) }
      end
      self
    end

    def to_h
      {
        "format" => FORMAT,
        "fields" => @fields,
        "boosts" => @boosts.map { |b| b == b.to_i ? b.to_i : b },
        "refs" => @refs,
        "tokens" => @postings.sort.to_h
      }
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end
  end
end
