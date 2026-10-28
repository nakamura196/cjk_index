# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class TestFilters < Minitest::Test
  DOCS = {
    "map1" => { "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖", "type" => "地圖", "era" => "明治;大正", "date" => "1900-01-01" },
    "map2" => { "title" => "東京大学農学部 構内図", "type" => "地図", "era" => "昭和", "date" => "１９３１年" },
    "photo1" => { "title" => "農学部 正門", "type" => "写真", "era" => "大正", "date" => 1923 },
    "book1" => { "title" => "群芳圖譜", "type" => ["図譜", "書籍"], "era" => " 明治 ", "date" => "明治33年" },
    "none" => { "title" => "農学部 資料" }
  }.freeze

  FILTERS = { "type" => "value", "era" => { "kind" => "value", "separator" => ";" }, "date" => "year" }.freeze

  def builder
    b = CJKIndex::Builder.new(fields: %w[title], filters: FILTERS)
    DOCS.each { |ref, doc| b.add(ref, doc) }
    b
  end

  def refs(results) = results.map { |r| r[:ref] }

  def test_index_stores_values_once_and_years
    f = builder.to_h["filters"]
    # 地圖 and 地図 fold to one value, kept as first written
    assert_equal({ "kind" => "value", "values" => %w[地圖 写真 図譜 書籍], "docs" => [[0], [0], [1], [2, 3], []] }, f["type"])
    assert_equal({ "kind" => "value", "values" => %w[明治 大正 昭和], "docs" => [[0, 1], [2], [1], [0], []], "separator" => ";" },
                 f["era"])
    # full-width digits fold; an era date gives no year
    assert_equal({ "kind" => "year", "docs" => [1900, 1931, 1923, nil, nil] }, f["date"])
  end

  def test_year_of_time_and_date
    require "date"
    b = CJKIndex::Builder.new(fields: %w[title], filters: { "date" => "year", "tag" => "value" })
    b.add("a", "title" => "x", "date" => Time.utc(1905, 3, 1), "tag" => Time.utc(1905, 3, 1))
    b.add("b", "title" => "y", "date" => Date.new(1912, 7, 30))
    f = b.to_h["filters"]
    assert_equal [1905, 1912], f["date"]["docs"]
    assert_equal [[0], []], f["tag"]["docs"]
  end

  def test_filters_restrict_search
    s = CJKIndex::Searcher.new(builder)
    assert_equal %w[map1 map2 none photo1], refs(s.search("農学部")).sort
    assert_equal %w[map2 map1], refs(s.search("構内", filter: { "type" => "地図" }))
    assert_equal %w[map1 book1], refs(s.search("", filter: { "era" => "明治" }))
    assert_equal %w[map1 photo1 book1], refs(s.search("", filter: { "era" => %w[明治 大正] }))
    assert_equal %w[map1 photo1], refs(s.search("", filter: { "date" => 1900..1925 }))
    assert_equal %w[map2 photo1], refs(s.search("", filter: { "date" => { "min" => 1920 } }))
    assert_equal %w[photo1], refs(s.search("", filter: { date: 1923, era: "大正" }))
    assert_equal %w[map1 map2 photo1 book1 none], refs(s.search("", filter: {}))
    assert_equal [], s.search("")
    assert_raises(ArgumentError) { s.search("", filter: { "creator" => "x" }) }
  end

  def test_filter_does_not_change_scores
    s = CJKIndex::Searcher.new(builder)
    all = s.search("農学部").to_h { |r| [r[:ref], r[:score]] }
    s.search("農学部", filter: { "type" => %w[地図 写真] }).each { |r| assert_equal all[r[:ref]], r[:score] }
  end

  def test_facets
    s = CJKIndex::Searcher.new(builder)
    assert_equal [{ value: "地圖", count: 2 }, { value: "写真", count: 1 }, { value: "図譜", count: 1 }, { value: "書籍", count: 1 }],
                 s.facets("type")
    assert_equal [{ value: "大正", count: 2 }, { value: "明治", count: 1 }, { value: "昭和", count: 1 }],
                 s.facets("era", s.search("農学部"))
    assert_equal [{ value: 1900, count: 1 }, { value: 1931, count: 1 }], s.facets("date", %w[map1 map2])
    assert_raises(ArgumentError) { s.facets("title") }
  end

  def test_unknown_kind
    assert_raises(ArgumentError) { CJKIndex::Builder.new(fields: %w[title], filters: { "date" => "range" }) }
  end

  def test_array_of_names
    b = CJKIndex::Builder.new(fields: %w[title], filters: %w[type])
    assert_equal({ "type" => { "kind" => "value" } }, b.filters)
  end
end

# The browser script must filter and count exactly like Searcher.
class TestFiltersMatchRuntime < Minitest::Test
  CASES = [
    ["農学部", nil], ["構内", { "type" => "地図" }], ["", { "era" => "明治" }], ["", { "era" => %w[明治 大正] }],
    ["", { "date" => { "min" => 1900, "max" => 1925 } }], ["", { "date" => { "min" => 1920 } }],
    ["", { "date" => 1923, "era" => "大正" }], ["", {}], ["", nil], ["農学部", { "type" => [] }],
    ["図", { "type" => "ちず" }], ["農学部", { "era" => "大正", "type" => "写真" }]
  ].freeze

  def setup
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
  end

  def test_same_results_and_facets_as_browser
    b = CJKIndex::Builder.new(fields: %w[title], filters: TestFilters::FILTERS)
    TestFilters::DOCS.each { |ref, doc| b.add(ref, doc) }
    b.add("map3", "title" => "地図", "type" => "チズ")
    s = CJKIndex::Searcher.new(b.to_json)
    js = Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source)
      File.write(File.join(dir, "run.js"), <<~JS)
        const c = require('./cjk-index.js');
        const [data, cases] = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        const idx = new c.Index(data);
        console.log(JSON.stringify(cases.map(([q, f]) => {
          const results = idx.search(q, f ? { filter: f } : undefined);
          return [results, ['type', 'era', 'date'].map(name => idx.facets(name, f ? results : undefined))];
        })));
      JS
      out, err, status = Open3.capture3("node", File.join(dir, "run.js"), stdin_data: JSON.generate([b.to_h, CASES]))
      assert status.success?, err
      JSON.parse(out)
    end

    CASES.each_with_index do |(q, f), i|
      results = s.search(q, filter: f)
      facets = %w[type era date].map { |name| s.facets(name, f ? results : nil) }
      expected = [results.map { |r| { "ref" => r[:ref], "score" => r[:score], "fields" => r[:fields] } },
                  facets.map { |list| list.map { |h| h.transform_keys(&:to_s) } }]
      assert_equal expected[0].map { |r| r["ref"] }, js[i][0].map { |r| r["ref"] }, [q, f].inspect
      expected[0].zip(js[i][0]) { |rb, n| assert_in_delta rb["score"], n["score"], 1e-9 }
      assert_equal expected[1], js[i][1], [q, f].inspect
    end
  end

  def test_version_2_index_still_loads
    v2 = { "format" => "cjk_index/2", "variants" => %w[ja], "fields" => %w[title], "boosts" => [1],
           "refs" => %w[a], "lengths" => [2], "tokens" => { "東京" => [0, 0, 1, 0], "東" => [0, 0, 1, 0], "京" => [0, 0, 1, 1] } }
    assert_equal %w[a], CJKIndex::Searcher.new(v2).search("東京").map { |r| r[:ref] }
    out = Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source)
      File.write(File.join(dir, "run.js"), <<~JS)
        const c = require('./cjk-index.js');
        const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        console.log(JSON.stringify(new c.Index(data).search('東京').map(r => r.ref)));
      JS
      o, err, status = Open3.capture3("node", File.join(dir, "run.js"), stdin_data: JSON.generate(v2))
      assert status.success?, err
      JSON.parse(o)
    end
    assert_equal %w[a], out
  end
end
