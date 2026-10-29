# frozen_string_literal: true

# Builds the catalog-scale Aozora Bunko indexes for the browser measurement.
#
# The records are the same as bench/aozora.rb in catalog mode (title, author
# and the first 200 characters of the text, fields and boosts unchanged), so
# the 16,951-record index is the one reported there (61.0 MB, 19.3 MB gzip).
#
# Usage (from the repository root):
#   ruby -Ilib bench/browser/build.rb bench/retrieval/cache/aozora.jsonl.gz 1000 5000 16951
#
# Writes to bench/browser/cache/ (not committed):
#   index-<n>.json, index-<n>.json.gz  the index, and its gzip (level 9)
#   expected-<n>.json                  refs returned by the Ruby Searcher per query
#   split-<n>/                         the same index split (Builder#write_split)
#   split-<n>-gz/                      the files of split-<n>/, gzip (level 9)
#   cjk-index.js                       the browser runtime
# The page checks every browser result against expected-<n>.json.

require "cjk_index"
require "json"
require "zlib"
require "fileutils"

path, *counts = ARGV
abort "usage: build.rb aozora.jsonl.gz N [N ...]" if path.nil? || counts.empty?
counts = counts.map { |c| Integer(c) }

HERE = __dir__
CACHE = File.join(HERE, "cache")
FileUtils.mkdir_p(CACHE)
QUERIES = JSON.parse(File.read(File.join(HERE, "queries.json")))

docs = []
Zlib::GzipReader.open(path) do |gz|
  gz.each_line do |line|
    break if docs.size >= counts.max

    d = JSON.parse(line)
    m = d["meta"]
    docs << [m["作品ID"], { "title" => m["作品名"], "author" => "#{m['姓']}#{m['名']}", "text" => d["text"][0, 200] }]
  end
end

File.write(File.join(CACHE, "cjk-index.js"), CJKIndex::Runtime.source)

counts.each do |n|
  builder = CJKIndex::Builder.new(fields: %w[title author text], boosts: { "title" => 3, "author" => 2 })
  docs.first(n).each { |ref, d| builder.add(ref, d) }
  json = builder.to_json
  File.write(File.join(CACHE, "index-#{n}.json"), json)
  File.binwrite(File.join(CACHE, "index-#{n}.json.gz"), Zlib.gzip(json, level: 9))
  split = File.join(CACHE, "split-#{n}")
  FileUtils.rm_rf([split, "#{split}-gz"])
  builder.write_split(split)
  FileUtils.mkdir_p("#{split}-gz")
  Dir.children(split).each do |name|
    File.binwrite(File.join("#{split}-gz", name), Zlib.gzip(File.read(File.join(split, name)), level: 9))
  end
  searcher = CJKIndex::Searcher.new(json)
  expected = QUERIES.to_h { |q| [q, searcher.search(q).map { |r| r[:ref] }] }
  File.write(File.join(CACHE, "expected-#{n}.json"), JSON.generate(expected))
  gz = File.size(File.join(CACHE, "index-#{n}.json.gz"))
  puts format("%d records: %.1f MB, gzip %.1f MB; split: %d files", n, json.bytesize / 1e6, gz / 1e6, Dir.children(split).size)
end
