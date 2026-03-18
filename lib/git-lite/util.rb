# Utility functions for git-lite

require 'digest'

module GitLite
  module Util
    # Hash a path for database naming
    def self.hash_path(path)
      Digest::SHA256.hexdigest(File.expand_path(path))[0..15]
    end
    
    # Format bytes for display
    def self.format_bytes(bytes)
      return "0 B" if bytes.nil? || bytes == 0
      
      units = %w[B KB MB GB TB]
      unit_index = 0
      
      size = bytes.to_f
      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end
      
      "#{size.round(2)} #{units[unit_index]}"
    end
    
    # Check if content is binary
    def self.binary?(content)
      return false if content.nil? || content.empty?
      
      # Force binary encoding for checking
      content = content.dup.force_encoding(Encoding::ASCII_8BIT)
      
      # Check for null bytes
      return true if content.include?("\x00")
      
      # Check for high ratio of non-printable chars
      sample = content[0..8000]
      non_printable = sample.bytes.count { |b| b < 32 && b != 9 && b != 10 && b != 13 || b >= 127 }
      
      non_printable > sample.length * 0.3
    end
    
    # Generate a ULID-like ID
    def self.generate_id
      time_part = Time.now.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18).downcase
      time_part + random_part
    end
    
    # Parse timestamp from ULID-like ID
    def self.id_to_time(id)
      time_part = id[0..7]
      Time.at(time_part.to_i(36))
    end
    
    # Truncate text
    def self.truncate(text, max_length)
      return text if text.length <= max_length
      text[0..max_length - 4] + "..."
    end
    
    # Pluralize
    def self.pluralize(count, singular, plural = nil)
      plural ||= singular + 's'
      count == 1 ? "#{count} #{singular}" : "#{count} #{plural}"
    end
  end
end
