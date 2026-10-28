# frozen_string_literal: true

require "rake"
require "rake/tasklib"
require "fileutils"
require_relative "cli"

module CJKIndex
  # A Rake task that builds an index (and the browser script) from a CSV,
  # JSON or JSON Lines file, usable from any Ruby build (Rails, Sinatra, a
  # plain Rakefile). It does what `cjk_index build` does.
  #
  #   require "cjk_index/rake_task"
  #
  #   CJKIndex::RakeTask.new(:search_index) do |t|
  #     t.source  = "data/items.csv"
  #     t.output  = "public/search/items.json"
  #     t.runtime = "public/search/cjk-index.js"   # optional
  #     t.ref     = "id"
  #     t.fields  = %w[title creator]
  #     t.boosts  = { "title" => 3 }
  #     t.filters = { "type" => "value", "date" => "year" }
  #   end
  #
  #   rake search_index
  #
  # records can be set instead of source: an Array of Hashes, or an object
  # that responds to call and returns one (e.g. a lambda reading the database).
  class RakeTask < Rake::TaskLib
    attr_accessor :name, :source, :records, :output, :runtime, :ref, :fields, :boosts, :filters, :variants, :format,
                  :description

    def initialize(name = :cjk_index)
      super()
      @name = name
      @boosts = {}
      @filters = {}
      @variants = Normalizer::DEFAULT_TABLES
      @description = "Build the CJK search index"
      yield self if block_given?
      define
    end

    # Builds the index now; the task calls this.
    def build
      raise CLI::Error, "#{name}: set output" unless output

      data = records.respond_to?(:call) ? records.call : records
      data ||= source ? CLI.read_records(source.to_s, format || CLI.format_of(source)) : raise(CLI::Error, "#{name}: set source or records")
      builder = CLI.build_index(records: data, ref: ref, fields: fields, boosts: boosts, filters: filters, variants: variants)
      write(output, builder.to_json)
      write(runtime, Runtime.source(normalizer: builder.normalizer)) if runtime
      builder
    end

    private

    def define
      desc description
      task(name) do
        builder = build
        puts "#{output}: #{builder.size} records"
      end
    end

    def write(path, content)
      FileUtils.mkdir_p(File.dirname(path.to_s))
      File.write(path.to_s, content)
    end
  end
end
