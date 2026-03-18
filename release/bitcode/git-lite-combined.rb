# mruby compatibility shims
# Replaces CRuby stdlib features not available in mruby

# SecureRandom replacement using mruby's built-in Random
module SecureRandom
  ALPHANUMERIC = ('a'..'z').to_a + ('0'..'9').to_a

  def self.alphanumeric(n = 16)
    n.times.map { ALPHANUMERIC[rand(ALPHANUMERIC.length)] }.join
  end

  def self.hex(n = 16)
    n.times.map { '%02x' % rand(256) }.join
  end
end

# FileUtils replacement using mruby-dir and mruby-io
module FileUtils
  def self.mkdir_p(path)
    return if File.directory?(path)
    parts = path.split('/')
    current = parts[0] == '' ? '/' : ''
    parts.each do |part|
      next if part.empty?
      current = current.empty? ? part : "#{current}/#{part}"
      Dir.mkdir(current) unless File.directory?(current)
    end
  end

  def self.rm_rf(path)
    return unless File.exist?(path) || File.directory?(path)
    if File.directory?(path)
      Dir.entries(path).each do |entry|
        next if entry == '.' || entry == '..'
        rm_rf(File.join(path, entry))
      end
      Dir.delete(path)
    else
      File.delete(path)
    end
  end

  def self.cp(src, dst)
    data = File.open(src, 'rb') { |f| f.read }
    File.open(dst, 'wb') { |f| f.write(data) }
  end

  def self.chmod(mode, path)
    # mruby-io may not support chmod directly
    # Use system call as fallback
    system("chmod #{mode.to_s(8)} #{path}")
  end
end

# File extensions for mruby
class File
  def self.binread(path)
    File.open(path, 'rb') { |f| f.read }
  end

  def self.binwrite(path, data)
    File.open(path, 'wb') { |f| f.write(data) }
  end

  def self.write(path, data)
    File.open(path, 'w') { |f| f.write(data) }
  end

  def self.read(path)
    File.open(path, 'r') { |f| f.read }
  end

  def self.readlink(path)
    # mruby doesn't have readlink - use system
    `readlink "#{path}"`.chomp
  end
end unless File.respond_to?(:binread)

# Dir.mktmpdir replacement
module Dir
  def self.mktmpdir(prefix = 'mruby')
    base = ENV['TMPDIR'] || '/tmp'
    path = "#{base}/#{prefix}-#{Time.now.to_i}-#{rand(100000)}"
    Dir.mkdir(path)
    if block_given?
      begin
        yield path
      ensure
        FileUtils.rm_rf(path)
      end
    else
      path
    end
  end
end unless Dir.respond_to?(:mktmpdir)

# Time extensions for mruby
class Time
  def iso8601
    strftime('%Y-%m-%dT%H:%M:%S%z')
  end

  def self.parse(str)
    # Simple ISO 8601 parser
    if str =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/
      Time.new($1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i)
    elsif str =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
      Time.new($1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i)
    else
      Time.now
    end
  end
end

# String extensions for mruby
class String
  def lines
    split("\n", -1).map { |l| l + "\n" }
  end unless method_defined?(:lines)

  def chomp(sep = "\n")
    if end_with?(sep)
      self[0..-(sep.length + 1)]
    else
      self
    end
  end unless method_defined?(:chomp)

  def start_with?(*prefixes)
    prefixes.any? { |prefix| self[0, prefix.length] == prefix }
  end unless method_defined?(:start_with?)

  def end_with?(*suffixes)
    suffixes.any? { |suffix| self[-suffix.length, suffix.length] == suffix }
  end unless method_defined?(:end_with?)

  def force_encoding(enc)
    self  # mruby strings are byte strings, encoding is a no-op
  end unless method_defined?(:force_encoding)

  def encode(*args)
    self  # No-op in mruby
  end unless method_defined?(:encode)

  def unpack1(fmt)
    unpack(fmt)[0]
  end unless method_defined?(:unpack1)

  def getbyte(index)
    bytes[index]
  end unless method_defined?(:getbyte)

  def byteslice(start, length = nil)
    if length
      self[start, length]
    else
      if start.is_a?(Range)
        self[start]
      else
        self[start, 1]
      end
    end
  end unless method_defined?(:byteslice)
end

# Digest module using mruby-sha2
module Digest
  class SHA256
    def self.hexdigest(data)
      SHA2.sha256_hex(data)
    end
  end
end unless defined?(Digest)

# Enumerable#to_set replacement
class Array
  def to_set
    hash = {}
    each { |item| hash[item] = true }
    hash
  end
end unless Array.method_defined?(:to_set)

# Hash-based Set substitute
class HashSet
  def initialize(arr = [])
    @hash = {}
    arr.each { |item| @hash[item] = true }
  end

  def include?(item)
    @hash.key?(item)
  end

  def add(item)
    @hash[item] = true
  end

  def to_a
    @hash.keys
  end
end
# SQLite wrapper for mruby-sqlite3
# Provides hash-based results and helper methods matching CRuby sqlite3 gem API

module GitLite
  class SQLiteWrapper
    attr_reader :db

    def initialize(path)
      @path = path
      @db = nil
      @column_cache = {}
    end

    def connect
      @db = SQLite3::Database.new(@path)
      execute("PRAGMA foreign_keys = ON")
      execute("PRAGMA journal_mode = WAL")
      execute("PRAGMA synchronous = NORMAL")
      execute("PRAGMA busy_timeout = 5000")
      self
    end

    def close
      @db.close if @db
      @db = nil
    end

    def execute(sql, params = [])
      if params.empty?
        rows = @db.execute(sql)
      else
        # Flatten single-element arrays for mruby-sqlite3
        params = [params] unless params.is_a?(Array)
        rows = @db.execute(sql, params)
      end

      # Convert to array of hashes if SELECT query
      return rows unless sql.strip.upcase.start_with?('SELECT') || sql.strip.upcase.start_with?('PRAGMA')
      return [] if rows.nil? || rows.empty?

      # Get column names from the query
      columns = get_columns_for_query(sql)
      return rows unless columns && !columns.empty?

      rows.map do |row|
        hash = {}
        columns.each_with_index do |col, i|
          hash[col] = row[i] if row[i] != nil || true
        end
        hash
      end
    end

    def get_first_row(sql, *params)
      results = execute(sql, params.flatten)
      results.is_a?(Array) ? results.first : nil
    end

    def get_first_value(sql, *params)
      rows = @db.execute(sql, params.flatten)
      return nil if rows.nil? || rows.empty?
      row = rows.first
      row.is_a?(Array) ? row.first : row
    end

    def last_insert_row_id
      get_first_value("SELECT last_insert_rowid()")
    end

    def transaction
      execute("BEGIN")
      begin
        yield
        execute("COMMIT")
      rescue => e
        execute("ROLLBACK")
        raise e
      end
    end

    def prepare(sql)
      # mruby-sqlite3 doesn't support prepared statements
      # Return a simple wrapper that executes immediately
      PreparedStatement.new(self, sql)
    end

    private

    def get_columns_for_query(sql)
      # Extract column names from SQL
      # For SELECT * queries, use PRAGMA table_info
      normalized = sql.strip.gsub(/\s+/, ' ')

      if normalized =~ /SELECT\s+\*\s+FROM\s+(\w+)/i
        table = $1
        get_table_columns(table)
      elsif normalized =~ /SELECT\s+(.+?)\s+FROM/i
        cols = $1
        parse_select_columns(cols)
      else
        nil
      end
    end

    def get_table_columns(table)
      @column_cache[table] ||= begin
        rows = @db.execute("PRAGMA table_info(#{table})")
        rows.map { |r| r[1] }  # Column name is at index 1
      end
    end

    def parse_select_columns(cols_str)
      cols_str.split(',').map do |col|
        col = col.strip
        # Handle "expr AS alias" and "table.column"
        if col =~ /\s+[Aa][Ss]\s+(\w+)\s*$/
          $1
        elsif col =~ /\.(\w+)$/
          $1
        elsif col =~ /^\w+$/
          col
        else
          # Aggregate or complex expression - use as-is
          col.gsub(/[^a-zA-Z0-9_]/, '_')
        end
      end
    end
  end

  class PreparedStatement
    def initialize(wrapper, sql)
      @wrapper = wrapper
      @sql = sql
    end

    def execute(params = [])
      @wrapper.execute(@sql, params)
    end

    def close
      # No-op for mruby
    end
  end
end
# Utility functions for git-lite (mruby-compatible)

module GitLite
  module Util
    def self.hash_path(path)
      full = File.expand_path(path)
      Digest::SHA256.hexdigest(full)[0..15]
    end

    def self.format_bytes(bytes)
      return "0 B" if bytes.nil? || bytes == 0

      units = ['B', 'KB', 'MB', 'GB', 'TB']
      unit_index = 0

      size = bytes.to_f
      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end

    def self.binary?(content)
      return false if content.nil? || content.empty?

      # Check for null bytes
      return true if content.include?("\x00")

      # Check for high ratio of non-printable chars
      sample = content[0..8000] || content
      non_printable = 0
      sample.bytes.each do |b|
        non_printable += 1 if (b < 32 && b != 9 && b != 10 && b != 13) || b >= 127
      end

      non_printable > sample.length * 0.3
    end

    def self.generate_id
      time_part = Time.now.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18)
      time_part + random_part
    end

    def self.id_to_time(id)
      time_part = id[0..7]
      Time.at(time_part.to_i(36))
    end

    def self.truncate(text, max_length)
      return text if text.length <= max_length
      text[0..max_length - 4] + "..."
    end

    def self.pluralize(count, singular, plural = nil)
      plural ||= singular + 's'
      count == 1 ? "#{count} #{singular}" : "#{count} #{plural}"
    end
  end
end
# Configuration management for git-lite (mruby-compatible)

module GitLite
  class Config
    attr_accessor :user_name, :user_email, :remotes

    def initialize(repo_path = nil)
      @repo_path = repo_path
      @user_name = ''
      @user_email = ''
      @remotes = {}

      load if config_file_exists?
    end

    def self.global
      @global ||= begin
        home = ENV['HOME'] || ENV['USERPROFILE'] || '/tmp'
        config_dir = File.join(home, '.config', 'git-lite')
        FileUtils.mkdir_p(config_dir)

        config = new
        config.instance_variable_set(:@global_config_file, File.join(config_dir, 'config.json'))
        config.load_global
        config
      end
    end

    def config_file
      @repo_path ? File.join(@repo_path, '.git-lite', 'config.json') : @global_config_file
    end

    def config_file_exists?
      cf = config_file
      cf && File.exist?(cf)
    end

    def load
      return unless config_file_exists?

      data = JSON.parse(File.read(config_file))
      @user_name = data['user_name'] || ''
      @user_email = data['user_email'] || ''
      @remotes = data['remotes'] || {}
    rescue StandardError
      # Use defaults
    end

    def load_global
      return unless config_file_exists?

      data = JSON.parse(File.read(config_file))
      @user_name = data['user_name'] || ''
      @user_email = data['user_email'] || ''
    rescue StandardError
      # Use defaults
    end

    def save
      data = {
        'user_name' => @user_name,
        'user_email' => @user_email,
        'remotes' => @remotes
      }

      File.write(config_file, JSON.generate(data))
    end

    def get(key)
      case key
      when 'user.name' then @user_name
      when 'user.email' then @user_email
      else
        if key.start_with?('remote.')
          parts = key.split('.')
          remote_name = parts[1]
          attr = parts[2]
          @remotes[remote_name] if attr == 'url'
        end
      end
    end

    def set(key, value)
      case key
      when 'user.name'
        @user_name = value
      when 'user.email'
        @user_email = value
      else
        if key.start_with?('remote.')
          parts = key.split('.')
          remote_name = parts[1]
          attr = parts[2]
          @remotes[remote_name] = value if attr == 'url'
        end
      end
      save
    end

    def add_remote(name, url)
      @remotes[name] = url
      save
    end

    def remove_remote(name)
      @remotes.delete(name)
      save
    end

    def get_remote(name)
      @remotes[name]
    end

    def effective_user_name
      @user_name.empty? ? Config.global.user_name : @user_name
    end

    def effective_user_email
      @user_email.empty? ? Config.global.user_email : @user_email
    end
  end
end
# Database layer for git-lite using SQLite (mruby-compatible)

module GitLite
  class DB
    SCHEMA_VERSION = 1

    def initialize(db_path)
      @db_path = db_path
      @wrapper = nil
    end

    def connect
      @wrapper = SQLiteWrapper.new(@db_path).connect
      self
    end

    def close
      @wrapper.close if @wrapper
      @wrapper = nil
    end

    def connected?
      !@wrapper.nil?
    end

    # Schema management
    def init_schema
      return if schema_exists?

      @wrapper.transaction do
        create_metadata_table
        create_commits_table
        create_paths_table
        create_file_refs_table
        create_content_table
        create_refs_table
        create_sync_state_table
        ContentStore.create_schema(@wrapper)
        set_schema_version(SCHEMA_VERSION)
      end
    end

    def content_store
      @content_store ||= ContentStore.new(self)
    end

    def schema_exists?
      result = @wrapper.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='commits'")
      result.length > 0
    end

    def get_schema_version
      return 0 unless schema_exists?
      result = @wrapper.get_first_value("SELECT value FROM metadata WHERE key = 'schema_version'")
      result ? result.to_i : 0
    rescue StandardError
      0
    end

    def set_schema_version(version)
      @wrapper.execute(
        "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
        ['schema_version', version.to_s]
      )
    end

    def drop_schema
      tables = ['metadata', 'sync_state', 'refs', 'file_refs', 'content', 'content_meta', 'paths', 'commits']
      tables.each do |table|
        @wrapper.execute("DROP TABLE IF EXISTS #{table}")
      end
    end

    private

    def create_metadata_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      SQL
    end

    def create_commits_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS commits (
          id TEXT PRIMARY KEY,
          parent_id TEXT,
          tree_hash TEXT NOT NULL,
          message TEXT NOT NULL,
          author_name TEXT NOT NULL,
          author_email TEXT NOT NULL,
          authored_at TEXT NOT NULL,
          committer_name TEXT NOT NULL,
          committer_email TEXT NOT NULL,
          committed_at TEXT NOT NULL
        )
      SQL
      @wrapper.execute("CREATE INDEX IF NOT EXISTS idx_commits_parent ON commits(parent_id)")
      @wrapper.execute("CREATE INDEX IF NOT EXISTS idx_commits_authored ON commits(authored_at DESC)")
    end

    def create_paths_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS paths (
          path_id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL,
          path TEXT NOT NULL UNIQUE
        )
      SQL
      @wrapper.execute("CREATE INDEX IF NOT EXISTS idx_paths_path ON paths(path)")
      @wrapper.execute("CREATE INDEX IF NOT EXISTS idx_paths_group ON paths(group_id)")
    end

    def create_file_refs_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS file_refs (
          path_id INTEGER NOT NULL,
          commit_id TEXT NOT NULL,
          version_id INTEGER NOT NULL,
          content_hash BLOB,
          mode INTEGER NOT NULL DEFAULT 33188,
          is_symlink INTEGER NOT NULL DEFAULT 0,
          symlink_target TEXT,
          is_binary INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (path_id, commit_id),
          FOREIGN KEY (path_id) REFERENCES paths(path_id),
          FOREIGN KEY (commit_id) REFERENCES commits(id)
        )
      SQL
      @wrapper.execute("CREATE INDEX IF NOT EXISTS idx_file_refs_commit ON file_refs(commit_id)")
      @wrapper.execute("CREATE INDEX IF NOT EXISTS idx_file_refs_version ON file_refs(path_id, version_id)")
    end

    def create_content_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS content (
          path_id INTEGER NOT NULL,
          version_id INTEGER NOT NULL,
          data BLOB NOT NULL,
          PRIMARY KEY (path_id, version_id),
          FOREIGN KEY (path_id) REFERENCES paths(path_id)
        )
      SQL
    end

    def create_refs_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS refs (
          name TEXT PRIMARY KEY,
          commit_id TEXT NOT NULL
        )
      SQL
    end

    def create_sync_state_table
      @wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS sync_state (
          remote_name TEXT PRIMARY KEY,
          last_commit_id TEXT,
          synced_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      SQL
    end

    public

    # Commit operations
    def create_commit(commit)
      @wrapper.execute(
        "INSERT INTO commits (id, parent_id, tree_hash, message, author_name, author_email, authored_at, committer_name, committer_email, committed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          commit[:id], commit[:parent_id], commit[:tree_hash], commit[:message],
          commit[:author_name], commit[:author_email], commit[:authored_at].iso8601,
          commit[:committer_name], commit[:committer_email], commit[:committed_at].iso8601
        ]
      )
    end

    def create_commits_batch(commits)
      return if commits.empty?
      @wrapper.transaction do
        commits.each { |c| create_commit(c) }
      end
    end

    def get_commit(id)
      row = @wrapper.get_first_row("SELECT * FROM commits WHERE id = ?", id)
      row ? hash_to_commit(row) : nil
    end

    def get_head_commit
      head_id = get_head
      return nil unless head_id
      get_commit(head_id)
    end

    def get_commit_log(limit = 50)
      head_id = get_head
      return [] unless head_id

      rows = @wrapper.execute(
        "SELECT * FROM commits WHERE id <= ? ORDER BY id DESC LIMIT ?",
        [head_id, limit]
      )
      rows.map { |r| hash_to_commit(r) }
    end

    def commit_exists?(id)
      result = @wrapper.get_first_value("SELECT 1 FROM commits WHERE id = ?", id)
      !result.nil?
    end

    def get_latest_commit_id
      @wrapper.get_first_value("SELECT id FROM commits ORDER BY id DESC LIMIT 1")
    end

    def count_commits
      @wrapper.get_first_value("SELECT COUNT(*) FROM commits").to_i
    end

    def delete_commits(commit_ids)
      return if commit_ids.empty?
      placeholders = commit_ids.map { '?' }.join(',')
      @wrapper.execute("DELETE FROM commits WHERE id IN (#{placeholders})", commit_ids)
    end

    # Ref operations
    def get_ref(name)
      row = @wrapper.get_first_row("SELECT * FROM refs WHERE name = ?", name)
      row ? { name: row['name'], commit_id: row['commit_id'] } : nil
    end

    def set_ref(name, commit_id)
      @wrapper.execute("INSERT OR REPLACE INTO refs (name, commit_id) VALUES (?, ?)", [name, commit_id])
    end

    def delete_ref(name)
      @wrapper.execute("DELETE FROM refs WHERE name = ?", [name])
    end

    def get_all_refs
      rows = @wrapper.execute("SELECT * FROM refs ORDER BY name")
      rows.map { |r| { name: r['name'], commit_id: r['commit_id'] } }
    end

    def get_head
      ref = get_ref('HEAD')
      ref ? ref[:commit_id] : nil
    end

    def set_head(commit_id)
      set_ref('HEAD', commit_id)
    end

    # Path operations
    def get_or_create_path(path, group_id = nil)
      row = @wrapper.get_first_row("SELECT path_id, group_id FROM paths WHERE path = ?", path)
      return [row['path_id'], row['group_id']] if row

      if group_id.nil?
        max_group = @wrapper.get_first_value("SELECT COALESCE(MAX(group_id), 0) FROM paths")
        group_id = max_group.to_i + 1
      end

      @wrapper.execute("INSERT INTO paths (group_id, path) VALUES (?, ?)", [group_id, path])
      [@wrapper.last_insert_row_id, group_id]
    end

    def get_path_id_and_group_id(path)
      row = @wrapper.get_first_row("SELECT path_id, group_id FROM paths WHERE path = ?", path)
      row ? [row['path_id'], row['group_id']] : [nil, nil]
    end

    def get_path_by_id(path_id)
      @wrapper.get_first_value("SELECT path FROM paths WHERE path_id = ?", path_id)
    end

    def get_all_paths
      @wrapper.execute("SELECT path FROM paths ORDER BY path").map { |r| r['path'] }
    end

    # File ref operations
    def create_file_ref(ref)
      @wrapper.execute(
        "INSERT INTO file_refs (path_id, commit_id, version_id, content_hash, mode, is_symlink, symlink_target, is_binary) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
          ref[:path_id], ref[:commit_id], ref[:version_id], ref[:content_hash],
          ref[:mode], ref[:is_symlink] ? 1 : 0, ref[:symlink_target],
          ref[:is_binary] ? 1 : 0
        ]
      )
    end

    def create_file_refs_batch(refs)
      return if refs.empty?
      @wrapper.transaction do
        refs.each { |r| create_file_ref(r) }
      end
    end

    def get_file_ref(path_id, commit_id)
      row = @wrapper.get_first_row(
        "SELECT fr.path_id, fr.commit_id, fr.version_id, fr.content_hash, fr.mode, fr.is_symlink, fr.symlink_target, fr.is_binary, p.path, p.group_id FROM file_refs fr JOIN paths p ON p.path_id = fr.path_id WHERE fr.path_id = ? AND fr.commit_id = ?",
        path_id, commit_id
      )
      row ? hash_to_file_ref(row) : nil
    end

    def get_file_refs_at_commit(commit_id)
      rows = @wrapper.execute(
        "SELECT fr.path_id, fr.commit_id, fr.version_id, fr.content_hash, fr.mode, fr.is_symlink, fr.symlink_target, fr.is_binary, p.path, p.group_id FROM file_refs fr JOIN paths p ON p.path_id = fr.path_id WHERE fr.commit_id = ? ORDER BY p.path",
        [commit_id]
      )
      rows.map { |r| hash_to_file_ref(r) }
    end

    def get_tree_at_commit(commit_id)
      rows = @wrapper.execute(
        "SELECT fr.path_id, fr.commit_id, fr.version_id, fr.content_hash, fr.mode, fr.is_symlink, fr.symlink_target, fr.is_binary, p.path, p.group_id FROM file_refs fr JOIN paths p ON p.path_id = fr.path_id WHERE fr.commit_id <= ? AND fr.path_id IN (SELECT path_id FROM file_refs WHERE commit_id <= ? GROUP BY path_id HAVING MAX(commit_id) = fr.commit_id) AND fr.content_hash IS NOT NULL ORDER BY p.path",
        [commit_id, commit_id]
      )
      rows.map { |r| hash_to_file_ref(r) }
    end

    def get_next_version_id(group_id)
      result = @wrapper.get_first_value(
        "SELECT COALESCE(MAX(fr.version_id), 0) + 1 FROM file_refs fr JOIN paths p ON p.path_id = fr.path_id WHERE p.group_id = ?",
        group_id
      )
      result.to_i
    end

    # Content operations with zlib compression
    def create_content(path_id, version_id, data)
      content = data.to_s

      if content.bytesize > 100
        compressed = Zlib.deflate(content)
        if compressed.bytesize < content.bytesize * 0.9
          packed = [0x03].pack('C') + compressed
        else
          packed = [0x01].pack('C') + content
        end
      else
        packed = [0x01].pack('C') + content
      end

      @wrapper.execute(
        "INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, ?)",
        [path_id, version_id, packed]
      )

      @wrapper.execute(
        "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 1, NULL)",
        [path_id, version_id]
      )
    end

    def create_content_batch(contents)
      return if contents.empty?
      contents.each do |c|
        create_content(c[:path_id], c[:version_id], c[:data])
      end
    end

    def get_content(path_id, version_id)
      meta = @wrapper.get_first_row(
        "SELECT is_keyframe, base_version FROM content_meta WHERE path_id = ? AND version_id = ?",
        path_id, version_id
      )

      return nil unless meta

      data = get_content_raw(path_id, version_id)
      return nil if data.nil? || data.empty?

      flags = data.getbyte(0)
      is_compressed = (flags & 0x02) != 0
      is_keyframe = (flags & 0x01) != 0
      content = data[1..-1]

      if is_compressed
        content = Zlib.inflate(content)
      end

      return content if is_keyframe || meta['is_keyframe'] == 1

      base_version = meta['base_version']
      if base_version
        base_content = get_content(path_id, base_version)
        return Delta.apply(base_content, content) if base_content
      end

      content
    rescue => e
      data ? data[1..-1] : nil
    end

    def get_content_raw(path_id, version_id)
      @wrapper.get_first_value(
        "SELECT data FROM content WHERE path_id = ? AND version_id = ?",
        path_id, version_id
      )
    end

    # Blob operations
    def create_blob(blob)
      path_id, group_id = get_or_create_path(blob[:path])
      version_id = get_next_version_id(group_id)

      ref = {
        path_id: path_id,
        commit_id: blob[:commit_id],
        version_id: version_id,
        content_hash: blob[:content_hash],
        mode: blob[:mode] || 33188,
        is_symlink: blob[:is_symlink] || false,
        symlink_target: blob[:symlink_target],
        is_binary: blob[:is_binary] || false
      }
      create_file_ref(ref)

      if blob[:content_hash] && blob[:content]
        create_content(path_id, version_id, blob[:content])
      end

      true
    end

    def get_blob(path, commit_id)
      path_id, group_id = get_path_id_and_group_id(path)
      return nil unless path_id

      ref = get_file_ref(path_id, commit_id)
      return nil unless ref

      content = get_content(path_id, ref[:version_id]) if ref[:content_hash]

      {
        path: path,
        commit_id: ref[:commit_id],
        content: content,
        content_hash: ref[:content_hash],
        mode: ref[:mode],
        is_symlink: ref[:is_symlink],
        symlink_target: ref[:symlink_target],
        is_binary: ref[:is_binary]
      }
    end

    def get_blobs_at_commit(commit_id)
      refs = get_file_refs_at_commit(commit_id)
      refs.map do |ref|
        content = get_content(ref[:path_id], ref[:version_id]) if ref[:content_hash]
        {
          path: ref[:path],
          commit_id: ref[:commit_id],
          content: content,
          content_hash: ref[:content_hash],
          mode: ref[:mode],
          is_symlink: ref[:is_symlink],
          symlink_target: ref[:symlink_target],
          is_binary: ref[:is_binary]
        }
      end
    end

    def get_tree(commit_id)
      refs = get_tree_at_commit(commit_id)
      refs.map do |ref|
        content = get_content(ref[:path_id], ref[:version_id]) if ref[:content_hash]
        {
          path: ref[:path],
          commit_id: ref[:commit_id],
          content: content,
          content_hash: ref[:content_hash],
          mode: ref[:mode],
          is_symlink: ref[:is_symlink],
          symlink_target: ref[:symlink_target],
          is_binary: ref[:is_binary]
        }
      end
    end

    # Metadata operations
    def get_metadata(key)
      @wrapper.get_first_value("SELECT value FROM metadata WHERE key = ?", key)
    end

    def set_metadata(key, value)
      @wrapper.execute("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)", [key, value])
    end

    def get_repo_path
      get_metadata('repo_path')
    end

    def set_repo_path(path)
      set_metadata('repo_path', path)
    end

    # Stats
    def get_stats
      {
        commits: @wrapper.get_first_value("SELECT COUNT(*) FROM commits").to_i,
        paths: @wrapper.get_first_value("SELECT COUNT(*) FROM paths").to_i,
        file_refs: @wrapper.get_first_value("SELECT COUNT(*) FROM file_refs").to_i,
        content_size: @wrapper.get_first_value("SELECT COALESCE(SUM(LENGTH(data)), 0) FROM content").to_i
      }
    end

    # Execute raw SQL
    def execute(sql, params = [])
      @wrapper.execute(sql, params)
    end

    # Find commit by prefix
    def find_commit_by_prefix(prefix)
      row = @wrapper.get_first_row("SELECT * FROM commits WHERE id LIKE ?", "#{prefix}%")
      row ? hash_to_commit(row) : nil
    end

    private

    def hash_to_commit(row)
      {
        id: row['id'],
        parent_id: row['parent_id'],
        tree_hash: row['tree_hash'],
        message: row['message'],
        author_name: row['author_name'],
        author_email: row['author_email'],
        authored_at: Time.parse(row['authored_at']),
        committer_name: row['committer_name'],
        committer_email: row['committer_email'],
        committed_at: Time.parse(row['committed_at'])
      }
    end

    def hash_to_file_ref(row)
      {
        path_id: row['path_id'],
        path: row['path'],
        group_id: row['group_id'],
        commit_id: row['commit_id'],
        version_id: row['version_id'],
        content_hash: row['content_hash'],
        mode: row['mode'],
        is_symlink: row['is_symlink'] == 1,
        symlink_target: row['symlink_target'],
        is_binary: row['is_binary'] == 1
      }
    end
  end
end
# Repository management for git-lite (mruby-compatible)

module GitLite
  class Repo
    attr_reader :root, :pgit_path, :config, :db

    def self.init(path = Dir.pwd)
      path = File.expand_path(path)
      pgit_dir = File.join(path, '.git-lite')

      if File.directory?(pgit_dir)
        raise AlreadyInitializedError, "Repository already exists"
      end

      Dir.mkdir(pgit_dir)

      config = Config.new(path)
      config.save

      db_path = File.join(pgit_dir, 'repo.db')
      db = DB.new(db_path).connect
      db.init_schema
      db.set_repo_path(path)
      db.close

      new(path)
    end

    def self.open(path = Dir.pwd)
      root = find_root(path)
      raise NotARepoError, "Not a git-lite repository" unless root
      new(root)
    end

    def self.find_root(path)
      return nil if path.nil? || path == '/'
      pgit_dir = File.join(path, '.git-lite')
      return path if File.directory?(pgit_dir)
      find_root(File.dirname(path))
    end

    def initialize(root)
      @root = root
      @pgit_path = File.join(root, '.git-lite')
      @config = Config.new(root)

      db_path = File.join(@pgit_path, 'repo.db')
      @db = DB.new(db_path).connect
    end

    def close
      @db.close if @db
    end

    def head
      @db.get_head
    end

    def current_branch
      'main'
    end

    def branches
      ['main']
    end

    def create_branch(name)
      head_id = head
      raise "No commits yet" unless head_id
      @db.set_ref(name, head_id)
    end

    def get_commit(id)
      @db.get_commit(id)
    end

    def log(limit = 50)
      @db.get_commit_log(limit)
    end

    # Staging operations
    STAGING_FILE = 'staging.json'

    def staging_path
      File.join(@pgit_path, STAGING_FILE)
    end

    def load_staging
      return {} unless File.exist?(staging_path)
      JSON.parse(File.read(staging_path))
    rescue StandardError
      {}
    end

    def save_staging(staging)
      File.write(staging_path, JSON.generate(staging))
    end

    def stage_file(path)
      staging = load_staging
      staging[path.to_s] = { 'status' => 'added', 'type' => 'file' }
      save_staging(staging)
    end

    def stage_deletion(path)
      staging = load_staging
      staging[path.to_s] = { 'status' => 'deleted', 'type' => 'file' }
      save_staging(staging)
    end

    def move_file(source, dest)
      staging = load_staging
      staging[source.to_s] = { 'status' => 'deleted', 'type' => 'file' }
      staging[dest.to_s] = { 'status' => 'added', 'type' => 'file', 'from' => source.to_s }
      save_staging(staging)
    end

    def reset_staging
      File.delete(staging_path) if File.exist?(staging_path)
    end

    def staged_changes
      staging = load_staging
      staging.map do |path, info|
        { path: path, status: info['status'].to_sym }
      end
    end

    def unstaged_changes
      changes = []
      head_id = head
      return changes unless head_id

      tree = @db.get_tree(head_id)
      tree.each do |blob|
        full_path = File.join(@root, blob[:path])
        if File.exist?(full_path)
          current_content = File.binread(full_path)
          if current_content != blob[:content]
            changes << { path: blob[:path], status: :modified }
          end
        else
          changes << { path: blob[:path], status: :deleted }
        end
      end

      changes
    end

    def untracked_files
      return [] unless head

      tree = @db.get_tree(head)
      tracked = tree.map { |b| b[:path] }.to_set  # returns Hash from compat

      untracked = []
      glob_files(@root).each do |path|
        next if path.start_with?('.git-lite')
        next if path == '.' || path == '..'
        full_path = File.join(@root, path)
        next unless File.file?(full_path)
        untracked << path unless tracked.include?(path)
      end

      untracked
    end

    def commit(message)
      staging = load_staging

      if staging.empty?
        raise "Nothing to commit (use 'git-lite add' to stage files)"
      end

      parent_id = head

      timestamp = Time.now
      time_part = timestamp.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18)
      commit_id = time_part + random_part

      staged = load_staging
      tree_hash = Digest::SHA256.hexdigest(staged.keys.sort.join)

      author_name = config.effective_user_name || 'Anonymous'
      author_email = config.effective_user_email || 'anonymous@example.com'

      staged.each do |path, info|
        if info['status'] == 'deleted'
          @db.create_blob({
            path: path,
            commit_id: commit_id,
            content_hash: nil,
            content: nil,
            mode: 0,
            is_symlink: false,
            symlink_target: nil,
            is_binary: false
          })
        else
          full_path = File.join(@root, path)
          content = File.binread(full_path)

          file_mode = 33188  # 0o100644 default
          begin
            file_mode = File.stat(full_path).mode & 0o7777
          rescue
            # Use default
          end

          @db.create_blob({
            path: path,
            commit_id: commit_id,
            content_hash: Digest::SHA256.hexdigest(content)[0..31],
            content: content,
            mode: file_mode,
            is_symlink: false,
            symlink_target: nil,
            is_binary: Util.binary?(content)
          })
        end
      end

      commit_data = {
        id: commit_id,
        parent_id: parent_id,
        tree_hash: tree_hash,
        message: message,
        author_name: author_name,
        author_email: author_email,
        authored_at: timestamp,
        committer_name: author_name,
        committer_email: author_email,
        committed_at: timestamp
      }

      @db.create_commit(commit_data)
      @db.set_head(commit_id)
      reset_staging

      commit_id
    end

    def checkout(commit_id)
      commit = @db.get_commit(commit_id) || @db.find_commit_by_prefix(commit_id)
      raise "Commit not found: #{commit_id}" unless commit

      blobs = @db.get_tree(commit[:id])
      blobs.each do |blob|
        full_path = File.join(@root, blob[:path])
        FileUtils.mkdir_p(File.dirname(full_path))

        if blob[:is_symlink] && blob[:symlink_target]
          system("ln -sf '#{blob[:symlink_target]}' '#{full_path}'")
        elsif blob[:content]
          File.binwrite(full_path, blob[:content])
          begin
            File.chmod(blob[:mode], full_path) if blob[:mode] && blob[:mode] > 0
          rescue
            # Ignore chmod errors in mruby
          end
        end
      end

      @db.set_head(commit[:id])
    end

    def diff_working_tree
      head_id = head
      return [] unless head_id

      diffs = []
      tree = @db.get_tree(head_id)

      tree.each do |blob|
        full_path = File.join(@root, blob[:path])
        if File.exist?(full_path)
          current = File.binread(full_path)
          if current != blob[:content]
            diffs << {
              path: blob[:path],
              diff: generate_diff(blob[:path], blob[:content], current)
            }
          end
        else
          diffs << {
            path: blob[:path],
            diff: "deleted: #{blob[:path]}"
          }
        end
      end

      diffs
    end

    def generate_diff(path, old_content, new_content)
      old_lines = (old_content || '').split("\n")
      new_lines = (new_content || '').split("\n")

      result = []
      max_lines = [old_lines.length, new_lines.length].max

      max_lines.times do |i|
        old_line = i < old_lines.length ? old_lines[i] : nil
        new_line = i < new_lines.length ? new_lines[i] : nil

        if old_line != new_line
          result << "-#{old_line}\n" if old_line
          result << "+#{new_line}\n" if new_line
        end
      end

      result.join
    end

    def execute_sql(query)
      @db.execute(query)
    end

    private

    def glob_files(base_dir)
      result = []
      entries = begin
        Dir.entries(base_dir)
      rescue
        []
      end

      entries.each do |entry|
        next if entry == '.' || entry == '..'
        full = File.join(base_dir, entry)
        rel = full.sub("#{@root}/", '')

        if File.directory?(full) && !entry.start_with?('.git-lite')
          result.concat(glob_files(full))
        elsif File.file?(full)
          result << rel
        end
      end

      result
    end
  end
end
# UI utilities for git-lite (mruby-compatible)

module GitLite
  module UI
    COLORS = {
      reset:   "\e[0m",
      black:   "\e[30m",
      red:     "\e[31m",
      green:   "\e[32m",
      yellow:  "\e[33m",
      blue:    "\e[34m",
      magenta: "\e[35m",
      cyan:    "\e[36m",
      white:   "\e[37m",
      bold:    "\e[1m"
    }

    def self.color(name)
      COLORS[name] || ''
    end

    def self.reset
      COLORS[:reset]
    end

    def self.colored(text, color_name)
      "#{color(color_name)}#{text}#{reset}"
    end

    def self.success(text)
      colored(text, :green)
    end

    def self.error(text)
      colored(text, :red)
    end

    def self.warning(text)
      colored(text, :yellow)
    end

    def self.info(text)
      colored(text, :cyan)
    end

    def self.format_bytes(bytes)
      return "0 B" if bytes.nil? || bytes == 0
      units = ['B', 'KB', 'MB', 'GB', 'TB']
      unit_index = 0
      size = bytes.to_f
      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end
      "#{size.round(2)} #{units[unit_index]}"
    end

    def self.format_count(n)
      s = n.to_s
      result = ''
      s.reverse.each_char.with_index do |c, i|
        result = ',' + result if i > 0 && i % 3 == 0
        result = c + result
      end
      result
    end

    def self.progress_bar(current, total, width = 40)
      return '' if total == 0
      ratio = current.to_f / total
      filled = (width * ratio).round
      empty = width - filled
      bar = '=' * filled + '>' + ' ' * [empty - 1, 0].max
      percentage = (ratio * 100).round(1)
      "[#{bar}] #{percentage}% (#{current}/#{total})"
    end

    def self.table(headers, rows)
      return "No data" if rows.empty?
      widths = headers.length.times.map do |i|
        [headers[i].to_s.length, *rows.map { |r| r[i].to_s.length }].max
      end

      header_line = headers.length.times.map { |i| headers[i].to_s.ljust(widths[i]) }.join(' | ')
      separator = widths.map { |w| '-' * w }.join('-+-')

      result = [header_line, separator]
      rows.each do |row|
        result << row.length.times.map { |i| row[i].to_s.ljust(widths[i]) }.join(' | ')
      end
      result.join("\n")
    end
  end
end
# Delta compression for git-lite (mruby-compatible)

module GitLite
  module Delta
    BLOCK_SIZE = 16

    def self.create(old_data, new_data)
      return nil if old_data.nil? || old_data.empty?
      return nil if new_data.bytesize < 200
      return nil if old_data == new_data

      similarity = quick_similarity(old_data, new_data)
      return nil if similarity < 0.3

      block_hashes = {}
      i = 0
      while i <= old_data.bytesize - BLOCK_SIZE
        hash = hash_block(old_data, i)
        block_hashes[hash] ||= []
        block_hashes[hash] << i
        i += BLOCK_SIZE
      end

      matches = []
      pos = 0

      while pos <= new_data.bytesize - BLOCK_SIZE
        hash = hash_block(new_data, pos)

        if block_hashes[hash]
          best_len = BLOCK_SIZE
          best_offset = block_hashes[hash].first

          block_hashes[hash].each do |offset|
            len = extend_match(old_data, new_data, offset, pos)
            if len > best_len
              best_len = len
              best_offset = offset
            end
          end

          if best_len >= BLOCK_SIZE
            matches << [pos, best_offset, best_len]
            pos += best_len
            next
          end
        end

        pos += 1
      end

      total_matched = matches.inject(0) { |sum, m| sum + m[2] }
      return nil if total_matched < new_data.bytesize * 0.2

      build_delta(old_data.bytesize, new_data, matches)
    end

    def self.apply(base_data, delta)
      return delta if delta.bytesize < 9

      magic = delta.getbyte(0)
      version = delta.getbyte(1)
      return delta unless magic == 0xD5 && version == 1

      base_size, output_size = delta[2..9].unpack('NN')

      result = ""
      pos = 10

      while pos < delta.bytesize && result.bytesize < output_size
        cmd = delta.getbyte(pos)
        pos += 1

        case cmd
        when 0x01  # Copy from base
          offset, length = delta[pos..pos+7].unpack('NN')
          pos += 8
          result << base_data[offset, length]
        when 0x02  # Insert literal
          length = delta[pos..pos+3].unpack('N')[0]
          pos += 4
          result << delta[pos, length]
          pos += length
        else
          return nil
        end
      end

      result
    end

    # Compression wrappers using Zlib
    def self.compress(data)
      Zlib.deflate(data)
    end

    def self.decompress(data)
      Zlib.inflate(data)
    end

    private

    def self.quick_similarity(old_data, new_data)
      samples = 10
      sample_size = 16
      matches = 0

      return 0 if new_data.bytesize < sample_size

      samples.times do
        pos = rand(0..new_data.bytesize - sample_size)
        sample = new_data[pos, sample_size]
        matches += 1 if old_data.include?(sample)
      end

      matches.to_f / samples
    end

    def self.hash_block(data, offset)
      hash = 0
      len = [BLOCK_SIZE, data.bytesize - offset].min
      len.times do |i|
        hash = ((hash << 5) - hash + data.getbyte(offset + i)) & 0xFFFFFFFF
      end
      hash
    end

    def self.extend_match(old_data, new_data, old_pos, new_pos)
      start_old = old_pos
      start_new = new_pos

      while start_old > 0 && start_new > 0 &&
            old_data.getbyte(start_old - 1) == new_data.getbyte(start_new - 1)
        start_old -= 1
        start_new -= 1
      end

      len = 0
      max_len = [old_data.bytesize - old_pos, new_data.bytesize - new_pos].min
      while len < max_len && old_data.getbyte(old_pos + len) == new_data.getbyte(new_pos + len)
        len += 1
      end

      len += (old_pos - start_old)
      len
    end

    def self.build_delta(base_size, new_data, matches)
      matches.sort_by! { |m| m[0] }

      merged = []
      matches.each do |match|
        if merged.empty? || match[0] > merged.last[0] + merged.last[2]
          merged << match
        else
          old_end = merged.last[0] + merged.last[2]
          if match[0] + match[2] > old_end
            merged.last[2] = match[0] + match[2] - merged.last[0]
          end
        end
      end

      delta = ""
      delta << 0xD5.chr
      delta << 0x01.chr
      delta << [base_size, new_data.bytesize].pack('NN')

      pos = 0
      merged.each do |new_pos, old_pos, length|
        if new_pos > pos
          literal = new_data[pos, new_pos - pos]
          delta << 0x02.chr
          delta << [literal.bytesize].pack('N')
          delta << literal
        end

        delta << 0x01.chr
        delta << [old_pos, length].pack('NN')

        pos = new_pos + length
      end

      if pos < new_data.bytesize
        literal = new_data[pos, new_data.bytesize - pos]
        delta << 0x02.chr
        delta << [literal.bytesize].pack('N')
        delta << literal
      end

      delta.bytesize < new_data.bytesize * 0.8 ? delta : nil
    end
  end
end
# Content storage with delta compression for git-lite (mruby-compatible)

module GitLite
  class ContentStore
    KEYFRAME_EVERY = 100

    def initialize(db)
      @db = db
    end

    def store(path_id, version_id, content)
      is_keyframe = should_be_keyframe?(path_id, version_id)

      if is_keyframe || content.nil? || content.empty?
        store_keyframe(path_id, version_id, content)
      else
        base_version = find_last_keyframe(path_id, version_id)

        if base_version
          base_content = retrieve_raw_content(path_id, base_version)
          delta = Delta.create(base_content, content)

          if delta && delta.bytesize < content.bytesize * 0.8
            store_delta(path_id, version_id, delta, base_version)
          else
            store_keyframe(path_id, version_id, content)
          end
        else
          store_keyframe(path_id, version_id, content)
        end
      end
    end

    def retrieve(path_id, version_id)
      meta = @db.execute(
        "SELECT is_keyframe, base_version FROM content_meta WHERE path_id = ? AND version_id = ?",
        [path_id, version_id]
      ).first

      return nil unless meta

      packed = retrieve_raw(path_id, version_id)
      is_keyframe, content = unpack_content(packed)

      if is_keyframe || meta['base_version'].nil?
        content
      else
        base = retrieve(path_id, meta['base_version'].to_i)
        Delta.apply(base, content)
      end
    end

    def retrieve_raw(path_id, version_id)
      @db.get_content_raw(path_id, version_id)
    end

    def store_batch(items)
      return if items.empty?
      items.each do |item|
        store(item[:path_id], item[:version_id], item[:content])
      end
    end

    def stats
      result = @db.execute(
        "SELECT COUNT(*) as total_versions, SUM(CASE WHEN is_keyframe = 1 THEN 1 ELSE 0 END) as keyframes, SUM(CASE WHEN is_keyframe = 0 THEN 1 ELSE 0 END) as deltas FROM content_meta"
      ).first

      sizes = @db.execute(
        "SELECT COALESCE(SUM(LENGTH(data)), 0) as total_bytes FROM content"
      ).first

      {
        versions: (result['total_versions'] || 0).to_i,
        keyframes: (result['keyframes'] || 0).to_i,
        deltas: (result['deltas'] || 0).to_i,
        total_bytes: (sizes['total_bytes'] || 0).to_i
      }
    end

    def self.create_schema(wrapper)
      wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS content_meta (
          path_id INTEGER NOT NULL,
          version_id INTEGER NOT NULL,
          is_keyframe INTEGER NOT NULL DEFAULT 1,
          base_version INTEGER,
          PRIMARY KEY (path_id, version_id)
        )
      SQL
      wrapper.execute("CREATE INDEX IF NOT EXISTS idx_content_meta_keyframe ON content_meta(path_id, is_keyframe)")
    end

    private

    def should_be_keyframe?(path_id, version_id)
      return true if version_id == 1
      return true if version_id % KEYFRAME_EVERY == 0
      false
    end

    def find_last_keyframe(path_id, before_version)
      result = @db.execute(
        "SELECT MAX(version_id) as version FROM content_meta WHERE path_id = ? AND is_keyframe = 1 AND version_id < ?",
        [path_id, before_version]
      ).first
      result && result['version'] ? result['version'].to_i : nil
    end

    def store_keyframe(path_id, version_id, content)
      packed = pack_content(content, true)
      @db.execute(
        "INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, ?)",
        [path_id, version_id, packed]
      )
      @db.execute(
        "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 1, NULL)",
        [path_id, version_id]
      )
    end

    def store_delta(path_id, version_id, delta, base_version)
      packed = pack_content(delta, false)
      @db.execute(
        "INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, ?)",
        [path_id, version_id, packed]
      )
      @db.execute(
        "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 0, ?)",
        [path_id, version_id, base_version]
      )
    end

    def retrieve_raw_content(path_id, version_id)
      packed = retrieve_raw(path_id, version_id)
      return nil unless packed
      _, content = unpack_content(packed)
      content
    end

    def pack_content(content, is_keyframe)
      return nil if content.nil?

      flags = 0
      flags |= 0x01 if is_keyframe

      if content.bytesize > 1024
        compressed = Zlib.deflate(content)
        if compressed.bytesize < content.bytesize * 0.9
          content = compressed
          flags |= 0x02
        end
      end

      [flags].pack('C') + content
    end

    def unpack_content(packed)
      return [true, nil] if packed.nil?

      flags = packed.getbyte(0)
      content = packed[1..-1]

      is_keyframe = (flags & 0x01) != 0
      is_compressed = (flags & 0x02) != 0

      if is_compressed
        content = Zlib.inflate(content)
      end

      [is_keyframe, content]
    end
  end
end
# Git importer for git-lite (mruby-compatible)

module GitLite
  class GitImporter
    def initialize(repo, git_path)
      @repo = repo
      @git_path = git_path
      @commit_count = 0
    end

    def import_branch(branch = 'main')
      puts "Exporting git history..."

      # Use backtick instead of Open3
      cmd = "cd '#{@git_path}' && git fast-export --reencode=yes --show-original-ids #{branch} 2>/dev/null"
      stdout = `#{cmd}`

      unless $?.success?
        raise "Failed to export git history"
      end

      parse_fast_export(stdout)
    end

    def parse_fast_export(data)
      lines = data.split("\n").map { |l| l + "\n" }
      index = 0

      blobs = {}
      commits = []

      while index < lines.length
        line = lines[index].chomp

        case line
        when 'blob'
          index += 1
          blob = parse_blob(lines, index)
          blobs[blob[:mark]] = blob if blob[:mark]
          index = blob[:next_index] if blob

        when /^commit /
          index += 1
          commit = parse_commit(lines, index)
          commits << commit if commit
          index = commit[:next_index] if commit

        when 'done'
          break
        else
          index += 1
        end
      end

      puts "Importing #{commits.length} commits..."

      commits.each_with_index do |commit, i|
        import_commit(commit, blobs)
        @commit_count += 1

        if (i + 1) % 100 == 0
          puts "  Imported #{i + 1}/#{commits.length} commits"
        end
      end

      @commit_count
    end

    def parse_blob(lines, start_index)
      index = start_index
      blob = { mark: nil, data: nil, next_index: start_index }

      while index < lines.length
        line = lines[index]

        if line.start_with?('mark ')
          blob[:mark] = line.chomp.sub('mark ', '').sub(':', '').to_i
          index += 1
        elsif line.start_with?('original-oid ')
          blob[:original_oid] = line.chomp.sub('original-oid ', '')
          index += 1
        elsif line.start_with?('data ')
          size = line.chomp.sub('data ', '').to_i
          index += 1

          data_parts = []
          bytes_read = 0
          while bytes_read < size && index < lines.length
            line_data = lines[index]
            data_parts << line_data
            bytes_read += line_data.length
            index += 1
          end
          blob[:data] = data_parts.join[0...size]

          blob[:next_index] = index
          return blob
        else
          blob[:next_index] = index
          return blob
        end
      end

      blob
    end

    def parse_commit(lines, start_index)
      index = start_index
      commit = {
        mark: nil,
        original_oid: nil,
        author_name: '',
        author_email: '',
        author_time: nil,
        committer_name: '',
        committer_email: '',
        committer_time: nil,
        message: '',
        from: nil,
        file_ops: [],
        next_index: start_index
      }

      while index < lines.length
        line = lines[index]
        chomped = line.chomp

        case chomped
        when /^mark /
          commit[:mark] = chomped.sub('mark ', '').sub(':', '').to_i
          index += 1

        when /^original-oid /
          commit[:original_oid] = chomped.sub('original-oid ', '')
          index += 1

        when /^author /
          commit[:author_name], commit[:author_email], commit[:author_time] = parse_author(chomped.sub('author ', ''))
          index += 1

        when /^committer /
          commit[:committer_name], commit[:committer_email], commit[:committer_time] = parse_author(chomped.sub('committer ', ''))
          index += 1

        when /^data /
          size = chomped.sub('data ', '').to_i
          index += 1

          message_data = lines[index..index + 10].join[0...size]
          commit[:message] = message_data
          index += 1

          remaining = size - message_data.length
          while remaining > 0 && index < lines.length
            remaining -= lines[index].length
            index += 1
          end

        when /^from /
          commit[:from] = chomped.sub('from ', '').sub(':', '').to_i
          index += 1

        when /^M /, /^D /
          parts = chomped.split(' ')
          if chomped.start_with?('M ')
            mode = parts[1]
            mark = parts[2].sub(':', '').to_i
            path = parts[3..-1].join(' ')
            commit[:file_ops] << { type: :modify, mode: mode.to_i(8), mark: mark, path: path }
          else
            path = parts[1..-1].join(' ')
            commit[:file_ops] << { type: :delete, path: path }
          end
          index += 1

        when ''
          commit[:next_index] = index + 1
          return commit

        else
          index += 1
        end
      end

      commit[:next_index] = index
      commit
    end

    def parse_author(author_line)
      match = author_line.match(/^(.+?) <(.+?)> (\d+) ([+-]\d+)$/)

      if match
        name = match[1]
        email = match[2]
        timestamp = Time.at(match[3].to_i)
        [name, email, timestamp]
      else
        ['Unknown', 'unknown@example.com', Time.now]
      end
    end

    def import_commit(commit_data, blobs)
      @commit_map ||= {}

      timestamp = commit_data[:committer_time] || Time.now
      time_part = timestamp.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18)
      commit_id = time_part + random_part

      parent_id = nil
      if commit_data[:from]
        parent_id = @commit_map[commit_data[:from]]
      end

      @commit_map[commit_data[:mark]] = commit_id if commit_data[:mark]

      # Clean message - force_encoding/encode are no-ops via compat
      message = commit_data[:message].to_s.chomp

      commit = {
        id: commit_id,
        parent_id: parent_id,
        tree_hash: Digest::SHA256.hexdigest(commit_data[:file_ops].map { |o| o[:path] }.sort.join),
        message: message,
        author_name: commit_data[:author_name],
        author_email: commit_data[:author_email],
        authored_at: commit_data[:author_time] || timestamp,
        committer_name: commit_data[:committer_name],
        committer_email: commit_data[:committer_email],
        committed_at: timestamp
      }

      @repo.db.create_commit(commit)

      commit_data[:file_ops].each do |op|
        if op[:type] == :delete
          @repo.db.create_blob({
            path: op[:path],
            commit_id: commit_id,
            content_hash: nil,
            content: nil,
            mode: 0,
            is_symlink: false,
            symlink_target: nil,
            is_binary: false
          })
        elsif op[:type] == :modify
          blob_data = blobs[op[:mark]]

          if blob_data && blob_data[:data]
            content = blob_data[:data]

            @repo.db.create_blob({
              path: op[:path],
              commit_id: commit_id,
              content_hash: Digest::SHA256.hexdigest(content)[0..31],
              content: content,
              mode: op[:mode] || 0o100644,
              is_symlink: (op[:mode] == 0o120000),
              symlink_target: nil,
              is_binary: Util.binary?(content)
            })
          end
        end
      end

      @repo.db.set_head(commit_id)
    end
  end
end
# CLI commands for git-lite (mruby-compatible)

module GitLite
  module CLI
    COMMANDS = {
      'init'      => 'Initialize a new repository',
      'add'       => 'Stage files for commit',
      'rm'        => 'Remove files and stage the deletion',
      'mv'        => 'Move/rename a file',
      'status'    => 'Show working tree status',
      'commit'    => 'Record changes to the repository',
      'log'       => 'Show commit history',
      'diff'      => 'Show changes between commits',
      'show'      => 'Show commit details',
      'checkout'  => 'Restore working tree files',
      'branch'    => 'List or create branches',
      'reset'     => 'Reset current HEAD to specified state',
      'import'    => 'Import from a git repository',
      'clone'     => 'Clone a repository',
      'push'      => 'Push to a remote',
      'pull'      => 'Pull from a remote',
      'remote'    => 'Manage remotes',
      'config'    => 'Get and set repository options',
      'stats'     => 'Show repository statistics',
      'gc'        => 'Run garbage collection (delta compression)',
      'sql'       => 'Run SQL queries on repository',
      'clean'     => 'Remove untracked files',
      'version'   => 'Show version',
      'help'      => 'Show help'
    }

    def self.run(args)
      if args.empty?
        show_help
        return
      end

      command = args.shift

      case command
      when 'init'
        run_init(args)
      when 'add'
        run_add(args)
      when 'rm'
        run_rm(args)
      when 'mv'
        run_mv(args)
      when 'status'
        run_status(args)
      when 'commit'
        run_commit(args)
      when 'log'
        run_log(args)
      when 'diff'
        run_diff(args)
      when 'show'
        run_show(args)
      when 'checkout'
        run_checkout(args)
      when 'branch'
        run_branch(args)
      when 'reset'
        run_reset(args)
      when 'import'
        run_import(args)
      when 'clone'
        run_clone(args)
      when 'push'
        run_push(args)
      when 'pull'
        run_pull(args)
      when 'remote'
        run_remote(args)
      when 'config'
        run_config(args)
      when 'stats'
        run_stats(args)
      when 'gc'
        run_gc(args)
      when 'sql'
        run_sql(args)
      when 'clean'
        run_clean(args)
      when 'version', '--version', '-v'
        puts "git-lite version #{VERSION}"
      when 'help', '--help', '-h'
        show_help
      else
        puts "Unknown command: #{command}"
        puts "Run 'git-lite help' for usage."
        exit(1)
      end
    rescue NotARepoError
      puts "Error: Not a git-lite repository."
      puts "Run 'git-lite init' to create one."
      exit(1)
    rescue => e
      puts "Error: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      exit(1)
    end

    def self.show_help
      puts "git-lite - A Git-like version control system backed by SQLite"
      puts ""
      puts "Usage: git-lite <command> [options]"
      puts ""
      puts "Commands:"
      COMMANDS.each do |cmd, desc|
        puts "  #{cmd.ljust(10)} #{desc}"
      end
    end

    def self.run_init(args)
      path = args.first || Dir.pwd
      path = File.expand_path(path)

      pgit_dir = File.join(path, '.git-lite')

      if File.directory?(pgit_dir)
        puts "Reinitialized existing git-lite repository in #{path}"
      else
        Dir.mkdir(pgit_dir)
        puts "Initialized empty git-lite repository in #{path}"
      end

      config = Config.new(path)
      config.save

      db_path = File.join(pgit_dir, 'repo.db')
      db = DB.new(db_path).connect
      db.init_schema
      db.set_repo_path(path)
      db.close

      puts "Database initialized at #{db_path}"
    end

    def self.run_add(args)
      repo = Repo.open

      if args.empty?
        puts "Nothing specified, nothing added."
        puts "hint: Use 'git-lite add <file>...' to add files"
        return
      end

      files = expand_paths(args)

      files.each do |file|
        repo.stage_file(file)
        puts "Staged: #{file}"
      end
    end

    def self.run_rm(args)
      repo = Repo.open

      if args.empty?
        puts "Nothing specified, nothing removed."
        return
      end

      files = expand_paths(args)

      files.each do |file|
        repo.stage_deletion(file)
        puts "Removed: #{file}"
      end
    end

    def self.run_mv(args)
      if args.length != 2
        puts "Usage: git-lite mv <source> <destination>"
        exit(1)
      end

      repo = Repo.open
      source, dest = args

      repo.move_file(source, dest)
      puts "Renamed: #{source} -> #{dest}"
    end

    def self.run_status(args)
      repo = Repo.open

      puts "On branch #{repo.current_branch}"
      puts ""

      staged = repo.staged_changes
      unstaged = repo.unstaged_changes
      untracked = repo.untracked_files

      unless staged.empty?
        puts "Changes to be committed:"
        staged.each do |change|
          puts "  #{format_status(change[:status])}    #{change[:path]}"
        end
        puts ""
      end

      unless unstaged.empty?
        puts "Changes not staged for commit:"
        unstaged.each do |change|
          puts "  #{format_status(change[:status])}    #{change[:path]}"
        end
        puts ""
      end

      unless untracked.empty?
        puts "Untracked files:"
        untracked.each { |f| puts "  #{f}" }
        puts ""
      end

      if staged.empty? && unstaged.empty? && untracked.empty?
        puts "Nothing to commit, working tree clean"
      end
    end

    def self.run_commit(args)
      repo = Repo.open

      message = nil
      if args.include?('-m')
        idx = args.index('-m')
        message = args[idx + 1]
      end

      if message.nil? || message.empty?
        puts "Aborting commit due to empty commit message."
        puts "Use -m 'message' to specify a commit message."
        exit(1)
      end

      commit_id = repo.commit(message)
      puts "[#{repo.current_branch} #{commit_id[0..7]}] #{message.split("\n").first}"
    end

    def self.run_log(args)
      repo = Repo.open
      limit = 50

      if args.include?('-n')
        idx = args.index('-n')
        limit = args[idx + 1].to_i if args[idx + 1]
      end

      commits = repo.log(limit)

      commits.each do |commit|
        puts "#{UI.color(:yellow)}commit #{commit[:id]}#{UI.reset}"
        puts "Author: #{commit[:author_name]} <#{commit[:author_email]}>"
        puts "Date:   #{commit[:authored_at].strftime('%a %b %d %H:%M:%S %Y %z')}"
        puts ""
        puts "    #{commit[:message].gsub("\n", "\n    ")}"
        puts ""
      end
    end

    def self.run_diff(args)
      repo = Repo.open

      diff = repo.diff_working_tree

      diff.each do |file_diff|
        puts "#{UI.color(:cyan)}diff --git a/#{file_diff[:path]} b/#{file_diff[:path]}#{UI.reset}"
        puts file_diff[:diff]
      end
    end

    def self.run_show(args)
      repo = Repo.open
      commit_id = args.first || repo.head

      commit = repo.get_commit(commit_id)

      unless commit
        puts "Error: Commit not found: #{commit_id}"
        exit(1)
      end

      puts "#{UI.color(:yellow)}commit #{commit[:id]}#{UI.reset}"
      puts "Author: #{commit[:author_name]} <#{commit[:author_email]}>"
      puts "Date:   #{commit[:authored_at].strftime('%a %b %d %H:%M:%S %Y %z')}"
      puts ""
      puts "    #{commit[:message].gsub("\n", "\n    ")}"
      puts ""

      blobs = repo.db.get_blobs_at_commit(commit[:id])
      puts "#{blobs.length} file(s) changed"
    end

    def self.run_checkout(args)
      repo = Repo.open

      if args.empty?
        puts "Usage: git-lite checkout <commit>"
        exit(1)
      end

      target = args.first
      repo.checkout(target)
      puts "Checked out: #{target}"
    end

    def self.run_branch(args)
      repo = Repo.open

      if args.empty?
        branches = repo.branches
        branches.each do |branch|
          marker = branch == repo.current_branch ? '* ' : '  '
          puts "#{marker}#{branch}"
        end
      else
        branch_name = args.first
        repo.create_branch(branch_name)
        puts "Created branch: #{branch_name}"
      end
    end

    def self.run_reset(args)
      repo = Repo.open
      repo.reset_staging
      puts "Staging area reset."
    end

    def self.run_import(args)
      if args.empty?
        puts "Usage: git-lite import <git-repo-path>"
        exit(1)
      end

      git_path = File.expand_path(args.first)
      branch = 'main'

      if args.include?('--branch')
        idx = args.index('--branch')
        branch = args[idx + 1] if args[idx + 1]
      end

      repo = Repo.open

      puts "Importing from: #{git_path}"
      puts "Branch: #{branch}"

      importer = GitImporter.new(repo, git_path)
      count = importer.import_branch(branch)

      puts ""
      puts "Successfully imported #{count} commits"
    end

    def self.run_clone(args)
      if args.empty?
        puts "Usage: git-lite clone <url> [directory]"
        exit(1)
      end

      url = args[0]
      dir = args[1] || File.basename(url, '.*')

      puts "Cloning into '#{dir}'..."

      Dir.mkdir(dir)
      Dir.chdir(dir) do
        run_init([])
        puts "Note: Remote cloning not fully implemented in git-lite"
      end
    end

    def self.run_push(args)
      puts "Push not implemented in git-lite."
      puts "git-lite uses SQLite files that can be copied directly."
    end

    def self.run_pull(args)
      puts "Pull not implemented in git-lite."
      puts "git-lite uses SQLite files that can be copied directly."
    end

    def self.run_remote(args)
      repo = Repo.open

      if args.empty?
        repo.config.remotes.each do |name, url|
          puts "#{name}\t#{url}"
        end
      elsif args[0] == 'add'
        if args.length < 3
          puts "Usage: git-lite remote add <name> <url>"
          exit(1)
        end
        repo.config.add_remote(args[1], args[2])
        puts "Added remote: #{args[1]}"
      elsif args[0] == 'rm'
        repo.config.remove_remote(args[1])
        puts "Removed remote: #{args[1]}"
      end
    end

    def self.run_config(args)
      repo = begin
        Repo.open
      rescue
        nil
      end

      if args.empty?
        puts "Usage: git-lite config <key> [value]"
        exit(1)
      end

      key = args[0]

      if args.length == 1
        value = if repo
          repo.config.get(key)
        else
          Config.global.get(key)
        end
        puts value if value
      else
        value = args[1]
        if repo
          repo.config.set(key, value)
        else
          Config.global.set(key, value)
        end
      end
    end

    def self.run_stats(args)
      repo = Repo.open
      stats = repo.db.get_stats

      puts "Repository Statistics"
      puts "=" * 30
      puts "Commits:      #{stats[:commits]}"
      puts "Paths:        #{stats[:paths]}"
      puts "File refs:    #{stats[:file_refs]}"
      puts "Content size: #{Util.format_bytes(stats[:content_size])}"

      db_size = File.size(File.join(repo.pgit_path, 'repo.db'))
      puts ""
      puts "Database:     #{Util.format_bytes(db_size)}"
    end

    def self.run_sql(args)
      if args.empty?
        puts "Usage: git-lite sql <query>"
        exit(1)
      end

      repo = Repo.open
      query = args.join(' ')

      begin
        rows = repo.db.execute(query)

        if rows.empty?
          puts "No results."
          return
        end

        headers = rows.first.keys
        puts headers.join(' | ')
        puts '-' * (headers.join(' | ').length)

        rows.each do |row|
          puts headers.map { |h| row[h].to_s }.join(' | ')
        end
      rescue => e
        puts "SQL Error: #{e.message}"
      end
    end

    def self.run_gc(args)
      repo = Repo.open

      puts "Running garbage collection with delta compression..."

      paths = repo.db.execute("SELECT DISTINCT path_id FROM content_meta ORDER BY path_id")

      total_paths = paths.length
      processed = 0
      deltas_created = 0
      bytes_saved = 0

      paths.each do |row|
        path_id = row['path_id']

        versions = repo.db.execute(
          "SELECT cm.version_id, c.data FROM content_meta cm JOIN content c ON c.path_id = cm.path_id AND c.version_id = cm.version_id WHERE cm.path_id = ? ORDER BY cm.version_id",
          [path_id]
        )

        next if versions.length < 2

        last_keyframe_content = nil
        last_keyframe_version = nil

        versions.each_with_index do |v, idx|
          version_id = v['version_id']
          data = v['data']

          flags = data.getbyte(0)
          is_compressed = (flags & 0x02) != 0
          raw_content = data[1..-1]

          if is_compressed
            begin
              raw_content = Zlib.inflate(raw_content)
            rescue => e
              # Keep as-is if decompression fails
            end
          end

          should_be_keyframe = (idx == 0) || (version_id % 100 == 0)

          if should_be_keyframe
            last_keyframe_content = raw_content
            last_keyframe_version = version_id

            repo.db.execute(
              "UPDATE content_meta SET is_keyframe = 1, base_version = NULL WHERE path_id = ? AND version_id = ?",
              [path_id, version_id]
            ) unless idx == 0
          elsif last_keyframe_content && raw_content.length > 100
            delta = Delta.create(last_keyframe_content, raw_content)

            if delta && delta.bytesize < raw_content.bytesize * 0.75
              final_data = delta
              final_flags = 0x00

              if delta.bytesize > 100
                compressed = Zlib.deflate(delta)
                if compressed.bytesize < delta.bytesize * 0.9
                  final_data = compressed
                  final_flags = 0x02
                end
              end

              packed = [final_flags].pack('C') + final_data

              repo.db.execute(
                "UPDATE content SET data = ? WHERE path_id = ? AND version_id = ?",
                [packed, path_id, version_id]
              )

              repo.db.execute(
                "UPDATE content_meta SET is_keyframe = 0, base_version = ? WHERE path_id = ? AND version_id = ?",
                [last_keyframe_version, path_id, version_id]
              )

              deltas_created += 1
              bytes_saved += (raw_content.bytesize - packed.bytesize)
            end
          end
        end

        processed += 1
        puts "  Processed #{processed}/#{total_paths} paths (#{deltas_created} deltas)" if processed % 20 == 0
      end

      puts "  Processed #{processed}/#{total_paths} paths (#{deltas_created} deltas)"
      puts "Vacuuming database..."
      repo.db.execute("VACUUM")

      puts ""
      puts "GC complete: #{deltas_created} deltas created, #{Util.format_bytes(bytes_saved)} saved"
    end

    def self.run_clean(args)
      repo = Repo.open

      untracked = repo.untracked_files

      if untracked.empty?
        puts "Nothing to clean."
        return
      end

      if args.include?('-f') || args.include?('--force')
        untracked.each do |file|
          File.delete(file)
          puts "Removed: #{file}"
        end
      else
        puts "Would remove:"
        untracked.each { |f| puts "  #{f}" }
        puts ""
        puts "Use -f or --force to actually remove files."
      end
    end

    # Helper methods

    def self.expand_paths(args)
      files = []
      args.each do |arg|
        if arg == '.'
          files.concat(list_all_files(Dir.pwd))
        elsif arg.include?('*')
          # Simple glob - list matching files
          files.concat(list_all_files(Dir.pwd).select { |f| File.fnmatch(arg, f) })
        else
          files << arg
        end
      end
      files.select { |f| File.exist?(f) }.uniq
    end

    def self.list_all_files(dir)
      result = []
      entries = begin
        Dir.entries(dir)
      rescue
        []
      end

      entries.each do |entry|
        next if entry == '.' || entry == '..'
        next if entry.start_with?('.git-lite')
        full = File.join(dir, entry)
        if File.directory?(full)
          result.concat(list_all_files(full).map { |f| File.join(entry, f) })
        elsif File.file?(full)
          result << entry
        end
      end

      result
    end

    def self.format_status(status)
      colors = {
        added: :green,
        modified: :yellow,
        deleted: :red,
        untracked: :cyan
      }

      labels = {
        added: 'A',
        modified: 'M',
        deleted: 'D',
        untracked: '?'
      }

      UI.color(colors[status]) + labels[status] + UI.reset
    end
  end
end
GitLite::CLI.run(ARGV)
