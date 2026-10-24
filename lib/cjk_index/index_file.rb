# frozen_string_literal: true

module CJKIndex
  # An index file shared by several processes, such as the workers of a Rails
  # app: any number of readers, and one writer at a time.
  #
  #   INDEX = CJKIndex::IndexFile.new("db/search-index.json")
  #   INDEX.write(builder)                                  # a full build
  #   INDEX.update { |builder| builder.update(ref, doc) }   # from any process
  #   INDEX.searcher.search("東京")                         # sees the last update
  #
  # update takes an exclusive lock on "<path>.lock", reads the index, runs the
  # block and writes the result, so updates from different processes are
  # applied one after another and none is lost. The lock is released when the
  # process ends, also when it crashes. An index is written to a temporary
  # file and renamed over the old one, so a reader gets the old index or the
  # new one, never a partly written file.
  #
  # Each reader keeps the index it loaded (a snapshot) and loads the file
  # again when it has changed: checked on each call to searcher, or once every
  # interval seconds. While one thread reloads, the others go on with the old
  # snapshot. The process that wrote an update sees it on its next call.
  #
  # The file is never changed in place. A writer killed at any point leaves
  # the previous index intact, the OS releases its lock, and its temporary
  # file is removed by the next writer; there is nothing to recover.
  #
  # Locks use flock, which is reliable on a local disk; do not share the file
  # over NFS.
  class IndexFile
    # Raised by update and write when another writer holds the lock too long.
    class LockTimeout < StandardError; end

    attr_reader :path

    # lock_timeout: seconds update and write wait for another writer.
    # options are passed to Searcher (prefix:, typos:).
    def initialize(path, interval: 0, lock_timeout: 60, **options)
      @path = path.to_s
      @lock_path = "#{@path}.lock"
      @interval = interval
      @lock_timeout = lock_timeout
      @options = options
      @read_mutex = Mutex.new
      @write_mutex = Mutex.new
      @searcher = nil
      @searcher_stamp = nil
      @checked_at = nil
      @builder = nil
      @builder_stamp = nil
    end

    # A Searcher for the current file, loaded again if the file has changed.
    def searcher
      return @searcher if @searcher && !due?

      if @searcher
        # Another thread is checking or loading: use the snapshot we have.
        return @searcher unless @read_mutex.try_lock

        begin
          reload
        ensure
          @read_mutex.unlock
        end
      else
        @read_mutex.synchronize { reload }
      end
      @searcher
    end

    # Applies the block to a Builder holding the index in the file, and writes
    # the result. The file must exist (see write). If the block raises,
    # nothing is written.
    def update
      @write_mutex.synchronize do
        lock do
          File.open(@path, "r:UTF-8") do |f|
            stamp = stamp(f.stat)
            @builder = Builder.load(f.read) unless @builder && stamp == @builder_stamp
          end
          done = false
          begin
            yield @builder
            done = true
          ensure
            @builder = nil unless done # half-applied changes; read the file again next time
          end
          @builder_stamp = replace(@builder.to_json)
        end
      end
      @checked_at = nil
      self
    end

    # Replaces the index in the file with builder's (e.g. after a full build).
    def write(builder)
      @write_mutex.synchronize do
        lock do
          replace(builder.to_json)
          @builder = nil
        end
      end
      @checked_at = nil
      self
    end

    private

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def due? = @checked_at.nil? || now - @checked_at >= @interval

    # What identifies one written version of the file. rename gives the new
    # file a new inode; mtime and size cover systems without inodes.
    def stamp(stat) = [stat.ino, stat.dev, stat.size, stat.mtime.to_r]

    def reload
      return unless due?

      @checked_at = now
      File.open(@path, "r:UTF-8") do |f|
        stamp = stamp(f.stat)
        next if @searcher && stamp == @searcher_stamp

        @searcher = Searcher.new(f.read, **@options)
        @searcher_stamp = stamp
      end
    end

    # Waits for the lock for at most lock_timeout seconds, so that a writer
    # that hangs while holding it cannot block the others for ever.
    def lock
      File.open(@lock_path, File::RDWR | File::CREAT, 0o644) do |f|
        deadline = now + @lock_timeout
        until f.flock(File::LOCK_EX | File::LOCK_NB)
          raise LockTimeout, "cjk_index: #{@lock_path} still locked after #{@lock_timeout} s" if now >= deadline

          sleep 0.01
        end
        remove_stale_files
        yield
      end
    end

    # Temporary files are made only while the lock is held, so any found now
    # were left by a writer that was killed.
    def remove_stale_files
      dir = File.dirname(@path)
      prefix = "#{File.basename(@path)}."
      Dir.each_child(dir) do |name|
        File.delete(File.join(dir, name)) if name.start_with?(prefix) && name.end_with?(".tmp")
      end
    end

    # Writes json next to the file and renames it over the file. Returns the
    # stamp of the new file.
    def replace(json)
      tmp = "#{@path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.open(tmp, "w:UTF-8") do |f|
        f.write(json)
        f.flush
        f.fsync
      end
      rename(tmp, @path)
      sync_dir
      stamp(File.stat(@path))
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end

    # The rename itself survives a power loss only once the directory is
    # synced too (Linux ext4, xfs). Windows cannot open a directory; skip it.
    def sync_dir
      File.open(File.dirname(@path), &:fsync)
    rescue SystemCallError, IOError
      nil
    end

    # On Windows, renaming over a file fails while a reader has it open;
    # readers hold it only for a moment, so try again.
    def rename(from, to)
      tries = 0
      begin
        File.rename(from, to)
      rescue Errno::EACCES, Errno::EPERM
        raise if (tries += 1) > 50

        sleep 0.01
        retry
      end
    end
  end
end
