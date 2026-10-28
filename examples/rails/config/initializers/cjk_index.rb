# The search index lives in one file that all Puma workers share (and the
# console, runners and jobs too): CJKIndex::IndexFile reads it without a lock
# and takes a lock only to write, so no update is lost.
require "cjk_index"

SEARCH_INDEX = CJKIndex::IndexFile.new(Rails.root.join("db", "search-#{Rails.env}.json"))

# An empty index when there is none yet (bin/rails search:rebuild fills it).
unless File.exist?(SEARCH_INDEX.path)
  SEARCH_INDEX.write(CJKIndex::Builder.new(fields: %w[title body], boosts: { "title" => 3 },
                                           filters: { "category" => "value", "published_on" => "year" }))
end
