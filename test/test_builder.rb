# frozen_string_literal: true

require "test_helper"

class TestBuilder < Minitest::Test
  def test_postings_carry_positions
    b = CJKIndex::Builder.new(fields: %w[title subject], boosts: { "title" => 3 })
    b.add("a.html", "title" => "國牛十圖", "subject" => "牛")
    b.add("b.html", "title" => "建物位置圖")
    h = b.to_h
    assert_equal "cjk_index/2", h["format"]
    assert_equal [3, 1], h["boosts"]
    assert_equal %w[a.html b.html], h["refs"]
    assert_equal [4, 1, 5, 0], h["lengths"]
    # doc, field, count, positions...
    assert_equal [0, 0, 1, 1, 0, 1, 1, 0], h["tokens"]["牛"]
    assert_equal [0, 0, 1, 3, 1, 0, 1, 4], h["tokens"]["図"]
    assert_equal [0, 0, 1, 0], h["tokens"]["国牛"]
  end

  def test_array_values_do_not_join
    b = CJKIndex::Builder.new(fields: %w[subject])
    b.add("a", "subject" => %w[植物 動物])
    h = b.to_h
    assert_equal [0, 0, 2, 1, 4], h["tokens"]["物"]
    assert_equal [5], h["lengths"]
    refute h["tokens"].key?("物動"), "no bigram across two values"
  end
end
