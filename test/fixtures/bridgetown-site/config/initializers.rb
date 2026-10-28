require "cjk_index/bridgetown"

Bridgetown.configure do |config|
  url ""
  template_engine "liquid"
  init :cjk_index,
       indexes: [
         { name: "posts", collection: "posts", fields: %w[title content], boosts: { title: 3 },
           filters: { category: "value", date: "year" } },
         { name: "items", data: "metadata", fields: %w[title] }
       ]
end
