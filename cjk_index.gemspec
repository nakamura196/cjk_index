# frozen_string_literal: true

require_relative "lib/cjk_index/version"

Gem::Specification.new do |spec|
  spec.name = "cjk_index"
  spec.version = CJKIndex::VERSION
  spec.authors = ["Satoru Nakamura"]
  spec.summary = "Dictionary-free full-text search for Chinese, Japanese and Korean on static sites"
  spec.description = "Builds a bigram search index in Ruby (with kana, old/new kanji and NFKC " \
                     "normalization) and ships a small browser runtime to query it. " \
                     "Includes a Jekyll plugin and a CollectionBuilder preset."
  spec.homepage = "https://github.com/nakamura196/cjk_index"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.{rb,js}", "data/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
end
