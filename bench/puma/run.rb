# frozen_string_literal: true

# Several Puma workers sharing one index file (CJKIndex::IndexFile): adds
# records through some workers while searching through all of them, then
# checks three things.
#
# - lost:   every added record is in the file and found by every worker
# - stale:  how often, and how long after an add returned, a search did not
#           find that record. Not a failure: while one thread of a worker
#           loads the changed file, the others answer from the previous
#           snapshot, so this lasts at most about one load of the file.
# - broken: no request failed (a partly written file would raise
#           JSON::ParserError in the worker and come back as status 500)
#
# Usage (from bench/puma, with the Aozora records of bench/aozora.rb):
#   bundle install
#   bundle exec ruby run.rb aozora.jsonl.gz [records] [adds] [options]
#
# Options: --workers 4 --threads 4 --writers 4 --readers 8 --preload --fault NAME
#   --preload: Puma loads the app (and a searcher) before forking, as Rails
#   apps usually do in production.
#   --fault no-lock|in-place: break IndexFile on purpose (see config.ru), to
#   check that the checks fail.

require "cjk_index"
require "json"
require "net/http"
require "socket"
require "tmpdir"
require "zlib"

opts = { workers: 4, threads: 4, writers: 4, readers: 8, preload: false, fault: nil }
args = []
until ARGV.empty?
  a = ARGV.shift
  case a
  when "--preload" then opts[:preload] = true
  when "--fault" then opts[:fault] = ARGV.shift
  when /\A--(workers|threads|writers|readers)\z/ then opts[Regexp.last_match(1).to_sym] = Integer(ARGV.shift)
  else args << a
  end
end
path, count, adds = args
count = Integer(count || 1000)
adds = Integer(adds || 100)
QUERY = "追加資料"

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

docs = []
Zlib::GzipReader.open(path) do |gz|
  gz.each_line do |line|
    break if docs.size >= count

    d = JSON.parse(line)
    m = d["meta"]
    docs << [m["作品ID"], { "title" => m["作品名"], "author" => "#{m['姓']}#{m['名']}", "text" => d["text"][0, 200] }]
  end
end

builder = CJKIndex::Builder.new(fields: %w[title author text], boosts: { "title" => 3, "author" => 2 })
docs.each { |ref, d| builder.add(ref, d) }
added = ->(refs) { refs.grep(/\Aadd-/) }

Dir.mktmpdir do |dir|
  file = File.join(dir, "index.json")
  CJKIndex::IndexFile.new(file).write(builder)
  port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
  log = File.join(dir, "puma.log")
  cmd = ["puma", "-w", opts[:workers].to_s, "-t", "#{opts[:threads]}:#{opts[:threads]}", "-b", "tcp://127.0.0.1:#{port}"]
  cmd << "--preload" if opts[:preload]
  env = { "CJK_INDEX_FILE" => file }
  env["PRELOAD_SEARCHER"] = "1" if opts[:preload]
  env["CJK_INDEX_FAULT"] = opts[:fault] if opts[:fault]
  puma = Process.spawn(env, *cmd, "config.ru", chdir: __dir__, out: log, err: log)

  request = lambda do |method, target|
    Net::HTTP.start("127.0.0.1", port) do |http|
      req = method == :post ? Net::HTTP::Post.new(target) : Net::HTTP::Get.new(target)
      req["Connection"] = "close" # a new connection each time, so the OS hands it to any worker
      res = http.request(req)
      [res.code.to_i, JSON.parse(res.body)]
    end
  end
  search = -> { request.(:get, "/search?q=#{URI.encode_www_form_component(QUERY)}") }

  begin
    deadline = now + 60
    pids = {}
    until pids.size == opts[:workers]
      raise "puma did not start:\n#{File.read(log)}" if now > deadline || Process.wait(puma, Process::WNOHANG)

      begin
        pids[search.()[1]["pid"]] = true
      rescue SystemCallError, EOFError
        sleep 0.2
      end
    end

    puts "records: #{count}, file: #{format('%.1f', File.size(file) / 1e6)} MB, adds: #{adds}, " \
         "puma -w #{opts[:workers]} -t #{opts[:threads]}#{' --preload' if opts[:preload]}, " \
         "#{"fault: #{opts[:fault]}, " if opts[:fault]}" \
         "client threads: #{opts[:writers]} writing, #{opts[:readers]} searching"

    done = {}        # ref => time its add returned
    mutex = Mutex.new
    queue = Queue.new
    adds.times { |i| queue << "add-#{i}" }
    opts[:writers].times { queue << nil }
    failures = []
    searches = []    # [start, finish, pid, snapshot, refs]
    write_pids = Hash.new(0)
    started = now

    writers = Array.new(opts[:writers]) do
      Thread.new do
        while (ref = queue.pop)
          code, body = request.(:post, "/add?ref=#{ref}")
          mutex.synchronize do
            if code == 200
              done[ref] = now
              write_pids[body["pid"]] += 1
            else
              failures << [:add, ref, code, body]
            end
          end
        end
      end
    end
    readers = Array.new(opts[:readers]) do
      Thread.new do
        while writers.any?(&:alive?)
          t = now
          code, body = search.()
          mutex.synchronize do
            if code == 200
              searches << [t, now, body["pid"], body["searcher"], added.(body["refs"])]
            else
              failures << [:search, nil, code, body]
            end
          end
        end
      end
    end
    (writers + readers).each(&:join)
    elapsed = now - started

    # stale: the record had been added (its request returned) before the search started
    misses = searches.flat_map { |t, _, _, _, refs| (done.select { |_, d| d < t }.keys - refs).map { |r| t - done[r] } }
    stale = misses.size
    read_pids = searches.group_by { |s| s[2] }
    snapshots = read_pids.transform_values { |ss| ss.map { |s| s[3] }.uniq.size }

    # lost: ask until every worker has answered once more
    final = {}
    deadline = now + 30
    until final.size == opts[:workers] || now > deadline
      code, body = search.()
      final[body["pid"]] = added.(body["refs"]).size if code == 200
    end
    in_file = added.(CJKIndex::Searcher.new(File.read(file, encoding: "UTF-8")).refs).size

    puts format("elapsed: %.1f s, adds: %d (%.2f s each on average), searches: %d", elapsed, done.size,
                elapsed / [done.size, 1].max, searches.size)
    puts "adds per worker: #{write_pids.values.sort.reverse.join(', ')}"
    puts "searches per worker: #{read_pids.values.map(&:size).sort.reverse.join(', ')}; " \
         "snapshots loaded per worker: #{snapshots.values.sort.reverse.join(', ')}"
    puts "lost: #{adds - in_file} (in the file: #{in_file} of #{adds}; each worker finds: #{final.values.join(', ')})"
    puts "stale: #{stale} (records missing from a search that started after their add returned)" \
         "#{format(", at most %.0f ms after the add returned", misses.max * 1000) unless misses.empty?}"
    puts "broken: #{failures.size}#{" #{failures.map { |f| f[3]['error'] }.tally}" unless failures.empty?}"
    exit(adds - in_file + failures.size + final.values.count { |n| n != adds }).zero?
  ensure
    Process.kill(:TERM, puma)
    Process.wait(puma)
  end
end
