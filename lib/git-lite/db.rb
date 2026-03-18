# Database layer for git-lite using SQLite

require 'sqlite3'

module GitLite
  class DB
    SCHEMA_VERSION = 1
    
    def initialize(db_path)
      @db_path = db_path
      @db = nil
    end
    
    def connect
      @db = SQLite3::Database.new(@db_path)
      @db.busy_timeout = 5000
      @db.results_as_hash = true
      @db.type_translation = true
      @db.execute("PRAGMA foreign_keys = ON")
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      self
    end
    
    def close
      @db&.close
      @db = nil
    end
    
    def connected?
      !@db.nil?
    end
    
    # Schema management
    def init_schema
      return if schema_exists?
      
      @db.transaction do
        create_metadata_table
        create_commits_table
        create_paths_table
        create_file_refs_table
        create_content_table
        create_refs_table
        create_sync_state_table
        ContentStore.create_schema(@db)
        set_schema_version(SCHEMA_VERSION)
      end
    end
    
    def content_store
      @content_store ||= ContentStore.new(self)
    end
    
    def schema_exists?
      result = @db.execute(<<-SQL)
        SELECT name FROM sqlite_master 
        WHERE type='table' AND name='commits'
      SQL
      result.length > 0
    end
    
    def get_schema_version
      return 0 unless schema_exists?
      result = @db.get_first_value("SELECT value FROM metadata WHERE key = 'schema_version'")
      result ? result.to_i : 0
    rescue SQLite3::Exception
      0
    end
    
    def set_schema_version(version)
      @db.execute(<<-SQL, ['schema_version', version.to_s])
        INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)
      SQL
    end
    
    def drop_schema
      tables = %w[metadata sync_state refs file_refs content paths commits]
      tables.each do |table|
        @db.execute("DROP TABLE IF EXISTS #{table}")
      end
    end
    
    # Table creation
    private
    
    def create_metadata_table
      @db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      SQL
    end
    
    def create_commits_table
      @db.execute(<<-SQL)
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
      
      @db.execute("CREATE INDEX IF NOT EXISTS idx_commits_parent ON commits(parent_id)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_commits_authored ON commits(authored_at DESC)")
    end
    
    def create_paths_table
      @db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS paths (
          path_id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INTEGER NOT NULL,
          path TEXT NOT NULL UNIQUE
        )
      SQL
      
      @db.execute("CREATE INDEX IF NOT EXISTS idx_paths_path ON paths(path)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_paths_group ON paths(group_id)")
    end
    
    def create_file_refs_table
      @db.execute(<<-SQL)
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
      
      @db.execute("CREATE INDEX IF NOT EXISTS idx_file_refs_commit ON file_refs(commit_id)")
      @db.execute("CREATE INDEX IF NOT EXISTS idx_file_refs_version ON file_refs(path_id, version_id)")
    end
    
    def create_content_table
      # Stores file content keyed by (path_id, version_id)
      @db.execute(<<-SQL)
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
      @db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS refs (
          name TEXT PRIMARY KEY,
          commit_id TEXT NOT NULL
        )
      SQL
    end
    
    def create_sync_state_table
      @db.execute(<<-SQL)
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
      @db.execute(<<-SQL, [
        commit[:id], commit[:parent_id], commit[:tree_hash], commit[:message],
        commit[:author_name], commit[:author_email], commit[:authored_at].iso8601,
        commit[:committer_name], commit[:committer_email], commit[:committed_at].iso8601
      ])
        INSERT INTO commits 
        (id, parent_id, tree_hash, message, author_name, author_email, 
         authored_at, committer_name, committer_email, committed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
    end
    
    def create_commits_batch(commits)
      return if commits.empty?
      
      @db.transaction do
        stmt = @db.prepare(<<-SQL)
          INSERT INTO commits 
          (id, parent_id, tree_hash, message, author_name, author_email, 
           authored_at, committer_name, committer_email, committed_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        
        commits.each do |c|
          stmt.execute([
            c[:id], c[:parent_id], c[:tree_hash], c[:message],
            c[:author_name], c[:author_email], c[:authored_at].iso8601,
            c[:committer_name], c[:committer_email], c[:committed_at].iso8601
          ])
        end
        stmt.close
      end
    end
    
    def get_commit(id)
      row = @db.get_first_row("SELECT * FROM commits WHERE id = ?", id)
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
      
      rows = @db.execute(<<-SQL, [head_id, limit])
        SELECT * FROM commits 
        WHERE id <= ?
        ORDER BY id DESC
        LIMIT ?
      SQL
      
      rows.map { |r| hash_to_commit(r) }
    end
    
    def commit_exists?(id)
      result = @db.get_first_value("SELECT 1 FROM commits WHERE id = ?", id)
      !result.nil?
    end
    
    def get_latest_commit_id
      @db.get_first_value("SELECT id FROM commits ORDER BY id DESC LIMIT 1")
    end
    
    def count_commits
      @db.get_first_value("SELECT COUNT(*) FROM commits").to_i
    end
    
    def delete_commits(commit_ids)
      return if commit_ids.empty?
      
      placeholders = commit_ids.map { '?' }.join(',')
      @db.execute("DELETE FROM commits WHERE id IN (#{placeholders})", commit_ids)
    end
    
    # Ref operations
    def get_ref(name)
      row = @db.get_first_row("SELECT * FROM refs WHERE name = ?", name)
      row ? { name: row['name'], commit_id: row['commit_id'] } : nil
    end
    
    def set_ref(name, commit_id)
      @db.execute(<<-SQL, [name, commit_id])
        INSERT OR REPLACE INTO refs (name, commit_id) VALUES (?, ?)
      SQL
    end
    
    def delete_ref(name)
      @db.execute("DELETE FROM refs WHERE name = ?", name)
    end
    
    def get_all_refs
      rows = @db.execute("SELECT * FROM refs ORDER BY name")
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
      # Try to get existing
      row = @db.get_first_row("SELECT path_id, group_id FROM paths WHERE path = ?", path)
      return [row['path_id'], row['group_id']] if row
      
      # Create new - if no group_id, use the next auto-increment as group_id
      if group_id.nil?
        max_group = @db.get_first_value("SELECT COALESCE(MAX(group_id), 0) FROM paths")
        group_id = max_group.to_i + 1
      end
      
      @db.execute("INSERT INTO paths (group_id, path) VALUES (?, ?)", [group_id, path])
      [@db.last_insert_row_id, group_id]
    end
    
    def get_path_id_and_group_id(path)
      row = @db.get_first_row("SELECT path_id, group_id FROM paths WHERE path = ?", path)
      row ? [row['path_id'], row['group_id']] : [nil, nil]
    end
    
    def get_path_by_id(path_id)
      @db.get_first_value("SELECT path FROM paths WHERE path_id = ?", path_id)
    end
    
    def get_all_paths
      @db.execute("SELECT path FROM paths ORDER BY path").map { |r| r['path'] }
    end
    
    # File ref operations
    def create_file_ref(ref)
      @db.execute(<<-SQL, [
        ref[:path_id], ref[:commit_id], ref[:version_id], ref[:content_hash],
        ref[:mode], ref[:is_symlink] ? 1 : 0, ref[:symlink_target],
        ref[:is_binary] ? 1 : 0
      ])
        INSERT INTO file_refs 
        (path_id, commit_id, version_id, content_hash, mode, is_symlink, symlink_target, is_binary)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
    end
    
    def create_file_refs_batch(refs)
      return if refs.empty?
      
      @db.transaction do
        stmt = @db.prepare(<<-SQL)
          INSERT INTO file_refs 
          (path_id, commit_id, version_id, content_hash, mode, is_symlink, symlink_target, is_binary)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        
        refs.each do |r|
          stmt.execute([
            r[:path_id], r[:commit_id], r[:version_id], r[:content_hash],
            r[:mode], r[:is_symlink] ? 1 : 0, r[:symlink_target],
            r[:is_binary] ? 1 : 0
          ])
        end
        stmt.close
      end
    end
    
    def get_file_ref(path_id, commit_id)
      row = @db.get_first_row(<<-SQL, [path_id, commit_id])
        SELECT fr.*, p.path, p.group_id 
        FROM file_refs fr
        JOIN paths p ON p.path_id = fr.path_id
        WHERE fr.path_id = ? AND fr.commit_id = ?
      SQL
      row ? hash_to_file_ref(row) : nil
    end
    
    def get_file_refs_at_commit(commit_id)
      rows = @db.execute(<<-SQL, commit_id)
        SELECT fr.*, p.path, p.group_id 
        FROM file_refs fr
        JOIN paths p ON p.path_id = fr.path_id
        WHERE fr.commit_id = ?
        ORDER BY p.path
      SQL
      rows.map { |r| hash_to_file_ref(r) }
    end
    
    def get_tree_at_commit(commit_id)
      # Get the latest version of each file at or before this commit
      rows = @db.execute(<<-SQL, commit_id)
        SELECT fr.*, p.path, p.group_id 
        FROM file_refs fr
        JOIN paths p ON p.path_id = fr.path_id
        WHERE fr.commit_id <= ?
        AND fr.path_id IN (
          SELECT path_id FROM file_refs 
          WHERE commit_id <= ? 
          GROUP BY path_id 
          HAVING MAX(commit_id) = fr.commit_id
        )
        AND fr.content_hash IS NOT NULL
        ORDER BY p.path
      SQL
      rows.map { |r| hash_to_file_ref(r) }
    end
    
    def get_next_version_id(group_id)
      result = @db.get_first_value(<<-SQL, group_id)
        SELECT COALESCE(MAX(fr.version_id), 0) + 1
        FROM file_refs fr
        JOIN paths p ON p.path_id = fr.path_id
        WHERE p.group_id = ?
      SQL
      result.to_i
    end
    
    # Content operations (with delta compression)
    def create_content(path_id, version_id, data)
      @db.execute(<<-SQL, [path_id, version_id, SQLite3::Blob.new(data)])
        INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, ?)
      SQL
    end
    
    def create_content_batch(contents)
      return if contents.empty?
      
      contents.each do |c|
        content_store.store(c[:path_id], c[:version_id], c[:data])
      end
    end
    
    def get_content(path_id, version_id)
      content_store.retrieve(path_id, version_id)
    end
    
    # Raw content access (for delta internal use)
    def get_content_raw(path_id, version_id)
      @db.get_first_value(
        "SELECT data FROM content WHERE path_id = ? AND version_id = ?",
        [path_id, version_id]
      )
    end
    
    # Blob operations (high-level)
    def create_blob(blob)
      path_id, group_id = get_or_create_path(blob[:path])
      version_id = get_next_version_id(group_id)
      
      # Create file ref
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
      
      # Create content (skip for deletions)
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
      @db.get_first_value("SELECT value FROM metadata WHERE key = ?", key)
    end
    
    def set_metadata(key, value)
      @db.execute(
        "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
        [key, value]
      )
    end
    
    def get_repo_path
      get_metadata('repo_path')
    end
    
    def set_repo_path(path)
      set_metadata('repo_path', path)
    end
    
    # Stats
    def get_stats
      base_stats = {
        commits: @db.get_first_value("SELECT COUNT(*) FROM commits").to_i,
        paths: @db.get_first_value("SELECT COUNT(*) FROM paths").to_i,
        file_refs: @db.get_first_value("SELECT COUNT(*) FROM file_refs").to_i,
        content_size: @db.get_first_value("SELECT COALESCE(SUM(LENGTH(data)), 0) FROM content").to_i
      }
      
      # Add content store stats
      begin
        content_stats = content_store.stats
        base_stats.merge!(
          content_versions: content_stats[:versions],
          content_keyframes: content_stats[:keyframes],
          content_deltas: content_stats[:deltas]
        )
      rescue
        # content_meta table might not exist yet
      end
      
      base_stats
    end
    
    # Execute raw SQL
    def execute(sql)
      @db.execute(sql)
    end
    
    # Find commit by prefix
    def find_commit_by_prefix(prefix)
      row = @db.get_first_row("SELECT * FROM commits WHERE id LIKE ?", "#{prefix}%")
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
