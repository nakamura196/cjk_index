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
      console.log(JSON.stringify(input.map(s => [c.normalize(s), c.tokenize(s, false), c.tokenize(s, true)])));
    JS
    ruby = SAMPLES.map { |s| [CJKIndex.normalize(s), CJKIndex.tokenize(s), CJKIndex.tokenize(s, unigrams: true)] }
    assert_equal ruby, js
  end

  def test_search_on_ruby_built_index
    b = CJKIndex::Builder.new(fields: %w[title creator], boosts: { "title" => 3 })
    b.add("a", "title" => "東京帝國大學本部構内及農學部建物鳥瞰圖")
    b.add("b", "title" => "建物位置圖", "creator" => "東京大学")
    b.add("c", "title" => "國牛十圖")
    js = run_node(<<~JS, [b.to_h, ["鳥瞰図", "建物", "東京大学", "牛", "存在しない", "図"]])
      const c = require('./cjk-index.js');
      const [data, queries] = JSON.parse(require('fs').readFileSync(0, 'utf8'));
      const idx = new c.Index(data);
      console.log(JSON.stringify(queries.map(q => idx.search(q).map(r => r.ref))));
    JS
    # 「東京大学」 does not match 「東京帝國大學…」: 京大 is not a substring of it.
    # Ties (same field, same tf) keep document order.
    assert_equal [%w[a], %w[a b], %w[b], %w[c], [], %w[a b c]], js
  end
end
