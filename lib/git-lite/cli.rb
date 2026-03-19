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
                "UPDATE content SET data = CAST(? AS BLOB) WHERE path_id = ? AND version_id = ?",
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
