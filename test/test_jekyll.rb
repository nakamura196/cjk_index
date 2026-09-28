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
    end
  end
end
