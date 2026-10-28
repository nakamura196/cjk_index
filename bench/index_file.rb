# frozen_string_literal: true

# An index file shared by processes (CJKIndex::IndexFile), on the Aozora
# Bunko catalog records (see bench/aozora.rb for the data).
#
# Usage:
#   ruby -Ilib bench/index_file.rb aozora.jsonl.gz 16951
#
# Prints one line per step. Times are medians of 5 runs where a step can be
# repeated.

require "cjk_index"
require "json"
require "tmpdir"
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

builder = CJKIndex::Builder.new(fields: %w[title author text], boosts: { "title" => 3, "author" => 2 },
                                filters: { "author" => "value", "kana" => "value", "year" => "year" })
docs.each { |ref, d| builder.add(ref, d) }
refs = docs.map(&:first)
rng = Random.new(1)
sample = Array.new(6) { refs.sample(random: rng) }
changed = ->(ref) { docs.assoc(ref)[1].merge("title" => "#{docs.assoc(ref)[1]['title']} 改訂版") }

Dir.mktmpdir do |dir|
  file_path = File.join(dir, "index.json")
  writer = CJKIndex::IndexFile.new(file_path)
  reader = CJKIndex::IndexFile.new(file_path)

  puts "records: #{count}"
  puts format("write a full build (to_json, fsync, rename): %.2f s", time { writer.write(builder) })
  puts format("index file: %.1f MB", File.size(file_path) / 1e6)
  puts format("first searcher in a process (loads the file): %.2f s", time { reader.searcher })
  puts format("searcher when the file has not changed: %.3f ms",
              median(Array.new(5) { time { reader.searcher } }) * 1000)
  puts format("first update in a process (loads, updates, writes): %.2f s",
              time { writer.update { |b| b.update(sample[0], changed.(sample[0])) } })
  puts format("later updates from the same process: %.2f s",
              median(sample[1, 5].map { |ref| time { writer.update { |b| b.update(ref, changed.(ref)) } } }))
  puts format("5 updates in one block: %.2f s",
              time { writer.update { |b| sample[1, 5].each { |ref| b.update(ref, changed.(ref)) } } })
  other = CJKIndex::IndexFile.new(file_path)
  other.update { |b| b.update(sample[0], changed.(sample[0])) }
  puts format("update after another process wrote (loads again): %.2f s",
              time { writer.update { |b| b.update(sample[1], changed.(sample[1])) } })
  puts format("searcher after the file changed (loads again): %.2f s", time { reader.searcher })
end
