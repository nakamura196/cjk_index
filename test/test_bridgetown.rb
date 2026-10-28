# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# Builds a small Bridgetown site with the plugin in a separate process (as
# `bridgetown build` would) and checks the files it writes. Skipped unless
# bridgetown-core is in the bundle (gemfiles/bridgetown.gemfile).
class TestBridgetown < Minitest::Test
  FIXTURE = File.expand_path("fixtures/bridgetown-site", __dir__)

  def setup
    skip "bridgetown-core is not in the bundle (see gemfiles/bridgetown.gemfile)" unless Gem.loaded_specs.key?("bridgetown")
  end

  def build
    Dir.mktmpdir do |root|
      FileUtils.cp_r(Dir.children(FIXTURE).map { |c| File.join(FIXTURE, c) }, root)
      _, err, status = Open3.capture3(RbConfig.ruby, "-S", "bundle", "exec", "bridgetown", "build", chdir: root)
      assert status.success?, err
      yield File.join(root, "output")
    end
  end

  def test_writes_indexes_and_script
    build do |out|
      assert File.exist?(File.join(out, "cjk-index/cjk-index.js"))
      assert_equal CJKIndex::Runtime.source, File.read(File.join(out, "cjk-index/cjk-index.js"))

      posts = JSON.parse(File.read(File.join(out, "cjk-index/posts.json")))
      assert_equal %w[title content], posts["fields"]
      assert_equal [3, 1], posts["boosts"]
      assert_equal 3, posts["refs"].length
      assert posts["refs"].all? { |r| r.start_with?("/") }, posts["refs"].inspect
      assert posts["tokens"].key?("鳥瞰"), "title is indexed"
      assert posts["tokens"].key?("そめ"), "content is indexed"
      assert_equal %w[category date], posts["filters"].keys
      assert_equal [2026, 2026, 2026], posts["filters"]["date"]["docs"]
      assert_equal %w[misc 図鑑 地図], posts["filters"]["category"]["values"].sort

      items = JSON.parse(File.read(File.join(out, "cjk-index/items.json")))
      assert_equal %w[r1 r2], items["refs"]
    end
  end

  def test_browser_script_finds_a_page_like_ruby
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
    build do |out|
      dir = File.join(out, "cjk-index")
      script = <<~JS
        const fs = require('fs');
        const c = require(#{File.join(dir, 'cjk-index.js').to_json});
        const index = new c.Index(JSON.parse(fs.readFileSync(#{File.join(dir, 'posts.json').to_json}, 'utf8')));
        console.log(JSON.stringify(index.search('鳥瞰図').map(r => r.ref)));
      JS
      file = File.join(dir, "q.js")
      File.write(file, script)
      stdout, err, status = Open3.capture3("node", file)
      assert status.success?, err
      ruby = CJKIndex::Searcher.load(File.join(dir, "posts.json")).search("鳥瞰図").map { |r| r[:ref] }
      assert_equal 1, ruby.length
      assert_equal ruby, JSON.parse(stdout)
    end
  end
end
