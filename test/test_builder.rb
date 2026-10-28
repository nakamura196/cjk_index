# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestBuilder < Minitest::Test
  def decode(h, token) = CJKIndex::Postings.decode(h["tokens"][token], h["fields"].length)

  def test_postings_carry_positions
    b = CJKIndex::Builder.new(fields: %w[title subject], boosts: { "title" => 3 })
    b.add("a.html", "title" => "國牛十圖", "subject" => "牛")
    b.add("b.html", "title" => "建物位置圖")
    h = b.to_h
    assert_equal "cjk_index/4", h["format"]
    refute h.key?("filters"), "no filters unless configured"
    assert_equal [3, 1], h["boosts"]
    assert_equal %w[a.html b.html], h["refs"]
    assert_equal [4, 1, 5, 0], h["lengths"]
    # doc, field, count, positions...
    assert_equal [0, 0, 1, 1, 0, 1, 1, 0], decode(h, "牛")
    assert_equal [0, 0, 1, 3, 1, 0, 1, 4], decode(h, "図")
    assert_equal [0, 0, 1, 0], decode(h, "国牛")
    # key gap, count, position gaps: keys 0 (doc 0 title) and 1 (doc 0 subject)
    assert_equal [0, 1, 1, 0, 1, 0], CJKIndex::Postings.numbers(h["tokens"]["牛"])
  end

  def test_array_values_do_not_join
    b = CJKIndex::Builder.new(fields: %w[subject])
    b.add("a", "subject" => %w[植物 動物])
    h = b.to_h
    assert_equal [0, 0, 2, 1, 4], decode(h, "物")
    assert_equal [5], h["lengths"]
    refute h["tokens"].key?("物動"), "no bigram across two values"
  end

  def test_write_is_to_json
    b = CJKIndex::Builder.new(fields: %w[title], filters: %w[type])
    b.add("a", "title" => "國牛十圖", "type" => "絵図")
    b.add("b", "title" => "\"引用\" と \\ IIIF", "type" => "地図")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "index.json")
      b.write(path)
      assert_equal b.to_json, File.read(path, encoding: "UTF-8")
      assert_equal [], Dir.children(dir) - ["index.json"], "no temporary file left"
    end
  end
end
