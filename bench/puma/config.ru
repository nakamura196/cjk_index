# frozen_string_literal: true

# A Rack app for bench/puma/run.rb: each Puma worker searches and updates
# one index file through CJKIndex::IndexFile.
#
#   GET  /search?q=...  {"pid", "searcher" (object_id of the snapshot), "refs"}
#   POST /add?ref=...   adds a record whose title contains the word 追加資料
#
# Any exception, such as JSON::ParserError from a partly written file, is
# answered with status 500 and its class, so the client can count it.

require "cjk_index"
require "json"

# To check that run.rb catches faults, CJK_INDEX_FAULT breaks IndexFile on purpose:
# "no-lock" lets writers run at the same time, "in-place" writes over the file
# instead of renaming a new one over it.
case ENV["CJK_INDEX_FAULT"]
when "no-lock" then CJKIndex::IndexFile.prepend(Module.new { private def lock = yield })
when "in-place"
  CJKIndex::IndexFile.prepend(Module.new do
    private def replace(json)
      File.write(@path, json)
      stamp
    end
  end)
end

INDEX = CJKIndex::IndexFile.new(ENV.fetch("CJK_INDEX_FILE"))
INDEX.searcher if ENV["PRELOAD_SEARCHER"] # with puma --preload, the workers start from this snapshot

reply = ->(status, body) { [status, { "content-type" => "application/json" }, [JSON.generate(body)]] }

run(lambda do |env|
  req = Rack::Request.new(env)
  case [req.request_method, req.path_info]
  in ["GET", "/search"]
    searcher = INDEX.searcher
    reply.(200, { pid: Process.pid, searcher: searcher.object_id,
                  refs: searcher.search(req.params.fetch("q")).map { |r| r[:ref] } })
  in ["POST", "/add"]
    ref = req.params.fetch("ref")
    INDEX.update { |b| b.add(ref, { "title" => "追加資料 #{ref}", "author" => "試験", "text" => "" }) }
    reply.(200, { pid: Process.pid })
  else
    reply.(404, {})
  end
rescue StandardError => e
  reply.(500, { pid: Process.pid, error: e.class.name, message: e.message[0, 200] })
end)
