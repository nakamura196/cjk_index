# frozen_string_literal: true

module CJKIndex
  # Folds text so that spelling variants a reader treats as "the same" compare
  # equal: NFKC (full-width -> half-width etc.), lowercase, katakana ->
  # hiragana, character variants from the selected tables, and the iteration
  # mark 々 expanded to the preceding character.
  #
  # The same rules run in the browser (see Runtime), so an index built here
  # and a query typed there are folded identically.
  #
  # Variant tables (data/*.tsv):
  #   ja  Japanese old forms -> modern forms (圖 -> 図). Default.
  #   zh  Traditional -> Simplified Chinese, from OpenCC. Opt in: it also
  #       merges characters that are distinct in Japanese (後 and 后).
  # With several tables, characters linked by any table fold to one form,
  # preferring the target of the table listed first: with [ja, zh],
  # 圖, 図 and 图 all become 図.
  class Normalizer
    DATA_DIR = File.expand_path("../../data", __dir__)
    TABLES = {
      "ja" => "ja-kyujitai.tsv",
      "zh" => "zh-hant-hans.tsv"
    }.freeze
    DEFAULT_TABLES = %w[ja].freeze

    # Katakana ァ (U+30A1) .. ヶ (U+30F6) map to hiragana by subtracting 0x60.
    KATAKANA_FIRST = 0x30A1
    KATAKANA_LAST = 0x30F6
    KANA_OFFSET = 0x60
    ITERATION_MARK = "々"

    def self.default
      @default ||= new
    end

    def self.read_table(name)
      file = TABLES.fetch(name) { raise ArgumentError, "unknown variant table #{name.inspect} (#{TABLES.keys.join(', ')})" }
      File.readlines(File.join(DATA_DIR, file), chomp: true, encoding: "UTF-8")
          .reject { |line| line.empty? || line.start_with?("#") }
          .map { |line| line.split("\t", 2) }
    end

    attr_reader :tables, :variants

    def initialize(tables: DEFAULT_TABLES)
      @tables = tables.map(&:to_s).uniq.freeze
      @variants = build_variants.freeze
    end

    def normalize(text)
      return "" if text.nil?

      prev = nil
      text.to_s.unicode_normalize(:nfkc).downcase.each_char.map do |ch|
        code = ch.ord
        ch = (code - KANA_OFFSET).chr(Encoding::UTF_8) if code.between?(KATAKANA_FIRST, KATAKANA_LAST)
        ch = @variants.fetch(ch, ch)
        ch = prev if ch == ITERATION_MARK && prev
        prev = ch
      end.join
    end

    private

    # Union-find over all pairs; each class folds to the target preferred by
    # the earliest table (lowest code point among equals, for determinism).
    def build_variants
      parent = {}
      find = lambda do |x|
        parent[x] ||= x
        parent[x] = find.call(parent[x]) unless parent[x] == x
        parent[x]
      end
      rank = {}
      @tables.each_with_index do |name, priority|
        self.class.read_table(name).each do |from, to|
          parent[find.call(from)] = find.call(to)
          rank[to] = [rank.fetch(to, [priority, to.ord]), [priority, to.ord]].min
        end
      end
      classes = parent.keys.group_by { |x| find.call(x) }
      classes.each_value.with_object({}) do |members, map|
        canonical = members.min_by { |m| rank.fetch(m, [Float::INFINITY, m.ord]) }
        members.each { |m| map[m] = canonical unless m == canonical }
      end
    end
  end
end
