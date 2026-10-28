# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

# Runs the generated browser script under Node.js and checks that it folds and
# splits text exactly like the Ruby side. Skipped when node is not installed.
class TestRuntime < Minitest::Test
  SAMPLES = [
    "東京帝國大學本部構内及農學部建物鳥瞰圖", "サクラ", "ＩＩＩＦ　２０２４", "佐々木",
    "第1輯、IIIF「マニフェスト」", "서울대학교 도서관", "Hello, World! 羣芳圖譜", "𠮟る", "ᄒᆞᆫ글 소학언초",
    "珊\u{E0100}瑚の葛\u{FE00}飾", "佐\u{E0101}々木", ""
  ].freeze

  def setup
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
  end

  def run_node(script, input, normalizer: CJKIndex::Normalizer.default)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source(normalizer: normalizer))
      File.write(File.join(dir, "run.js"), script)
      out, err, status = Open3.capture3("node", File.join(dir, "run.js"), stdin_data: JSON.generate(input))
      assert status.success?, err
      JSON.parse(out)
    end
  end

  def test_normalize_and_tokenize_match_ruby
    js = run_node(<<~JS, SAMPLES)
      const c = require('./cjk-index.js');
      const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      console.log(JSON.stringify(input.map(s => [c.normalize(s), c.phrases(s, false), c.phrases(s, true)])));
    JS
    ruby = SAMPLES.map do |s|
      [CJKIndex.normalize(s), CJKIndex::Tokenizer.phrases(s), CJKIndex::Tokenizer.phrases(s, unigrams: true)]
    end
    assert_equal ruby, js
  end

  def search(builder, queries, options = {})
    run_node(<<~JS, [builder.to_h, queries, options])
      const c = require('./cjk-index.js');
      const [data, queries, options] = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      const idx = new c.Index(data, options);
      console.log(JSON.stringify(queries.map(q => idx.search(q).map(r => r.ref))));
    JS
  end

  def test_search_on_ruby_built_index
    b = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
    b.add("a", "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖")
    b.add("b", "title" => "建物位置圖", "creator" => "東京大学")
    b.add("c", "title" => "國牛十圖")
    # 「東京大学」 does not match 「東京帝國大學…」: it is not a substring of it.
    assert_equal [%w[a], %w[b a], %w[b], %w[c], [], %w[c b a]],
                 search(b, ["鳥瞰図", "建物", "東京大学", "牛", "存在しない", "図"])
  end

  def test_bigrams_must_be_adjacent
    b = CJKIndex::Builder.new(fields: %w[title])
    b.add("scattered", "title" => "京大の東京での大学祭") # has 東京, 京大, 大学 but not 東京大学
    b.add("exact", "title" => "東京大学の歴史")
    assert_equal [%w[exact], %w[exact scattered]], search(b, ["東京大学", "東京 大学"])
  end

  def test_latin_prefix_and_typo
    b = CJKIndex::Builder.new(fields: %w[title])
    b.add("a", "title" => "IIIF Manifest 解説")
    b.add("b", "title" => "Photograph of 桜")
    assert_equal [%w[a], %w[b], %w[a], []], search(b, ["mani", "photgraph", "manifest 解説", "iii 桜"])
    assert_equal [[], []], search(b, %w[mani photgraph], { "prefix" => false, "typos" => false })
  end

  def test_chinese_tables_match_ruby
    zh = CJKIndex::Normalizer.new(tables: %w[ja zh])
    samples = ["國立故宮博物院", "国立故宫博物院", "圖書館 图书馆", "東京帝國大學"]
    js = run_node(<<~JS, samples, normalizer: zh)
      const c = require('./cjk-index.js');
      const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      console.log(JSON.stringify([c.tables, input.map(s => c.normalize(s))]));
    JS
    assert_equal [%w[ja zh], samples.map { |s| zh.normalize(s) }], js
  end

  def test_all_tables_match_ruby
    samples = [
      "國立故宮博物院", "皇后 以後", "頭髮 發展", "證明書 頰 𠮟る 禱", "가\uE97D[歌辭]", "경\uF1FC십이월",
      "\u1112\u1161\u11AB\u1100\u1173\u11AF 한글 ㅎㅏㄴ", "\uE3A8셩훈몽젼", "\uF537\uE97D々", "\uF914", "ｶﾞｲﾄﾞ", "與 醼讌 嶌島"
    ]
    fixtures = File.expand_path("fixtures/variants", __dir__)
    [%w[ja zh-safe ko], %w[zh ja], %w[ko], %w[zh-safe], %w[itaiji.tsv ja]].each do |tables|
      normalizer = CJKIndex::Normalizer.new(tables: tables, base: fixtures)
      js = run_node(<<~JS, samples, normalizer: normalizer)
        const c = require('./cjk-index.js');
        const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        console.log(JSON.stringify([c.tables, input.map(s => [c.normalize(s), c.phrases(s, true)])]));
      JS
      ruby = samples.map { |s| [normalizer.normalize(s), CJKIndex::Tokenizer.phrases(s, unigrams: true, normalizer: normalizer)] }
      assert_equal [tables, ruby], js, tables.join(",")
    end
  end

  def test_highlight_old_hangul_in_the_private_use_area
    out = run_node(<<~JS, [], normalizer: CJKIndex::Normalizer.new(tables: %w[ja ko]))
      const c = require('./cjk-index.js');
      console.log(JSON.stringify([
        c.highlight('가\uE97D[歌辭]', '가\u1109\u119E'),
        c.highlight('가\u1109\u119E[歌辭]', '가\uE97D'),
        c.highlight('경\uF1FC십이월', '\u110C\u119E'),
        c.highlight('경\uF1FC십이월', '\u119E십'),
        c.highlight('경\uF1FC십이월', '\uF1FC')
      ]));
    JS
    assert_equal "<mark>가\uE97D</mark>[歌辭]", out[0], "query typed in standard jamo"
    assert_equal "<mark>가\u1109\u119E</mark>[歌辭]", out[1], "query in PUA, text in jamo"
    assert_equal "경<mark>\uF1FC</mark>십이월", out[2]
    assert_equal "경<mark>\uF1FC십</mark>이월", out[3], "a match that starts inside the PUA character marks all of it"
    assert_equal "경<mark>\uF1FC</mark>십이월", out[4]
  end

  def test_highlight_composed_and_decomposed_hangul
    out = run_node(<<~JS, [])
      const c = require('./cjk-index.js');
      console.log(JSON.stringify([
        c.highlight('\u1112\u1161\u11AB\u1100\u1173\u11AF 문자', '한글'),
        c.highlight('한글 문자', '\u1112\u1161\u11AB\u1100\u1173\u11AF'),
        c.highlight('ｶﾞｲﾄﾞ', 'がいど'),
        c.highlight('cafe\u0301', 'café')
      ]));
    JS
    assert_equal "<mark>\u1112\u1161\u11AB\u1100\u1173\u11AF</mark> 문자", out[0]
    assert_equal "<mark>한글</mark> 문자", out[1]
    assert_equal "<mark>ｶﾞｲﾄﾞ</mark>", out[2]
    assert_equal "<mark>cafe\u0301</mark>", out[3]
  end

  def test_index_and_script_must_use_the_same_tables
    b = CJKIndex::Builder.new(fields: %w[title], normalizer: CJKIndex::Normalizer.new(tables: %w[ja zh]))
    b.add("a", "title" => "圖書館")
    out = run_node(<<~JS, b.to_h)
      const c = require('./cjk-index.js');
      const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      try { new c.Index(data); console.log('"loaded"'); } catch (e) { console.log(JSON.stringify(e.message)); }
    JS
    assert_match(/rebuild both together/, out)
  end

  def test_index_and_script_must_use_the_same_table_contents
    b = CJKIndex::Builder.new(fields: %w[title])
    b.add("a", "title" => "圖書館")
    stale = b.to_h.merge("variant_digest" => "0" * 16)
    out = run_node(<<~JS, stale)
      const c = require('./cjk-index.js');
      const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      try { new c.Index(data); console.log('"loaded"'); } catch (e) { console.log(JSON.stringify(e.message)); }
    JS
    assert_match(/other contents of the variant tables/, out)
    assert_raises(ArgumentError) { CJKIndex::Searcher.new(stale) }
    assert_raises(ArgumentError) { CJKIndex::Builder.load(stale) }
    # the digest follows what the tables fold, so another table set differs
    refute_equal CJKIndex::Normalizer.new(tables: %w[ja]).digest, CJKIndex::Normalizer.new(tables: %w[ja zh-safe]).digest
  end

  def test_highlight_maps_back_to_original_text
    out = run_node(<<~JS, [])
      const c = require('./cjk-index.js');
      console.log(JSON.stringify([
        c.highlight('東京帝國大學<b>', '帝国大学'),
        c.highlight('サクラと桜', 'さくら 桜'),
        c.excerpt('あ'.repeat(100) + '鳥瞰圖' + 'い'.repeat(100), '鳥瞰図', 20)
      ]));
    JS
    assert_equal "東京<mark>帝國大學</mark>&lt;b&gt;", out[0]
    assert_equal "<mark>サクラ</mark>と<mark>桜</mark>", out[1]
    assert_equal "…ああああああ<mark>鳥瞰圖</mark>いいいいいいいいいいい…", out[2]
  end

  def test_highlight_keeps_a_variation_selector_with_its_character
    out = run_node(<<~JS, [])
      const c = require('./cjk-index.js');
      console.log(JSON.stringify([
        c.highlight('珊\u{E0100}瑚', '珊瑚'),
        c.highlight('珊\u{E0100}瑚', '珊'),
        c.highlight('葛\uFE00飾北斎', '飾')
      ]));
    JS
    assert_equal ["<mark>珊\u{E0100}瑚</mark>", "<mark>珊\u{E0100}</mark>瑚", "葛\u{FE00}<mark>飾</mark>北斎"], out
    assert_equal out, [CJKIndex.highlight("珊\u{E0100}瑚", "珊瑚"), CJKIndex.highlight("珊\u{E0100}瑚", "珊"),
                       CJKIndex.highlight("葛\u{FE00}飾北斎", "飾")]
  end

  def test_words_named_like_object_members
    b = CJKIndex::Builder.new(fields: %w[title])
    b.add("a", "title" => "constructors and 東京")
    queries = %w[constructor tostring __proto__ hasownproperty]
    js = run_node(<<~JS, [b.to_h, queries])
      const c = require('./cjk-index.js');
      const [data, queries] = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      const idx = new c.Index(data);
      console.log(JSON.stringify(queries.map(q => idx.search(q).map(r => [r.ref, r.score]))));
    JS
    s = CJKIndex::Searcher.new(b)
    queries.each_with_index do |q, i|
      ruby = s.search(q).map { |r| [r[:ref], r[:score]] }
      assert_equal ruby.map(&:first), js[i].map(&:first), q
      ruby.zip(js[i]) { |r, n| assert_in_delta r[1], n[1], 1e-9, q }
    end
  end
end
