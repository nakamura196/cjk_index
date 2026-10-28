# frozen_string_literal: true

require "json"

module CJKIndex
  # Builds a prebuilt inverted index that the browser runtime loads as JSON.
  #
  #   builder = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 },
  #                                   filters: { "type" => "value", "date" => "year" })
  #   builder.add("item1.html", "title" => "東京帝國大學", "creator" => "…", "type" => "地図", "date" => "1900")
  #   File.write("search-index.json", builder.to_json)
  #
  # Format (version 3):
  #   {
  #     "format":  "cjk_index/3",
  #     "variants": ["ja"],
  #     "fields":  ["title", "creator"],
  #     "boosts":  [3, 1],
  #     "refs":    ["item1.html", ...],
  #     "lengths": [len(doc0.title), len(doc0.creator), len(doc1.title), ...],
  #     "tokens":  { "東京": [doc, field, n, pos1, ..., posn, doc, field, n, ...], ... },
  #     "filters": {
  #       "type": { "kind": "value", "values": ["地図", ...], "docs": [[0], [], ...] },
  #       "date": { "kind": "year", "docs": [1900, null, ...] }
  #     }
  #   }
  # doc and field are positions in "refs" and "fields"; n is the number of
  # occurrences and pos are character offsets in the normalized field text.
  # Offsets let the runtime require the bigrams of a query to be adjacent
  # (exact substring match); lengths feed BM25 ranking.
  # "filters" is present only when filters were configured. A value filter
  # stores each distinct value once (by its folded form, as first written)
  # and lists the values of each document by number; a year filter stores one
  # year or null per document. Version 2 is the same without "filters".
  #
  # Documents can be removed and replaced (remove, update), also in an index
  # read back with Builder.load. to_h is then the same as for an index built
  # from scratch with the remaining documents in the same order.
  class Builder
    FORMAT = "cjk_index/3"
    FORMATS = ["cjk_index/2", FORMAT].freeze

    # Gap between the values of a multi-valued field, so that a phrase cannot
    # match across two values.
    VALUE_GAP = 1

    FILTER_KINDS = %w[value year].freeze

    # Space, tab and line breaks, written out so that Ruby and JavaScript agree.
    WHITESPACE = /[ \t\n\r\f\v]+/

    attr_reader :fields, :normalizer, :filters, :version

    # normalizer must match the one the runtime script was generated with
    # (Runtime.source(normalizer:)); the index records its tables and the
    # runtime refuses an index built with different ones.
    # filters: field name => "value" or "year", or { "kind" => "value", "separator" => ";" }
    # for several values written in one string; an Array of names means "value" for each.
    def initialize(fields:, boosts: {}, normalizer: Normalizer.default, filters: {})
      raise ArgumentError, "fields must not be empty" if fields.empty?

      @normalizer = normalizer
      @fields = fields.map(&:to_s)
      @boosts = @fields.map { |f| (boosts[f] || boosts[f.to_sym] || 1).to_f }
      @filters = Builder.filter_specs(filters)
      # Indexed by slot; a removed document leaves nil until to_h renumbers.
      @refs = []
      @lengths = []
      @filter_values = []
      @doc_tokens = []
      @doc_tokens_complete = true
      @postings = Hash.new { |h, k| h[k] = [] }
      @slots = Hash.new { |h, k| h[k] = [] }
      @count = 0
      @version = 0
    end

    def self.filter_specs(filters)
      filters = filters.to_h { |name| [name, "value"] } if filters.is_a?(Array)
      filters.to_h do |name, spec|
        spec = { "kind" => spec } unless spec.is_a?(Hash)
        spec = spec.to_h { |k, v| [k.to_s, v.to_s] }
        unless FILTER_KINDS.include?(spec["kind"])
          raise ArgumentError, "cjk_index: filter #{name} has kind #{spec['kind'].inspect}; use value or year"
        end

        [name.to_s, spec.slice("kind", "separator")]
      end
    end

    # Reads an index written by to_json (String) or to_h back, to update it.
    # A value filter keeps the form of each value that the index stored.
    def self.load(index)
      data = index.is_a?(String) ? JSON.parse(index) : index
      unless data.is_a?(Hash) && FORMATS.include?(data["format"])
        raise ArgumentError, "cjk_index: unsupported index format #{data.is_a?(Hash) ? data['format'].inspect : data.class}"
      end

      filters = (data["filters"] || {}).transform_values { |f| f.slice("kind", "separator") }
      builder = new(fields: data["fields"], boosts: data["fields"].zip(data["boosts"]).to_h,
                    normalizer: Normalizer.new(tables: data["variants"]), filters: filters)
      builder.send(:restore, data)
      builder
    end

    # Folded form of a value filter's value, used to compare values.
    def self.filter_key(value, normalizer)
      normalizer.normalize(value.to_s).gsub(WHITESPACE, " ").delete_prefix(" ").delete_suffix(" ")
    end

    # The first four-digit number in a value (after folding full-width digits).
    def self.year(value, normalizer)
      return value.to_i if value.is_a?(Numeric)
      return value.year if value.respond_to?(:year) # Time, Date (YAML front matter)

      normalizer.normalize(value.to_s)[/(?<!\d)\d{4}(?!\d)/]&.to_i
    end

    # Refs of the documents in the index, in index order.
    def refs = holes? ? @refs.compact : @refs

    def size = @count

    def include?(ref) = !@slots[ref.to_s].empty?

    # doc is a Hash of field name => value. Array values are indexed as
    # separate strings (e.g. multi-valued subject fields).
    def add(ref, doc)
      slot = @refs.length
      @refs << ref.to_s
      @slots[ref.to_s] << slot
      @count += 1
      index(slot, doc)
      self
    end

    # Removes the first document added with ref. Returns false if there is none.
    def remove(ref)
      slot = @slots[ref.to_s].shift or return false

      unindex(slot)
      @refs[slot] = nil
      @lengths.fill(nil, slot * @fields.length, @fields.length)
      @filter_values[slot] = nil
      @count -= 1
      true
    end

    # Replaces the document with ref in place, or adds it if there is none.
    def update(ref, doc)
      slot = @slots[ref.to_s].first or return add(ref, doc)

      unindex(slot)
      index(slot, doc)
      self
    end

    def to_h
      live = holes? ? @refs.each_index.reject { |slot| @refs[slot].nil? } : @refs.each_index.to_a
      h = {
        "format" => FORMAT,
        "variants" => @normalizer.tables,
        "fields" => @fields,
        "boosts" => @boosts.map { |b| b == b.to_i ? b.to_i : b },
        "refs" => live.map { |slot| @refs[slot] },
        "lengths" => live.flat_map { |slot| @lengths[slot * @fields.length, @fields.length] },
        "tokens" => holes? ? renumbered_postings(live) : @postings.sort.to_h
      }
      h["filters"] = @filters.to_h { |name, spec| [name, filter_to_h(name, spec, live)] } unless @filters.empty?
      h
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end

    # For Searcher: the current documents by slot, with nil for removed ones.
    def live_data # :nodoc:
      {
        "variants" => @normalizer.tables, "fields" => @fields, "boosts" => @boosts,
        "refs" => @refs, "lengths" => @lengths, "tokens" => @postings, "count" => @count,
        "filters" => @filters.to_h do |name, spec|
          [name, { "kind" => spec["kind"], "docs" => @filter_values.map { |v| v && v[name] } }]
        end
      }
    end

    private

    def index(slot, doc)
      in_place = slot < @refs.length - 1
      tokens = []
      @fields.each_with_index do |field, field_index|
        positions = Hash.new { |h, k| h[k] = [] }
        base = 0
        Array(value_of(doc, field)).each do |v|
          text = v.to_s
          Tokenizer.tokens_with_offsets(text, unigrams: true, normalizer: @normalizer)
                   .each { |t, offset| positions[t] << (base + offset) }
          base += @normalizer.normalize(text).length + VALUE_GAP
        end
        @lengths[(slot * @fields.length) + field_index] = [base - VALUE_GAP, 0].max
        positions.each do |token, offsets|
          postings = @postings[token]
          # A document replaced in place goes before the later slots, so that
          # every list stays in the order a fresh build writes.
          at = in_place ? insertion_point(postings, slot, field_index) : postings.length
          postings.insert(at, slot, field_index, offsets.length, *offsets)
        end
        tokens.concat(positions.keys)
      end
      @doc_tokens[slot] = tokens.uniq
      @filter_values[slot] = @filters.to_h { |name, spec| [name, filter_value(spec, value_of(doc, name))] }
      @version += 1
    end

    def unindex(slot)
      doc_tokens(slot).each do |token|
        postings = @postings[token]
        kept = []
        i = 0
        while i < postings.length
          n = 3 + postings[i + 2]
          kept.concat(postings[i, n]) unless postings[i] == slot
          i += n
        end
        if kept.empty? then @postings.delete(token)
        else @postings[token] = kept
        end
      end
      @doc_tokens[slot] = nil
      @version += 1
    end

    def value_of(doc, field) = doc[field] || doc[field.to_sym]

    # Value filter: [[key, value as written], ...]; year filter: Integer or nil.
    def filter_value(spec, raw)
      # Array() would split a Time into its parts
      raw = raw.is_a?(Array) ? raw : [raw].compact
      if spec["kind"] == "year"
        raw.each do |v|
          year = Builder.year(v, @normalizer)
          return year if year
        end
        return nil
      end

      raw.flat_map { |v| spec["separator"] ? v.to_s.split(spec["separator"]) : [v.to_s] }
                .map { |v| v.gsub(WHITESPACE, " ").strip }.reject(&:empty?)
                .map { |v| [Builder.filter_key(v, @normalizer), v] }.uniq(&:first)
    end

    def filter_to_h(name, spec, live)
      return { "kind" => "year", "docs" => live.map { |slot| @filter_values[slot][name] } } if spec["kind"] == "year"

      ids = {}
      values = []
      docs = live.map do |slot|
        @filter_values[slot][name].map do |key, value|
          ids.fetch(key) do
            values << value
            ids[key] = values.length - 1
          end
        end
      end
      { "kind" => "value", "values" => values, "docs" => docs }.merge(spec.slice("separator"))
    end

    def holes? = @count < @refs.length

    # Where an entry for slot and field goes in a list ordered by slot, then field.
    def insertion_point(postings, slot, field_index)
      i = 0
      while i < postings.length && (postings[i] < slot || (postings[i] == slot && postings[i + 1] < field_index))
        i += 3 + postings[i + 2]
      end
      i
    end

    # Postings with slots renumbered to positions among the live documents.
    # Removed slots appear in no list any more, and renumbering keeps the
    # order, so sorted lists stay sorted.
    def renumbered_postings(live)
      number = []
      live.each_with_index { |slot, doc| number[slot] = doc }
      @postings.sort.to_h do |token, postings|
        postings = postings.dup
        i = 0
        while i < postings.length
          postings[i] = number[postings[i]]
          i += 3 + postings[i + 2]
        end
        [token, postings]
      end
    end

    # Tokens of a slot. An index read with load does not record them, so the
    # first change scans the postings once.
    def doc_tokens(slot)
      unless @doc_tokens_complete
        @postings.each do |token, postings|
          i = 0
          while i < postings.length
            (@doc_tokens[postings[i]] ||= []) << token
            i += 3 + postings[i + 2]
          end
        end
        @doc_tokens.each { |tokens| tokens&.uniq! }
        @doc_tokens_complete = true
      end
      @doc_tokens[slot] || []
    end

    def restore(data)
      @refs = data["refs"].dup
      @refs.each_with_index { |ref, slot| @slots[ref] << slot }
      @count = @refs.length
      @lengths = data["lengths"].dup
      unless @lengths.length == @count * @fields.length
        raise ArgumentError, "cjk_index: index has #{@lengths.length} lengths for #{@count} documents"
      end

      data["tokens"].each { |token, postings| @postings[token] = postings.dup }
      filters = data["filters"] || {}
      @filter_values = Array.new(@count) do |slot|
        filters.to_h do |name, f|
          value = f["docs"][slot]
          next [name, value] if f["kind"] == "year"

          [name, value.map { |id| [Builder.filter_key(f["values"][id], @normalizer), f["values"][id]] }]
        end
      end
      @doc_tokens = []
      @doc_tokens_complete = false
    end
  end
end
