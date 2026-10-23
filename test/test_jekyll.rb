# frozen_string_literal: true

require "test_helper"
require "cjk_index/jekyll"
require "json"
require "tmpdir"

class TestJekyll < Minitest::Test
  FIXTURE = File.expand_path("fixtures/cb-site", __dir__)

  def build(extra = {})
    Dir.mktmpdir do |dest|
      config = Jekyll.configuration(
        "source" => FIXTURE, "destination" => dest, "quiet" => true,
        "metadata" => "demo-metadata",
        "cjk_index" => { "indexes" => [{ "name" => "search", "preset" => "collectionbuilder" }] }
      ).merge(extra)
      Jekyll::Site.new(config).process
      yield dest
    end
  end

  def test_collectionbuilder_preset
    build do |dest|
      assert File.exist?(File.join(dest, "assets/cjk-index/cjk-index.js"))
      index = JSON.parse(File.read(File.join(dest, "assets/cjk-index/search.json")))
      assert_equal %w[title creator], index["fields"]
      assert_equal [3, 1], index["boosts"]
      # the child object is skipped unless theme.search-child-objects is true
      assert_equal %w[item1.html item2.html], index["refs"]
      assert index["tokens"].key?("鳥瞰")
      refute index["tokens"].key?("非表示"), "description is not an index field"
      assert_equal %w[ja], index["variants"]
      # metadata-facets-fields of the theme, and a year from the date column
      assert_equal %w[type creator date], index["filters"].keys
      assert_equal({ "kind" => "value", "values" => %w[地図 絵図], "docs" => [[0, 1], [1]], "separator" => ";" },
                   index["filters"]["type"])
      assert_equal [1900, nil], index["filters"]["date"]["docs"]
    end
  end

  def test_filters_option
    spec = { "name" => "items", "data" => "demo-metadata", "ref" => "objectid", "fields" => %w[title],
             "filters" => { "type" => { "kind" => "value", "separator" => ";" } } }
    build("cjk_index" => { "indexes" => [spec] }) do |dest|
      index = JSON.parse(File.read(File.join(dest, "assets/cjk-index/items.json")))
      assert_equal %w[item1 item2 child1], index["refs"]
      assert_equal [[0, 1], [1], [0]], index["filters"]["type"]["docs"]
    end
  end

  def test_variants_option
    build("cjk_index" => { "variants" => %w[ja zh], "indexes" => [{ "name" => "search", "preset" => "collectionbuilder" }] }) do |dest|
      index = JSON.parse(File.read(File.join(dest, "assets/cjk-index/search.json")))
      assert_equal %w[ja zh], index["variants"]
      assert_includes File.read(File.join(dest, "assets/cjk-index/cjk-index.js")), '["ja","zh"]'
    end
  end
end
