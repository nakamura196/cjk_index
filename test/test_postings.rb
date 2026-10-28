# frozen_string_literal: true

require "test_helper"

class TestPostings < Minitest::Test
  P = CJKIndex::Postings

  def test_numbers_round_trip
    values = [0, 1, 59, 60, 61, 1799, 1800, 53_999, 54_000, 1_000_000, 123_456_789]
    s = values.map { |v| P.number(v) }.join
    assert_equal values, P.numbers(s)
    assert_equal 1, P.number(59).length
    assert_equal 2, P.number(1799).length
    assert_equal 3, P.number(53_999).length
    assert_equal 4, P.number(54_000).length
    refute_match(/["\\]/, P::ALPHABET)
    assert_equal 90, P::ALPHABET.length
  end

  def test_encode_and_decode
    flat = [0, 0, 1, 3, 0, 2, 2, 5, 70_000, 4, 1, 3, 1, 2, 3]
    s = P.encode(flat, 3)
    assert_equal flat, P.decode(s, 3)
    assert_equal 13, P.last_key(s)
    assert_equal [0, 2, 13], P.each_key(s).to_a
    assert_equal(-1, P.last_key(""))
  end

  def test_changes
    s = P.encode([0, 0, 1, 3, 0, 2, 2, 5, 70_000, 4, 1, 3, 1, 2, 3, 6, 0, 1, 9], 3)
    flat = ->(str) { P.decode(str, 3) }
    assert_equal [4, 1, 3, 1, 2, 3, 6, 0, 1, 9], flat.(P.delete(s, 0..2))
    assert_equal [0, 0, 1, 3, 0, 2, 2, 5, 70_000, 6, 0, 1, 9], flat.(P.delete(s, 12..14))
    assert_equal [0, 0, 1, 3, 0, 2, 2, 5, 70_000, 4, 1, 3, 1, 2, 3], flat.(P.delete(s, 18..20))
    assert_same s, P.delete(s, 3..5)
    assert_equal "", P.delete(P.encode([2, 1, 1, 0], 3), 6..8)
    assert_equal [0, 0, 1, 3, 0, 2, 2, 5, 70_000, 2, 0, 2, 7, 8, 4, 1, 3, 1, 2, 3, 6, 0, 1, 9],
                 flat.(P.insert(s, 6, [7, 8]))
    assert_equal [0, 0, 1, 3, 0, 2, 2, 5, 70_000, 4, 1, 3, 1, 2, 3, 6, 0, 1, 9, 7, 1, 1, 0], flat.(P.insert(s.dup, 22, [0]))
    assert_equal [0, 0, 1, 3, 0, 2, 2, 5, 70_000, 1, 1, 3, 1, 2, 3, 2, 0, 1, 9],
                 flat.(P.renumber(s, 3, [0, nil, nil, nil, 1, nil, 2]))
    assert_same s, P.renumber(s, 3, (0..6).to_a)
  end
end
