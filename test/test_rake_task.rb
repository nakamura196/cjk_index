# frozen_string_literal: true

require "test_helper"
require "cjk_index/rake_task"
require "json"
require "tmpdir"

class TestRakeTask < Minitest::Test
  CSV_FILE = File.expand_path("fixtures/cli/items.csv", __dir__)

  def setup
    Rake.application = Rake::Application.new
  end

  def test_task_builds_index_and_runtime
    Dir.mktmpdir do |dir|
      CJKIndex::RakeTask.new(:search_index) do |t|
        t.source = CSV_FILE
        t.output = File.join(dir, "out/items.json")
        t.runtime = File.join(dir, "out/cjk-index.js")
        t.fields = %w[title creator]
        t.boosts = { "title" => 3 }
        t.filters = { "type" => "value" }
      end
      assert_output(/items.json: 3 records/) { Rake::Task[:search_index].invoke }
      index = JSON.parse(File.read(File.join(dir, "out/items.json")))
      assert_equal [3, 1], index["boosts"]
      assert_equal %w[a1 a2 a3], index["refs"]
      assert_equal ["type"], index["filters"].keys
      assert_equal CJKIndex::Runtime.source, File.read(File.join(dir, "out/cjk-index.js"))
      assert_equal "a1", CJKIndex::Searcher.load(File.join(dir, "out/items.json")).search("鳥瞰図").first[:ref]
    end
  end

  def test_task_takes_records_from_a_lambda
    Dir.mktmpdir do |dir|
      CJKIndex::RakeTask.new(:from_records) do |t|
        t.records = -> { [{ "id" => 1, "body" => "桜の花" }, { "id" => 2, "body" => "梅の花" }] }
        t.output = File.join(dir, "i.json")
      end
      capture_io { Rake::Task[:from_records].invoke }
      assert_equal %w[1 2], JSON.parse(File.read(File.join(dir, "i.json")))["refs"]
    end
  end

  def test_missing_settings_are_reported
    CJKIndex::RakeTask.new(:bad) { |t| t.output = "x.json" }
    assert_raises(CJKIndex::CLI::Error) { Rake::Task[:bad].invoke }
  end
end
