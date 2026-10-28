# include Searchable in a model; define search_document with the fields of
# the index. The index follows create, update and destroy once the
# transaction is committed.
module Searchable
  extend ActiveSupport::Concern

  included do
    after_commit :index_for_search, on: %i[create update]
    after_commit :remove_from_search, on: :destroy
  end

  class_methods do
    # Records that match, best match first. filter: { "category" => "地図", "published_on" => 1890..1910 }
    def search(query, filter: nil)
      refs = SEARCH_INDEX.searcher.search(query, filter: filter).map { |r| r[:ref].to_i }
      records = where(id: refs).index_by(&:id)
      refs.filter_map { |id| records[id] }
    end

    # A full build in one pass: after a deploy, a migration, or a bulk import.
    def rebuild_search_index
      builder = CJKIndex::Builder.new(fields: %w[title body], boosts: { "title" => 3 },
                                      filters: { "category" => "value", "published_on" => "year" })
      find_each { |record| builder.add(record.id, record.search_document) }
      SEARCH_INDEX.write(builder)
    end
  end

  private

  def index_for_search
    SEARCH_INDEX.update { |builder| builder.update(id, search_document) } # adds when new
  end

  def remove_from_search
    SEARCH_INDEX.update { |builder| builder.remove(id) }
  end
end
