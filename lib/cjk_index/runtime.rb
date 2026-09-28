# frozen_string_literal: true

require "json"

module CJKIndex
  # Writes the browser script. The normalization table and character classes
  # come from Normalizer and Tokenizer, so Ruby (indexing) and JavaScript
  # (querying) cannot drift apart.
  module Runtime
    TEMPLATE_PATH = File.expand_path("runtime.js", __dir__)

    module_function

    def source
      File.read(TEMPLATE_PATH, encoding: "UTF-8")
          # Block form: a replacement string would treat its backslashes as
          # back-references and drop half of the regexp escapes.
          .sub("/*@VARIANTS@*/{}") { JSON.generate(Normalizer.variants) }
          .sub("/*@CJK@*/''") { JSON.generate(Tokenizer.char_class(Tokenizer::CJK_RANGES)) }
          .sub("/*@SEPARATOR@*/''") do
            JSON.generate(Tokenizer.char_class(Tokenizer::SEPARATOR_RANGES, Tokenizer::SEPARATOR_CHARS))
          end
    end
  end
end
