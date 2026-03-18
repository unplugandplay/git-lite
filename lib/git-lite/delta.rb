# Delta compression for git-lite (mruby-compatible)

module GitLite
  module Delta
    BLOCK_SIZE = 16

    def self.create(old_data, new_data)
      return nil if old_data.nil? || old_data.empty?
      return nil if new_data.bytesize < 200
      return nil if old_data == new_data

      similarity = quick_similarity(old_data, new_data)
      return nil if similarity < 0.3

      block_hashes = {}
      i = 0
      while i <= old_data.bytesize - BLOCK_SIZE
        hash = hash_block(old_data, i)
        block_hashes[hash] ||= []
        block_hashes[hash] << i
        i += BLOCK_SIZE
      end

      matches = []
      pos = 0

      while pos <= new_data.bytesize - BLOCK_SIZE
        hash = hash_block(new_data, pos)

        if block_hashes[hash]
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

      total_matched = matches.inject(0) { |sum, m| sum + m[2] }
      return nil if total_matched < new_data.bytesize * 0.2

      build_delta(old_data.bytesize, new_data, matches)
    end

    def self.apply(base_data, delta)
      return delta if delta.bytesize < 9

      magic = delta.getbyte(0)
      version = delta.getbyte(1)
      return delta unless magic == 0xD5 && version == 1

      base_size, output_size = delta[2..9].unpack('NN')

      result = ""
      pos = 10

      while pos < delta.bytesize && result.bytesize < output_size
        cmd = delta.getbyte(pos)
        pos += 1

        case cmd
        when 0x01  # Copy from base
          offset, length = delta[pos..pos+7].unpack('NN')
          pos += 8
          result << base_data[offset, length]
        when 0x02  # Insert literal
          length = delta[pos..pos+3].unpack('N')[0]
          pos += 4
          result << delta[pos, length]
          pos += length
        else
          return nil
        end
      end

      result
    end

    # Compression wrappers using Zlib
    def self.compress(data)
      Zlib.deflate(data)
    end

    def self.decompress(data)
      Zlib.inflate(data)
    end

    private

    def self.quick_similarity(old_data, new_data)
      samples = 10
      sample_size = 16
      matches = 0

      return 0 if new_data.bytesize < sample_size

      samples.times do
        pos = rand(0..new_data.bytesize - sample_size)
        sample = new_data[pos, sample_size]
        matches += 1 if old_data.include?(sample)
      end

      matches.to_f / samples
    end

    def self.hash_block(data, offset)
      hash = 0
      len = [BLOCK_SIZE, data.bytesize - offset].min
      len.times do |i|
        hash = ((hash << 5) - hash + data.getbyte(offset + i)) & 0xFFFFFFFF
      end
      hash
    end

    def self.extend_match(old_data, new_data, old_pos, new_pos)
      start_old = old_pos
      start_new = new_pos

      while start_old > 0 && start_new > 0 &&
            old_data.getbyte(start_old - 1) == new_data.getbyte(start_new - 1)
        start_old -= 1
        start_new -= 1
      end

      len = 0
      max_len = [old_data.bytesize - old_pos, new_data.bytesize - new_pos].min
      while len < max_len && old_data.getbyte(old_pos + len) == new_data.getbyte(new_pos + len)
        len += 1
      end

      len += (old_pos - start_old)
      len
    end

    def self.build_delta(base_size, new_data, matches)
      matches.sort_by! { |m| m[0] }

      merged = []
      matches.each do |match|
        if merged.empty? || match[0] > merged.last[0] + merged.last[2]
          merged << match
        else
          old_end = merged.last[0] + merged.last[2]
          if match[0] + match[2] > old_end
            merged.last[2] = match[0] + match[2] - merged.last[0]
          end
        end
      end

      delta = ""
      delta << 0xD5.chr
      delta << 0x01.chr
      delta << [base_size, new_data.bytesize].pack('NN')

      pos = 0
      merged.each do |new_pos, old_pos, length|
        if new_pos > pos
          literal = new_data[pos, new_pos - pos]
          delta << 0x02.chr
          delta << [literal.bytesize].pack('N')
          delta << literal
        end

        delta << 0x01.chr
        delta << [old_pos, length].pack('NN')

        pos = new_pos + length
      end

      if pos < new_data.bytesize
        literal = new_data[pos, new_data.bytesize - pos]
        delta << 0x02.chr
        delta << [literal.bytesize].pack('N')
        delta << literal
      end

      delta.bytesize < new_data.bytesize * 0.8 ? delta : nil
    end
  end
end
