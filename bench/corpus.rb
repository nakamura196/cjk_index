# frozen_string_literal: true

# Documents for the benchmarks, as [ref, fields] pairs, with the fields,
# boosts and queries used for each source.
#
#   aozora:catalog:<path>:<n>   title, author and the first 200 characters of
#                               the first n works of the Aozora Bunko data
#                               (see aozora.rb for where to get it)
#   aozora:fulltext:<path>:<n>  title, author and the whole text
#   markdown:<dir>              every *.md file under dir (front matter title
#                               and tags, and the Markdown body), such as a
#                               blog's posts; files named _index.md are skipped
#
# Only the numbers measured on these are committed, never the texts.

require "json"
require "yaml"
require "zlib"
require "date"

module Corpus
  AOZORA_QUERIES = %w[
    東京 明治 汽車 戦争 恋愛 月夜 電信柱 帝国大学 吾輩は猫である 坊っちゃん
    銀河鉄道 羅生門 蜘蛛の糸 夏目漱石 宮沢賢治 芥川 ふるさと ランプ 停車場 存在しない語句
  ].freeze

  # Topics of a technical blog on digital archives, in Japanese and English.
  MARKDOWN_QUERIES = %w[
    IIIF Omeka 検索 全文検索 翻刻 画像 データベース 東京大学 マニフェスト 地図
    Next.js Drupal cantaloupe 機械学習 アノテーション 書誌 github 公開 ワークフロー 存在しない語句
  ].freeze

  Source = Struct.new(:name, :docs, :fields, :boosts, :queries)

  module_function

  def load(spec)
    kind, *rest = spec.split(":")
    case kind
    when "aozora"
      mode, path, count = rest
      raise ArgumentError, "mode must be catalog or fulltext" unless %w[catalog fulltext].include?(mode)

      Source.new("#{mode} #{count}", aozora(path, mode, Integer(count)), %w[title author text],
                 { "title" => 3, "author" => 2 }, AOZORA_QUERIES)
    when "markdown"
      dir = rest.join(":")
      Source.new("markdown #{File.basename(dir)}", markdown(dir), %w[title tags text], { "title" => 3, "tags" => 2 },
                 MARKDOWN_QUERIES)
    else
      raise ArgumentError, "unknown source #{spec}"
    end
  end

  def aozora(path, mode, count)
    docs = []
    Zlib::GzipReader.open(path) do |gz|
      gz.each_line do |line|
        break if docs.size >= count

        d = JSON.parse(line)
        m = d["meta"]
        text = mode == "catalog" ? d["text"][0, 200] : d["text"]
        docs << [m["作品ID"], { "title" => m["作品名"], "author" => "#{m['姓']}#{m['名']}", "text" => text }]
      end
    end
    docs
  end

  def markdown(dir)
    Dir.glob(File.join(dir, "**", "*.md")).sort.reject { |f| File.basename(f) == "_index.md" }.map do |file|
      text = File.read(file, encoding: "UTF-8")
      meta = {}
      if (m = text.match(/\A---\n(.*?)\n---\n/m))
        meta = YAML.safe_load(m[1], permitted_classes: [Date, Time]) || {}
        text = m.post_match
      end
      [file.delete_prefix(dir).delete_prefix("/"), { "title" => meta["title"].to_s, "tags" => Array(meta["tags"]).map(&:to_s), "text" => text }]
    end
  end

  def chars(docs) = docs.sum { |_, d| d["text"].size }
end
