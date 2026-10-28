#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates the variant tables in data/ from their sources.
#
#   ruby script/variant_tables.rb            # download (once) and write data/*.tsv
#   ruby script/variant_tables.rb --check    # exit 1 if data/*.tsv would change
#
# Sources are downloaded into tmp/variant-sources/ (git-ignored) and checked
# against the SHA-256 digests below, so the tables are reproducible. See
# docs/notes/variant-tables.md for why each relation is or is not folded.
#
# Table format (all files): UTF-8, one pair per line, "variant<TAB>folded"
# with an optional third column (source or code points, for reviewers).
# Lines starting with "#" are comments. "folded" may be several characters
# (ko: one Private Use Area character -> a jamo sequence).

require "digest"
require "fileutils"
require "open-uri"
require "set"

ROOT = File.expand_path("..", __dir__)
DATA = File.join(ROOT, "data")
CACHE = File.join(ROOT, "tmp", "variant-sources")

UNICODE_VERSION = "18.0.0"
OPENCC_COMMIT = "2939943bd6f4d459b46d7fdcf07a885ab3f01761"
HYPUA_COMMIT = "7e47655730d4cfea89564768ebb277b86072eef9"

SOURCES = {
  "Unihan.zip" => ["https://www.unicode.org/Public/#{UNICODE_VERSION}/ucd/Unihan.zip",
                   "4c93ea9c1f636451729a840978f1667a53886af37ba854fdcce109721c63d43e"],
  "TSCharacters.txt" => ["https://raw.githubusercontent.com/BYVoid/OpenCC/#{OPENCC_COMMIT}/data/dictionary/TSCharacters.txt", nil],
  "STCharacters.txt" => ["https://raw.githubusercontent.com/BYVoid/OpenCC/#{OPENCC_COMMIT}/data/dictionary/STCharacters.txt", nil],
  "hypua-table" => ["https://raw.githubusercontent.com/kiwiyou/hypua/#{HYPUA_COMMIT}/table", nil]
}.freeze

def fetch(name)
  url, sha = SOURCES.fetch(name)
  path = File.join(CACHE, name)
  unless File.exist?(path)
    FileUtils.mkdir_p(CACHE)
    warn "downloading #{url}"
    File.binwrite(path, URI.parse(url).open("rb", &:read))
  end
  digest = Digest::SHA256.file(path).hexdigest
  abort "#{name}: SHA-256 #{digest} does not match #{sha}" if sha && digest != sha
  path
end

def unihan(file)
  dir = File.join(CACHE, "unihan-#{UNICODE_VERSION}")
  unless File.exist?(File.join(dir, file))
    FileUtils.mkdir_p(dir)
    system("unzip", "-qo", fetch("Unihan.zip"), "-d", dir, exception: true)
  end
  File.foreach(File.join(dir, file), encoding: "UTF-8").filter_map do |line|
    next if line.start_with?("#") || line.strip.empty?

    line.chomp.split("\t", 3)
  end
end

def char(ucs) = ucs[/U\+(\h+)/, 1].to_i(16).chr(Encoding::UTF_8)
def nfkc(str) = str.unicode_normalize(:nfkc)
def codes(str) = str.each_char.map { |c| format("U+%04X", c.ord) }.join(" ")

# ---------------------------------------------------------------- ja

# Pairs [variant, standard, source]; folded into classes below.
def japanese_pairs
  other = unihan("Unihan_OtherMappings.txt")
  variants = unihan("Unihan_Variants.txt")
  pairs = []
  variants.each do |cp, field, value|
    next unless field == "kJapaneseOldVariant" # same pairs as kJapaneseNewVariant, other direction

    value.split.each { |old| pairs << [char(old), char(cp), "joyo"] }
  end
  other.each do |cp, field, value|
    pairs << [char(value), char(cp), "joyo-jis"] if field == "kJoyoKanji" && value.start_with?("U+")
    pairs << [char(cp), char(value[/U\+\h+/]), "jinmei"] if field == "kJinmeiyoKanji" && value.include?("U+")
  end
  variants.each do |cp, field, value|
    next unless field == "kZVariant"

    value.split.each { |v| pairs << [char(cp), char(v), "zvariant"] }
  end
  File.foreach(File.join(DATA, "src", "ja-extra.tsv"), encoding: "UTF-8") do |line|
    next if line.start_with?("#") || line.strip.empty?

    from, to = line.chomp.split("\t")
    pairs << [from, to, "extra"]
  end
  pairs
end

# Which member of a class the others fold to. Lower is preferred.
def japanese_rank(other, extra_targets)
  joyo_jis = Set.new
  joyo = Set.new
  jinmei_standard = Set.new
  jis0 = Set.new
  other.each do |cp, field, value|
    c = char(cp)
    case field
    when "kJoyoKanji" then value.start_with?("U+") ? joyo_jis << c : joyo << c
    when "kJinmeiyoKanji" then jinmei_standard << c unless value.include?("U+")
    when "kJis0" then jis0 << c
    end
  end
  lambda do |c|
    tier = if joyo_jis.include?(c) then 0 # 剥 rather than 剝: the JIS X 0208 form of a Joyo kanji
           elsif joyo.include?(c) then 1
           elsif extra_targets.include?(c) then 2
           elsif jinmei_standard.include?(c) then 3
           elsif jis0.include?(c) then 4
           else 5
           end
    [tier, c.ord]
  end
end

def classes(pairs)
  parent = {}
  find = lambda do |x|
    parent[x] ||= x
    parent[x] = find.call(parent[x]) unless parent[x] == x
    parent[x]
  end
  pairs.each { |a, b| parent[find.call(a)] = find.call(b) }
  parent.keys.group_by { |x| find.call(x) }.values
end

def japanese_table(stats)
  other = unihan("Unihan_OtherMappings.txt")
  raw = japanese_pairs
  stats[:ja_raw] = raw.group_by(&:last).transform_values(&:size)
  # NFKC runs before the table: a compatibility ideograph (U+F900..) never
  # reaches it, so fold its unified equivalent instead.
  pairs = raw.map { |a, b, src| [nfkc(a), nfkc(b), src] }.reject { |a, b, _| a == b }
  source = {}
  pairs.each { |a, b, src| source[a] ||= src; source[b] ||= src }
  extra_targets = Set.new(pairs.select { |*, s| s == "extra" }.map { |_, b, _| b })
  rank = japanese_rank(other, extra_targets)
  joyo = Set.new(other.select { |_, f, v| f == "kJoyoKanji" && !v.start_with?("U+") }.map { |cp, *| char(cp) })
  rows = []
  stats[:ja_multi_joyo] = []
  classes(pairs).each do |members|
    canonical = members.min_by(&rank)
    stats[:ja_multi_joyo] << members.sort.join if members.count { |m| joyo.include?(m) } > 1
    (members - [canonical]).each { |m| rows << [m, canonical, source.fetch(m)] }
  end
  stats[:ja_classes] = classes(pairs).size
  rows.sort_by { |a, *| a.ord }
end

# ---------------------------------------------------------------- zh

def opencc(name)
  File.foreach(fetch(name), encoding: "UTF-8").filter_map do |line|
    next if line.start_with?("#") || line.strip.empty?

    key, values = line.chomp.split("\t", 2)
    [key, values.split]
  end.to_h
end

# Unchanged since 0.1: the first value of each entry, minus entries whose own
# key is among the values (乾 -> 干 乾).
def chinese_full
  opencc("TSCharacters.txt").filter_map do |trad, simps|
    next if simps.include?(trad)

    [trad, simps.first]
  end
end

# Only pairs that are one-to-one in both directions: the Simplified form
# converts back to this Traditional character and to no other. Folding them
# never makes two characters that are distinct in Traditional Chinese equal.
# Also left out: pairs where both sides are Japanese kanji (Joyo or Jinmeiyo,
# after the ja table) that Japanese keeps apart (機 and 机), so that the table
# can be combined with ja without merging Japanese words. Pairs like 貓 -> 猫,
# where the Simplified form is also the Japanese form, stay.
def chinese_safe(full, ja_rows, stats)
  ts = opencc("TSCharacters.txt")
  st = opencc("STCharacters.txt")
  ja = ja_rows.to_h { |from, to, _| [from, to] }
  japanese = Set.new(unihan("Unihan_OtherMappings.txt").filter_map do |cp, field, value|
    nfkc(char(cp)) if %w[kJoyoKanji kJinmeiyoKanji].include?(field) && value.match?(/\A\d{4}\z/)
  end)
  reasons = Hash.new(0)
  rows = full.select do |trad, simp|
    back = st[simp]
    reason = if back.nil? then :simplified_is_also_traditional_no_entry
             elsif back.include?(simp) then :simplified_is_also_traditional
             elsif back != [trad] then :several_traditional
             elsif ts[trad].size > 1 then :several_simplified
             elsif japanese.include?(simp) && japanese.include?(ja.fetch(trad, trad)) && ja.fetch(trad, trad) != simp
               :both_are_japanese_kanji
             end
    reasons[reason] += 1 if reason
    reason.nil?
  end
  stats[:zh_dropped] = reasons
  rows
end

# ---------------------------------------------------------------- ko

def korean_table
  File.foreach(fetch("hypua-table"), encoding: "UTF-8").filter_map do |line|
    next if line.strip.empty?

    pua, jamo = line.strip.split(",")
    from = pua.to_i(16).chr(Encoding::UTF_8)
    # Stored in NFKC, the form the normalizer compares in: modern jamo
    # sequences become precomposed syllables (ᄀ + ᅡ -> 가), old ones stay.
    to = nfkc(jamo.split("&").map { |h| h.to_i(16).chr(Encoding::UTF_8) }.join)
    [from, to, codes(to)]
  end
end

# ---------------------------------------------------------------- output

def write(file, header, rows)
  body = rows.map { |r| r.join("\t") }.join("\n")
  text = header.map { |h| "# #{h}".rstrip }.join("\n") + "\n" + body + "\n"
  path = File.join(DATA, file)
  if ARGV.include?("--check")
    current = File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
    (@changed ||= []) << file unless current == text
  else
    File.write(path, text)
  end
  rows.size
end

stats = {}
ja = japanese_table(stats)
zh = chinese_full
zh_safe = chinese_safe(zh, ja, stats)
ko = korean_table

counts = {}
counts[:ja] = write("ja-kyujitai.tsv", [
  "Japanese variants -> one form per character (old forms -> modern forms, glyph variants).",
  "Generated by script/variant_tables.rb; do not edit by hand (edit data/src/ja-extra.tsv).",
  "Format: variant<TAB>folded<TAB>source.  Sources:",
  "  joyo      Joyo Kanji Table (常用漢字表, Cabinet Notice No. 2, 2010-11-30): old forms in brackets,",
  "            via Unihan kJapaneseOldVariant",
  "  joyo-jis  Joyo Kanji Table: JIS X 0208 forms of the five kanji with two accepted forms",
  "            (剥/剝 etc.), via Unihan kJoyoKanji",
  "  jinmei    Jinmeiyo Kanji (人名用漢字, Family Register Act Enforcement Regulations, appended table 3,",
  "            2010, amended to 2026), via Unihan kJinmeiyoKanji",
  "  zvariant  Unihan kZVariant (same abstract character encoded twice)",
  "  extra     data/src/ja-extra.tsv, written for cjk_index",
  "Unihan #{UNICODE_VERSION}: Copyright (c) 1991-2026 Unicode, Inc. Unicode License v3 (see LICENSE-Unicode).",
  "The official lists are not subject to copyright in Japan (Copyright Act, art. 13).",
  "Compatibility ideographs are left out: NFKC folds them before this table is read."
], ja)
counts[:zh] = write("zh-hant-hans.tsv", [
  "Traditional -> Simplified Chinese, one character each.",
  "Derived from OpenCC data/dictionary/TSCharacters.txt (commit #{OPENCC_COMMIT})",
  "https://github.com/BYVoid/OpenCC  Copyright (c) 2010-2026 Carbo Kuo and contributors, Apache License 2.0",
  "Changes: kept the first value of each entry; dropped entries whose own key is among",
  "its values (ambiguous, e.g. 乾 -> 干 乾) so that searching does not merge distinct words."
], zh)
counts[:zh_safe] = write("zh-hant-hans-safe.tsv", [
  "Traditional -> Simplified Chinese, only pairs that are one-to-one in both directions.",
  "Derived from OpenCC data/dictionary/TSCharacters.txt and STCharacters.txt (commit #{OPENCC_COMMIT})",
  "https://github.com/BYVoid/OpenCC  Copyright (c) 2010-2026 Carbo Kuo and contributors, Apache License 2.0",
  "Generated by script/variant_tables.rb. Changes: the pairs of zh-hant-hans.tsv whose Simplified form",
  "converts back to that Traditional character only. Left out, e.g.: 後 -> 后 (后 is also a Traditional",
  "character), 發/髮 -> 发 (two Traditional characters), 乾/幹 -> 干, 麵 -> 面, 裡 -> 里, 鬆 -> 松,",
  "and pairs of two distinct Japanese kanji (機 -> 机, 憐 -> 怜, 棲 -> 栖, 莊 -> 庄)."
], zh_safe)
counts[:ko] = write("ko-hanyang-pua.tsv", [
  "Old Hangul written in the Hanyang Private Use Area (U+E0BC..U+F8F7; HWP and the Hanyang fonts)",
  "-> standard Unicode conjoining jamo, stored in NFKC (modern sequences precomposed).",
  "Format: pua<TAB>jamo<TAB>code points of jamo.",
  "From the table of the hypua crate, https://github.com/kiwiyou/hypua (commit #{HYPUA_COMMIT}),",
  "released by its author under the Unlicense (public domain dedication). The same mapping as",
  "hypua2jamo (p2jc), both based on the KTUG Hanyang PUA Table Project. See NOTICE."
], ko)

warn "counts: #{counts}"
warn "ja raw pairs by source: #{stats[:ja_raw]}; classes: #{stats[:ja_classes]}"
warn "ja classes with more than one Joyo kanji: #{stats[:ja_multi_joyo].join(' ')}"
warn "zh-safe dropped: #{stats[:zh_dropped]}"
if @changed&.any?
  warn "out of date: #{@changed.join(', ')}"
  exit 1
end
