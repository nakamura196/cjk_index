# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "tmpdir"

# Format 4 in one file and split into shards, and the older formats: Ruby
# and the browser script must give the same results from each.
class TestSplit < Minitest::Test
  DOCS = TestSearcherMatchesRuntime::DOCS.merge(
    # Characters at and beyond U+E000 sort differently by code point (Ruby)
    # and by UTF-16 code unit (JavaScript's <): shards must still be found.
    "private" => { "title" => "\u{E000}abc 私用 😀 emoji", "subject" => %w[記号] },
    "astral" => { "title" => "𠮟る 𩸽 ﹏﹏ ｼｬｯ", "subject" => %w[記号 漢字] }
  ).freeze
  QUERIES = (TestSearcherMatchesRuntime::QUERIES + ["\u{E000}abc", "😀", "emoj", "𠮟", "𩸽", "記号", "私用"]).freeze
  CASES = QUERIES.map { |q| [q, nil] } + [["", { "subject" => "地図" }], ["東京", { "subject" => %w[地図 植物] }],
                                          ["", { "subject" => "記号" }]]

  def builder
    b = CJKIndex::Builder.new(fields: %w[title creator subject], boosts: { "title" => 3, "subject" => 2 },
                              filters: %w[subject])
    DOCS.each { |ref, doc| b.add(ref, doc) }
    b
  end

  def node?
    system("node", "--version", out: File::NULL, err: File::NULL)
  end

  def answers(searcher)
    CASES.map do |q, f|
      results = searcher.search(q, filter: f)
      [results.map { |r| [r[:ref], r[:score], r[:fields]] }, searcher.facets("subject", results)]
    end
  end

  # The same index in format 3: posting lists as JSON arrays.
  def version3(h)
    h.merge("format" => "cjk_index/3",
            "tokens" => h["tokens"].transform_values { |s| CJKIndex::Postings.decode(s, h["fields"].length) })
  end

  def assert_same_answers(expected, actual)
    assert_equal expected.length, actual.length
    expected.zip(actual, CASES) do |(results, facets), (results2, facets2), c|
      assert_equal results.map { |r| [r[0], r[2]] }, results2.map { |r| [r[0], r[2]] }, c.inspect
      results.zip(results2) { |r, r2| assert_in_delta r[1], r2[1], 1e-9, c.inspect }
      assert_equal facets.map { |h| h.transform_keys(&:to_s) }, facets2.map { |h| h.transform_keys(&:to_s) }, c.inspect
    end
  end

  def test_version_3_reads_the_same
    b = builder
    expected = answers(CJKIndex::Searcher.new(b))
    v3 = version3(b.to_h)
    assert_same_answers expected, answers(CJKIndex::Searcher.new(JSON.generate(v3)))
    assert_equal b.to_h, CJKIndex::Builder.load(JSON.generate(v3)).to_h
    assert_equal b.to_h, CJKIndex::Builder.load(v3.merge("format" => "cjk_index/2")).to_h
  end

  def test_split_reads_the_same
    b = builder
    expected = answers(CJKIndex::Searcher.new(b))
    Dir.mktmpdir do |dir|
      manifest = b.write_split(dir, shard_size: 60)
      data = JSON.parse(File.read(manifest))
      assert_equal "cjk_index/4", data["format"]
      refute data.key?("tokens")
      assert_operator data["shards"].length, :>, 20
      assert_equal data["shards"].map(&:last).sort, (Dir.children(dir) - ["index.json"]).sort
      assert_equal b.to_h["tokens"].keys.reject { |t| t.match?(CJKIndex::Tokenizer::CJK) }.sort, data["latin"]
      assert_equal b.to_h, CJKIndex::Builder.read(dir).to_h
      assert_equal b.to_h, CJKIndex::Builder.read(manifest).to_h
      assert_raises(ArgumentError) { CJKIndex::Builder.load(data) }
      assert_raises(ArgumentError) { CJKIndex::Searcher.new(data) }
      assert_same_answers expected, answers(CJKIndex::Searcher.load(dir))

      loaded = []
      lazy = CJKIndex::Searcher.new(data, load_shard: lambda { |file|
        loaded << file
        JSON.parse(File.read(File.join(dir, file)))
      })
      lazy.search("鳥瞰図")
      assert_equal 2, loaded.uniq.length, "鳥瞰 and 瞰図 only"
    end
  end

  def test_rewriting_a_split_index
    b = builder
    Dir.mktmpdir do |dir|
      b.write_split(dir, shard_size: 200)
      before = Dir.children(dir).to_h { |f| [f, File.mtime(File.join(dir, f))] }
      b.update("agri3", "title" => "國牛十圖 改訂", "subject" => ["牛"])
      b.remove("astral") # the last document: no later document is renumbered
      b.write_split(dir, shard_size: 200)
      data = JSON.parse(File.read(File.join(dir, "index.json")))
      assert_equal data["shards"].map(&:last).sort, (Dir.children(dir) - ["index.json"]).sort, "stale shards removed"
      kept = data["shards"].map(&:last) & before.keys
      refute_empty kept, "unchanged shards keep their names"
      kept.each { |f| assert_equal before[f], File.mtime(File.join(dir, f)) }
      assert_equal b.to_h, CJKIndex::Builder.read(dir).to_h
    end
  end

  def test_split_with_one_shard_and_empty_index
    Dir.mktmpdir do |dir|
      b = builder
      b.write_split(dir, shard_size: 100_000_000)
      assert_equal 1, JSON.parse(File.read(File.join(dir, "index.json")))["shards"].length
      empty = CJKIndex::Builder.new(fields: %w[title])
      empty.write_split(File.join(dir, "empty"))
      assert_equal [], CJKIndex::Searcher.load(File.join(dir, "empty")).search("東京")
    end
  end

  def run_node(script, input, dir)
    File.write(File.join(dir, "cjk-index.js"), CJKIndex::Runtime.source)
    File.write(File.join(dir, "run.js"), script)
    out, err, status = Open3.capture3("node", File.join(dir, "run.js"), stdin_data: JSON.generate(input))
    assert status.success?, err
    JSON.parse(out)
  end

  NODE_ANSWERS = <<~JS
    function answers(idx, cases, search) {
      return cases.reduce((p, [q, f]) => p.then(acc => search(idx, q, f ? { filter: f } : undefined).then(results => {
        acc.push([results.map(r => [r.ref, r.score, r.fields]), idx.facets('subject', results)]);
        return acc;
      })), Promise.resolve([]));
    }
  JS

  def test_browser_reads_every_format_the_same
    skip "node is not installed" unless node?
    b = builder
    expected = answers(CJKIndex::Searcher.new(b))
    Dir.mktmpdir do |dir|
      b.write_split(File.join(dir, "split"), shard_size: 60)
      js = run_node(<<~JS, [b.to_h, version3(b.to_h), CASES], dir)
        const c = require('./cjk-index.js');
        const fs = require('fs');
        const [v4, v3, cases] = JSON.parse(fs.readFileSync(0, 'utf8'));
        #{NODE_ANSWERS}
        const sync = (idx, q, o) => Promise.resolve(idx.search(q, o));
        const async = (idx, q, o) => idx.searchAsync(q, o);
        // CJKIndex.load with fetch from the split directory, as a browser would.
        const requested = [];
        globalThis.fetch = url => {
          requested.push(url);
          const path = __dirname + '/split/' + url.replace('https://example.test/search/', '');
          return Promise.resolve({ ok: true, json: () => Promise.resolve(JSON.parse(fs.readFileSync(path, 'utf8'))) });
        };
        (async () => {
          const out = {};
          out.v4 = await answers(new c.Index(v4), cases, sync);
          out.v3 = await answers(new c.Index(v3), cases, sync);
          out.v4async = await answers(new c.Index(v4), cases, async);
          const split = await c.load('https://example.test/search/index.json');
          out.split = await answers(split, cases, async);
          out.requested = requested.length;
          out.shards = split.shardFile.length;
          const fresh = await c.load('https://example.test/search/index.json');
          try { fresh.search('鳥瞰図'); out.sync = 'no error'; } catch (e) { out.sync = e.message; }
          out.blank = fresh.search('', { filter: { subject: '地図' } }).map(r => r.ref);
          const before = requested.length;
          await fresh.prepare('鳥瞰図');
          out.fetched = requested.length - before;
          out.after = fresh.search('鳥瞰図').map(r => r.ref);
          console.log(JSON.stringify(out));
        })().catch(e => { console.error(e); process.exit(1); });
      JS
      %w[v4 v3 v4async split].each { |k| assert_same_answers expected, js[k] }
      assert_match(/not loaded/, js["sync"])
      assert_equal %w[agri1 agri4], js["blank"]
      assert_equal 2, js["fetched"]
      assert_equal %w[agri1], js["after"]
      assert_operator js["requested"], :<, js["shards"], "a search fetches only some shards"
    end
  end
end
