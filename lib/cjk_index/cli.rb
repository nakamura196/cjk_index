# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../cjk_index"

module CJKIndex
  # The command-line tool (exe/cjk_index) and the logic that the Rake task
  # shares with it. Needs only Ruby's standard library; "csv" is loaded the
  # first time a CSV file is read (see Records.csv).
  #
  #   cjk_index build items.csv --ref objectid --fields title,creator --boost title=3 -o index.json
  #   cjk_index search index.json 鳥瞰図 --filter type=地図
  #   cjk_index runtime -o cjk-index.js
  module CLI
    # A mistake in the arguments or the input; run prints it and returns 2.
    class Error < StandardError; end

    USAGE = <<~TEXT
      Usage: cjk_index COMMAND [options]

      Commands:
        build     read records (CSV, JSON, JSON Lines) and write an index
        search    query an index file
        runtime   write the browser script

      Run "cjk_index COMMAND --help" for the options of a command.
      Options: -h, --help   -v, --version
    TEXT

    FORMATS = %w[csv json jsonl].freeze

    module_function

    # Runs the tool and returns the exit status: 0 done, 1 failed (input could
    # not be read), 2 wrong usage. Output goes to the given streams.
    def run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      argv = argv.dup
      command = argv.shift
      case command
      when nil
        stderr.puts USAGE
        return 2
      when "-h", "--help", "help" then stdout.puts USAGE
      when "-v", "--version", "version" then stdout.puts VERSION
      when "build" then build_command(argv, stdin, stdout)
      when "search" then search_command(argv, stdout)
      when "runtime" then runtime_command(argv, stdout)
      else raise Error, "unknown command #{command.inspect}\n\n#{USAGE}"
      end
      0
    rescue Error, OptionParser::ParseError, ArgumentError => e
      stderr.puts "cjk_index: #{e.message.sub(/\Acjk_index: /, '')}"
      2
    rescue SystemCallError, JSON::ParserError, IOError => e
      stderr.puts "cjk_index: #{e.message}"
      1
    end

    # ---- build -------------------------------------------------------------

    def build_command(argv, stdin, stdout)
      opts = { fields: nil, boosts: {}, filters: {}, variants: Normalizer::DEFAULT_TABLES }
      output = runtime = nil
      parser = OptionParser.new do |o|
        o.banner = "Usage: cjk_index build [FILE|-] [options]\n" \
                   "Records come from FILE or standard input: CSV, a JSON array, or JSON Lines."
        o.on("--format FORMAT", FORMATS, "csv, json or jsonl (default: from the file name, or sniffed on stdin)") { |v| opts[:format] = v }
        o.on("--ref COLUMN", "field that identifies a record (default: first field)") { |v| opts[:ref] = v }
        o.on("--fields LIST", Array, "fields to index (default: all but the ref)") { |v| opts[:fields] = v }
        o.on("--boost FIELD=N", "weight of a field, repeatable (default 1)") { |v| name, n = split_pair(v, "--boost"); opts[:boosts][name] = Float(n) }
        o.on("--filter FIELD[=KIND[:SEP]]", "filter on a field: KIND value (default) or year; SEP splits several values in one cell") do |v|
          name, spec = parse_filter(v)
          opts[:filters][name] = spec
        end
        o.on("--variants LIST", Array, "variant tables: ja (default), zh-safe, zh, ko, or table files") { |v| opts[:variants] = v }
        o.on("-o", "--output PATH", "index file (default: standard output)") { |v| output = v }
        o.on("--runtime PATH", "also write the browser script for these variants") { |v| runtime = v }
      end
      parser.parse!(argv)
      raise Error, "too many arguments: #{argv.drop(1).join(' ')}" if argv.length > 1

      source = argv.first
      source = nil if source == "-"
      format = opts.delete(:format) || format_of(source)
      builder = build_index(**opts, records: read_records(source, format, stdin))
      write_output(output, stdout, builder.to_json)
      write_output(runtime, nil, Runtime.source(normalizer: builder.normalizer)) if runtime
    end

    # Builds an index from records (an Array of Hashes with string keys).
    # Shared by the command and CJKIndex::RakeTask.
    def build_index(records:, ref: nil, fields: nil, boosts: {}, filters: {}, variants: Normalizer::DEFAULT_TABLES)
      raise Error, "no records" if records.empty?

      keys = records.first.keys.map(&:to_s)
      ref = (ref || keys.first).to_s
      raise Error, "no field #{ref.inspect} in the records (fields: #{keys.join(', ')})" unless keys.include?(ref)

      fields = Array(fields || (keys - [ref])).map(&:to_s)
      raise Error, "no fields to index" if fields.empty?

      missing = (fields + filters.keys.map(&:to_s) + boosts.keys.map(&:to_s)) - keys
      raise Error, "no such field in the records: #{missing.uniq.join(', ')} (fields: #{keys.join(', ')})" unless missing.empty?

      builder = Builder.new(fields: fields, boosts: boosts, filters: filters,
                            normalizer: Normalizer.new(tables: Array(variants).map(&:to_s)))
      records.each do |record|
        value = record[ref] || record[ref.to_sym]
        builder.add(value, record) unless value.to_s.empty?
      end
      builder
    end

    # ---- reading records ---------------------------------------------------

    def format_of(path)
      case File.extname(path.to_s).downcase
      when ".csv" then "csv"
      when ".json" then "json"
      when ".jsonl", ".ndjson" then "jsonl"
      end
    end

    def read_records(path, format, stdin = $stdin)
      text = path ? File.read(path, encoding: "UTF-8") : stdin.read.to_s.dup.force_encoding("UTF-8")
      text = text.delete_prefix("﻿")
      format ||= text.lstrip.start_with?("[") ? "json" : "jsonl"
      case format
      when "csv" then csv(text)
      when "json"
        data = JSON.parse(text)
        raise Error, "the JSON must be an array of objects" unless data.is_a?(Array) && data.all?(Hash)

        data
      else
        text.each_line.reject { |l| l.strip.empty? }.map.with_index(1) do |line, n|
          JSON.parse(line).tap { |r| raise Error, "line #{n} is not a JSON object" unless r.is_a?(Hash) }
        end
      end
    end

    # CSV is a bundled gem, not a default one, since Ruby 3.4: under Bundler
    # it can only be loaded when the Gemfile lists it. The gem does not depend
    # on it, so it is loaded here and a missing one is reported.
    def csv(text)
      begin
        require "csv"
      rescue LoadError
        raise Error, "reading CSV needs the csv gem (a bundled gem since Ruby 3.4); " \
                     "run `gem install csv`, add `gem \"csv\"` to your Gemfile, or give JSON / JSON Lines instead"
      end
      CSV.parse(text, headers: true).map(&:to_h)
    rescue CSV::MalformedCSVError => e
      raise Error, "invalid CSV: #{e.message}"
    end

    # ---- search ------------------------------------------------------------

    def search_command(argv, stdout)
      filter = {}
      limit = 10
      json = false
      parser = OptionParser.new do |o|
        o.banner = "Usage: cjk_index search INDEX.json QUERY [options]"
        o.on("--filter FIELD=VALUE", "keep matching records; repeat for several values or fields; a year filter takes 1900 or 1890..1910") do |v|
          name, value = split_pair(v, "--filter")
          (filter[name] ||= []) << value
        end
        o.on("--limit N", Integer, "results to show (default 10, 0 for all)") { |v| limit = v }
        o.on("--json", "print JSON: [{ref, score, fields}]") { json = true }
      end
      parser.parse!(argv)
      path, *words = argv
      raise Error, "usage: cjk_index search INDEX.json QUERY" if path.nil? || (words.empty? && filter.empty?)

      searcher = Searcher.load(path)
      filter = filter.transform_values { |values| values.map { |v| filter_value(v) } }
      filter = filter.transform_values { |values| values.length == 1 ? values.first : values }
      results = searcher.search(words.join(" "), filter: filter.empty? ? nil : filter)
      shown = limit.positive? ? results.first(limit) : results
      if json
        stdout.puts JSON.generate(shown)
      else
        shown.each { |r| stdout.puts format("%s\t%.3f\t%s", r[:ref], r[:score], r[:fields].join(",")) }
        stdout.puts "(#{results.length} result#{'s' unless results.length == 1})" if shown.length < results.length
      end
    rescue Errno::ENOENT
      raise Error, "no such file: #{path}"
    end

    # ---- runtime -----------------------------------------------------------

    def runtime_command(argv, stdout)
      variants = Normalizer::DEFAULT_TABLES
      output = nil
      OptionParser.new do |o|
        o.banner = "Usage: cjk_index runtime [options]"
        o.on("--variants LIST", Array, "variant tables: ja (default), zh-safe, zh, ko, or table files; must match the index") { |v| variants = v }
        o.on("-o", "--output PATH", "script file (default: standard output)") { |v| output = v }
      end.parse!(argv)
      raise Error, "too many arguments: #{argv.join(' ')}" unless argv.empty?

      write_output(output, stdout, Runtime.source(normalizer: Normalizer.new(tables: variants)))
    end

    # ---- helpers -----------------------------------------------------------

    def split_pair(text, option)
      name, value = text.split("=", 2)
      raise Error, "#{option} takes NAME=VALUE, got #{text.inspect}" if name.to_s.empty? || value.nil?

      [name, value]
    end

    # "type", "date=year", "subject=value:;"
    def parse_filter(text)
      name, spec = text.split("=", 2)
      kind, separator = (spec || "value").split(":", 2)
      raise Error, "--filter #{text.inspect}: kind must be value or year" unless Builder::FILTER_KINDS.include?(kind)

      [name, separator ? { "kind" => kind, "separator" => separator } : kind]
    end

    def filter_value(text)
      return text unless (m = text.match(/\A(\d*)\.\.(\d*)\z/)) && !(m[1].empty? && m[2].empty?)

      { "min" => (m[1].empty? ? nil : m[1].to_i), "max" => (m[2].empty? ? nil : m[2].to_i) }.compact
    end

    def write_output(path, stdout, content)
      if path
        File.write(path, content)
      else
        stdout.write(content)
        stdout.write("\n") unless content.end_with?("\n")
      end
    end
  end
end
