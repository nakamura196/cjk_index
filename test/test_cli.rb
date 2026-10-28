# frozen_string_literal: true

require "test_helper"
require "csv"
require "cjk_index/cli"
require "json"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"

class TestCLI < Minitest::Test
  FIXTURES = File.expand_path("fixtures/cli", __dir__)
  EXE = File.expand_path("../exe/cjk_index", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  Result = Struct.new(:out, :err, :status)

  def cli(*args, stdin: "")
    out = StringIO.new
    err = StringIO.new
    status = CJKIndex::CLI.run(args, stdin: StringIO.new(stdin), stdout: out, stderr: err)
    Result.new(out.string, err.string, status)
  end

  def csv = File.join(FIXTURES, "items.csv")

  def test_build_csv_to_stdout
    r = cli("build", csv, "--fields", "title,creator", "--boost", "title=3")
    assert_equal 0, r.status
    index = JSON.parse(r.out)
    assert_equal %w[title creator], index["fields"]
    assert_equal [3, 1], index["boosts"]
    assert_equal %w[a1 a2 a3], index["refs"]
    assert index["tokens"].key?("鳥瞰")
  end

  def test_build_defaults_use_first_column_as_ref_and_the_rest_as_fields
    index = JSON.parse(cli("build", csv).out)
    assert_equal %w[title creator type date], index["fields"]
  end

  def test_build_with_filters_matches_the_library
    r = cli("build", csv, "--fields", "title", "--filter", "type=value:;", "--filter", "date=year")
    index = JSON.parse(r.out)
    assert_equal %w[type date], index["filters"].keys
    assert_equal ";", index["filters"]["type"]["separator"]
    assert_equal [1900, 1920, 1950], index["filters"]["date"]["docs"]
    builder = CJKIndex::Builder.new(fields: %w[title], filters: { "type" => { "kind" => "value", "separator" => ";" }, "date" => "year" })
    CSV.read(csv, headers: true).each { |row| builder.add(row["id"], row.to_h) }
    assert_equal JSON.parse(builder.to_json), index
  end

  def test_build_json_jsonl_and_stdin
    json = JSON.parse(cli("build", File.join(FIXTURES, "items.json"), "--fields", "title").out)
    jsonl = JSON.parse(cli("build", File.join(FIXTURES, "items.jsonl"), "--fields", "title").out)
    assert_equal json["tokens"], jsonl["tokens"]
    piped = cli("build", "-", "--fields", "title", stdin: File.read(File.join(FIXTURES, "items.jsonl")))
    assert_equal jsonl, JSON.parse(piped.out)
    piped = cli("build", "--fields", "title", stdin: File.read(File.join(FIXTURES, "items.json")))
    assert_equal json, JSON.parse(piped.out)
    piped = cli("build", "--format", "csv", "--fields", "title", stdin: File.read(csv))
    assert_equal 3, JSON.parse(piped.out)["refs"].length
  end

  def test_build_writes_files_and_the_runtime
    Dir.mktmpdir do |dir|
      index = File.join(dir, "i.json")
      js = File.join(dir, "cjk-index.js")
      r = cli("build", csv, "--fields", "title", "--variants", "ja,zh", "-o", index, "--runtime", js)
      assert_equal 0, r.status, r.err
      assert_equal "", r.out
      assert_equal %w[ja zh], JSON.parse(File.read(index))["variants"]
      assert_equal CJKIndex::Runtime.source(normalizer: CJKIndex::Normalizer.new(tables: %w[ja zh])), File.read(js)
    end
  end

  def test_search_prints_refs_scores_and_json
    Dir.mktmpdir do |dir|
      index = File.join(dir, "i.json")
      cli("build", csv, "--fields", "title", "--filter", "type", "--filter", "date=year", "-o", index)
      r = cli("search", index, "鳥瞰図")
      assert_equal 0, r.status
      ref, score, fields = r.out.lines.first.chomp.split("\t")
      assert_equal "a1", ref
      assert_operator score.to_f, :>, 0
      assert_equal "title", fields

      json = JSON.parse(cli("search", index, "map", "--json").out)
      assert_equal %w[a3], json.map { |x| x["ref"] }

      assert_equal %w[a1 a3], JSON.parse(cli("search", index, "", "--filter", "type=地図", "--json").out).map { |x| x["ref"] }
      assert_equal %w[a2 a3], JSON.parse(cli("search", index, "", "--filter", "date=1910..", "--json").out).map { |x| x["ref"] }
      assert_equal %w[a1], JSON.parse(cli("search", index, "", "--filter", "type=地図", "--filter", "date=1900", "--json").out).map { |x| x["ref"] }
    end
  end

  def test_search_limit
    Dir.mktmpdir do |dir|
      index = File.join(dir, "i.json")
      cli("build", csv, "--fields", "title,creator", "--filter", "date=year", "-o", index)
      r = cli("search", index, "", "--filter", "date=1800..", "--limit", "1")
      assert_equal 2, r.out.lines.length
      assert_match(/\(3 results\)/, r.out)
    end
  end

  def test_runtime_command
    r = cli("runtime")
    assert_equal 0, r.status
    assert_equal CJKIndex::Runtime.source, r.out
    Dir.mktmpdir do |dir|
      cli("runtime", "--variants", "ja,zh", "-o", File.join(dir, "x.js"))
      refute_equal CJKIndex::Runtime.source, File.read(File.join(dir, "x.js"))
    end
  end

  def test_help_and_version
    assert_match(/Commands:/, cli("--help").out)
    assert_equal "#{CJKIndex::VERSION}\n", cli("--version").out
    r = cli
    assert_equal 2, r.status
    assert_match(/Usage/, r.err)
  end

  def test_errors_have_clear_messages_and_exit_codes
    r = cli("frobnicate")
    assert_equal 2, r.status
    assert_match(/unknown command "frobnicate"/, r.err)
    assert_match(/no field "nope"/, cli("build", csv, "--ref", "nope").err)
    assert_match(/no such field in the records: nope/, cli("build", csv, "--fields", "nope").err)
    assert_match(/invalid option/, cli("build", csv, "--bogus").err)
    assert_match(/kind must be value or year/, cli("build", csv, "--filter", "x=bad").err)
    assert_match(/no such file/, cli("search", "/nonexistent/i.json", "x").err)
    assert_equal 2, cli("search", "/nonexistent/i.json", "x").status
    assert_equal 1, cli("build", "/nonexistent/items.csv").status
    assert_equal 1, cli("build", "-", "--format", "json", stdin: "{").status
    assert_match(/array of objects/, cli("build", "-", "--format", "json", stdin: "{}").err)
    assert_match(/no records/, cli("build", "-", "--format", "jsonl", stdin: "").err)
    assert_match(/unknown variant table/, cli("build", csv, "--variants", "xx").err)
  end

  def test_executable
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", LIB, EXE, "build", csv, "--fields", "title", "--boost", "title=2")
    assert status.success?, err
    assert_equal [2], JSON.parse(out)["boosts"]
    _, err, status = Open3.capture3(RbConfig.ruby, "-I", LIB, EXE, "build", "/nonexistent.csv")
    assert_equal 1, status.exitstatus
    assert_match(/cjk_index:/, err)
    out, = Open3.capture3(RbConfig.ruby, "-I", LIB, EXE, "--version")
    assert_equal "#{CJKIndex::VERSION}\n", out
  end

  def test_missing_csv_gem_is_reported
    CJKIndex::CLI.stub(:require, ->(name) { name == "csv" ? raise(LoadError) : super(name) }) do
      r = cli("build", csv)
      assert_equal 2, r.status
      assert_match(/needs the csv gem/, r.err)
    end
  end
end
