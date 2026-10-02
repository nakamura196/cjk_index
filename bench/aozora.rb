# frozen_string_literal: true

# Index size and query time on Aozora Bunko (public-domain Japanese literature).
#
# Data: globis-university/aozorabunko-clean on Hugging Face (16,951 works,
# CC BY 4.0 for the dataset; the texts are in the public domain):
#   curl -L -o aozora.jsonl.gz https://huggingface.co/datasets/globis-university/aozorabunko-clean/resolve/main/aozorabunko-dedupe-clean.jsonl.gz
#
# Usage:
#   ruby -Ilib bench/aozora.rb aozora.jsonl.gz catalog 16951
#   ruby -Ilib bench/aozora.rb aozora.jsonl.gz fulltext 1000
#
# catalog:  title, author and the first 200 characters of the text (like a
#           collection site's records)
# fulltext: title, author and the whole text
#
# Prints one Markdown table row. Query times are medians of 5 runs per query;
# the browser runtime is timed under Node with the same index and queries.

require "cjk_index"
require "json"
require "zlib"
require "tmpdir"
require "open3"

path, mode, count = ARGV
count = Integer(count || 1000)
abort "mode must be catalog or fulltext" unless %w[catalog fulltext].include?(mode)

QUERIES = %w[
  東京 明治 汽車 戦争 恋愛 月夜 電信柱 帝国大学 吾輩は猫である 坊っちゃん
  銀河鉄道 羅生門 蜘蛛の糸 夏目漱石 宮沢賢治 芥川 ふるさと ランプ 停車場 存在しない語句
].freeze

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def median(xs) = xs.sort[xs.size / 2]

docs = []
Zlib::GzipReader.open(path) do |gz|
  gz.each_line do |line|
    break if docs.size >= count

    d = JSON.parse(line)
    m = d["meta"]
    text = d["text"]
    text = text[0, 200] if mode == "catalog"
    docs << [m["作品ID"], { "title" => m["作品名"], "author" => "#{m['姓']}#{m['名']}", "text" => text }]
  end
end
chars = docs.sum { |_, d| d["text"].size }

t = now
builder = CJKIndex::Builder.new(fields: %w[title author text], boosts: { "title" => 3, "author" => 2 })
docs.each { |ref, d| builder.add(ref, d) }
json = builder.to_json
build = now - t
docs = nil
GC.start

gzip = Zlib.gzip(json, level: 9).bytesize

t = now
searcher = CJKIndex::Searcher.new(json)
load = now - t

ruby_times = {}
hits = {}
QUERIES.each do |q|
  ruby_times[q] = median(Array.new(5) { t = now; r = searcher.search(q); hits[q] = r.size; now - t })
end
rss_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0

node = Dir.mktmpdir do |dir|
  File.write(File.join(dir, "index.json"), json)
  File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source)
  File.write(File.join(dir, "run.js"), <<~JS)
    const c = require('./cjk-index.js');
    const fs = require('fs');
    const queries = JSON.parse(process.argv[2]);
    let t = performance.now();
    const idx = new c.Index(JSON.parse(fs.readFileSync(__dirname + '/index.json', 'utf8')));
    const load = performance.now() - t;
    const times = {}, hits = {};
    for (const q of queries) {
      const runs = [];
      for (let i = 0; i < 5; i++) { t = performance.now(); hits[q] = idx.search(q).length; runs.push(performance.now() - t); }
      times[q] = runs.sort((a, b) => a - b)[2];
    }
    console.log(JSON.stringify({ load, times, hits }));
  JS
  out, err, status = Open3.capture3("node", File.join(dir, "run.js"), JSON.generate(QUERIES))
  abort err unless status.success?
  JSON.parse(out)
end

mismatch = QUERIES.reject { |q| node["hits"][q] == hits[q] }
abort "hit counts differ between Ruby and Node: #{mismatch.join(', ')}" unless mismatch.empty?

ms = ->(s) { format("%.2f", s * 1000) }
puts format(
  "| %s | %d | %.1f M | %.1f s | %.1f MB | %.1f MB | %.0f MB | %.2f s | %s / %s ms | %.2f s | %s / %s ms |",
  mode, count, chars / 1e6, build, json.bytesize / 1e6, gzip / 1e6, rss_mb, load,
  ms.(median(ruby_times.values)), ms.(ruby_times.values.max),
  node["load"] / 1000, format("%.2f", median(node["times"].values)), format("%.2f", node["times"].values.max)
)
warn "hits: #{hits.map { |q, n| "#{q}=#{n}" }.join(' ')}"
