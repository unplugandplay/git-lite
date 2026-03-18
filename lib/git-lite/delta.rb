# Delta compression for git-lite
# Simple and fast delta format

module GitLite
  module Delta
    BLOCK_SIZE = 16  # Bytes per hash block
    
    # Create delta - returns nil if not beneficial
    def self.create(old_data, new_data)
      return nil if old_data.nil? || old_data.empty?
      return nil if new_data.bytesize < 200  # Only delta compress larger files
      return nil if old_data == new_data
      
      # Quick check: if files are very different, skip delta
      similarity = quick_similarity(old_data, new_data)
      return nil if similarity < 0.3  # Less than 30% similar
      
      # Build hash table of old_data blocks
      block_hashes = {}
      (0..old_data.bytesize - BLOCK_SIZE).step(BLOCK_SIZE) do |i|
        hash = hash_block(old_data, i)
        block_hashes[hash] ||= []
        block_hashes[hash] << i
      end
      
      # Find matches in new_data
      matches = []
      pos = 0
      
      while pos <= new_data.bytesize - BLOCK_SIZE
        hash = hash_block(new_data, pos)
        
        if block_hashes[hash]
          # Found potential match, extend it
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
      
      # If not enough matches, don't use delta
      total_matched = matches.sum { |m| m[2] }
      return nil if total_matched < new_data.bytesize * 0.2
      
      # Build delta from matches
      build_delta(old_data.bytesize, new_data, matches)
    end
    
    # Apply delta to reconstruct target
    def self.apply(base_data, delta)
      return delta if delta.bytesize < 9
      
      # Check magic
      magic, version = delta[0..1].unpack('CC')
      return delta unless magic == 0xD5 && version == 1
      
      base_size, output_size = delta[2..9].unpack('NN')
      
      result = String.new(encoding: Encoding::BINARY, capacity: output_size)
      pos = 10
      
      while pos < delta.bytesize && result.bytesize < output_size
        cmd = delta.getbyte(pos)
        pos += 1
        
        case cmd
        when 0x01  # Copy from base
          offset, length = delta[pos..pos+7].unpack('NN')
          pos += 8
          result << base_data.byteslice(offset, length)
        when 0x02  # Insert literal
          length = delta[pos..pos+3].unpack1('N')
          pos += 4
          result << delta[pos, length]
          pos += length
        else
          # Invalid command
          return nil
        end
      end
      
      result
    end
    
    private
    
    def self.quick_similarity(old_data, new_data)
      # Sample-based similarity check
      samples = 10
      sample_size = 16
      matches = 0
      
      return 0 if new_data.bytesize < sample_size
      
      samples.times do
        pos = rand(0..new_data.bytesize - sample_size)
        sample = new_data.byteslice(pos, sample_size)
        matches += 1 if old_data.include?(sample)
      end
      
      matches.to_f / samples
    end
    
    def self.hash_block(data, offset)
      # Simple rolling hash
      hash = 0
      len = [BLOCK_SIZE, data.bytesize - offset].min
      len.times do |i|
        hash = ((hash << 5) - hash + data.getbyte(offset + i)) & 0xFFFFFFFF
      end
      hash
    end
    
    def self.extend_match(old_data, new_data, old_pos, new_pos)
      # Extend match backward
      start_old = old_pos
      start_new = new_pos
      
      while start_old > 0 && start_new > 0 && 
            old_data.getbyte(start_old - 1) == new_data.getbyte(start_new - 1)
        start_old -= 1
        start_new -= 1
      end
      
      # Extend match forward
      len = 0
      max_len = [old_data.bytesize - old_pos, new_data.bytesize - new_pos].min
      while len < max_len && old_data.getbyte(old_pos + len) == new_data.getbyte(new_pos + len)
        len += 1
      end
      
      # Add backward extension
      len += (old_pos - start_old)
      
      len
    end
    
    def self.build_delta(base_size, new_data, matches)
      # Sort matches by position in new_data
      matches.sort_by! { |m| m[0] }
      
      # Merge overlapping/adjacent matches
      merged = []
      matches.each do |match|
        if merged.empty? || match[0] > merged.last[0] + merged.last[2]
          merged << match
        else
          # Extend current match if beneficial
          old_end = merged.last[0] + merged.last[2]
          if match[0] + match[2] > old_end
            merged.last[2] = match[0] + match[2] - merged.last[0]
          end
        end
      end
      
      # Build delta: [magic][version][base_size][output_size][commands...]
      delta = String.new(encoding: Encoding::BINARY)
      delta << 0xD5.chr  # Magic
      delta << 0x01.chr  # Version
      delta << [base_size, new_data.bytesize].pack('NN')
      
      pos = 0
      merged.each do |new_pos, old_pos, length|
        # Insert literal before match if needed
        if new_pos > pos
          literal = new_data.byteslice(pos, new_pos - pos)
          delta << 0x02.chr
          delta << [literal.bytesize].pack('N')
          delta << literal
        end
        
        # Copy from base
        delta << 0x01.chr
        delta << [old_pos, length].pack('NN')
        
        pos = new_pos + length
      end
      
      # Final literal
      if pos < new_data.bytesize
        literal = new_data.byteslice(pos, new_data.bytesize - pos)
        delta << 0x02.chr
        delta << [literal.bytesize].pack('N')
        delta << literal
      end
      
      # Only return if beneficial
      delta.bytesize < new_data.bytesize * 0.8 ? delta : nil
    end
  end
end
