require_relative 'test_helper'

class DBAdvancedTest < GitLite::TestCase
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
  
  def test_batch_commit_insertion
    commits = 100.times.map do |i|
      {
        id: "commit#{i}",
        parent_id: i > 0 ? "commit#{i-1}" : nil,
        tree_hash: "tree#{i}",
        message: "Commit #{i}",
        author_name: 'Test',
        author_email: 'test@test.com',
        authored_at: Time.now - i,
        committer_name: 'Test',
        committer_email: 'test@test.com',
        committed_at: Time.now - i
      }
    end
    
    @db.create_commits_batch(commits)
    
    assert_equal 100, @db.count_commits
  end
  
  def test_batch_file_ref_insertion
    # First create a commit and path
    @db.create_commit({
      id: 'test1',
      parent_id: nil,
      tree_hash: 'tree1',
      message: 'Test',
      author_name: 'Test',
      author_email: 'test@test.com',
      authored_at: Time.now,
      committer_name: 'Test',
      committer_email: 'test@test.com',
      committed_at: Time.now
    })
    
    path_id, _ = @db.get_or_create_path('test.txt')
    
    refs = 50.times.map do |i|
      {
        path_id: path_id,
        commit_id: 'test1',
        version_id: i + 1,
        content_hash: Digest::SHA256.hexdigest("content#{i}"),
        mode: 0o100644,
        is_symlink: false,
        symlink_target: nil,
        is_binary: false
      }
    end
    
    @db.create_file_refs_batch(refs)
    
    count = @db.execute('SELECT COUNT(*) as c FROM file_refs').first['c']
    assert_equal 50, count
  end
  
  def test_concurrent_path_creation
    paths = %w[a.txt b.txt c.txt d.txt e.txt]
    
    # Simulate concurrent creation by calling multiple times
    path_ids = paths.map { |p| @db.get_or_create_path(p) }
    
    # Should return consistent IDs
    paths.each_with_index do |path, i|
      id, _ = @db.get_or_create_path(path)
      assert_equal path_ids[i][0], id
    end
  end
  
  def test_get_tree_with_deletions
    # Setup
    @db.create_commit({
      id: 'c1',
      parent_id: nil,
      tree_hash: 't1',
      message: 'First',
      author_name: 'Test',
      author_email: 'test@test.com',
      authored_at: Time.now,
      committer_name: 'Test',
      committer_email: 'test@test.com',
      committed_at: Time.now
    })
    
    @db.create_commit({
      id: 'c2',
      parent_id: 'c1',
      tree_hash: 't2',
      message: 'Second',
      author_name: 'Test',
      author_email: 'test@test.com',
      authored_at: Time.now,
      committer_name: 'Test',
      committer_email: 'test@test.com',
      committed_at: Time.now
    })
    
    path_id1, _ = @db.get_or_create_path('keep.txt')
    path_id2, _ = @db.get_or_create_path('delete.txt')
    
    # Add both files in c1
    @db.create_file_ref({
      path_id: path_id1,
      commit_id: 'c1',
      version_id: 1,
      content_hash: 'hash1',
      mode: 0o100644,
      is_symlink: false,
      symlink_target: nil,
      is_binary: false
    })
    
    @db.create_file_ref({
      path_id: path_id2,
      commit_id: 'c1',
      version_id: 1,
      content_hash: 'hash2',
      mode: 0o100644,
      is_symlink: false,
      symlink_target: nil,
      is_binary: false
    })
    
    # Delete in c2 (null hash)
    @db.create_file_ref({
      path_id: path_id2,
      commit_id: 'c2',
      version_id: 2,
      content_hash: nil,
      mode: 0,
      is_symlink: false,
      symlink_target: nil,
      is_binary: false
    })
    
    # Get tree at c2
    tree = @db.get_tree('c2')
    
    paths = tree.map { |b| b[:path] }
    assert_includes paths, 'keep.txt'
    refute_includes paths, 'delete.txt'
  end
  
  def test_find_commit_by_prefix
    @db.create_commit({
      id: 'abcd1234xyz',
      parent_id: nil,
      tree_hash: 't1',
      message: 'Test',
      author_name: 'Test',
      author_email: 'test@test.com',
      authored_at: Time.now,
      committer_name: 'Test',
      committer_email: 'test@test.com',
      committed_at: Time.now
    })
    
    found = @db.find_commit_by_prefix('abcd')
    assert_equal 'abcd1234xyz', found[:id]
    
    found = @db.find_commit_by_prefix('abcd1234')
    assert_equal 'abcd1234xyz', found[:id]
    
    not_found = @db.find_commit_by_prefix('zzzz')
    assert_nil not_found
  end
  
  def test_metadata_operations
    @db.set_metadata('key1', 'value1')
    @db.set_metadata('key2', 'value2')
    
    assert_equal 'value1', @db.get_metadata('key1')
    assert_equal 'value2', @db.get_metadata('key2')
    
    @db.set_metadata('key1', 'updated')
    assert_equal 'updated', @db.get_metadata('key1')
  end
  
  def test_repo_path_metadata
    @db.set_repo_path('/some/path')
    assert_equal '/some/path', @db.get_repo_path
    
    @db.set_repo_path('/other/path')
    assert_equal '/other/path', @db.get_repo_path
  end
  
  def test_all_refs
    @db.set_ref('HEAD', 'commit1')
    @db.set_ref('main', 'commit1')
    @db.set_ref('feature', 'commit2')
    
    refs = @db.get_all_refs
    names = refs.map { |r| r[:name] }
    
    assert_includes names, 'HEAD'
    assert_includes names, 'main'
    assert_includes names, 'feature'
  end
  
  def test_delete_ref
    @db.set_ref('temp', 'commit1')
    assert @db.get_ref('temp')
    
    @db.delete_ref('temp')
    assert_nil @db.get_ref('temp')
  end
  
  def test_schema_version
    assert_equal 1, @db.get_schema_version
  end
  
  def test_drop_and_reinit_schema
    @db.drop_schema
    refute @db.schema_exists?
    
    @db.init_schema
    assert @db.schema_exists?
    assert_equal 1, @db.get_schema_version
  end
  
  def test_wal_mode_enabled
    result = @db.execute("PRAGMA journal_mode")
    assert_equal 'wal', result.first['journal_mode'].downcase
  end
  
  def test_foreign_keys_enabled
    result = @db.execute("PRAGMA foreign_keys")
    assert_equal 1, result.first['foreign_keys']
  end
  
  def test_content_store_stats
    @db.content_store.store(1, 1, "Keyframe content")
    @db.content_store.store(1, 2, "Delta content")
    
    stats = @db.content_store.stats
    
    assert stats[:versions] >= 2
    assert stats[:keyframes] >= 1
    assert stats[:total_bytes] > 0
  end
end
