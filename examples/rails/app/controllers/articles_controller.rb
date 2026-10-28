class ArticlesController < ApplicationController
  # GET /articles?q=鳥瞰図&category=地図&from=1890&until=1910
  def index
    filter = {}
    filter["category"] = params[:category] if params[:category].present?
    years = { "min" => params[:from], "max" => params[:until] }.compact_blank.transform_values(&:to_i)
    filter["published_on"] = years if years.any?

    articles = if params[:q].present? || filter.any?
                 Article.search(params[:q].to_s, filter: filter.presence) # no query: every record that passes the filter
               else
                 Article.order(:id)
               end
    render json: articles.map { |a| a.slice(:id, :title, :category, :published_on) }
  end
end
