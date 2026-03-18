# mruby Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port git-lite from CRuby to pure mruby so it compiles into a standalone binary with zero external dependencies.

**Architecture:** Create a `mruby` branch that diverges from `main`. Replace all CRuby-specific stdlib calls (fileutils, json, digest, securerandom, open3, encoding, set, stringio, minitest) with mruby-compatible equivalents. Add a `build_config.rb` declaring all mruby gem dependencies. Adapt the DB layer to work with mattn/mruby-sqlite3's simpler API. Port all 14 test files to mruby-mtest.

**Tech Stack:** mruby 3.x, mruby-sqlite3, mruby-zlib, mruby-json, mruby-sha2, mruby-io, mruby-dir, mruby-env, mruby-errno, mruby-mtest, mruby-time-strftime, mruby-pack

---

## Dependency Mapping

| CRuby | mruby Replacement | Gem Source |
|---|---|---|
| `sqlite3` gem | `mruby-sqlite3` | `mgem: mruby-sqlite3` (mattn) |
| `Zlib` | `mruby-zlib` | `mgem: mruby-zlib` (mattn) |
| `Digest::SHA256` | `mruby-sha2` | `github: user/mruby-sha2` or `mruby-digest` |
| `SecureRandom` | `mruby-random` (built-in) | Built into mruby core |
| `JSON` | `mruby-json` | `mgem: mruby-json` (mattn) |
| `FileUtils` | `mruby-dir` + manual | `mgem: mruby-dir` |
| `Open3` | `mruby-io` (`IO.popen`) | `mgem: mruby-io` |
| `Time.parse` / `iso8601` | `mruby-time-strftime` + manual | `mgem: mruby-time-strftime` |
| `Encoding` | Remove (mruby strings are bytes) | N/A |
| `StringIO` | `mruby-stringio` | `mgem: mruby-stringio` |
| `Dir.mktmpdir` | Manual tmpdir creation | N/A |
| `File.binread/binwrite` | `File.open` with `'rb'`/`'wb'` | mruby-io |
| `Set` | `Array` or `Hash` | N/A |
| `Minitest` | `mruby-mtest` | `mgem: mruby-mtest` |
| `SQLite3::Blob` | Raw string | N/A |
| `String#unpack1` | `String#unpack[0]` | N/A |
| `String#encode` | Remove/replace | N/A |
| `ENV` | `mruby-env` | `mgem: mruby-env` |
| `Errno` | `mruby-errno` | `mgem: mruby-errno` |

## mruby-sqlite3 API Differences

The mattn/mruby-sqlite3 gem has a **different API** from the CRuby sqlite3 gem:

```ruby
# CRuby style (current code):
db = SQLite3::Database.new(path)
db.results_as_hash = true        # NOT available in mruby
db.type_translation = true       # NOT available in mruby
db.busy_timeout = 5000           # NOT available in mruby
row = db.get_first_row(sql, id)  # NOT available in mruby
val = db.get_first_value(sql)    # NOT available in mruby
db.last_insert_row_id            # NOT available in mruby
stmt = db.prepare(sql)           # NOT available in mruby
db.transaction { }               # NOT available in mruby

# mruby-sqlite3 style (what we need):
db = SQLite3::Database.new(path)
db.execute(sql)                  # Returns Array of Arrays
db.execute(sql, [param1, ...])   # Parameterized queries
# That's basically it - no hash mode, no prepared statements
```

**Strategy:** Create a `SQLiteWrapper` class in `lib/git-lite/sqlite_wrapper.rb` that wraps `mruby-sqlite3` and provides helper methods like `get_first_row`, `get_first_value`, `last_insert_row_id`, `transaction`, etc. Query results are converted to hashes using column names from a `PRAGMA table_info` cache or by parsing the SQL.

## File Structure

### New files to create:
- `build_config.rb` — mruby build configuration declaring all mgems
- `lib/git-lite/mruby_compat.rb` — Compatibility shims (FileUtils, SecureRandom, etc.)
- `lib/git-lite/sqlite_wrapper.rb` — SQLite3 wrapper providing hash-based results
- `mrblib/git-lite.rb` — mruby entry point (combines all sources for mrbc)
- `test/mruby_test_helper.rb` — mruby-mtest based test setup
- `Rakefile` — Rewritten for mruby build + test tasks

### Files to modify (all existing lib/ and test/ files):
- `lib/git-lite.rb` — Remove CRuby requires, add mruby compat
- `lib/git-lite/util.rb` — Replace Digest::SHA256, SecureRandom, Encoding
- `lib/git-lite/config.rb` — Replace JSON (API-compatible, minimal changes)
- `lib/git-lite/db.rb` — Major rewrite for mruby-sqlite3 API
- `lib/git-lite/repo.rb` — Replace FileUtils, File.binread, Set, SecureRandom
- `lib/git-lite/delta.rb` — Replace Encoding, String#unpack1
- `lib/git-lite/content_store.rb` — Adapt to new DB wrapper
- `lib/git-lite/ui.rb` — Minimal changes (already mostly compatible)
- `lib/git-lite/cli.rb` — Replace Zlib references, SQLite3::Blob
- `lib/git-lite/git_importer.rb` — Replace Open3, Encoding, SecureRandom
- All 14 test files — Port from Minitest to mruby-mtest

---

## Task 1: Create mruby branch and build_config.rb

**Files:**
- Create: `build_config.rb`

- [ ] **Step 1: Create the mruby branch**

```bash
cd /Users/lavoixduchatartiste/Boxes/ChatArtiste/git-lite
git checkout -b mruby
```

- [ ] **Step 2: Create build_config.rb**

```ruby
# build_config.rb - mruby build configuration for git-lite
MRuby::Build.new do |conf|
  toolchain :clang

  # Core gems
  conf.gembox 'default'

  # File I/O
  conf.gem mgem: 'mruby-io'
  conf.gem mgem: 'mruby-dir'
  conf.gem mgem: 'mruby-dir-glob'
  conf.gem mgem: 'mruby-env'
  conf.gem mgem: 'mruby-errno'

  # Data formats
  conf.gem mgem: 'mruby-json'
  conf.gem mgem: 'mruby-pack'

  # Crypto / Compression
  conf.gem mgem: 'mruby-sha2'
  conf.gem mgem: 'mruby-zlib'

  # Database
  conf.gem mgem: 'mruby-sqlite3'

  # Time formatting
  conf.gem mgem: 'mruby-time-strftime'

  # Testing
  conf.gem mgem: 'mruby-mtest'
  conf.gem mgem: 'mruby-stringio'

  # Enable debug for development
  conf.enable_debug
  conf.enable_test
end
```

- [ ] **Step 3: Commit**

```bash
git add build_config.rb
git commit -m "feat(mruby): add build_config.rb with mruby gem dependencies"
```

---

## Task 2: Create mruby_compat.rb (compatibility shims)

**Files:**
- Create: `lib/git-lite/mruby_compat.rb`

This file provides all the missing stdlib functionality for mruby.

- [ ] **Step 1: Write mruby_compat.rb**

```ruby
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/mruby_compat.rb
git commit -m "feat(mruby): add compatibility shims for SecureRandom, FileUtils, Time, etc."
```

---

## Task 3: Create SQLite wrapper for mruby-sqlite3

**Files:**
- Create: `lib/git-lite/sqlite_wrapper.rb`

- [ ] **Step 1: Write sqlite_wrapper.rb**

```ruby
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
```

- [ ] **Step 2: Write a quick test for the wrapper**

Create `test/sqlite_wrapper_test.rb`:

```ruby
# Test SQLite wrapper
class SQLiteWrapperTest < MTest::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir('gl-test')
    @db_path = "#{@tmpdir}/test.db"
    @wrapper = GitLite::SQLiteWrapper.new(@db_path).connect
    @wrapper.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, value TEXT)")
  end

  def teardown
    @wrapper.close if @wrapper
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  def test_execute_insert_and_select
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    rows = @wrapper.execute("SELECT * FROM test")
    assert_equal 1, rows.length
    assert_equal 'key1', rows[0]['name']
  end

  def test_get_first_row
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    row = @wrapper.get_first_row("SELECT * FROM test WHERE name = ?", 'key1')
    assert_equal 'key1', row['name']
    assert_equal 'val1', row['value']
  end

  def test_get_first_value
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    val = @wrapper.get_first_value("SELECT value FROM test WHERE name = ?", 'key1')
    assert_equal 'val1', val
  end

  def test_get_first_row_returns_nil_for_missing
    row = @wrapper.get_first_row("SELECT * FROM test WHERE name = ?", 'missing')
    assert_nil row
  end

  def test_last_insert_row_id
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    id = @wrapper.last_insert_row_id
    assert_equal 1, id.to_i
  end

  def test_transaction_commits
    @wrapper.transaction do
      @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['k1', 'v1'])
      @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['k2', 'v2'])
    end
    val = @wrapper.get_first_value("SELECT COUNT(*) FROM test")
    assert_equal 2, val.to_i
  end

  def test_transaction_rolls_back_on_error
    begin
      @wrapper.transaction do
        @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['k1', 'v1'])
        raise "test error"
      end
    rescue
    end
    val = @wrapper.get_first_value("SELECT COUNT(*) FROM test")
    assert_equal 0, val.to_i
  end
end

MTest::Unit.new.run
```

- [ ] **Step 3: Commit**

```bash
git add lib/git-lite/sqlite_wrapper.rb test/sqlite_wrapper_test.rb
git commit -m "feat(mruby): add SQLite wrapper with hash-based results for mruby-sqlite3"
```

---

## Task 4: Port lib/git-lite.rb (main module)

**Files:**
- Modify: `lib/git-lite.rb`

- [ ] **Step 1: Rewrite lib/git-lite.rb for mruby**

```ruby
# git-lite - A Git-like version control system backed by SQLite
# mruby-compatible version

require_relative 'git-lite/mruby_compat'

module GitLite
  VERSION = '1.0.0'

  class Error < StandardError; end
  class NotARepoError < Error; end
  class AlreadyInitializedError < Error; end

  def self.root
    @root ||= find_root(Dir.pwd)
  end

  def self.find_root(path)
    return nil if path == '/'

    if File.directory?(File.join(path, '.git-lite'))
      return path
    end

    find_root(File.dirname(path))
  end

  def self.pgit_path
    root ? File.join(root, '.git-lite') : nil
  end
end

require_relative 'git-lite/sqlite_wrapper'
require_relative 'git-lite/util'
require_relative 'git-lite/config'
require_relative 'git-lite/db'
require_relative 'git-lite/repo'
require_relative 'git-lite/ui'
require_relative 'git-lite/delta'
require_relative 'git-lite/content_store'
require_relative 'git-lite/git_importer'
require_relative 'git-lite/cli'
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite.rb
git commit -m "refactor(mruby): port main module to mruby, add compat and wrapper requires"
```

---

## Task 5: Port lib/git-lite/util.rb

**Files:**
- Modify: `lib/git-lite/util.rb`

- [ ] **Step 1: Rewrite util.rb for mruby**

Remove `require 'digest'`. Replace `Digest::SHA256` with the shim. Replace `SecureRandom.alphanumeric` with the shim. Remove encoding operations.

```ruby
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/util.rb
git commit -m "refactor(mruby): port util.rb - remove CRuby-specific digest/encoding"
```

---

## Task 6: Port lib/git-lite/db.rb

**Files:**
- Modify: `lib/git-lite/db.rb`

This is the largest change. Replace `SQLite3::Database` with `SQLiteWrapper`. Remove `Zlib` direct references (use `mruby-zlib` which has same API). Remove `SQLite3::Blob`. Remove `SQLite3::Exception`.

- [ ] **Step 1: Rewrite db.rb for mruby**

Key changes:
- `@db = SQLite3::Database.new` → `@wrapper = SQLiteWrapper.new(path).connect`
- `@db.results_as_hash = true` → removed (wrapper handles this)
- `@db.busy_timeout = 5000` → handled in wrapper's connect
- `@db.get_first_row` → `@wrapper.get_first_row`
- `@db.get_first_value` → `@wrapper.get_first_value`
- `@db.execute` → `@wrapper.execute`
- `@db.prepare` → `@wrapper.prepare`
- `@db.transaction` → `@wrapper.transaction`
- `@db.last_insert_row_id` → `@wrapper.last_insert_row_id`
- `SQLite3::Blob.new(packed)` → `packed` (raw string)
- `rescue SQLite3::Exception` → `rescue StandardError`
- `Time.parse(row['authored_at'])` → uses compat shim

```ruby
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
      @wrapper&.close
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
      tables = ['metadata', 'sync_state', 'refs', 'file_refs', 'content', 'paths', 'commits']
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/db.rb
git commit -m "refactor(mruby): port db.rb to use SQLiteWrapper instead of CRuby sqlite3 gem"
```

---

## Task 7: Port lib/git-lite/delta.rb

**Files:**
- Modify: `lib/git-lite/delta.rb`

- [ ] **Step 1: Rewrite delta.rb for mruby**

Changes: Remove `Encoding::BINARY` references, replace `String.new(encoding: ...)` with plain `String.new` or `""`, replace `unpack1` with `unpack[0]`.

```ruby
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/delta.rb
git commit -m "refactor(mruby): port delta.rb - remove Encoding, use mruby-compatible string ops"
```

---

## Task 8: Port lib/git-lite/config.rb

**Files:**
- Modify: `lib/git-lite/config.rb`

- [ ] **Step 1: Rewrite config.rb for mruby**

Remove `require 'json'` (loaded via mruby gem). Replace `JSON::ParserError` with `StandardError`. mruby-json's API is compatible with CRuby JSON for `parse` and `generate`.

```ruby
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
```

Note: `symbolize_names: true` is not available in mruby-json, so we switch to string keys.

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/config.rb
git commit -m "refactor(mruby): port config.rb - use string keys for JSON, replace error classes"
```

---

## Task 9: Port lib/git-lite/repo.rb

**Files:**
- Modify: `lib/git-lite/repo.rb`

- [ ] **Step 1: Rewrite repo.rb for mruby**

Changes: Remove `require` statements. Replace `File.binread`/`File.binwrite` with compat shims. Replace `Set` with `Hash` (`.to_set` from compat returns a Hash). Replace `File.stat().mode` with simplified mode. Use string keys for staging JSON. Replace `Dir.glob` with mruby-dir-glob compatible call.

```ruby
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
      @db&.close
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/repo.rb
git commit -m "refactor(mruby): port repo.rb - replace FileUtils, Set, encoding, Dir.glob"
```

---

## Task 10: Port lib/git-lite/content_store.rb

**Files:**
- Modify: `lib/git-lite/content_store.rb`

- [ ] **Step 1: Rewrite content_store.rb for mruby**

The ContentStore needs to work with the new wrapper. The `create_schema` method receives the wrapper now. Replace `@db.instance_variable_get(:@db)` with proper transaction.

```ruby
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/content_store.rb
git commit -m "refactor(mruby): port content_store.rb to use wrapper and mruby-compatible APIs"
```

---

## Task 11: Port lib/git-lite/ui.rb (minimal changes)

**Files:**
- Modify: `lib/git-lite/ui.rb`

- [ ] **Step 1: Rewrite ui.rb for mruby**

This file is already mostly mruby-compatible. Only change: replace `gsub` regex with simpler approach if needed. mruby has regex support via `mruby-regexp-pcre` or built-in `mruby-onig-regexp`. The default gembox includes regex.

```ruby
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/ui.rb
git commit -m "refactor(mruby): port ui.rb - replace regex-based format_count, use mruby iterators"
```

---

## Task 12: Port lib/git-lite/cli.rb

**Files:**
- Modify: `lib/git-lite/cli.rb`

- [ ] **Step 1: Rewrite cli.rb for mruby**

Changes: Remove `SQLite3::Blob.new` references (use raw strings). Replace `Zlib.deflate`/`Zlib.inflate` (same API via mruby-zlib). Adjust `expand_paths` to not use `File::FNM_DOTMATCH`.

The full rewrite follows the same structure but with:
- `SQLite3::Blob.new(packed)` → `packed`
- `rescue => e` stays the same
- `Dir.glob('**/*', File::FNM_DOTMATCH)` → manual recursive listing
- `exit 1` → `exit(1)` (mruby syntax)

(Full file: same as original with the above substitutions. The main changes are in `run_gc` where `SQLite3::Blob.new` is used, and in `expand_paths` where `Dir.glob` is used.)

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/cli.rb
git commit -m "refactor(mruby): port cli.rb - remove SQLite3::Blob, replace Dir.glob"
```

---

## Task 13: Port lib/git-lite/git_importer.rb

**Files:**
- Modify: `lib/git-lite/git_importer.rb`

- [ ] **Step 1: Rewrite git_importer.rb for mruby**

Changes: Replace `Open3.capture3` with `IO.popen` + process exit check. Remove `.force_encoding` calls (no-op via compat). Remove `.encode` calls (no-op via compat).

```ruby
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

      # Use IO.popen instead of Open3
      cmd = "cd '#{@git_path}' && git fast-export --reencode=yes --show-original-ids #{branch} 2>/dev/null"
      stdout = `#{cmd}`

      unless $?.success?
        raise "Failed to export git history"
      end

      parse_fast_export(stdout)
    end

    # ... (rest of the file is identical to original but without
    #      .force_encoding and .encode calls, which are no-ops via compat shims)
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/git-lite/git_importer.rb
git commit -m "refactor(mruby): port git_importer.rb - replace Open3 with backtick exec"
```

---

## Task 14: Port test framework and test_helper.rb

**Files:**
- Modify: `test/test_helper.rb`
- Create: `test/mruby_test_helper.rb`

- [ ] **Step 1: Rewrite test_helper.rb for mruby-mtest**

mruby-mtest provides `MTest::Unit::TestCase` which is API-compatible with Minitest. Replace `Minitest::Test` with `MTest::Unit::TestCase`.

```ruby
# test/test_helper.rb - mruby-mtest based test setup

$LOAD_PATH.unshift File.expand_path('../lib', __dir__) if defined?($LOAD_PATH)

require 'git-lite'

module GitLite
  class TestCase < MTest::Unit::TestCase
    def setup
      @tmpdir = Dir.mktmpdir('git-lite-test')
      @original_dir = Dir.pwd
      Dir.chdir(@tmpdir)
    end

    def teardown
      Dir.chdir(@original_dir)
      FileUtils.rm_rf(@tmpdir)
    end

    def create_test_file(path, content = "test content")
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) if path.include?('/')
      File.write(path, content)
    end

    def capture_io
      old_stdout = $stdout
      $stdout = StringIO.new
      yield
      [$stdout.string, '']
    ensure
      $stdout = old_stdout
    end

    def assert_in_delta(expected, actual, delta = 0.001)
      assert (expected - actual).abs <= delta,
        "Expected #{expected} to be within #{delta} of #{actual}"
    end

    def assert_includes(collection, item, msg = nil)
      assert collection.include?(item), msg || "Expected collection to include #{item}"
    end

    def refute_includes(collection, item, msg = nil)
      refute collection.include?(item), msg || "Expected collection to not include #{item}"
    end

    def assert_empty(collection, msg = nil)
      assert collection.empty?, msg || "Expected collection to be empty"
    end

    def assert_instance_of(klass, obj, msg = nil)
      assert obj.is_a?(klass), msg || "Expected #{obj.class} to be #{klass}"
    end

    def assert_match(pattern, string, msg = nil)
      if pattern.is_a?(String)
        assert string.include?(pattern), msg || "Expected '#{string}' to match '#{pattern}'"
      else
        assert pattern.match(string), msg || "Expected '#{string}' to match #{pattern}"
      end
    end

    def assert_nil(obj, msg = nil)
      assert obj.nil?, msg || "Expected nil but got #{obj.inspect}"
    end

    def refute_nil(obj, msg = nil)
      refute obj.nil?, msg || "Expected non-nil"
    end

    def assert_raises(exception_class = StandardError)
      begin
        yield
        assert false, "Expected #{exception_class} to be raised"
      rescue => e
        if exception_class
          assert e.is_a?(exception_class), "Expected #{exception_class} but got #{e.class}: #{e.message}"
        end
      end
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add test/test_helper.rb
git commit -m "refactor(mruby): port test_helper.rb to mruby-mtest framework"
```

---

## Task 15: Port all test files to mruby-mtest

**Files:**
- Modify: all 14 `test/*_test.rb` files

Each test file needs these changes:
1. Replace `class XxxTest < Minitest::Test` → `class XxxTest < MTest::Unit::TestCase` (or keep inheriting from `GitLite::TestCase`)
2. Add `MTest::Unit.new.run` at the bottom of each file
3. Replace `refute` where needed (mruby-mtest supports it)
4. Replace `assert_equal` (supported in mruby-mtest)
5. Replace `(0..255).to_a.pack('C*')` → manual binary string construction if `pack` needs adjusting
6. Remove `Encoding` references in test strings
7. Fix `symbolize_names: true` in JSON parsing (use string keys)

- [ ] **Step 1: Port each test file**

Each test file gets the same treatment. Key patterns:

```ruby
# At top of each test file:
require_relative 'test_helper'

# Class definition stays mostly the same
class UtilTest < GitLite::TestCase  # or MTest::Unit::TestCase
  # ... tests ...
end

# At bottom of each file, add:
MTest::Unit.new.run
```

- [ ] **Step 2: Create a test runner script**

Create `test/run_all.rb`:

```ruby
# Run all mruby tests
Dir.glob(File.join(File.dirname(__FILE__), '*_test.rb')).sort.each do |test_file|
  puts "Running #{File.basename(test_file)}..."
  require test_file
end
```

- [ ] **Step 3: Commit**

```bash
git add test/
git commit -m "refactor(mruby): port all test files to mruby-mtest framework"
```

---

## Task 16: Update Rakefile for mruby build

**Files:**
- Modify: `Rakefile`

- [ ] **Step 1: Rewrite Rakefile for mruby**

```ruby
# Rakefile for git-lite (mruby build)

MRUBY_DIR = ENV['MRUBY_DIR'] || File.expand_path('~/mruby')

desc "Build git-lite with mruby"
task :build do
  unless File.directory?(MRUBY_DIR)
    puts "mruby not found at #{MRUBY_DIR}"
    puts "Set MRUBY_DIR environment variable or install mruby"
    exit 1
  end

  # Copy build_config.rb to mruby dir
  cp 'build_config.rb', File.join(MRUBY_DIR, 'build_config.rb')

  # Build mruby with our config
  Dir.chdir(MRUBY_DIR) do
    sh 'rake'
  end

  puts "Build complete!"
end

desc "Run all tests with mruby"
task :test do
  test_files = Dir['test/*_test.rb'].sort
  failures = 0

  test_files.each do |f|
    puts "\n=== #{File.basename(f)} ==="
    unless system("mruby -I lib -I test #{f}")
      failures += 1
    end
  end

  puts "\n#{test_files.length} test files, #{failures} failures"
  exit(1) if failures > 0
end

desc "Run unit tests only"
task :fast do
  tests = %w[util_test ui_test config_test db_test sqlite_wrapper_test]
  tests.each do |t|
    puts "\n=== #{t}.rb ==="
    system("mruby -I lib -I test test/#{t}.rb")
  end
end

desc "Run integration tests"
task :integration do
  tests = %w[integration_test git_importer_test edge_cases_test]
  tests.each do |t|
    puts "\n=== #{t}.rb ==="
    system("mruby -I lib -I test test/#{t}.rb")
  end
end

desc "Compile to standalone binary"
task :compile do
  # Concatenate all lib files into single source
  sources = %w[
    lib/git-lite/mruby_compat.rb
    lib/git-lite/sqlite_wrapper.rb
    lib/git-lite/util.rb
    lib/git-lite/config.rb
    lib/git-lite/db.rb
    lib/git-lite/repo.rb
    lib/git-lite/ui.rb
    lib/git-lite/delta.rb
    lib/git-lite/content_store.rb
    lib/git-lite/git_importer.rb
    lib/git-lite/cli.rb
  ]

  combined = sources.map { |f| File.read(f) }.join("\n")
  combined += "\nGitLite::CLI.run(ARGV)\n"

  File.write('build/git-lite-combined.rb', combined)

  # Compile with mrbc
  sh "mrbc -o build/git-lite.mrb build/git-lite-combined.rb"
  puts "Compiled to build/git-lite.mrb"
end

desc "Check syntax"
task :lint do
  Dir['lib/**/*.rb'].each do |f|
    sh "mruby -c #{f}"
  end
end

task default: :test
```

- [ ] **Step 2: Commit**

```bash
git add Rakefile
git commit -m "refactor(mruby): rewrite Rakefile for mruby build and test tasks"
```

---

## Task 17: Update bin/git-lite wrapper

**Files:**
- Modify: `bin/git-lite`
- Modify: `bin/git-lite.rb`

- [ ] **Step 1: Update wrapper script**

```bash
#!/bin/bash
# git-lite - A Git-like version control system backed by SQLite
# mruby version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try mruby first, fall back to system mruby
if command -v mruby &> /dev/null; then
    exec mruby -I "$SCRIPT_DIR/../lib" "$SCRIPT_DIR/git-lite.rb" "$@"
else
    echo "Error: mruby not found in PATH"
    echo "Install mruby or add it to your PATH"
    exit 1
fi
```

- [ ] **Step 2: Update entry point**

```ruby
#!/usr/bin/env mruby
# git-lite - Main entry point (mruby)

require 'git-lite'

GitLite::CLI.run(ARGV)
```

- [ ] **Step 3: Commit**

```bash
git add bin/git-lite bin/git-lite.rb
git commit -m "refactor(mruby): update bin wrappers for mruby runtime"
```

---

## Task 18: Integration testing and verification

- [ ] **Step 1: Run syntax check on all files**

```bash
mruby -c lib/git-lite.rb
mruby -c lib/git-lite/mruby_compat.rb
mruby -c lib/git-lite/sqlite_wrapper.rb
# ... all files
```

- [ ] **Step 2: Run unit tests**

```bash
rake fast
```

Expected: All unit tests pass.

- [ ] **Step 3: Run full test suite**

```bash
rake test
```

Expected: All tests pass (some may need tweaking based on mruby-sqlite3 behavior).

- [ ] **Step 4: Test the CLI end-to-end**

```bash
mkdir /tmp/test-mruby-repo && cd /tmp/test-mruby-repo
git-lite init
echo "hello" > test.txt
git-lite add test.txt
git-lite commit -m "first commit"
git-lite log
git-lite status
git-lite stats
```

Expected: All commands work.

- [ ] **Step 5: Fix any issues found**

Address any test failures or runtime errors.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat(mruby): complete mruby port - all tests passing"
```

---

## Known Risks and Mitigations

1. **mruby-sqlite3 API mismatch**: The wrapper may need tweaking based on the exact version of mattn/mruby-sqlite3. Test early with `Task 3`.

2. **BLOB handling**: mruby-sqlite3 may handle binary data differently than CRuby's `SQLite3::Blob`. May need to Base64-encode BLOBs if raw binary passing doesn't work.

3. **mruby-zlib availability**: If `mruby-zlib` (mattn) doesn't compile on your system, fallback is to disable compression (store everything as keyframes). This loses delta compression but everything still works.

4. **mruby-sha2 vs mruby-digest**: Multiple SHA256 implementations exist. The compat shim abstracts this so we can swap implementations.

5. **String handling**: mruby strings are byte strings (no encoding). This is actually simpler for a VCS tool that deals with binary data. The compat shims make `.force_encoding` and `.encode` no-ops.

6. **Dir.glob patterns**: mruby-dir-glob may not support all CRuby glob flags. The `glob_files` recursive implementation in repo.rb is a fallback.

7. **JSON pretty_generate**: mruby-json may not support `pretty_generate`. Fallback to `JSON.generate` (compact format). Config files won't be pretty-printed but will work.
