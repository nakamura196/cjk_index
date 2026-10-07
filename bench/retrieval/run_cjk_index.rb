# frozen_string_literal: true

# Runs the queries of queries.tsv with cjk_index itself: the index is built
# by the Ruby builder and searched by the browser runtime (runtime.js, under
# Node). The Ruby searcher runs the same queries on the same index, and the
# script stops if the two disagree on any result list.
#
#   ruby -Ilib bench/retrieval/run_cjk_index.rb utokyo
#   ruby -Ilib bench/retrieval/run_cjk_index.rb aozora
#
# utokyo is indexed as the cb-ja-demo site does it (collectionbuilder preset:
# title boosted 3, variant tables ja and zh); aozora as bench/aozora.rb does
# (title 3, author 2, the default ja table). Writes results/<corpus>-cjk_index.tsv
# and keeps the index and the generated script in cache/.

require "cjk_index"
require "csv"
require "json"
require "open3"

HERE = __dir__
SETTINGS = {
  "utokyo" => { source: File.join(HERE, "data", "utokyo.jsonl"), tables: %w[ja zh], boosts: { "title" => 3 },
                fields: %w[title title_kana alternative date creator description note era] },
  "aozora" => { source: File.join(HERE, "cache", "aozora.jsonl"), tables: %w[ja], boosts: { "title" => 3, "author" => 2 },
                fields: %w[title author text] }
}.freeze

corpus = ARGV.fetch(0)
setting = SETTINGS.fetch(corpus)
queries = CSV.read(File.join(HERE, "queries.tsv"), col_sep: "\t", headers: true, quote_char: "\x00")
             .select { |q| q["corpus"] == corpus }
             .map { |q| [q["qid"], q["query"]] }

normalizer = CJKIndex::Normalizer.new(tables: setting[:tables])
builder = CJKIndex::Builder.new(fields: setting[:fields], boosts: setting[:boosts], normalizer: normalizer)
File.foreach(setting[:source]) do |line|
  r = JSON.parse(line)
  builder.add(r["id"], r["fields"])
end

cache = File.join(HERE, "cache")
Dir.mkdir(cache) unless Dir.exist?(cache)
index_path = File.join(cache, "#{corpus}-index.json")
script_path = File.join(cache, "#{corpus}-cjk-index.js")
File.write(index_path, builder.to_json)
File.write(script_path, CJKIndex::Runtime.source(normalizer: normalizer))

node = <<~JS
  const c = require(process.argv[1]);
  const idx = new c.Index(JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8')));
  const queries = JSON.parse(require('fs').readFileSync(0, 'utf8'));
  console.log(JSON.stringify(queries.map(q => idx.search(q).map(r => r.ref))));
JS
out, err, status = Open3.capture3("node", "-e", node, script_path, index_path, stdin_data: JSON.generate(queries.map(&:last)))
abort err unless status.success?
browser = JSON.parse(out)

searcher = CJKIndex::Searcher.new(builder, normalizer: normalizer)
ruby = queries.map { |_, q| searcher.search(q).map { |r| r[:ref] } }
abort "Ruby and the browser runtime disagree" unless ruby == browser

File.open(File.join(HERE, "results", "#{corpus}-cjk_index.tsv"), "w") do |f|
  f.puts "qid\trank\tdoc"
  queries.zip(browser).each do |(qid, _), refs|
    refs.each_with_index { |ref, i| f.puts "#{qid}\t#{i + 1}\t#{ref}" }
  end
end
puts "#{corpus}: #{builder.refs.size} records, #{queries.size} queries, Ruby and runtime.js agree"
