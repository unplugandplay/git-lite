# UI utilities for git-lite (mruby-compatible)

module GitLite
  module UI
    COLORS = {
      reset:   "\e[0m",
      black:   "\e[30m",
      red:     "\e[31m",
      green:   "\e[32m",
      yellow:  "\e[33m",
      blue:    "\e[34m",
      magenta: "\e[35m",
      cyan:    "\e[36m",
      white:   "\e[37m",
      bold:    "\e[1m"
    }

    def self.color(name)
      COLORS[name] || ''
    end

    def self.reset
      COLORS[:reset]
    end

    def self.colored(text, color_name)
      "#{color(color_name)}#{text}#{reset}"
    end

    def self.success(text)
      colored(text, :green)
    end

    def self.error(text)
      colored(text, :red)
    end

    def self.warning(text)
      colored(text, :yellow)
    end

    def self.info(text)
      colored(text, :cyan)
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

    def self.format_count(n)
      s = n.to_s
      result = ''
      s.reverse.each_char.with_index do |c, i|
        result = ',' + result if i > 0 && i % 3 == 0
        result = c + result
      end
      result
    end

    def self.progress_bar(current, total, width = 40)
      return '' if total == 0
      ratio = current.to_f / total
      filled = (width * ratio).round
      empty = width - filled
      bar = '=' * filled + '>' + ' ' * [empty - 1, 0].max
      percentage = (ratio * 100).round(1)
      "[#{bar}] #{percentage}% (#{current}/#{total})"
    end

    def self.table(headers, rows)
      return "No data" if rows.empty?
      widths = headers.length.times.map do |i|
        [headers[i].to_s.length, *rows.map { |r| r[i].to_s.length }].max
      end

      header_line = headers.length.times.map { |i| headers[i].to_s.ljust(widths[i]) }.join(' | ')
      separator = widths.map { |w| '-' * w }.join('-+-')

      result = [header_line, separator]
      rows.each do |row|
        result << row.length.times.map { |i| row[i].to_s.ljust(widths[i]) }.join(' | ')
      end
      result.join("\n")
    end
  end
end
