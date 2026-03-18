# Repository management for git-lite

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
      
      # Create config
      config = Config.new(path)
      config.save
      
      # Initialize database
      db_path = File.join(pgit_dir, 'repo.db')
      db = DB.new(db_path).connect
      db.init_schema
      db.set_repo_path(path)
      db.close
      
      new(path)
    end
    
    def self.open(path = Dir.pwd)
      # Find repository root
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
      'main' # Simplified - always main for now
    end
    
    def branches
      ['main'] # Simplified
    end
    
    def create_branch(name)
      # Simplified - just set a ref
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
    STAGING_FILE = 'staging.json'.freeze
    
    def staging_path
      File.join(@pgit_path, STAGING_FILE)
    end
    
    def load_staging
      return {} unless File.exist?(staging_path)
      
      JSON.parse(File.read(staging_path), symbolize_names: true)
    rescue JSON::ParserError
      {}
    end
    
    def save_staging(staging)
      File.write(staging_path, JSON.pretty_generate(staging))
    end
    
    def stage_file(path)
      staging = load_staging
      staging[path] = { status: 'added', type: 'file' }
      save_staging(staging)
    end
    
    def stage_deletion(path)
      staging = load_staging
      staging[path] = { status: 'deleted', type: 'file' }
      save_staging(staging)
    end
    
    def move_file(source, dest)
      staging = load_staging
      staging[source] = { status: 'deleted', type: 'file' }
      staging[dest] = { status: 'added', type: 'file', from: source }
      save_staging(staging)
    end
    
    def reset_staging
      File.delete(staging_path) if File.exist?(staging_path)
    end
    
    def staged_changes
      staging = load_staging
      staging.map do |path, info|
        { path: path, status: info[:status].to_sym }
      end
    end
    
    def unstaged_changes
      # Compare working tree with HEAD
      changes = []
      
      head_id = head
      return changes unless head_id
      
      # Get tree at HEAD
      tree = @db.get_tree(head_id)
      tree_paths = tree.map { |b| b[:path] }
      
      # Check each file in tree
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
      
      # Get tracked paths
      tree = @db.get_tree(head)
      tracked = tree.map { |b| b[:path] }.to_set
      
      # Find untracked
      untracked = []
      Dir.glob('**/*', File::FNM_DOTMATCH, base: @root).each do |path|
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
      
      # Get parent commit
      parent_id = head
      
      # Generate commit ID (ULID-like: timestamp + random)
      timestamp = Time.now
      time_part = timestamp.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18).downcase
      commit_id = time_part + random_part
      
      # Create blobs for staged files
      staged = load_staging
      tree_hash = Digest::SHA256.hexdigest(staged.keys.sort.join)
      
      author_name = config.effective_user_name || 'Anonymous'
      author_email = config.effective_user_email || 'anonymous@example.com'
      
      # Insert blobs
      staged.each do |path, info|
        if info[:status] == 'deleted'
          # Create deletion blob
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
          # Create file blob
          full_path = File.join(@root, path)
          content = File.binread(full_path)
          
          @db.create_blob({
            path: path,
            commit_id: commit_id,
            content_hash: Digest::SHA256.hexdigest(content)[0..31],
            content: content,
            mode: File.stat(full_path).mode & 0o7777,
            is_symlink: File.symlink?(full_path),
            symlink_target: File.symlink?(full_path) ? File.readlink(full_path) : nil,
            is_binary: Util.binary?(content)
          })
        end
      end
      
      # Create commit
      commit = {
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
      
      @db.create_commit(commit)
      
      # Update HEAD
      @db.set_head(commit_id)
      
      # Clear staging
      reset_staging
      
      commit_id
    end
    
    def checkout(commit_id)
      commit = @db.get_commit(commit_id) || @db.find_commit_by_prefix(commit_id)
      raise "Commit not found: #{commit_id}" unless commit
      
      # Get tree
      blobs = @db.get_tree(commit[:id])
      
      # Write files
      blobs.each do |blob|
        full_path = File.join(@root, blob[:path])
        FileUtils.mkdir_p(File.dirname(full_path))
        
        if blob[:is_symlink] && blob[:symlink_target]
          File.symlink(blob[:symlink_target], full_path)
        elsif blob[:content]
          File.binwrite(full_path, blob[:content])
          File.chmod(blob[:mode], full_path) if blob[:mode]
        end
      end
      
      # Update HEAD
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
      # Simple diff output
      old_lines = (old_content || '').lines
      new_lines = (new_content || '').lines
      
      result = []
      max_lines = [old_lines.length, new_lines.length].max
      
      max_lines.times do |i|
        old_line = old_lines[i]
        new_line = new_lines[i]
        
        if old_line != new_line
          result << "-#{old_line}" if old_line
          result << "+#{new_line}" if new_line
        end
      end
      
      result.join
    end
    
    def execute_sql(query)
      @db.execute(query)
    end
  end
end
