require_relative 'test_helper'

class ConfigTest < GitLite::TestCase
  def setup
    super
    @config_path = File.join(@tmpdir, 'config.json')
    @config = GitLite::Config.new(@tmpdir)
  end
  
  def test_default_values
    assert_equal '', @config.user_name
    assert_equal '', @config.user_email
    assert_empty @config.remotes
  end
  
  def test_set_and_get_user_name
    @config.user_name = "Test User"
    assert_equal "Test User", @config.user_name
  end
  
  def test_set_and_get_user_email
    @config.user_email = "test@example.com"
    assert_equal "test@example.com", @config.user_email
  end
  
  def test_save_and_load
    @config.user_name = "Test User"
    @config.user_email = "test@example.com"
    @config.save
    
    # Create new config instance and load
    new_config = GitLite::Config.new(@tmpdir)
    
    assert_equal "Test User", new_config.user_name
    assert_equal "test@example.com", new_config.user_email
  end
  
  def test_get_value_by_key
    @config.user_name = "Test User"
    @config.user_email = "test@example.com"
    
    assert_equal "Test User", @config.get('user.name')
    assert_equal "test@example.com", @config.get('user.email')
  end
  
  def test_set_value_by_key
    @config.set('user.name', 'New Name')
    @config.set('user.email', 'new@example.com')
    
    assert_equal 'New Name', @config.user_name
    assert_equal 'new@example.com', @config.user_email
  end
  
  def test_get_unknown_key_returns_nil
    assert_nil @config.get('unknown.key')
  end
  
  def test_add_remote
    @config.add_remote('origin', 'https://github.com/user/repo.git')
    
    assert_equal 'https://github.com/user/repo.git', @config.get_remote('origin')
  end
  
  def test_add_multiple_remotes
    @config.add_remote('origin', 'https://github.com/user/repo.git')
    @config.add_remote('upstream', 'https://github.com/original/repo.git')
    
    assert_equal 2, @config.remotes.length
    assert_equal 'https://github.com/user/repo.git', @config.remotes['origin']
    assert_equal 'https://github.com/original/repo.git', @config.remotes['upstream']
  end
  
  def test_remove_remote
    @config.add_remote('origin', 'https://github.com/user/repo.git')
    @config.remove_remote('origin')
    
    assert_nil @config.get_remote('origin')
    assert_empty @config.remotes
  end
  
  def test_remove_nonexistent_remote
    # Should not raise
    @config.remove_remote('nonexistent')
  end
  
  def test_remote_url_via_get
    @config.add_remote('origin', 'https://github.com/user/repo.git')
    
    assert_equal 'https://github.com/user/repo.git', @config.get('remote.origin.url')
  end
  
  def test_set_remote_url
    @config.set('remote.origin.url', 'https://new-url.com/repo.git')
    
    assert_equal 'https://new-url.com/repo.git', @config.get_remote('origin')
  end
  
  def test_effective_user_name_prefers_local
    @config.user_name = "Local User"
    
    assert_equal "Local User", @config.effective_user_name
  end
  
  def test_effective_user_name_falls_back_to_global
    skip "Global config test - would need mock"
  end
  
  def test_persists_remotes
    @config.add_remote('origin', 'https://github.com/user/repo.git')
    @config.add_remote('upstream', 'https://github.com/original/repo.git')
    @config.save
    
    new_config = GitLite::Config.new(@tmpdir)
    
    assert_equal 2, new_config.remotes.length
    assert_equal 'https://github.com/user/repo.git', new_config.remotes['origin']
  end
  
  def test_handles_corrupted_config
    File.write(@config_path, 'not valid json{')
    
    # Should not raise, uses defaults
    config = GitLite::Config.new(@tmpdir)
    assert_equal '', config.user_name
  end
  
  def test_config_file_not_exists
    File.delete(@config_path) if File.exist?(@config_path)
    
    config = GitLite::Config.new(@tmpdir)
    assert_equal '', config.user_name
  end
end
