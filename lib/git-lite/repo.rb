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
