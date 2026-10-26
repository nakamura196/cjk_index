# frozen_string_literal: true

# A separate process that writes to an IndexFile, started by
# test_index_file.rb with Process.spawn (fork is not available on Windows).
#
#   ruby -I lib index_file_writer.rb add <path> <prefix> <count>
#     adds <count> documents "<prefix>-0", "<prefix>-1", ..., one update each
#   ruby -I lib index_file_writer.rb loop <path>
#     updates document "d0" until it is killed

require "cjk_index"

mode, path, *args = ARGV
file = CJKIndex::IndexFile.new(path)

case mode
when "add"
  prefix, count = args
  Integer(count).times { |i| file.update { |b| b.add("#{prefix}-#{i}", "title" => "資料 #{prefix} #{i}") } }
when "loop"
  loop { file.update { |b| b.update("d0", "title" => "改訂 #{rand}") } }
else
  abort "unknown mode: #{mode}"
end
