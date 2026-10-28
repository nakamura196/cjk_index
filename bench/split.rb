# frozen_string_literal: true

# What a browser fetches for a query from a split index, by shard size.
#
# Usage (from the repository root):
#   ruby -Ilib bench/split.rb <source> [shard size ...]
#
# source: see corpus.rb. Shard sizes in bytes, default 8000 32000 128000.
#
# Builds the index once, writes it as one file and split with each shard
# size, and runs the queries of the source in the browser script under Node.
# Each query starts from a freshly loaded manifest, so it fetches every
# shard it needs (as a first search on a page does). Fetching is simulated:
# files are read from disk and counted at their gzip size (level 9), which
# is what a server sending them compressed transfers. The results of every
# query must equal Searcher.load on the same directory (refs, order, scores).
#
# Prints one Markdown row per layout:
# | source | layout | files | first load (gzip) | all files (gzip) | fetched per query, median / max | requests per query, median / max | Node: load / first query median / max |

require "cjk_index"
require "json"
require "zlib"
require "tmpdir"
require "open3"
require_relative "corpus"

spec, *sizes = ARGV
abort "usage: split.rb <source> [shard size ...]" unless spec
sizes = (sizes.empty? ? %w[8000 32000 128000] : sizes).map { |s| Integer(s) }

source = Corpus.load(spec)
builder = CJKIndex::Builder.new(fields: source.fields, boosts: source.boosts)
source.docs.each { |ref, d| builder.add(ref, d) }

def median(xs) = xs.sort[xs.size / 2]
def kb(bytes) = format("%.1f KB", bytes / 1e3)

NODE = <<~JS
  const c = require(process.argv[2]);
  const fs = require('fs');
  const [dir, queries, gz] = JSON.parse(fs.readFileSync(0, 'utf8'));
  let fetched = [];
  globalThis.fetch = url => {
    const name = url.replace('https://example.test/', '');
    fetched.push(name);
    const text = fs.readFileSync(dir + '/' + name, 'utf8');
    return Promise.resolve({ ok: true, json: () => Promise.resolve(JSON.parse(text)) });
  };
  (async () => {
    const out = { queries: {} };
    let t = performance.now();
    await c.load('https://example.test/index.json');
    out.load = performance.now() - t;
    for (const q of queries) {
      const idx = await c.load('https://example.test/index.json');
      fetched = [];
      t = performance.now();
      const results = await idx.searchAsync(q);
      const ms = performance.now() - t;
      out.queries[q] = { ms, files: fetched.length, bytes: fetched.reduce((s, f) => s + gz[f], 0),
                         results: results.map(r => [r.ref, r.score]) };
    }
    console.log(JSON.stringify(out));
  })().catch(e => { console.error(e); process.exit(1); });
JS

Dir.mktmpdir do |tmp|
  File.write(File.join(tmp, "cjk-index.js"), CJKIndex::Runtime.source)
  File.write(File.join(tmp, "run.js"), NODE)
  single = builder.write(File.join(tmp, "single.json"))
  whole = kb(Zlib.gzip(File.binread(single), level: 9).bytesize)
  puts format("| %s | one file | 1 | %s | %s | 0 (all loaded first) | 0 | |", source.name, whole, whole)
  sizes.each do |size|
    dir = File.join(tmp, "split-#{size}")
    builder.write_split(dir, shard_size: size)
    gz = Dir.children(dir).to_h { |f| [f, Zlib.gzip(File.binread(File.join(dir, f)), level: 9).bytesize] }
    out, err, status = Open3.capture3("node", File.join(tmp, "run.js"), File.join(tmp, "cjk-index.js"),
                                      stdin_data: JSON.generate([dir, source.queries, gz]))
    abort err unless status.success?
    node = JSON.parse(out)
    searcher = CJKIndex::Searcher.load(dir)
    source.queries.each do |q|
      ruby = searcher.search(q).map { |r| [r[:ref], r[:score]] }
      js = node["queries"][q]["results"]
      ok = ruby.length == js.length && ruby.zip(js).all? { |(a, s), (b, t)| a == b && (s - t).abs < 1e-9 }
      abort "results differ between Ruby and Node for #{q}" unless ok
    end
    qs = node["queries"].values
    puts format("| %s | split, %d B shards | %d | %s | %s | %s / %s | %d / %d | %.0f ms / %.1f / %.1f ms |",
                source.name, size, gz.size, kb(gz["index.json"]), kb(gz.values.sum),
                kb(median(qs.map { |r| r["bytes"] })), kb(qs.map { |r| r["bytes"] }.max),
                median(qs.map { |r| r["files"] }), qs.map { |r| r["files"] }.max,
                node["load"], median(qs.map { |r| r["ms"] }), qs.map { |r| r["ms"] }.max)
  end
  warn "hits: #{source.queries.map { |q| "#{q}=#{CJKIndex::Searcher.new(builder).search(q).size}" }.join(' ')}"
end
