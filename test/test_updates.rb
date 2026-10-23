# frozen_string_literal: true

require "test_helper"

# An index changed with add, remove and update must be the same as one built
# from scratch with the final documents in the same order.
class TestUpdates < Minitest::Test
  TITLES = ["東京帝國大學本部構内及農學部建物鳥瞰圖", "國牛十圖", "群芳圖譜 第1輯", "IIIF Manifest Guide",
            "소학언해 小學諺解", "佐々木家文書", "農学部 正門", "建物位置圖", "Photograph of Sakura サクラ", ""].freeze
  TYPES = ["地図", "地圖", "写真", "図譜;書籍", nil].freeze
  DATES = ["1900", "１９３１年", "明治33年", 1923, nil].freeze

  FIELDS = %w[title creator].freeze
  FILTERS = { "type" => { "kind" => "value", "separator" => ";" }, "date" => "year" }.freeze

  def new_builder = CJKIndex::Builder.new(fields: FIELDS, boosts: { "title" => 3 }, filters: FILTERS)

  def random_doc(rng)
    { "title" => TITLES.sample(random: rng), "creator" => [TITLES.sample(random: rng), "東京大学"].sample(random: rng),
      "type" => TYPES.sample(random: rng), "date" => DATES.sample(random: rng) }
  end

  def rebuild(docs)
    b = new_builder
    docs.each { |ref, doc| b.add(ref, doc) }
    b
  end

  def test_random_changes_equal_rebuild
    20.times do |seed|
      rng = Random.new(seed)
      b = new_builder
      docs = {} # ref => doc, in index order
      60.times do
        ref = "d#{rng.rand(15)}"
        case rng.rand(3)
        when 0
          next if docs.key?(ref)

          doc = random_doc(rng)
          b.add(ref, doc)
          docs[ref] = doc
        when 1
          assert_equal docs.key?(ref), b.remove(ref)
          docs.delete(ref)
        else
          doc = random_doc(rng)
          b.update(ref, doc)
          docs[ref] = doc
        end
      end
      assert_equal rebuild(docs).to_h, b.to_h, "seed #{seed}"
      assert_equal docs.keys, b.refs
      assert_equal docs.size, b.size
    end
  end

  def test_load_round_trips_and_can_be_updated
    rng = Random.new(1)
    docs = (0...12).to_h { |i| ["d#{i}", random_doc(rng)] }
    written = rebuild(docs).to_json
    loaded = CJKIndex::Builder.load(written)
    assert_equal JSON.parse(written), loaded.to_h

    loaded.remove("d3")
    docs.delete("d3")
    loaded.update("d5", docs["d5"] = { "title" => "新しい題名", "type" => "写真", "date" => "2001" })
    loaded.add("d12", docs["d12"] = { "title" => "追加した資料", "type" => "地図" })
    assert_equal rebuild(docs).to_h, loaded.to_h
  end

  def test_searcher_sees_changes
    b = new_builder
    b.add("a", "title" => "國牛十圖", "type" => "地図")
    s = CJKIndex::Searcher.new(b)
    assert_equal %w[a], s.search("牛").map { |r| r[:ref] }
    b.add("b", "title" => "牛の図", "type" => "写真")
    b.update("a", "title" => "建物位置圖", "type" => "写真")
    assert_equal %w[b], s.search("牛").map { |r| r[:ref] }
    assert_equal [{ value: "写真", count: 2 }], s.facets("type")
    b.remove("b")
    assert_equal [], s.search("牛")
    assert_equal %w[a], s.refs
    # the same answers as an index written now
    fresh = CJKIndex::Searcher.new(b.to_json)
    assert_equal fresh.search("建物"), s.search("建物")
  end

  def test_remove_missing_ref
    refute new_builder.remove("nothing")
  end
end
