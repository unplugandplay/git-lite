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
        "INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, CAST(? AS BLOB))",
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
