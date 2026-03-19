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

      cmd = "cd '#{@git_path}' && git fast-export --reencode=yes --show-original-ids #{branch} 2>/dev/null"
      blobs = {}

      io = IO.popen(cmd)
      parse_fast_export_stream(io, blobs)
      io.close

      @commit_count
    end

    def parse_fast_export_stream(io, blobs)
      while (line = io.gets)
        line = line.chomp

        case line
        when 'blob'
          parse_blob_stream(io, blobs)

        when /^commit /
          commit = parse_commit_stream(io)
          if commit
            import_commit(commit, blobs)
            @commit_count += 1

            if @commit_count % 100 == 0
              puts "  Imported #{@commit_count} commits"
            end
          end

        when 'done'
          break
        end
      end
    end

    def parse_blob_stream(io, blobs)
      blob = { mark: nil, data: nil }

      while (line = io.gets)
        line = line.chomp

        if line.start_with?('mark ')
          blob[:mark] = line.sub('mark ', '').sub(':', '').to_i
        elsif line.start_with?('original-oid ')
          # skip
        elsif line.start_with?('data ')
          size = line.sub('data ', '').to_i
          blob[:data] = size > 0 ? io.read(size) : ''
          io.gets  # consume trailing newline
          blobs[blob[:mark]] = blob if blob[:mark]
          return
        else
          return
        end
      end
    end

    def parse_commit_stream(io)
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
        file_ops: []
      }

      while (line = io.gets)
        line = line.chomp

        if line.start_with?('mark ')
          commit[:mark] = line.sub('mark ', '').sub(':', '').to_i

        elsif line.start_with?('original-oid ')
          commit[:original_oid] = line.sub('original-oid ', '')

        elsif line.start_with?('author ')
          commit[:author_name], commit[:author_email], commit[:author_time] = parse_author(line.sub('author ', ''))

        elsif line.start_with?('committer ')
          commit[:committer_name], commit[:committer_email], commit[:committer_time] = parse_author(line.sub('committer ', ''))

        elsif line.start_with?('data ')
          size = line.sub('data ', '').to_i
          commit[:message] = size > 0 ? io.read(size) : ''
          io.gets  # consume trailing newline

        elsif line.start_with?('from ')
          commit[:from] = line.sub('from ', '').sub(':', '').to_i

        elsif line.start_with?('M ')
          parts = line.split(' ')
          mode = parts[1]
          mark = parts[2].sub(':', '').to_i
          path = parts[3..-1].join(' ')
          commit[:file_ops] << { type: :modify, mode: mode.to_i(8), mark: mark, path: path }

        elsif line.start_with?('D ')
          parts = line.split(' ')
          path = parts[1..-1].join(' ')
          commit[:file_ops] << { type: :delete, path: path }

        elsif line == ''
          return commit

        end
      end

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
