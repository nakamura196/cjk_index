# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class TestSearcher < Minitest::Test
  def refs(searcher, *queries)
    queries.map { |q| searcher.search(q).map { |r| r[:ref] } }
  end

  # The same cases as TestRuntime, answered in Ruby.
  def test_search
    b = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
    b.add("a", "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖")
    b.add("b", "title" => "建物位置圖", "creator" => "東京大学")
    b.add("c", "title" => "國牛十圖")
    s = CJKIndex::Searcher.new(b)
    assert_equal [%w[a], %w[b a], %w[b], %w[c], [], %w[c b a]],
                 refs(s, "鳥瞰図", "建物", "東京大学", "牛", "存在しない", "図")
    assert_equal %w[title creator], s.search("建物 東京大学").first[:fields]
  end

  def test_bigrams_must_be_adjacent
    b = CJKIndex::Builder.new(fields: %w[title])
    b.add("scattered", "title" => "京大の東京での大学祭")
    b.add("exact", "title" => "東京大学の歴史")
    assert_equal [%w[exact], %w[exact scattered]], refs(CJKIndex::Searcher.new(b), "東京大学", "東京 大学")
  end

  def test_latin_prefix_and_typo
    b = CJKIndex::Builder.new(fields: %w[title])
    b.add("a", "title" => "IIIF Manifest 解説")
    b.add("b", "title" => "Photograph of 桜")
    assert_equal [%w[a], %w[b], %w[a], []], refs(CJKIndex::Searcher.new(b), "mani", "photgraph", "manifest 解説", "iii 桜")
    assert_equal [[], []], refs(CJKIndex::Searcher.new(b, prefix: false, typos: false), "mani", "photgraph")
  end

  def test_loads_json_and_takes_tables_from_the_index
    b = CJKIndex::Builder.new(fields: %w[title], normalizer: CJKIndex::Normalizer.new(tables: %w[ja zh]))
    b.add("a", "title" => "國立故宮博物院")
    s = CJKIndex::Searcher.new(b.to_json)
    assert_equal %w[ja zh], s.normalizer.tables
    assert_equal [%w[a]], refs(s, "国立故宫")
    assert_raises(ArgumentError) { CJKIndex::Searcher.new(b.to_h, normalizer: CJKIndex::Normalizer.default) }
    assert_raises(ArgumentError) { CJKIndex::Searcher.new({ "format" => "cjk_index/1" }) }
  end

  def test_highlight_and_excerpt
    assert_equal "東京<mark>帝國大學</mark>&lt;b&gt;", CJKIndex.highlight("東京帝國大學<b>", "帝国大学")
    assert_equal "<mark>サクラ</mark>と<mark>桜</mark>", CJKIndex.highlight("サクラと桜", "さくら 桜")
    assert_equal "<mark>佐々木</mark>", CJKIndex.highlight("佐々木", "佐佐木")
    assert_equal "…ああああああ<mark>鳥瞰圖</mark>いいいいいいいいいいい…",
                 CJKIndex.excerpt("#{'あ' * 100}鳥瞰圖#{'い' * 100}", "鳥瞰図", 20)
    assert CJKIndex.includes?("東京 帝國大學", "京帝国")
  end
end

# Runs the browser script on the same index and queries, and checks that it
# returns the same refs, scores, fields, highlights and excerpts as Ruby.
# Skipped when node is not installed.
class TestSearcherMatchesRuntime < Minitest::Test
  DOCS = {
    "agri1" => { "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖", "creator" => "東京帝國大學", "subject" => %w[地図 建物] },
    "agri2" => { "title" => "群芳圖譜 第1輯第9編", "creator" => "和田英作", "subject" => %w[植物 図譜] },
    "agri3" => { "title" => "國牛十圖", "subject" => ["牛"] },
    "agri4" => { "title" => "東京大学農学部 構内図", "creator" => "東京大学", "subject" => %w[地図] },
    "sillok1" => { "title" => "成宗實錄 卷1", "creator" => "春秋館", "subject" => %w[实录 朝鮮王朝実録] },
    "sillok2" => { "title" => "中宗實錄 卷3", "creator" => "春秋館", "subject" => %w[朝鮮王朝実録] },
    "ogura1" => { "title" => "소학언해 小學諺解", "creator" => "", "subject" => %w[소학 諺解] },
    "ogura2" => { "title" => "ᄒᆞᆫ글 두창집요", "subject" => %w[의학] },
    "latin1" => { "title" => "IIIF Manifest Guide", "creator" => "Satoru Nakamura", "subject" => %w[IIIF metadata] },
    "latin2" => { "title" => "Photograph of Sakura サクラ", "creator" => "Photographer unknown", "subject" => %w[photograph] },
    "mixed" => { "title" => "佐々木家文書 Sasaki family papers", "creator" => "佐佐木", "subject" => %w[文書 archives] }
  }.freeze

  QUERIES = [
    "鳥瞰図", "東京大学", "東京帝国大学", "図", "地図 建物", "実録", "朝鮮王朝", "卷", "소학", "두창", "諺解",
    "iiif", "manif", "photo", "photgraph", "sakura", "さくら", "佐佐木", "佐々木 papers", "第1輯", "牛",
    "存在しない", "", "  ", "nakamura", "metadata iiif", "archive"
  ].freeze

  def setup
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
  end

  def node(normalizer, input)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source(normalizer: normalizer))
      File.write(File.join(dir, "run.js"), <<~JS)
        const c = require('./cjk-index.js');
        const [data, queries, texts] = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        const idx = new c.Index(data);
        console.log(JSON.stringify([
          queries.map(q => idx.search(q)),
          queries.map(q => texts.map(t => [c.highlight(t, q), c.excerpt(t, q, 12)]))
        ]));
      JS
      out, err, status = Open3.capture3("node", File.join(dir, "run.js"), stdin_data: JSON.generate(input))
      assert status.success?, err
      JSON.parse(out)
    end
  end

  def check(tables)
    normalizer = CJKIndex::Normalizer.new(tables: tables)
    b = CJKIndex::Builder.new(fields: %w[title creator subject], boosts: { "title" => 3, "subject" => 2 }, normalizer: normalizer)
    DOCS.each { |ref, doc| b.add(ref, doc) }
    texts = DOCS.values.map { |d| d["title"] }
    s = CJKIndex::Searcher.new(b)
    js_results, js_marks = node(normalizer, [b.to_h, QUERIES, texts])

    ruby_results = QUERIES.map { |q| s.search(q).map { |r| { "ref" => r[:ref], "score" => r[:score], "fields" => r[:fields] } } }
    QUERIES.each_with_index do |q, i|
      assert_equal js_results[i].map { |r| [r["ref"], r["fields"]] }, ruby_results[i].map { |r| [r["ref"], r["fields"]] }, q
      js_results[i].zip(ruby_results[i]) { |js, rb| assert_in_delta js["score"], rb["score"], 1e-9, q }
    end
    assert QUERIES.count { |q| !s.search(q).empty? } >= 20, "most queries should match something"
    ruby_marks = QUERIES.map { |q| texts.map { |t| [s.highlight(t, q), s.excerpt(t, q, 12)] } }
    assert_equal js_marks, ruby_marks
  end

  def test_same_results_as_browser_with_japanese_table
    check(%w[ja])
  end

  def test_same_results_as_browser_with_chinese_table
    check(%w[ja zh])
  end
end
