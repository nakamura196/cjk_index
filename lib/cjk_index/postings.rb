# frozen_string_literal: true

module CJKIndex
  # The compact encoding of a posting list in format 4, shared by Builder
  # (writing) and Searcher (reading); runtime.js decodes it the same way.
  #
  # A list is a sequence of entries, ordered by document and field. Each
  # entry is written as numbers:
  #
  #   key gap, n, first position, gap to the next position, ...
  #
  # where key = document * number of fields + field, and the key gap is the
  # difference to the key of the previous entry minus 1 (the first entry
  # counts from -1). n is the number of positions. Each number is written in
  # printable ASCII: the last digit in base 60 from the first 60 characters
  # of ALPHABET, the digits before it in base 30 from the other 30, most
  # significant first. 0..59 take one character, up to 1,799 two, up to
  # 53,999 three. ALPHABET has neither " nor \, so a list is a JSON string
  # without escapes.
  module Postings
    ALPHABET = ((0x23..0x7d).map(&:chr) - ["\\"]).join.freeze
    LAST = 60
    LEAD = 30
    # byte => digit; 0...60 ends a number, 60...90 leads.
    DIGIT = Array.new(256, -1).tap { |t| ALPHABET.each_byte.with_index { |b, i| t[b] = i } }.freeze

    def self.number_slow(value)
      s = ALPHABET[value % LAST]
      value /= LAST
      while value.positive?
        s = ALPHABET[LAST + (value % LEAD)] + s
        value /= LEAD
      end
      s
    end

    # Every number of up to three characters, written once.
    NUMBERS = Array.new(LAST * LEAD * LEAD) { |v| number_slow(v).freeze }.freeze

    module_function

    def number(value) = NUMBERS[value] || number_slow(value)

    # Appends one entry to out. offsets are ascending positions.
    def append(out, key_gap, offsets)
      out << number(key_gap) << number(offsets.length)
      last = 0
      offsets.each do |pos|
        out << number(pos - last)
        last = pos
      end
      out
    end

    # All numbers of a list.
    def numbers(str)
      out = []
      acc = 0
      str.each_byte do |b|
        d = DIGIT[b]
        if d >= LAST then acc = (acc * LEAD) + d - LAST
        else
          out << ((acc * LAST) + d)
          acc = 0
        end
      end
      out
    end

    # Yields key, start, body and stop for each entry: its key, and the byte
    # offsets where the entry starts, where its key gap ends and where it
    # ends. Loops over bytes rather than numbers, so that the changes below
    # can copy the rest of a list as it is.
    def each_entry(str)
      return enum_for(:each_entry, str) unless block_given?

      key = -1
      i = 0
      len = str.bytesize
      while i < len
        start = i
        acc = 0
        while (d = DIGIT[str.getbyte(i)]) >= LAST
          acc = (acc * LEAD) + d - LAST
          i += 1
        end
        key += (acc * LAST) + d + 1
        i += 1
        body = i
        acc = 0
        while (d = DIGIT[str.getbyte(i)]) >= LAST
          acc = (acc * LEAD) + d - LAST
          i += 1
        end
        n = (acc * LAST) + d
        i += 1
        while n.positive?
          n -= 1 if DIGIT[str.getbyte(i)] < LAST
          i += 1
        end
        yield key, start, body, i
      end
    end

    # Key of the last entry, -1 for an empty list.
    def last_key(str)
      key = -1
      each_entry(str) { |k| key = k }
      key
    end

    # Each key of a list, in order.
    def each_key(str)
      return enum_for(:each_key, str) unless block_given?

      each_entry(str) { |key| yield key }
    end

    # The list without the entries whose keys are in range (consecutive).
    def delete(str, range)
      before = -1
      from = nil
      each_entry(str) do |key, start, body|
        if range.cover?(key)
          from ||= start
        elsif from
          return str.byteslice(0, from) + number(key - before - 1) + str.byteslice(body..)
        elsif key > range.end
          return str
        else
          before = key
        end
      end
      from ? str.byteslice(0, from) : str
    end

    # The list with an entry for key (not yet in it) and offsets inserted in order.
    def insert(str, key, offsets)
      before = -1
      each_entry(str) do |k, start, body|
        if k > key
          entry = append(+"", key - before - 1, offsets)
          return str.byteslice(0, start) + entry + number(k - key - 1) + str.byteslice(body..)
        end
        before = k
      end
      append(+str, key - before - 1, offsets)
    end

    # The list with each key's document replaced by numbering[document], which
    # keeps the order (removed documents have no entries).
    def renumber(str, fields, numbering)
      out = +""
      old_before = -1
      new_before = -1
      copied = 0 # str up to here is in out or to be copied as it is
      each_entry(str) do |key, start, body|
        new_key = (numbering[key / fields] * fields) + (key % fields)
        if new_key - new_before != key - old_before
          out << str.byteslice(copied, start - copied) << number(new_key - new_before - 1)
          copied = body
        end
        old_before = key
        new_before = new_key
      end
      copied.zero? ? str : out << str.byteslice(copied..)
    end

    # The flat list of format 3, [doc, field, n, pos, ..., doc, ...].
    def decode(str, fields)
      nums = numbers(str)
      out = []
      key = -1
      i = 0
      while i < nums.length
        key += nums[i] + 1
        n = nums[i + 1]
        out << (key / fields) << (key % fields) << n
        pos = 0
        j = i + 2
        stop = j + n
        while j < stop
          pos += nums[j]
          out << pos
          j += 1
        end
        i = stop
      end
      out
    end

    # A flat list of format 2 or 3 in this encoding.
    def encode(flat, fields)
      out = +""
      last = -1
      i = 0
      while i < flat.length
        key = (flat[i] * fields) + flat[i + 1]
        n = flat[i + 2]
        append(out, key - last - 1, flat[i + 3, n])
        last = key
        i += 3 + n
      end
      out
    end
  end
end
