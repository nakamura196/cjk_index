# frozen_string_literal: true

# The options compared before choosing format 4: encodings of the posting
# lists, and ways of assigning tokens to shards.
#
# Usage (from the repository root):
#   ruby -Ilib bench/layouts.rb <source>        (source: see corpus.rb)
#
# Encodings (sizes of the "tokens" object alone, gzip level 9 and 6):
#   A  format 3: JSON arrays [doc, field, n, pos, ...]
#   B  arrays with document gaps and position gaps
#   C  arrays with key gaps (key = doc * fields + field) and position gaps
#   D  C as BER integers (pack "w"), base64
#   E  C as the characters of Postings (format 4)
# Shards (with encoding E): tokens assigned by an FNV-1a hash of their code
# points modulo a number of shards, or by cutting the sorted tokens at a
# size (what write_split does). For each: number of files, gzip size of all
# shards, and the gzip bytes of the shards holding the tokens of each query
# of the source (exact tokens only: no Latin expansion, no manifest),
# median and max over the queries.

require "cjk_index"
require "json"
require "zlib"
require_relative "corpus"

source = Corpus.load(ARGV.fetch(0))
builder = CJKIndex::Builder.new(fields: source.fields, boosts: source.boosts)
source.docs.each { |ref, d| builder.add(ref, d) }
NF = source.fields.length
ENCODED = builder.to_h["tokens"]
FLAT = ENCODED.transform_values { |s| CJKIndex::Postings.decode(s, NF) }

def gaps(flat, keys:)
  out = []
  prev_key = -1
  prev_doc = 0
  i = 0
  while i < flat.length
    n = flat[i + 2]
    if keys
      key = (flat[i] * NF) + flat[i + 1]
      out << (key - prev_key - 1) << n
      prev_key = key
    else
      out << (flat[i] - prev_doc) << flat[i + 1] << n
      prev_doc = flat[i]
    end
    last = 0
    flat[i + 3, n].each do |pos|
      out << (pos - last)
      last = pos
    end
    i += 3 + n
  end
  out
end

def size(tokens)
  json = JSON.generate(tokens)
  format("raw %6.1f MB, gzip -9 %6.1f MB, gzip -6 %6.1f MB", json.bytesize / 1e6, Zlib.gzip(json, level: 9).bytesize / 1e6,
         Zlib.gzip(json, level: 6).bytesize / 1e6)
end

puts "#{source.name}: #{ENCODED.size} tokens"
{
  "A format 3 arrays" => ->(f) { f },
  "B document gaps" => ->(f) { gaps(f, keys: false) },
  "C key gaps" => ->(f) { gaps(f, keys: true) },
  "D C as BER, base64" => ->(f) { [gaps(f, keys: true).pack("w*")].pack("m0") },
  "E C as Postings (format 4)" => nil
}.each do |name, encode|
  puts format("  %-28s %s", name, size(encode ? FLAT.transform_values(&encode) : ENCODED))
end

query_tokens = source.queries.map { |q| CJKIndex::Tokenizer.phrases(q).flatten(1).map(&:first).uniq }

def fnv(token) = token.each_codepoint.reduce(0x811c9dc5) { |h, c| ((h ^ c) * 0x01000193) & 0xffffffff }

report = lambda do |name, assign|
  groups = Hash.new { |h, k| h[k] = {} }
  ENCODED.each { |t, e| groups[assign[t]][t] = e }
  gz = groups.transform_values { |h| Zlib.gzip(JSON.generate(h), level: 9).bytesize }
  fetched = query_tokens.map { |tokens| tokens.filter_map { |t| ENCODED.key?(t) ? assign[t] : nil }.uniq.sum { |i| gz[i] } }.sort
  puts format("  %-22s files %6d, all %6.2f MB, per query %7.1f / %7.1f KB", name, gz.size, gz.values.sum / 1e6,
              fetched[fetched.size / 2] / 1e3, fetched.max / 1e3)
end
[256, 1024, 4096].each { |n| report.call("hash, #{n} shards", ->(t) { fnv(t) % n }) }
sorted = ENCODED.keys.sort
[8_000, 32_000, 128_000].each do |target|
  shard = {}
  id = 0
  bytes = 0
  sorted.each do |t|
    pair = t.bytesize + ENCODED[t].bytesize + 6
    if bytes.positive? && bytes + pair > target
      id += 1
      bytes = 0
    end
    shard[t] = id
    bytes += pair
  end
  report.call("sorted, #{target} B", shard)
end
report.call("one file per token", ->(t) { t })
