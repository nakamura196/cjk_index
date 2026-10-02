# frozen_string_literal: true

# Search a CSV catalog from the command line, with no server and no Jekyll.
#
#   ruby examples/search_csv.rb items.csv 帝国大学
#   ruby examples/search_csv.rb items.csv 实录 --fields title,creator --ref objectid --variants ja,zh
#
# To keep an index between runs, write builder.to_json to a file and open it
# with CJKIndex::Searcher.load; the same file works with the browser script.

require "cjk_index"
require "cgi/escape"
require "csv"
require "optparse"

options = { fields: %w[title], ref: nil, limit: 10, variants: CJKIndex::Normalizer::DEFAULT_TABLES }
OptionParser.new do |o|
  o.banner = "Usage: ruby search_csv.rb FILE.csv QUERY [options]"
  o.on("--fields LIST", Array, "columns to index (default: title)") { |v| options[:fields] = v }
  o.on("--ref COLUMN", "column that identifies a row (default: first column)") { |v| options[:ref] = v }
  o.on("--variants LIST", Array, "variant tables: ja (default), zh (Traditional/Simplified)") { |v| options[:variants] = v }
  o.on("--limit N", Integer, "results to show (default: 10)") { |v| options[:limit] = v }
end.parse!
csv_path, query = ARGV
abort "Usage: ruby search_csv.rb FILE.csv QUERY [options]" unless csv_path && query

rows = CSV.read(csv_path, headers: true)
ref_column = options[:ref] || rows.headers.first
by_ref = rows.to_h { |row| [row[ref_column], row] }

normalizer = CJKIndex::Normalizer.new(tables: options[:variants])
builder = CJKIndex::Builder.new(fields: options[:fields], normalizer: normalizer)
rows.each { |row| builder.add(row[ref_column], row.to_h.slice(*options[:fields])) }
searcher = CJKIndex::Searcher.new(builder)

results = searcher.search(query)
puts "#{results.size} result#{"s" unless results.size == 1} for #{query}"
results.first(options[:limit]).each do |r|
  title = by_ref[r[:ref]][options[:fields].first].to_s
  # highlight returns HTML; show the match in brackets on a terminal.
  shown = searcher.highlight(title, query).gsub("<mark>", "[").gsub("</mark>", "]")
  puts format("%-20s %s", r[:ref], CGI.unescapeHTML(shown))
end
