# mruby compatibility shims
# Replaces CRuby stdlib features not available in mruby

# SecureRandom replacement using mruby's built-in Random
module SecureRandom
  ALPHANUMERIC = ('a'..'z').to_a + ('0'..'9').to_a

  def self.alphanumeric(n = 16)
    n.times.map { ALPHANUMERIC[rand(ALPHANUMERIC.length)] }.join
  end

  def self.hex(n = 16)
    n.times.map { '%02x' % rand(256) }.join
  end
end

# FileUtils replacement using mruby-dir and mruby-io
module FileUtils
  def self.mkdir_p(path)
    return if File.directory?(path)
    parts = path.split('/')
    current = parts[0] == '' ? '/' : ''
    parts.each do |part|
      next if part.empty?
      current = current.empty? ? part : "#{current}/#{part}"
      Dir.mkdir(current) unless File.directory?(current)
    end
  end

  def self.rm_rf(path)
    return unless File.exist?(path) || File.directory?(path)
    if File.directory?(path)
      Dir.entries(path).each do |entry|
        next if entry == '.' || entry == '..'
        rm_rf(File.join(path, entry))
      end
      Dir.delete(path)
    else
      File.delete(path)
    end
  end

  def self.cp(src, dst)
    data = File.open(src, 'rb') { |f| f.read }
    File.open(dst, 'wb') { |f| f.write(data) }
  end

  def self.chmod(mode, path)
    # mruby-io may not support chmod directly
    # Use system call as fallback
    system("chmod #{mode.to_s(8)} #{path}")
  end
end

# File extensions for mruby
class File
  def self.binread(path)
    File.open(path, 'rb') { |f| f.read }
  end

  def self.binwrite(path, data)
    File.open(path, 'wb') { |f| f.write(data) }
  end

  def self.write(path, data)
    File.open(path, 'w') { |f| f.write(data) }
  end

  def self.read(path)
    File.open(path, 'r') { |f| f.read }
  end

  def self.readlink(path)
    # mruby doesn't have readlink - use system
    `readlink "#{path}"`.chomp
  end
end unless File.respond_to?(:binread)

# Dir.mktmpdir replacement
module Dir
  def self.mktmpdir(prefix = 'mruby')
    base = ENV['TMPDIR'] || '/tmp'
    path = "#{base}/#{prefix}-#{Time.now.to_i}-#{rand(100000)}"
    Dir.mkdir(path)
    if block_given?
      begin
        yield path
      ensure
        FileUtils.rm_rf(path)
      end
    else
      path
    end
  end
end unless Dir.respond_to?(:mktmpdir)

# Time extensions for mruby
class Time
  def iso8601
    strftime('%Y-%m-%dT%H:%M:%S%z')
  end

  def self.parse(str)
    # Simple ISO 8601 parser
    if str =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/
      Time.new($1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i)
    elsif str =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
      Time.new($1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i)
    else
      Time.now
    end
  end
end

# String extensions for mruby
class String
  def lines
    split("\n", -1).map { |l| l + "\n" }
  end unless method_defined?(:lines)

  def chomp(sep = "\n")
    if end_with?(sep)
      self[0..-(sep.length + 1)]
    else
      self
    end
  end unless method_defined?(:chomp)

  def start_with?(*prefixes)
    prefixes.any? { |prefix| self[0, prefix.length] == prefix }
  end unless method_defined?(:start_with?)

  def end_with?(*suffixes)
    suffixes.any? { |suffix| self[-suffix.length, suffix.length] == suffix }
  end unless method_defined?(:end_with?)

  def force_encoding(enc)
    self  # mruby strings are byte strings, encoding is a no-op
  end unless method_defined?(:force_encoding)

  def encode(*args)
    self  # No-op in mruby
  end unless method_defined?(:encode)

  def unpack1(fmt)
    unpack(fmt)[0]
  end unless method_defined?(:unpack1)

  def getbyte(index)
    bytes[index]
  end unless method_defined?(:getbyte)

  def byteslice(start, length = nil)
    if length
      self[start, length]
    else
      if start.is_a?(Range)
        self[start]
      else
        self[start, 1]
      end
    end
  end unless method_defined?(:byteslice)
end

# Digest module using mruby-sha2
module Digest
  class SHA256
    def self.hexdigest(data)
      SHA2.sha256_hex(data)
    end
  end
end unless defined?(Digest)

# Enumerable#to_set replacement
class Array
  def to_set
    hash = {}
    each { |item| hash[item] = true }
    hash
  end
end unless Array.method_defined?(:to_set)

# Hash-based Set substitute
class HashSet
  def initialize(arr = [])
    @hash = {}
    arr.each { |item| @hash[item] = true }
  end

  def include?(item)
    @hash.key?(item)
  end

  def add(item)
    @hash[item] = true
  end

  def to_a
    @hash.keys
  end
end
