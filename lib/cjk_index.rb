# frozen_string_literal: true

require_relative "cjk_index/version"
require_relative "cjk_index/normalizer"
require_relative "cjk_index/tokenizer"
require_relative "cjk_index/builder"
require_relative "cjk_index/runtime"

# Dictionary-free full-text search for Chinese, Japanese and Korean text on
# static sites: build the index in Ruby, query it in the browser.
module CJKIndex
  def self.normalize(text) = Normalizer.normalize(text)

  def self.tokenize(text, unigrams: false) = Tokenizer.tokenize(text, unigrams: unigrams)
end
