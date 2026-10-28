class Article < ApplicationRecord
  include Searchable

  def search_document
    { "title" => title, "body" => body, "category" => category, "published_on" => published_on&.year }
  end
end
