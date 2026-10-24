# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# An index file shared by several readers and writers: no update is lost, and
# no reader sees a partly written file.
class TestIndexFile < Minitest::Test
  FIELDS = %w[title].freeze

  def setup
    @dir = Dir.mktmpdir("cjk_index")
    @path = File.join(@dir, "index.json")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def builder(docs = {})
    b = CJKIndex::Builder.new(fields: FIELDS, filters: { "type" => "value" })
    docs.each { |ref, doc| b.add(ref, doc) }
    b
  end

  def refs_in_file = JSON.parse(File.read(@path))["refs"]

  def test_searcher_sees_updates_from_another_instance
    CJKIndex::IndexFile.new(@path).write(builder("a" => { "title" => "東京帝國大學" }))
    reader = CJKIndex::IndexFile.new(@path)
    writer = CJKIndex::IndexFile.new(@path)

    assert_equal ["a"], reader.searcher.search("帝国").map { |r| r[:ref] }
    writer.update { |b| b.add("b", "title" => "帝国大学 農学部") }

    assert_equal %w[a b], reader.searcher.search("帝国").map { |r| r[:ref] }.sort
  end

  def test_the_writer_sees_its_own_update
    file = CJKIndex::IndexFile.new(@path, interval: 3600)
    file.write(builder("a" => { "title" => "國牛十圖" }))

    assert_empty file.searcher.search("鳥瞰")
    file.update { |b| b.add("b", "title" => "鳥瞰圖") }

    assert_equal ["b"], file.searcher.search("鳥瞰").map { |r| r[:ref] }
  end

  def test_interval_keeps_the_snapshot
    CJKIndex::IndexFile.new(@path).write(builder("a" => { "title" => "國牛十圖" }))
    reader = CJKIndex::IndexFile.new(@path, interval: 3600)
    snapshot = reader.searcher
    CJKIndex::IndexFile.new(@path).update { |b| b.add("b", "title" => "鳥瞰圖") }

    assert_same snapshot, reader.searcher
  end

  def test_unchanged_file_is_not_loaded_again
    CJKIndex::IndexFile.new(@path).write(builder("a" => { "title" => "國牛十圖" }))
    reader = CJKIndex::IndexFile.new(@path)

    assert_same reader.searcher, reader.searcher
  end

  def test_updated_file_equals_a_rebuild
    file = CJKIndex::IndexFile.new(@path)
    file.write(builder("a" => { "title" => "國牛十圖", "type" => "図譜" }, "b" => { "title" => "鳥瞰圖" }))
    file.update { |b| b.update("a", "title" => "群芳圖譜", "type" => "写真") }
    CJKIndex::IndexFile.new(@path).update { |b| b.remove("b") }
    file.update { |b| b.add("c", "title" => "農学部 正門", "type" => "写真") }

    expected = builder("a" => { "title" => "群芳圖譜", "type" => "写真" }, "c" => { "title" => "農学部 正門", "type" => "写真" })

    assert_equal expected.to_h, JSON.parse(File.read(@path))
  end

  def test_failed_block_writes_nothing
    file = CJKIndex::IndexFile.new(@path)
    file.write(builder("a" => { "title" => "國牛十圖" }))
    before = File.read(@path)

    assert_raises(RuntimeError) do
      file.update do |b|
        b.add("b", "title" => "鳥瞰圖")
        raise "stop"
      end
    end

    assert_equal before, File.read(@path)
    file.update { |b| b.add("c", "title" => "正門") }

    assert_equal %w[a c], refs_in_file
  end

  def test_no_temporary_files_are_left
    file = CJKIndex::IndexFile.new(@path)
    file.write(builder("a" => { "title" => "國牛十圖" }))
    file.update { |b| b.add("b", "title" => "鳥瞰圖") }

    assert_equal %w[index.json index.json.lock], Dir.children(@dir).sort
  end

  def test_threads_update_without_losing_any
    CJKIndex::IndexFile.new(@path).write(builder)
    threads = 4.times.map do |t|
      Thread.new do
        file = CJKIndex::IndexFile.new(@path)
        5.times { |i| file.update { |b| b.add("t#{t}-#{i}", "title" => "資料 #{t} #{i}") } }
      end
    end
    threads.each(&:join)

    assert_equal 20, refs_in_file.uniq.length
  end

  def test_processes_update_without_losing_any
    skip "needs fork" unless Process.respond_to?(:fork)

    CJKIndex::IndexFile.new(@path).write(builder)
    pids = 4.times.map do |p|
      fork do
        file = CJKIndex::IndexFile.new(@path)
        5.times { |i| file.update { |b| b.add("p#{p}-#{i}", "title" => "資料 #{p} #{i}") } }
        exit!(0)
      end
    end
    statuses = pids.map { |pid| Process.wait2(pid).last }

    assert(statuses.all?(&:success?))
    assert_equal 20, refs_in_file.uniq.length
  end

  def test_readers_never_see_a_partial_file
    docs = 300.times.to_h { |i| ["d#{i}", { "title" => "東京帝國大學 資料 #{i}" * 3 }] }
    CJKIndex::IndexFile.new(@path).write(builder(docs))
    errors = []
    stop = false
    readers = 3.times.map do
      Thread.new do
        file = CJKIndex::IndexFile.new(@path)
        until stop
          begin
            hits = file.searcher.search("帝国").length
            errors << hits unless hits.between?(300, 310)
          rescue StandardError => e
            errors << e
          end
        end
      end
    end
    writer = CJKIndex::IndexFile.new(@path)
    10.times { |i| writer.update { |b| b.add("n#{i}", "title" => "帝国大学 #{i}") } }
    stop = true
    readers.each(&:join)

    assert_empty errors
    assert_equal 310, writer.searcher.search("帝国").length
  ensure
    stop = true
    readers&.each(&:join)
  end

  def test_a_writer_that_hangs_times_out_the_others
    CJKIndex::IndexFile.new(@path).write(builder("a" => { "title" => "國牛十圖" }))
    inside = Queue.new
    release = Queue.new
    holder = Thread.new { CJKIndex::IndexFile.new(@path).update { |_b| inside << true; release.pop } }
    inside.pop

    assert_raises(CJKIndex::IndexFile::LockTimeout) do
      CJKIndex::IndexFile.new(@path, lock_timeout: 0.2).update { |b| b.add("b", "title" => "鳥瞰圖") }
    end
  ensure
    release << true
    holder&.join
  end

  def test_a_killed_writer_leaves_the_index_intact
    skip "needs fork" unless Process.respond_to?(:fork)

    docs = 2000.times.to_h { |i| ["d#{i}", { "title" => "東京帝國大學 資料 #{i} " * 5 }] }
    CJKIndex::IndexFile.new(@path).write(builder(docs))
    pid = fork do
      file = CJKIndex::IndexFile.new(@path)
      loop { file.update { |b| b.update("d0", "title" => "改訂 #{rand}") } }
    end
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    sleep 0.001 until Dir.children(@dir).any? { |n| n.end_with?(".tmp") } ||
                      Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    Process.kill(:KILL, pid)
    Process.wait(pid)

    skip "the writer was not killed while writing; run again" unless Dir.children(@dir).any? { |n| n.end_with?(".tmp") }

    after = JSON.parse(File.read(@path)) # the old index or a later one, never a partial file

    assert_equal 2000, after["refs"].length
    CJKIndex::IndexFile.new(@path, lock_timeout: 1).update { |b| b.add("x", "title" => "正門") }

    assert_equal %w[index.json index.json.lock], Dir.children(@dir).sort
    assert_includes refs_in_file, "x"
  end
end
