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
    "第1輯、IIIF「マニフェスト」", "서울대학교 도서관", "Hello, World! 羣芳圖譜", "𠮟る", ""
  ].freeze

  def setup
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)
  end

  def run_node(script, input)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source)
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
end
