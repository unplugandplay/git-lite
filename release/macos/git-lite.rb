#!/usr/bin/env ruby
# git-lite - A Git-like version control system backed by SQLite
# Compiled standalone executable for macOS (Apple Silicon)
# Version: 1.0.0

# Clear rvm/gem environment to avoid conflicts with system Ruby
ENV.delete('GEM_HOME')
ENV.delete('GEM_PATH')
ENV.delete('RUBYOPT')
ENV.delete('RUBYLIB')

require 'fileutils'
require 'json'
require 'time'
require 'digest'
require 'securerandom'
require 'sqlite3'
require 'pathname'
require 'zlib'

module GitLite
  VERSION = '1.0.0'
  
  class Error < StandardError; end
  class NotARepoError < Error; end
  class AlreadyInitializedError < Error; end
  
  def self.root
    @root ||= find_root(Dir.pwd)
  end
  
  def self.find_root(path)
    return nil if path == '/'
    if File.directory?(File.join(path, '.git-lite'))
      return path
    end
    find_root(File.dirname(path))
  end
  
  def self.pgit_path
    root ? File.join(root, '.git-lite') : nil
  end
  
  module Util
    def self.hash_content(content)
      Digest::SHA256.hexdigest(content)
    end
    
    def self.timestamp
      Time.now.utc.iso8601
    end
    
    def self.short_hash(hash, length = 7)
      hash[0...length]
    end
  end
  
  module UI
    COLORS = {
      reset: "\e[0m",
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      blue: "\e[34m",
      bold: "\e[1m"
    }.freeze
    
    def self.color(name, text)
      if $stdout.tty? && !ENV['NO_COLOR']
        "#{COLORS[name]}#{text}#{COLORS[:reset]}"
      else
        text
      end
    end
    
    def self.success(text); color(:green, text); end
    def self.error(text); color(:red, text); end
    def self.warning(text); color(:yellow, text); end
    def self.info(text); color(:blue, text); end
  end
  
  class Database
    def initialize(db_path)
      @db_path = db_path
      @db = nil
    end
    
    def open
      FileUtils.mkdir_p(File.dirname(@db_path))
      @db = SQLite3::Database.new(@db_path)
      @db.results_as_hash = true
      @db.busy_timeout = 5000
      migrate
      self
    end
    
    def close
      @db&.close
    end
    
    def execute(sql, *args)
      @db.execute(sql, *args)
    end
    
    def migrate
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS commits (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          hash TEXT UNIQUE NOT NULL,
          parent_hash TEXT,
          message TEXT NOT NULL,
          author TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          tree_hash TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_commits_hash ON commits(hash);
        CREATE TABLE IF NOT EXISTS blobs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          hash TEXT UNIQUE NOT NULL,
          content BLOB NOT NULL,
          compressed INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_blobs_hash ON blobs(hash);
        CREATE TABLE IF NOT EXISTS refs (
          name TEXT PRIMARY KEY,
          hash TEXT NOT NULL,
          type TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS staging (
          path TEXT PRIMARY KEY,
          hash TEXT NOT NULL,
          mode TEXT NOT NULL
        );
      SQL
    end
  end
  
  class Repo
    attr_reader :path, :pgit_path, :db
    
    def initialize(path)
      @path = path
      @pgit_path = File.join(path, '.git-lite')
      @db = nil
    end
    
    def init
      raise AlreadyInitializedError, "Already a git-lite repository" if exist?
      FileUtils.mkdir_p(@pgit_path)
      FileUtils.mkdir_p(File.join(@pgit_path, 'refs'))
      @db = Database.new(db_path).open
      File.write(head_path, "ref: refs/heads/main\n")
      self
    end
    
    def open
      raise NotARepoError, "Not a git-lite repository" unless exist?
      @db = Database.new(db_path).open
      self
    end
    
    def exist?
      File.directory?(@pgit_path) && File.exist?(db_path)
    end
    
    def head_path
      File.join(@pgit_path, 'HEAD')
    end
    
    def current_branch
      return nil unless File.exist?(head_path)
      content = File.read(head_path).strip
      content.start_with?('ref: ') ? content[5..-1] : content
    end
    
    def current_commit_hash
      branch = current_branch
      return branch unless branch&.start_with?('refs/')
      result = @db.execute('SELECT hash FROM refs WHERE name = ?', branch)
      result.first&.fetch('hash')
    end
    
    def db_path
      File.join(@pgit_path, 'repo.db')
    end
    
    def close
      @db&.close
    end
  end
  
  class ContentStore
    def initialize(repo)
      @repo = repo
    end
    
    def store(content)
      hash = Util.hash_content(content)
      existing = @repo.db.execute('SELECT 1 FROM blobs WHERE hash = ?', hash)
      return hash unless existing.empty?
      
      compressed = Zlib::Deflate.deflate(content)
      is_compressed = compressed.length < content.length * 0.9
      data_to_store = is_compressed ? compressed : content
      
      @repo.db.execute(
        'INSERT INTO blobs (hash, content, compressed) VALUES (?, ?, ?)',
        [hash, SQLite3::Blob.new(data_to_store), is_compressed ? 1 : 0]
      )
      hash
    end
    
    def retrieve(hash)
      result = @repo.db.execute('SELECT content, compressed FROM blobs WHERE hash = ?', hash)
      return nil if result.empty?
      row = result.first
      content = row['content']
      row['compressed'] == 1 ? Zlib::Inflate.inflate(content) : content
    end
  end
  
  class CLI
    def self.run(args)
      new.run(args)
    end
    
    def run(args)
      if args.empty?
        help
        return
      end
      
      command = args.shift
      case command
      when 'init' then cmd_init(args)
      when 'add' then cmd_add(args)
      when 'commit' then cmd_commit(args)
      when 'log' then cmd_log(args)
      when 'status' then cmd_status(args)
      when 'branch' then cmd_branch(args)
      when 'help', '--help', '-h' then help
      else
        puts UI.error("Unknown command: #{command}")
        exit 1
      end
    rescue NotARepoError => e
      puts UI.error("Error: #{e.message}")
      exit 1
    rescue AlreadyInitializedError => e
      puts UI.warning("Warning: #{e.message}")
      exit 1
    end
    
    private
    
    def cmd_init(args)
      path = args.first || Dir.pwd
      repo = Repo.new(path).init
      puts UI.success("Initialized empty git-lite repository in #{repo.pgit_path}")
      repo.close
    end
    
    def cmd_add(args)
      if args.empty?
        puts UI.error("Nothing specified, nothing added.")
        return
      end
      
      repo = current_repo
      store = ContentStore.new(repo)
      
      args.each do |path|
        full_path = File.expand_path(path, repo.path)
        unless File.exist?(full_path)
          puts UI.warning("pathspec '#{path}' did not match any files")
          next
        end
        
        if File.directory?(full_path)
          Dir.glob(File.join(full_path, '**', '*'), File::FNM_DOTMATCH).each do |file|
            next if File.directory?(file)
            next if file.include?('/.git-lite/')
            next if file.include?('/.git/')
            add_file(repo, store, file)
          end
        else
          add_file(repo, store, full_path)
        end
      end
      repo.close
    end
    
    def add_file(repo, store, file_path)
      content = File.read(file_path, mode: 'rb')
      hash = store.store(content)
      rel_path = Pathname.new(file_path).relative_path_from(Pathname.new(repo.path)).to_s
      mode = File.executable?(file_path) ? '100755' : '100644'
      repo.db.execute(
        'INSERT OR REPLACE INTO staging (path, hash, mode) VALUES (?, ?, ?)',
        [rel_path, hash, mode]
      )
      puts "Added: #{rel_path}"
    end
    
    def cmd_commit(args)
      message = nil
      if args[0] == '-m' && args[1]
        message = args[1]
      end
      
      unless message
        puts UI.error("Please provide a commit message with -m")
        return
      end
      
      repo = current_repo
      staged = repo.db.execute('SELECT * FROM staging')
      
      if staged.empty?
        puts UI.warning("nothing to commit, working tree clean")
        repo.close
        return
      end
      
      entries = {}
      staged.each { |row| entries[row['path']] = { hash: row['hash'], mode: row['mode'] } }
      tree_content = entries.to_json
      tree_hash = Util.hash_content(tree_content)
      
      store = ContentStore.new(repo)
      store.store(tree_content)
      
      parent = repo.current_commit_hash
      author = ENV['GIT_AUTHOR_NAME'] || ENV['USER'] || 'unknown'
      timestamp = Util.timestamp
      
      commit_data = { tree: tree_hash, parent: parent, author: author, timestamp: timestamp, message: message }
      commit_content = commit_data.to_json
      commit_hash = Util.hash_content(commit_content)
      
      repo.db.execute(
        'INSERT INTO commits (hash, parent_hash, message, author, timestamp, tree_hash) VALUES (?, ?, ?, ?, ?, ?)',
        [commit_hash, parent, message, author, timestamp, tree_hash]
      )
      
      branch = repo.current_branch
      if branch && branch.start_with?('refs/')
        repo.db.execute(
          'INSERT OR REPLACE INTO refs (name, hash, type) VALUES (?, ?, ?)',
          [branch, commit_hash, 'branch']
        )
      end
      
      repo.db.execute('DELETE FROM staging')
      puts UI.success("[#{branch.split('/').last} #{Util.short_hash(commit_hash)}] #{message}")
      repo.close
    end
    
    def cmd_log(args)
      repo = current_repo
      commit_hash = repo.current_commit_hash
      
      unless commit_hash
        puts UI.error("HEAD is not pointing to any commit")
        repo.close
        return
      end
      
      limit = args.include?('-n') ? args[args.index('-n') + 1].to_i : nil
      count = 0
      
      while commit_hash && (limit.nil? || count < limit)
        result = repo.db.execute('SELECT * FROM commits WHERE hash = ?', commit_hash)
        break if result.empty?
        commit = result.first
        
        puts UI.color(:yellow, "commit #{commit_hash}")
        puts "Author: #{commit['author']}"
        puts "Date:   #{commit['timestamp']}"
        puts
        puts "    #{commit['message']}"
        puts
        
        commit_hash = commit['parent_hash']
        count += 1
      end
      repo.close
    end
    
    def cmd_status(args)
      repo = current_repo
      branch = repo.current_branch || 'HEAD (no branch)'
      puts "On branch #{branch.split('/').last}"
      puts
      
      staged = repo.db.execute('SELECT * FROM staging')
      if staged.empty?
        puts "nothing to commit, working tree clean"
      else
        puts "Changes to be committed:"
        staged.each { |row| puts "\t#{UI.color(:green, 'modified:')} #{row['path']}" }
        puts
      end
      repo.close
    end
    
    def cmd_branch(args)
      repo = current_repo
      
      if args.empty?
        current = repo.current_branch&.split('/')&.last
        refs = repo.db.execute("SELECT name, hash FROM refs WHERE name LIKE 'refs/heads/%'")
        refs.each do |row|
          branch = row['name'].split('/').last
          prefix = branch == current ? '* ' : '  '
          colored = branch == current ? UI.color(:green, branch) : branch
          puts "#{prefix}#{colored}"
        end
        puts "  (no branches yet)" if refs.empty?
      else
        branch = args.first
        commit_hash = repo.current_commit_hash
        if commit_hash
          repo.db.execute(
            'INSERT OR REPLACE INTO refs (name, hash, type) VALUES (?, ?, ?)',
            ["refs/heads/#{branch}", commit_hash, 'branch']
          )
          puts "Created branch '#{branch}'"
        else
          puts UI.error("Cannot create branch: no commits yet")
        end
      end
      repo.close
    end
    
    def current_repo
      root = GitLite.root
      raise NotARepoError, "Not a git-lite repository (or any parent)" unless root
      Repo.new(root).open
    end
    
    def help
      puts "git-lite - A Git-like version control system backed by SQLite"
      puts
      puts "Usage: git-lite <command> [options]"
      puts
      puts "Commands:"
      puts "  init [path]           Initialize a new repository"
      puts "  add <path>...         Add files to staging area"
      puts "  commit -m <message>   Commit staged changes"
      puts "  log [-n <count>]      Show commit history"
      puts "  status                Show working tree status"
      puts "  branch [name]         List or create branches"
      puts "  help                  Show this help message"
    end
  end
end

GitLite::CLI.run(ARGV)
