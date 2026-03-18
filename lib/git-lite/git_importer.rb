# Git importer for git-lite
# Imports git repositories using fast-export

require 'open3'
require 'fileutils'

module GitLite
  class GitImporter
    def initialize(repo, git_path)
      @repo = repo
      @git_path = git_path
      @commit_count = 0
    end
    
    def import_branch(branch = 'main')
      puts "Exporting git history..."
      
      # Run git fast-export
      cmd = ['git', 'fast-export', '--reencode=yes', '--show-original-ids', branch]
      
      stdout, stderr, status = Open3.capture3(*cmd, chdir: @git_path)
      
      unless status.success?
        puts "Error: #{stderr}"
        raise "Failed to export git history"
      end
      
      # Parse the export
      parse_fast_export(stdout)
    end
    
    def parse_fast_export(data)
      lines = data.lines
      index = 0
      
      blobs = {}
      commits = []
      current_commit = nil
      
      while index < lines.length
        line = lines[index].chomp
        
        case line
        when 'blob'
          # Parse blob
          index += 1
          blob = parse_blob(lines, index)
          blobs[blob[:mark]] = blob if blob[:mark]
          index = blob[:next_index] if blob
          
        when /^commit /
          # Parse commit
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
      
      # Now import commits in order
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
          
          # Read data
          blob[:data] = lines[index..index].join[0...size]
          index += 1
          
          # Skip trailing newline if present
          index += 1 if lines[index] == "\n"
          
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
      
      in_message = false
      message_lines_left = 0
      
      while index < lines.length
        line = lines[index]
        chomped = line.chomp
        
        if in_message
          commit[:message] += line
          message_lines_left -= 1
          
          if message_lines_left <= 0
            in_message = false
            # Continue to read file ops
          end
          index += 1
          next
        end
        
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
          
          # Read message
          message_data = lines[index..index + 10].join[0...size]
          commit[:message] = message_data
          index += 1
          
          # Skip to end of data
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
          # End of commit
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
      # Format: "Name <email> timestamp tz"
      # Example: "John Doe <john@example.com> 1234567890 +0100"
      
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
      # Generate commit ID
      timestamp = commit_data[:committer_time] || Time.now
      time_part = timestamp.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18).downcase
      commit_id = time_part + random_part
      
      # Map parent
      parent_id = nil
      if commit_data[:from]
        parent_id = @commit_map[commit_data[:from]] if @commit_map
      end
      
      @commit_map ||= {}
      @commit_map[commit_data[:mark]] = commit_id if commit_data[:mark]
      
      # Process file operations
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
      
      # Create the commit
      commit = {
        id: commit_id,
        parent_id: parent_id,
        tree_hash: Digest::SHA256.hexdigest(commit_data[:file_ops].map { |o| o[:path] }.sort.join),
        message: commit_data[:message].chomp,
        author_name: commit_data[:author_name],
        author_email: commit_data[:author_email],
        authored_at: commit_data[:author_time] || timestamp,
        committer_name: commit_data[:committer_name],
        committer_email: commit_data[:committer_email],
        committed_at: timestamp
      }
      
      @repo.db.create_commit(commit)
      
      # Update HEAD
      @repo.db.set_head(commit_id)
    end
  end
end
