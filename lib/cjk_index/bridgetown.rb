# frozen_string_literal: true

require "fileutils"
require "bridgetown-core"
require_relative "../cjk_index"

module CJKIndex
  # Bridgetown plugin. Add `gem "cjk_index"` to the Gemfile, then in
  # config/initializers.rb:
  #
  #   Bridgetown.configure do |config|
  #     init :cjk_index,
  #          output: "cjk-index",               # folder inside the output (default)
  #          variants: ["ja"],                  # variant tables: ja (default), zh
  #          indexes: [
  #            { name: "posts",                 # -> output/cjk-index/posts.json
  #              collection: "posts",           # a collection (or a list of them), or...
  #              fields: ["title", "tags", "content"],
  #              boosts: { title: 3 },
  #              filters: { category: "value", date: "year" } },
  #            { name: "items", data: "metadata", ref: "id", fields: ["title"] } # ...rows of src/_data/metadata.csv
  #          ]
  #   end
  #
  # After each build the index files and the browser script (cjk-index.js)
  # are written to the output folder. A resource is indexed by its URL; the
  # field "content" is the source text of the resource (Markdown, before
  # rendering), any other field is read from its front matter.
  module Bridgetown
    DEFAULT_OUTPUT = "cjk-index"
    RUNTIME_NAME = "cjk-index.js"

    module_function

    # Writes the browser script and every index of the config (a Hash with
    # symbol or string keys) into site's destination folder.
    def write(site, config)
      config = stringify(config)
      output = config.fetch("output", DEFAULT_OUTPUT).to_s.gsub(%r{\A/+|/+\z}, "")
      normalizer = Normalizer.new(tables: Array(config.fetch("variants", Normalizer::DEFAULT_TABLES)))
      put(site, output, RUNTIME_NAME, Runtime.source(normalizer: normalizer))
      Array(config["indexes"]).each do |spec|
        builder = build(site, stringify(spec), normalizer)
        put(site, output, "#{spec['name'] || spec[:name]}.json", builder.to_json)
        ::Bridgetown.logger.info "cjk_index:", "#{output}/#{spec['name'] || spec[:name]}.json (#{builder.size} documents)"
      end
    end

    def build(site, spec, normalizer)
      builder = Builder.new(fields: Array(spec.fetch("fields")), boosts: spec.fetch("boosts", {}),
                            normalizer: normalizer, filters: spec.fetch("filters", {}))
      if spec["collection"]
        Array(spec["collection"]).each do |name|
          collection = site.collections[name] or raise ArgumentError, "cjk_index: no collection #{name}"
          collection.resources.each do |resource|
            next unless resource.write?

            builder.add(resource.relative_url, resource_fields(resource, builder.fields | builder.filters.keys))
          end
        end
      elsif spec["data"]
        ref = spec.fetch("ref", "id")
        Array(site.data[spec["data"]]).each do |row|
          row = row.to_h.transform_keys(&:to_s)
          builder.add(row[ref], row) unless row[ref].to_s.empty?
        end
      else
        raise ArgumentError, "cjk_index: index #{spec['name']} needs collection or data"
      end
      builder
    end

    def resource_fields(resource, fields)
      fields.to_h { |f| [f, f == "content" ? resource.untransformed_content : plain(resource.data[f])] }
    end

    # A Time or Date as "2026-10-01": Builder applies Array() to values, which
    # would turn a Time into its parts [sec, min, hour, ...].
    def plain(value)
      value.respond_to?(:strftime) ? value.strftime("%Y-%m-%d") : value
    end

    def stringify(hash) = hash.to_h { |k, v| [k.to_s, v] }

    # Skips the write when the file already has this content.
    def put(site, dir, name, content)
      path = site.in_dest_dir(dir, name)
      return if File.exist?(path) && File.read(path, encoding: "UTF-8") == content

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end
end

Bridgetown.initializer :cjk_index do |_config, **options|
  Bridgetown::Hooks.register_one :site, :post_write, reloadable: false do |site|
    CJKIndex::Bridgetown.write(site, options)
  end
end
