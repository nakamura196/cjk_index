# frozen_string_literal: true

require "test_helper"

class TestBuilder < Minitest::Test
  def test_postings_are_doc_field_tf_triples
    b = CJKIndex::Builder.new(fields: %w[title subject], boosts: { "title" => 3 })
    b.add("a.html", "title" => "國牛十圖", "subject" => "牛")
    b.add("b.html", "title" => "建物位置圖")
    h = b.to_h
    assert_equal "cjk_index/1", h["format"]
    assert_equal [3, 1], h["boosts"]
    assert_equal %w[a.html b.html], h["refs"]
    assert_equal [0, 0, 1, 0, 1, 1], h["tokens"]["牛"]
    assert_equal [0, 0, 1, 1, 0, 1], h["tokens"]["図"]
  end

  def test_array_values_are_indexed
    b = CJKIndex::Builder.new(fields: %w[subject])
    b.add("a", "subject" => %w[植物 動物])
    assert_equal [0, 0, 2], b.to_h["tokens"]["物"]
  end
end
