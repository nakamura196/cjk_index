# frozen_string_literal: true

require "jekyll"
require_relative "../cjk_index"

module CJKIndex
  # Jekyll plugin. Add `gem "cjk_index"` to the :jekyll_plugins group (or list
  # "cjk_index/jekyll" under `plugins:`), then configure in _config.yml:
  #
  #   cjk_index:
  #     output: assets/cjk-index          # where files are written (default)
  #     indexes:
  #       - name: posts                   # -> assets/cjk-index/posts.json
  #         collection: posts             # a Jekyll collection, or...
  #         fields: [title, tags, content]
  #         boosts: { title: 3 }
  #       - name: items
  #         data: metadata                # ...rows of _data/metadata.csv
  #         ref: objectid                 # column used as the result's ref
  #         fields: [title, creator, subject]
  #       - name: search
  #         preset: collectionbuilder     # reads CollectionBuilder's own config
  #
  # The browser script is written to <output>/cjk-index.js.
  module Jekyll
    DEFAULT_OUTPUT = "assets/cjk-index"
    RUNTIME_NAME = "cjk-index.js"

    # A file whose content is produced at build time (no source file, no Liquid).
    class GeneratedFile < ::Jekyll::StaticFile
      def initialize(site, dir, name, content)
        super(site, site.source, dir, name)
        @generated_content = content
      end

      def write(dest)
        path = destination(dest)
        return false if File.exist?(path) && File.read(path, encoding: "UTF-8") == @generated_content

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, @generated_content)
        true
      end
    end

    class Generator < ::Jekyll::Generator
      safe true
      priority :lowest

      def generate(site)
        config = site.config["cjk_index"]
        return unless config.is_a?(Hash)

        output = config.fetch("output", DEFAULT_OUTPUT).sub(%r{\A/+}, "").sub(%r{/+\z}, "")
        site.static_files << GeneratedFile.new(site, output, RUNTIME_NAME, Runtime.source)
        Array(config["indexes"]).each do |spec|
          builder = build(site, spec)
          name = "#{spec.fetch('name')}.json"
          site.static_files << GeneratedFile.new(site, output, name, builder.to_json)
          ::Jekyll.logger.info "cjk_index:", "#{output}/#{name} (#{builder.refs.length} documents)"
        end
      end

      private

      def build(site, spec)
        return Presets::CollectionBuilder.build(site, spec) if spec["preset"] == "collectionbuilder"
        raise ::Jekyll::Errors::FatalException, "cjk_index: unknown preset #{spec['preset']}" if spec["preset"]

        builder = Builder.new(fields: Array(spec.fetch("fields")), boosts: spec.fetch("boosts", {}))
        if spec["collection"]
          docs = site.collections.fetch(spec["collection"]) do
            raise ::Jekyll::Errors::FatalException, "cjk_index: no collection #{spec['collection']}"
          end.docs
          docs.each { |doc| builder.add(doc.url, document_fields(doc, builder.fields)) }
        elsif spec["data"]
          ref = spec.fetch("ref", "id")
          Array(site.data[spec["data"]]).each do |row|
            builder.add(row[ref], row) unless row[ref].to_s.empty?
          end
        else
          raise ::Jekyll::Errors::FatalException, "cjk_index: index #{spec['name']} needs collection or data"
        end
        builder
      end

      def document_fields(doc, fields)
        fields.to_h { |f| [f, f == "content" ? doc.content : doc.data[f]] }
      end
    end

    module Presets
      # Mirrors assets/js/lunr-store.js of CollectionBuilder (collectionbuilder-csv):
      # items with an objectid, child objects only when the theme asks for them,
      # fields marked index=true in _data/config-search.csv, and the same "id"
      # values, so results can be looked up in the existing search store.
      module CollectionBuilder
        module_function

        def build(site, spec)
          rows = Array(site.data[site.config["metadata"]])
          children = site.data.dig("theme", "search-child-objects") == true
          fields = Array(site.data["config-search"])
                   .select { |f| f["index"].to_s == "true" }
                   .map { |f| f["field"] }
          boosts = spec.fetch("boosts") { fields.first ? { fields.first => 3 } : {} }
          builder = Builder.new(fields: fields, boosts: boosts)
          rows.each do |row|
            next if row["objectid"].to_s.empty?
            next if !row["parentid"].to_s.empty? && !children

            builder.add(ref_for(row), row.to_h { |k, v| [k, v.is_a?(String) ? v.split.join(" ") : v] })
          end
          builder
        end

        def ref_for(row)
          parent = row["parentid"].to_s
          parent.empty? ? "#{row['objectid']}.html" : "#{parent}.html##{row['objectid']}"
        end
      end
    end
  end
end
