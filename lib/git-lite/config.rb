# Configuration management for git-lite

require 'json'

module GitLite
  class Config
    attr_accessor :user_name, :user_email, :remotes
    
    def initialize(repo_path = nil)
      @repo_path = repo_path
      @user_name = ''
      @user_email = ''
      @remotes = {}
      
      load if config_file_exists?
    end
    
    def self.global
      @global ||= begin
        home = ENV['HOME'] || ENV['USERPROFILE']
        config_dir = File.join(home, '.config', 'git-lite')
        Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
        
        config = new
        config.instance_variable_set(:@global_config_file, File.join(config_dir, 'config.json'))
        config.load_global
        config
      end
    end
    
    def config_file
      @repo_path ? File.join(@repo_path, '.git-lite', 'config.json') : @global_config_file
    end
    
    def config_file_exists?
      File.exist?(config_file)
    end
    
    def load
      return unless config_file_exists?
      
      data = JSON.parse(File.read(config_file), symbolize_names: true)
      @user_name = data[:user_name] || ''
      @user_email = data[:user_email] || ''
      @remotes = data[:remotes] || {}
    rescue JSON::ParserError
      # Use defaults
    end
    
    def load_global
      return unless config_file_exists?
      
      data = JSON.parse(File.read(config_file), symbolize_names: true)
      @user_name = data[:user_name] || ''
      @user_email = data[:user_email] || ''
    rescue JSON::ParserError
      # Use defaults
    end
    
    def save
      data = {
        user_name: @user_name,
        user_email: @user_email,
        remotes: @remotes
      }
      
      File.write(config_file, JSON.pretty_generate(data))
    end
    
    def get(key)
      case key
      when 'user.name' then @user_name
      when 'user.email' then @user_email
      else
        # Check remotes
        if key.start_with?('remote.')
          parts = key.split('.')
          remote_name = parts[1]
          attr = parts[2]
          
          if attr == 'url'
            @remotes[remote_name]
          end
        end
      end
    end
    
    def set(key, value)
      case key
      when 'user.name'
        @user_name = value
      when 'user.email'
        @user_email = value
      else
        if key.start_with?('remote.')
          parts = key.split('.')
          remote_name = parts[1]
          attr = parts[2]
          
          if attr == 'url'
            @remotes[remote_name] = value
          end
        end
      end
      
      save
    end
    
    def add_remote(name, url)
      @remotes[name] = url
      save
    end
    
    def remove_remote(name)
      @remotes.delete(name)
      save
    end
    
    def get_remote(name)
      @remotes[name]
    end
    
    def effective_user_name
      @user_name.empty? ? Config.global.user_name : @user_name
    end
    
    def effective_user_email
      @user_email.empty? ? Config.global.user_email : @user_email
    end
  end
end
