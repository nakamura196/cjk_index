# frozen_string_literal: true

require_relative "lib/cjk_index/version"

Gem::Specification.new do |spec|
  spec.name = "cjk_index"
  spec.version = CJKIndex::VERSION
  spec.authors = ["Satoru Nakamura"]
  spec.summary = "Dictionary-free full-text search for Chinese, Japanese and Korean in pure Ruby and the browser"
  spec.description = "Builds a bigram search index in Ruby (with kana, old/new kanji and NFKC " \
                     "normalization), and queries it in Ruby or with a small browser runtime " \
                     "that returns the same results. " \
                     "Includes a Jekyll plugin and a CollectionBuilder preset."
  spec.homepage = "https://github.com/nakamura196/cjk_index"
  spec.licenses = ["MIT", "Apache-2.0"] # Apache-2.0: the optional OpenCC-derived table (data/zh-hant-hans.tsv)
  spec.required_ruby_version = ">= 3.1"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "#{spec.homepage}#readme"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.{rb,js}", "data/*", "LICENSE", "LICENSE-OpenCC", "NOTICE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
