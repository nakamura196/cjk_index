# frozen_string_literal: true

# Build time, peak memory and output size of the Builder.
#
# Usage (from the repository root):
#   ruby -Ilib bench/build.rb <source> <output>
#
# source: see corpus.rb, e.g. aozora:fulltext:bench/retrieval/cache/aozora.jsonl.gz:3000
#         or markdown:/path/to/blog/content/ja/posts
# output: json   builder.to_json written with File.write (also works with
#                earlier versions, to measure them the same way)
#         write  builder.write(path), one file written as it is generated
#         split  builder.write_split(dir), a manifest and shards
#
# The build runs in a child process under /usr/bin/time, whose "maximum
# resident set size" is the peak memory (texts of the source included; the
# memory after reading them is printed as well). Prints one Markdown row:
# | source | output | documents | characters | memory after reading | build | write | peak memory | files | size | gzipped |

require "json"
require "zlib"
require "tmpdir"
require "open3"
require "rbconfig"
require_relative "corpus"

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def rss_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0

if ARGV.first == "--child"
  _, spec, output, dest = ARGV
  require "cjk_index"
  source = Corpus.load(spec)
  docs = source.docs
  GC.start
  after_read = rss_mb
  t = now
  builder = CJKIndex::Builder.new(fields: source.fields, boosts: source.boosts)
  docs.each { |ref, d| builder.add(ref, d) }
  build = now - t
  t = now
  case output
  when "json" then File.write(File.join(dest, "index.json"), builder.to_json)
  when "write" then builder.write(File.join(dest, "index.json"))
  when "split" then builder.write_split(File.join(dest, "index"))
  else abort "output must be json, write or split"
  end
  write = now - t
  puts JSON.generate("name" => source.name, "documents" => docs.size, "characters" => Corpus.chars(docs), "after_read" => after_read,
                     "build" => build, "write" => write)
  exit
end

spec, output = ARGV
abort "usage: build.rb <source> json|write|split" unless spec && output
require "cjk_index"
lib = File.expand_path("../..", CJKIndex::Builder.instance_method(:add).source_location.first)

Dir.mktmpdir do |dest|
  time = RUBY_PLATFORM.include?("darwin") ? ["/usr/bin/time", "-l"] : ["/usr/bin/time", "-v"]
  out, err, status = Open3.capture3(*time, RbConfig.ruby, "-I", lib, __FILE__, "--child", spec, output, dest)
  abort err unless status.success?
  r = JSON.parse(out.lines.last)
  peak = if (m = err.match(/(\d+)\s+maximum resident set size/)) then m[1].to_i / 1e6 # bytes (macOS)
         elsif (m = err.match(/Maximum resident set size \(kbytes\): (\d+)/)) then m[1].to_i / 1e3
         end
  files = Dir.glob(File.join(dest, "**", "*")).select { |f| File.file?(f) }
  size = files.sum { |f| File.size(f) }
  gz = files.sum { |f| Zlib.gzip(File.binread(f), level: 9).bytesize }
  puts format("| %s | %s | %d | %.1f M | %.0f MB | %.1f s | %.1f s | %.0f MB | %d | %.1f MB | %.1f MB |",
              r["name"], output,
              r["documents"], r["characters"] / 1e6, r["after_read"], r["build"], r["write"], peak, files.size,
              size / 1e6, gz / 1e6)
end
