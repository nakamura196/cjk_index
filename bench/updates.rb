# frozen_string_literal: true

# Updating an index against rebuilding it, and the size of filters, on the
# Aozora Bunko catalog records (see bench/aozora.rb for the data).
#
# Usage:
#   ruby -Ilib bench/updates.rb aozora.jsonl.gz 16951
#
# Prints one line per step. Times are medians of 5 runs where a step can be
# repeated.

require "cjk_index"
require "json"
require "zlib"

path, count = ARGV
count = Integer(count || 1000)

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def median(xs) = xs.sort[xs.size / 2]

def time
  t = now
  yield
  now - t
end

docs = []
Zlib::GzipReader.open(path) do |gz|
  gz.each_line do |line|
    break if docs.size >= count

    d = JSON.parse(line)
    m = d["meta"]
    docs << [m["作品ID"], { "title" => m["作品名"], "author" => "#{m['姓']}#{m['名']}", "text" => d["text"][0, 200],
                           "kana" => m["文字遣い種別"], "year" => m["底本初版発行年1"] }]
  end
end

FIELDS = %w[title author text].freeze
BOOSTS = { "title" => 3, "author" => 2 }.freeze
build = lambda do |filters|
  b = CJKIndex::Builder.new(fields: FIELDS, boosts: BOOSTS, filters: filters)
  docs.each { |ref, d| b.add(ref, d) }
  b
end

plain = nil
t_build = time { plain = build.call({}) }
plain_json = plain.to_json
filtered = build.call({ "author" => "value", "kana" => "value", "year" => "year" })
filtered_json = filtered.to_json
gz = ->(s) { Zlib.gzip(s, level: 9).bytesize / 1e6 }
filters = filtered.to_h["filters"]

puts "records: #{count}"
puts format("full build: %.1f s", t_build)
puts format("index: %.1f MB (%.1f MB gzipped); with filters author/kana/year: %.1f MB (%.1f MB gzipped)",
            plain_json.bytesize / 1e6, gz.(plain_json), filtered_json.bytesize / 1e6, gz.(filtered_json))
puts "distinct values: author #{filters['author']['values'].size}, kana #{filters['kana']['values'].size}; " \
     "years found: #{filters['year']['docs'].compact.size}"

refs = docs.map(&:first)
rng = Random.new(1)
sample = Array.new(5) { refs.sample(random: rng) }
changed = ->(ref) { docs.assoc(ref)[1].merge("title" => "#{docs.assoc(ref)[1]['title']} 改訂版") }

puts format("update one record in a builder: %.1f ms",
            median(sample.map { |ref| time { plain.update(ref, changed.(ref)) } }) * 1000)
puts format("remove one record from a builder: %.1f ms",
            median(sample.uniq.map { |ref| time { plain.remove(ref) } }) * 1000)

loaded = nil
puts format("load the written index (Builder.load): %.2f s", time { loaded = CJKIndex::Builder.load(plain_json) })
puts format("first update after load (scans postings once): %.2f s",
            time { loaded.update(sample[0], changed.(sample[0])) })
puts format("later updates after load: %.1f ms",
            median(sample.drop(1).map { |ref| time { loaded.update(ref, changed.(ref)) } }) * 1000)
puts format("write the index again after updates (to_json): %.2f s", time { loaded.to_json })
loaded.remove(sample[0])
puts format("write the index again after a remove (to_json): %.2f s", time { loaded.to_json })

searcher = CJKIndex::Searcher.new(filtered)
searcher.search("東京")
filtered.update(sample[0], changed.(sample[0]))
puts format("first search after an update (Searcher refreshes): %.0f ms", time { searcher.search("東京") } * 1000)
puts format("search without changes: %.2f ms", median(Array.new(5) { time { searcher.search("東京") } }) * 1000)
puts format("filter only (author = 夏目漱石): %.2f ms, %d hits",
            median(Array.new(5) { time { searcher.search("", filter: { "author" => "夏目漱石" }) } }) * 1000,
            searcher.search("", filter: { "author" => "夏目漱石" }).size)
puts format("search with filter (東京, year 1900..1920): %.2f ms",
            median(Array.new(5) { time { searcher.search("東京", filter: { "year" => 1900..1920 }) } }) * 1000)
puts format("facets over all records (author): %.1f ms", median(Array.new(5) { time { searcher.facets("author") } }) * 1000)
