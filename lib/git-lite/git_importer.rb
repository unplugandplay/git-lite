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
