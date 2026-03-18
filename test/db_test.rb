require_relative 'test_helper'

class DBTest < GitLite::TestCase
  def setup
    super
    @db_path = File.join(@tmpdir, 'test.db')
    @db = GitLite::DB.new(@db_path).connect
    @db.init_schema
  end
  
  def teardown
    @db.close if @db
    super
  end
  
  def test_schema_initialized
    assert @db.schema_exists?
    assert_equal 1, @db.get_schema_version
  end
  
  def test_commit_crud
    commit = {
      id: 'test123',
      parent_id: nil,
      tree_hash: 'tree456',
      message: 'Test commit',
      author_name: 'Test User',
      author_email: 'test@example.com',
      authored_at: Time.now,
      committer_name: 'Test User',
      committer_email: 'test@example.com',
      committed_at: Time.now
    }
    
    @db.create_commit(commit)
    
    retrieved = @db.get_commit('test123')
    assert_equal 'test123', retrieved[:id]
    assert_equal 'Test commit', retrieved[:message]
  end
  
  def test_ref_management
    @db.set_ref('HEAD', 'commit123')
    
    head = @db.get_head
    assert_equal 'commit123', head
    
    ref = @db.get_ref('HEAD')
    assert_equal 'HEAD', ref[:name]
    assert_equal 'commit123', ref[:commit_id]
  end
  
  def test_path_management
    path_id, group_id = @db.get_or_create_path('src/main.rb')
    
    assert path_id > 0
    assert group_id > 0
    
    # Getting existing path should return same IDs
    path_id2, group_id2 = @db.get_or_create_path('src/main.rb')
    assert_equal path_id, path_id2
    assert_equal group_id, group_id2
  end
  
  def test_metadata
    @db.set_metadata('test_key', 'test_value')
    assert_equal 'test_value', @db.get_metadata('test_key')
    
    @db.set_metadata('test_key', 'updated')
    assert_equal 'updated', @db.get_metadata('test_key')
  end
end
