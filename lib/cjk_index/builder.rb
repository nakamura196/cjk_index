# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"

module CJKIndex
  # Builds a prebuilt inverted index that the browser runtime loads as JSON.
  #
  #   builder = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 },
  #                                   filters: { "type" => "value", "date" => "year" })
  #   builder.add("item1.html", "title" => "東京帝國大學", "creator" => "…", "type" => "地図", "date" => "1900")
  #   builder.write("search-index.json")     # one file (the same as File.write(path, builder.to_json))
  #   builder.write_split("search-index")    # or a manifest and shards, loaded as a query needs them
  #
  # Format (version 4), one file:
  #   {
  #     "format":  "cjk_index/4",
  #     "variants": ["ja"],
  #     "fields":  ["title", "creator"],
  #     "boosts":  [3, 1],
  #     "refs":    ["item1.html", ...],
  #     "lengths": [len(doc0.title), len(doc0.creator), len(doc1.title), ...],
  #     "tokens":  { "東京": "#$#'+…", ... },
  #     "filters": {
  #       "type": { "kind": "value", "values": ["地図", ...], "docs": [[0], [], ...] },
  #       "date": { "kind": "year", "docs": [1900, null, ...] }
  #     }
  #   }
  # Each token maps to its posting list: for each document and field where it
  # occurs, the number of occurrences and their character offsets in the
  # normalized field text, written compactly as a string (see Postings).
  # Offsets let the runtime require the bigrams of a query to be adjacent
  # (exact substring match); lengths feed BM25 ranking.
  # "filters" is present only when filters were configured. A value filter
  # stores each distinct value once (by its folded form, as first written)
  # and lists the values of each document by number; a year filter stores one
  # year or null per document.
  #
  # Split (write_split): a directory with the manifest index.json, which is
  # the same without "tokens" and adds
  #     "latin":  "9c1d…07.json",                 file of the Latin tokens
  #     "shards": [["一", "3f2a…e1.json"], ...]   first token and file of each shard
  # the shard files, each a JSON object of tokens => posting lists, and the
  # file of Latin tokens: a JSON array of every token without CJK characters,
  # sorted, that lets the runtime expand Latin prefixes and typos. The
  # tokens are sorted by code point and cut into shards of about shard_size
  # bytes, so a token is in the last shard whose first token is not greater.
  # A shard file is named after a digest of its content, so a browser may
  # cache it: a changed shard gets a new name. The runtime loads the manifest
  # (refs, lengths, filters: what a blank query and facets need), and fetches
  # only the shards of the tokens of a query, and the Latin tokens when the
  # query has a Latin word (on a technical blog they are most of the
  # manifest's size otherwise).
  #
  # Older formats, still read by Builder.load, Searcher and the runtime:
  # version 3 writes each posting list as a JSON array
  # [doc, field, n, pos1, ..., posn, doc, field, n, ...] (doc and field are
  # positions in "refs" and "fields"); version 2 is version 3 without "filters".
  #
  # Documents can be removed and replaced (remove, update), also in an index
  # read back with Builder.load or Builder.read. to_h is then the same as for
  # an index built from scratch with the remaining documents in the same order.
  class Builder
    FORMAT = "cjk_index/4"
    FORMATS = ["cjk_index/2", "cjk_index/3", FORMAT].freeze

    # Name of the manifest in a split index.
    MANIFEST = "index.json"
    # Default size of a shard in bytes (of JSON, before compression).
    SHARD_SIZE = 32_000
    # Names of shard files: a digest of the content.
    SHARD_NAME = /\A\h{16}\.json\z/

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
      # Indexed by slot; a removed document leaves nil until the slots are
      # renumbered (compact).
      @refs = []
      @lengths = []
      @filter_values = []
      # token => posting list in the encoding of Postings, with slots for
      # documents (the same as the format while there are no removed slots).
      @postings = {}
      # token => key of its last entry, filled as entries are appended.
      @last_keys = {}
      # Tokens of each slot, kept only once a document has been removed or
      # replaced (nil until then): a build that only adds does not need them.
      @doc_tokens = nil
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
    # Reads formats 2, 3 and 4; a split index is read with read.
    # A value filter keeps the form of each value that the index stored.
    def self.load(index)
      data = index.is_a?(String) ? JSON.parse(index) : index
      unless data.is_a?(Hash) && FORMATS.include?(data["format"])
        raise ArgumentError, "cjk_index: unsupported index format #{data.is_a?(Hash) ? data['format'].inspect : data.class}"
      end
      raise ArgumentError, "cjk_index: a split index is read with Builder.read(directory)" unless data["tokens"]

      filters = (data["filters"] || {}).transform_values { |f| f.slice("kind", "separator") }
      normalizer = Normalizer.new(tables: data["variants"])
      normalizer.check!(data)
      builder = new(fields: data["fields"], boosts: data["fields"].zip(data["boosts"]).to_h,
                    normalizer: normalizer, filters: filters)
      builder.send(:restore, data)
      builder
    end

    # Reads an index from a file (written by write or to_json) or from the
    # directory of a split index (written by write_split), to update it.
    def self.read(path)
      load(Builder.read_data(path))
    end

    # The index at path as one Hash with "tokens", for a file or a split
    # index (its directory or its manifest).
    def self.read_data(path) # :nodoc:
      path = File.join(path, MANIFEST) if File.directory?(path)
      data = JSON.parse(File.read(path, encoding: "UTF-8"))
      return data unless data.is_a?(Hash) && data["shards"]

      dir = File.dirname(path)
      tokens = {}
      data["shards"].each { |_, file| tokens.merge!(JSON.parse(File.read(File.join(dir, file), encoding: "UTF-8"))) }
      data.reject { |k, _| %w[latin shards].include?(k) }.merge("tokens" => tokens)
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
      compact
      h = header
      h["tokens"] = @postings.keys.sort!.to_h { |token| [token, @postings[token].dup] }
      h["filters"] = filters_h unless @filters.empty?
      h
    end

    def to_json(*_args)
      JSON.generate(to_h)
    end

    # Writes the index to one file, the same as File.write(path, to_json),
    # without first making the whole JSON in memory. The file is written to a
    # temporary file and renamed, so a reader never sees it partly written.
    def write(path)
      compact
      atomic_write(path) do |io|
        io << JSON.generate(header).delete_suffix("}") << ',"tokens":{'
        @postings.keys.sort!.each_with_index do |token, i|
          io << "," if i.positive?
          io << JSON.generate(token) << ':"' << @postings[token] << '"'
        end
        io << "}"
        io << ',"filters":' << JSON.generate(filters_h) unless @filters.empty?
        io << "}"
      end
      path
    end

    # Writes a split index to the directory dir: the manifest index.json and
    # shard files of about shard_size bytes (see the format above). Shard
    # files are written first and the manifest last (renamed into place), and
    # shard files that the new manifest does not list are then removed.
    # Returns the path of the manifest.
    def write_split(dir, shard_size: SHARD_SIZE)
      FileUtils.mkdir_p(dir)
      names = []
      manifest = nil
      each_split_file(shard_size: shard_size) do |name, content|
        if name == MANIFEST
          manifest = content
        else
          path = File.join(dir, name)
          atomic_write(path) { |io| io << content } unless File.exist?(path) && File.size(path) == content.bytesize
          names << name
        end
      end
      atomic_write(File.join(dir, MANIFEST)) { |io| io << manifest }
      Dir.children(dir).each do |name|
        File.delete(File.join(dir, name)) if name.match?(SHARD_NAME) && !names.include?(name)
      end
      File.join(dir, MANIFEST)
    end

    # Yields [name, content] for each file of a split index: the shards, the
    # Latin tokens, then the manifest (MANIFEST). For writing them somewhere other than a
    # directory on disk (the Jekyll plugin uses it).
    def each_split_file(shard_size: SHARD_SIZE)
      return enum_for(:each_split_file, shard_size: shard_size) unless block_given?

      compact
      shards = []
      latin = []
      part = []
      bytes = 0
      first = nil
      flush = lambda do
        content = "{#{part.join(',')}}"
        name = "#{Digest::SHA256.hexdigest(content)[0, 16]}.json"
        yield name, content
        shards << [first, name]
        part = []
        bytes = 0
      end
      @postings.keys.sort!.each do |token|
        latin << token unless token.match?(Tokenizer::CJK)
        pair = "#{JSON.generate(token)}:\"#{@postings[token]}\""
        flush.call if bytes.positive? && bytes + pair.bytesize > shard_size
        first = token if part.empty?
        part << pair
        bytes += pair.bytesize + 1
      end
      flush.call unless part.empty?
      content = JSON.generate(latin)
      latin_name = "#{Digest::SHA256.hexdigest(content)[0, 16]}.json"
      yield latin_name, content
      manifest = header.merge("latin" => latin_name, "shards" => shards)
      manifest["filters"] = filters_h unless @filters.empty?
      yield MANIFEST, JSON.generate(manifest)
    end

    # For Searcher: the current documents by slot, with nil for removed ones.
    def live_data # :nodoc:
      {
        "format" => FORMAT, "variants" => @normalizer.tables, "variant_digest" => @normalizer.digest,
        "fields" => @fields, "boosts" => @boosts,
        "refs" => @refs, "lengths" => @lengths, "tokens" => @postings, "count" => @count,
        "filters" => @filters.to_h do |name, spec|
          [name, { "kind" => spec["kind"], "docs" => @filter_values.map { |v| v && v[name] } }]
        end
      }
    end

    private

    def header
      {
        "format" => FORMAT,
        "variants" => @normalizer.tables,
        "variant_digest" => @normalizer.digest,
        "fields" => @fields,
        "boosts" => @boosts.map { |b| b == b.to_i ? b.to_i : b },
        "refs" => @refs.dup,
        "lengths" => @lengths.dup
      }
    end

    def filters_h = @filters.to_h { |name, spec| [name, filter_to_h(name, spec)] }

    def atomic_write(path)
      tmp = "#{path}.#{Process.pid}.tmp"
      File.open(tmp, "wb") { |io| yield io }
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end

    def index(slot, doc)
      nf = @fields.length
      # A document replaced in place goes before the later slots, so that
      # every list stays in the order a fresh build writes.
      in_place = slot < @refs.length - 1
      tokens = @doc_tokens ? [] : nil
      @fields.each_with_index do |field, field_index|
        positions = Hash.new { |h, k| h[k] = [] }
        base = 0
        Array(value_of(doc, field)).each do |v|
          text = @normalizer.normalize(v.to_s)
          Tokenizer.each_token(text, unigrams: true) { |t, offset| positions[t] << (base + offset) }
          base += text.length + VALUE_GAP
        end
        @lengths[(slot * nf) + field_index] = [base - VALUE_GAP, 0].max
        key = (slot * nf) + field_index
        positions.each do |token, offsets|
          if in_place
            @postings[token] = Postings.insert(@postings[token] || +"", key, offsets)
            @last_keys.delete(token)
          else
            list = (@postings[token] ||= +"")
            last = @last_keys.fetch(token) { Postings.last_key(list) }
            Postings.append(list, key - last - 1, offsets)
            @last_keys[token] = key
          end
        end
        tokens&.concat(positions.keys)
      end
      @doc_tokens[slot] = tokens.uniq if tokens
      @filter_values[slot] = @filters.to_h { |name, spec| [name, filter_value(spec, value_of(doc, name))] }
      @version += 1
    end

    def unindex(slot)
      nf = @fields.length
      first = slot * nf
      doc_tokens(slot).each do |token|
        kept = Postings.delete(@postings[token], first..(first + nf - 1))
        if kept.empty? then @postings.delete(token)
        else @postings[token] = kept
        end
        @last_keys.delete(token)
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

    def filter_to_h(name, spec)
      return { "kind" => "year", "docs" => @filter_values.map { |v| v[name] } } if spec["kind"] == "year"

      ids = {}
      values = []
      docs = @filter_values.map do |v|
        v[name].map do |key, value|
          ids.fetch(key) do
            values << value
            ids[key] = values.length - 1
          end
        end
      end
      { "kind" => "value", "values" => values, "docs" => docs }.merge(spec.slice("separator"))
    end

    def holes? = @count < @refs.length

    # Renumbers the slots to positions among the live documents, dropping the
    # removed ones. Renumbering keeps the order, so sorted lists stay sorted.
    def compact
      return unless holes?

      nf = @fields.length
      live = @refs.each_index.reject { |slot| @refs[slot].nil? }
      number = []
      live.each_with_index { |slot, doc| number[slot] = doc }
      @postings.each_key { |token| @postings[token] = Postings.renumber(@postings[token], nf, number) }
      @last_keys.clear
      @refs = live.map { |slot| @refs[slot] }
      @lengths = live.flat_map { |slot| @lengths[slot * nf, nf] }
      @filter_values = live.map { |slot| @filter_values[slot] }
      @doc_tokens = live.map { |slot| @doc_tokens[slot] } if @doc_tokens
      @slots.each_value { |slots| slots.map! { |slot| number[slot] } }
      @version += 1
    end

    # Tokens of a slot. They are not recorded until a document is first
    # removed or replaced; that first change scans the postings once.
    def doc_tokens(slot)
      unless @doc_tokens
        nf = @fields.length
        @doc_tokens = []
        @postings.each do |token, list|
          Postings.each_key(list) do |key|
            tokens = (@doc_tokens[key / nf] ||= [])
            tokens << token unless tokens.last.equal?(token)
          end
        end
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

      nf = @fields.length
      if data["format"] == FORMAT
        data["tokens"].each { |token, list| @postings[token] = +list }
      else
        data["tokens"].each { |token, flat| @postings[token] = Postings.encode(flat, nf) }
      end
      filters = data["filters"] || {}
      @filter_values = Array.new(@count) do |slot|
        filters.to_h do |name, f|
          value = f["docs"][slot]
          next [name, value] if f["kind"] == "year"

          [name, value.map { |id| [Builder.filter_key(f["values"][id], @normalizer), f["values"][id]] }]
        end
      end
    end
  end
end
