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

  # Random lists with key gaps and position counts of one to four characters
  # (and so many positions to skip), checked against plain arrays.
  def test_changes_on_random_lists
    fields = 3
    flatten = ->(entries) { entries.flat_map { |doc, field, offsets| [doc, field, offsets.size, *offsets] } }
    key = ->(entry) { (entry[0] * fields) + entry[1] }
    random_offsets = ->(rng) { Array.new([1, 2, 9, 70, 1900].sample(random: rng)) { rng.rand(60_000) }.sort }
    50.times do |seed|
      rng = Random.new(seed)
      doc = 0
      entries = Array.new(rng.rand(1..12)) do
        doc += [0, 1, 25, 700, 20_000].sample(random: rng) + 1
        [doc, rng.rand(fields), random_offsets.(rng)]
      end
      s = P.encode(flatten.(entries), fields)
      keys = entries.map(&key)
      assert_equal flatten.(entries), P.decode(s, fields), "seed #{seed}"
      assert_equal keys, P.each_key(s).to_a
      assert_equal keys.last, P.last_key(s)

      gone = entries.sample(random: rng)
      range = (gone[0] * fields)...((gone[0] + 1) * fields)
      assert_equal flatten.(entries.reject { |e| range.cover?(key.(e)) }), P.decode(P.delete(s, range), fields)

      new_doc = rng.rand(doc + 2)
      unless entries.any? { |e| e[0] == new_doc }
        added = [new_doc, rng.rand(fields), random_offsets.(rng)]
        assert_equal flatten.((entries + [added]).sort_by(&key)), P.decode(P.insert(s.dup, key.(added), added[2]), fields)
      end

      kept = entries.map(&:first).uniq.reject { rng.rand(3).zero? }
      numbering = []
      kept.each_with_index { |d, i| numbering[d] = i }
      renumbered = entries.select { |e| kept.include?(e[0]) }.map { |d, f, o| [numbering[d], f, o] }
      # renumber expects the removed documents' entries to be gone already
      left = (entries.map(&:first).uniq - kept).reduce(s) { |str, d| P.delete(str, (d * fields)...((d + 1) * fields)) }
      assert_equal flatten.(renumbered), P.decode(P.renumber(left, fields, numbering), fields)
    end
  end
end
