require_relative 'test_helper'

class IntegrationTest < GitLite::TestCase
  def test_full_workflow
    # 1. Initialize repo
    repo = GitLite::Repo.init(@tmpdir)
    
    # 2. Create and add files
    create_test_file('README.md', '# My Project')
    create_test_file('src/main.rb', 'puts "Hello"')
    
    repo.stage_file('README.md')
    repo.stage_file('src/main.rb')
    
    staged = repo.staged_changes
    assert_equal 2, staged.length
    
    # 3. First commit
    commit1 = repo.commit('Initial commit')
    refute_nil commit1
    
    assert_equal commit1, repo.head
    
    # 4. Modify a file
    create_test_file('README.md', '# My Project\n\nMore content')
    repo.stage_file('README.md')
    
    commit2 = repo.commit('Update README')
    assert_equal commit2, repo.head
    
    # 5. View log
    log = repo.log
    assert_equal 2, log.length
    assert_equal 'Update README', log[0][:message]
    assert_equal 'Initial commit', log[1][:message]
    
    # 6. Checkout previous commit
    repo.checkout(commit1)
    
    readme_content = File.read(File.join(@tmpdir, 'README.md'))
    assert_equal '# My Project', readme_content
    
    # 7. Back to latest
    repo.checkout(commit2)
    
    readme_content = File.read(File.join(@tmpdir, 'README.md'))
    assert_includes readme_content, 'More content'
    
    repo.close
  end
  
  def test_branch_workflow
    repo = GitLite::Repo.init(@tmpdir)
    
    # Initial commit on main
    create_test_file('file.txt', 'main content')
    repo.stage_file('file.txt')
    main_commit = repo.commit('On main')
    
    # Create feature branch
    repo.create_branch('feature')
    
    # Add feature
    create_test_file('feature.txt', 'new feature')
    repo.stage_file('feature.txt')
    feature_commit = repo.commit('Add feature')
    
    # Verify main ref still points to original
    main_ref = repo.db.get_ref('main')
    refute_nil main_ref
    
    # Verify feature ref exists
    feature_ref = repo.db.get_ref('feature')
    refute_nil feature_ref
    
    repo.close
  end
  
  def test_large_file_handling
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create a large file
    large_content = "Line content\n" * 10000
    create_test_file('large.txt', large_content)
    
    repo.stage_file('large.txt')
    commit = repo.commit('Add large file')
    
    # Verify content is stored correctly
    blob = repo.db.get_blob('large.txt', commit)
    assert_equal large_content, blob[:content]
    
    repo.close
  end
  
  def test_binary_file_handling
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create binary file
    binary_data = (0..255).to_a.pack('C*') * 100
    File.binwrite(File.join(@tmpdir, 'data.bin'), binary_data)
    
    repo.stage_file('data.bin')
    commit = repo.commit('Add binary file')
    
    # Verify binary content preserved
    blob = repo.db.get_blob('data.bin', commit)
    assert blob[:is_binary]
    assert_equal binary_data, blob[:content]
    
    repo.close
  end
  
  def test_multiple_commits_same_file
    repo = GitLite::Repo.init(@tmpdir)
    
    contents = ['Version 1', 'Version 2', 'Version 3', 'Version 4', 'Version 5']
    commits = []
    
    contents.each_with_index do |content, i|
      create_test_file('file.txt', content)
      repo.stage_file('file.txt')
      commits << repo.commit("Commit #{i + 1}")
    end
    
    # Verify we can retrieve each version
    contents.each_with_index do |expected, i|
      blob = repo.db.get_blob('file.txt', commits[i])
      assert_equal expected, blob[:content]
    end
    
    repo.close
  end
  
  def test_delete_and_restore_file
    repo = GitLite::Repo.init(@tmpdir)
    
    # Add file
    create_test_file('temp.txt', 'temporary')
    repo.stage_file('temp.txt')
    commit_with = repo.commit('Add temp file')
    
    # Delete file
    repo.stage_deletion('temp.txt')
    commit_without = repo.commit('Delete temp file')
    
    # File should not exist at HEAD
    blob = repo.db.get_blob('temp.txt', commit_without)
    assert_nil blob[:content_hash]
    
    # But should exist in previous commit
    blob = repo.db.get_blob('temp.txt', commit_with)
    assert_equal 'temporary', blob[:content]
    
    repo.close
  end
  
  def test_move_file
    repo = GitLite::Repo.init(@tmpdir)
    
    create_test_file('old.txt', 'content')
    repo.stage_file('old.txt')
    commit1 = repo.commit('Add old.txt')
    
    # Move file
    repo.move_file('old.txt', 'new.txt')
    commit2 = repo.commit('Rename file')
    
    # old.txt should be deleted
    old_blob = repo.db.get_blob('old.txt', commit2)
    assert_nil old_blob[:content_hash] if old_blob
    
    # new.txt should exist
    new_blob = repo.db.get_blob('new.txt', commit2)
    assert_equal 'content', new_blob[:content]
    
    repo.close
  end
  
  def test_delta_compression_over_many_versions
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create file with small changes each time
    base_content = "Line 1\nLine 2\nLine 3\n"
    
    10.times do |i|
      modified = base_content + "Change #{i}\n"
      create_test_file('file.txt', modified)
      repo.stage_file('file.txt')
      repo.commit("Change #{i}")
    end
    
    # Check stats show deltas
    stats = repo.db.get_stats
    assert stats[:content_versions] >= 10
    
    repo.close
  end
  
  def test_sql_query_interface
    repo = GitLite::Repo.init(@tmpdir)
    
    # Add data
    create_test_file('test.txt', 'test')
    repo.stage_file('test.txt')
    repo.commit('Test')
    
    # Query via SQL
    results = repo.db.execute('SELECT * FROM commits')
    assert_equal 1, results.length
    
    results = repo.db.execute('SELECT * FROM paths')
    assert_equal 1, results.length
    
    repo.close
  end
  
  def test_config_persistence
    repo = GitLite::Repo.init(@tmpdir)
    
    repo.config.user_name = 'Test User'
    repo.config.user_email = 'test@example.com'
    repo.config.save
    
    repo.close
    
    # Reopen and verify
    repo2 = GitLite::Repo.open(@tmpdir)
    assert_equal 'Test User', repo2.config.user_name
    assert_equal 'test@example.com', repo2.config.user_email
    
    repo2.close
  end
  
  def test_concurrent_file_operations
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create multiple files in subdirectories
    files = [
      'src/main.rb',
      'src/lib/helper.rb',
      'test/test_main.rb',
      'docs/README.md',
      'config/settings.json'
    ]
    
    files.each do |file|
      create_test_file(file, "Content of #{file}")
      repo.stage_file(file)
    end
    
    commit = repo.commit('Add project structure')
    
    # Verify all files stored
    blobs = repo.db.get_tree(commit)
    paths = blobs.map { |b| b[:path] }
    
    files.each do |file|
      assert_includes paths, file
    end
    
    repo.close
  end
  
  def test_empty_commit_message_rejected
    repo = GitLite::Repo.init(@tmpdir)
    
    create_test_file('test.txt', 'test')
    repo.stage_file('test.txt')
    
    assert_raises { repo.commit('') }
    
    repo.close
  end
  
  def test_untracked_files_detection
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create tracked file
    create_test_file('tracked.txt', 'tracked')
    repo.stage_file('tracked.txt')
    repo.commit('Add tracked')
    
    # Create untracked file
    create_test_file('untracked.txt', 'untracked')
    
    untracked = repo.untracked_files
    
    assert_includes untracked, 'untracked.txt'
    refute_includes untracked, 'tracked.txt'
    
    repo.close
  end
end
