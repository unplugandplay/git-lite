# Delta compression for git-lite
# Implements a simple delta format similar to Fossil/git

module GitLite
  module Delta
    # Maximum size for inline content (store full if smaller)
    INLINE_THRESHOLD = 100
    
    # Create a delta from old_data to new_data
    # Returns delta bytes that can reconstruct new_data from old_data
    def self.create(old_data, new_data)
      return new_data if old_data.nil? || old_data.empty?
      return new_data if new_data.bytesize < INLINE_THRESHOLD
      
      # Simple delta format:
      # [1 byte: version][4 bytes: output length]
      # Commands:
      #   0x01 + 4-byte offset + 2-byte length = copy from source
      #   0x02 + 2-byte length + data = insert new bytes
      
      commands = []
      output_len = new_data.bytesize
      
      # Find matching chunks using rolling hash
      pos = 0
      while pos < new_data.bytesize
        match = find_best_match(old_data, new_data, pos)
        
        if match && match[:length] > 8
          # Copy from source: offset, length
          commands << [:copy, match[:offset], match[:length]]
          pos += match[:length]
        else
          # Insert new bytes: find next match or end
          insert_len = [64, new_data.bytesize - pos].min
          if match
            insert_len = [insert_len, match[:start] - pos].min
          end
          insert_len = new_data.bytesize - pos if pos + insert_len >= new_data.bytesize
          
          commands << [:insert, new_data.byteslice(pos, insert_len)]
          pos += insert_len
        end
      end
      
      encode_delta(commands, output_len)
    end
    
    # Apply delta to base data to reconstruct target
    def self.apply(base_data, delta)
      # Check if delta is actually compressed data (no delta)
      return delta if delta.bytesize < 5
      
      version, output_len = decode_header(delta)
      return delta if version == 0  # Uncompressed
      
      result = String.new(encoding: Encoding::BINARY)
      pos = 5  # Skip header
      
      while pos < delta.bytesize && result.bytesize < output_len
        cmd = delta.getbyte(pos)
        pos += 1
        
        case cmd
        when 0x01  # Copy
          offset = delta.byteslice(pos, 4).unpack1('N')
          pos += 4
          length = delta.byteslice(pos, 2).unpack1('n')
          pos += 2
          result << base_data.byteslice(offset, length)
        when 0x02  # Insert
          length = delta.byteslice(pos, 2).unpack1('n')
          pos += 2
          result << delta.byteslice(pos, length)
          pos += length
        else
          # Unknown command, treat as uncompressed
          return delta
        end
      end
      
      result
    end
    
    # Compress using zstd (simpler alternative to delta)
    def self.compress(data)
      require 'zstd-ruby' rescue return data
      Zstd.compress(data)
    end
    
    def self.decompress(data)
      require 'zstd-ruby' rescue return data
      Zstd.decompress(data)
    rescue
      data
    end
    
    private
    
    def self.find_best_match(old_data, new_data, start_pos)
      return nil if old_data.nil? || old_data.empty?
      
      # Simple hash-based matching
      best = nil
      best_score = 0
      
      # Try exact match of first 8 bytes at start_pos
      chunk = new_data.byteslice(start_pos, 8)
      return nil if chunk.nil? || chunk.bytesize < 4
      
      # Find all occurrences in old_data
      offset = 0
      while (found = old_data.index(chunk, offset))
        # Extend match
        length = chunk.bytesize
        while start_pos + length < new_data.bytesize &&
              found + length < old_data.bytesize &&
              new_data.getbyte(start_pos + length) == old_data.getbyte(found + length)
          length += 1
        end
        
        if length > best_score
          best_score = length
          best = { offset: found, length: length, start: start_pos }
        end
        
        offset = found + 1
      end
      
      best
    end
    
    def self.encode_delta(commands, output_len)
      result = String.new(encoding: Encoding::BINARY)
      
      # Header: version 1 + 4-byte output length
      result << 0x01.chr
      result << [output_len].pack('N')
      
      commands.each do |cmd|
        case cmd[0]
        when :copy
          result << 0x01.chr
          result << [cmd[1]].pack('N')  # offset
          result << [cmd[2]].pack('n')  # length
        when :insert
          data = cmd[1]
          result << 0x02.chr
          result << [data.bytesize].pack('n')
          result << data
        end
      end
      
      # Only use delta if it's smaller
      result.bytesize < output_len ? result : nil
    end
    
    def self.decode_header(delta)
      return [0, 0] if delta.bytesize < 5
      
      version = delta.getbyte(0)
      output_len = delta.byteslice(1, 4).unpack1('N')
      
      [version, output_len]
    end
  end
end
