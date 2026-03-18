# git-lite - A Git-like version control system backed by SQLite
# mruby-compatible version

require_relative 'git-lite/mruby_compat'

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
end

require_relative 'git-lite/sqlite_wrapper'
require_relative 'git-lite/util'
require_relative 'git-lite/config'
require_relative 'git-lite/db'
require_relative 'git-lite/repo'
require_relative 'git-lite/ui'
require_relative 'git-lite/delta'
require_relative 'git-lite/content_store'
require_relative 'git-lite/git_importer'
require_relative 'git-lite/cli'
