# config/initializers.rb of a Bridgetown 2 site.
# Gemfile: gem "cjk_index"
require "cjk_index/bridgetown"

Bridgetown.configure do |config|
  template_engine "liquid"

  init :cjk_index,
       output: "cjk-index",     # written to output/cjk-index/ (default)
       variants: ["ja"],        # "zh" adds Traditional/Simplified Chinese
       indexes: [
         {
           name: "posts",      # -> output/cjk-index/posts.json
           collection: "posts", # or a list of collections
           fields: %w[title content], # "content" is the Markdown source of the resource
           boosts: { title: 3 },
           filters: { category: "value", date: "year" }
         },
         # rows of src/_data/metadata.csv instead of resources
         { name: "items", data: "metadata", ref: "id", fields: %w[title creator] }
       ]
end
