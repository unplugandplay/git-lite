# Utility functions for git-lite (mruby-compatible)

module GitLite
  module Util
    def self.hash_path(path)
      full = File.expand_path(path)
      Digest::SHA256.hexdigest(full)[0..15]
    end

    def self.format_bytes(bytes)
      return "0 B" if bytes.nil? || bytes == 0

      units = ['B', 'KB', 'MB', 'GB', 'TB']
      unit_index = 0

      size = bytes.to_f
      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end

    def self.binary?(content)
      return false if content.nil? || content.empty?

      # Check for null bytes
      return true if content.include?("\x00")

      # Check for high ratio of non-printable chars
      sample = content[0..8000] || content
      non_printable = 0
      sample.bytes.each do |b|
        non_printable += 1 if (b < 32 && b != 9 && b != 10 && b != 13) || b >= 127
      end

      non_printable > sample.length * 0.3
    end

    def self.generate_id
      time_part = Time.now.to_i.to_s(36).rjust(8, '0')
      random_part = SecureRandom.alphanumeric(18)
      time_part + random_part
    end

    def self.id_to_time(id)
      time_part = id[0..7]
      Time.at(time_part.to_i(36))
    end

    def self.truncate(text, max_length)
      return text if text.length <= max_length
      text[0..max_length - 4] + "..."
    end

    def self.pluralize(count, singular, plural = nil)
      plural ||= singular + 's'
      count == 1 ? "#{count} #{singular}" : "#{count} #{plural}"
    end
  end
end
