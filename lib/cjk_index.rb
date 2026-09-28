# frozen_string_literal: true

require_relative "cjk_index/version"
require_relative "cjk_index/normalizer"
require_relative "cjk_index/tokenizer"
require_relative "cjk_index/builder"
require_relative "cjk_index/runtime"
require_relative "cjk_index/searcher"

# Dictionary-free full-text search for Chinese, Japanese and Korean text:
# build the index in Ruby, query it in Ruby (Searcher) or in the browser
# (Runtime), with the same results.
module CJKIndex
  def self.normalize(text, normalizer: Normalizer.default) = normalizer.normalize(text)

  def self.tokenize(text, unigrams: false, normalizer: Normalizer.default)
    Tokenizer.tokenize(text, unigrams: unigrams, normalizer: normalizer)
  end
end
