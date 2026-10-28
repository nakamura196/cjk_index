namespace :search do
  desc "Build the search index from the database"
  task rebuild: :environment do
    Article.rebuild_search_index
    puts "#{SEARCH_INDEX.path}: #{SEARCH_INDEX.searcher.refs.length} records"
  end
end
