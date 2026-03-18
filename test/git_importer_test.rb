require_relative 'test_helper'

class GitImporterTest < GitLite::TestCase
  def setup
    super
    @git_repo_path = File.join(@tmpdir, 'source_git_repo')
    Dir.mkdir(@git_repo_path)
    
    # Initialize a git repo
    system("git init #{@git_repo_path} --quiet")
    system("git -C #{@git_repo_path} config user.email 'test@test.com'")
    system("git -C #{@git_repo_path} config user.name 'Test User'")
    
    # Create some commits
    File.write(File.join(@git_repo_path, 'file1.txt'), 'content 1')
    system("git -C #{@git_repo_path} add .")
    system("git -C #{@git_repo_path} commit -m 'First commit' --quiet")
    
    File.write(File.join(@git_repo_path, 'file1.txt'), 'content 2')
    File.write(File.join(@git_repo_path, 'file2.txt'), 'content 3')
    system("git -C #{@git_repo_path} add .")
    system("git -C #{@git_repo_path} commit -m 'Second commit' --quiet")
    
    # Setup git-lite repo
    @pgit_repo = GitLite::Repo.init(@tmpdir)
  end
  
  def teardown
    @pgit_repo.close if @pgit_repo
    super
  end
  
  def test_import_creates_commits
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    count = importer.import_branch('main')
    
    assert count >= 2
    
    stats = @pgit_repo.db.get_stats
    assert stats[:commits] >= 2
  end
  
  def test_import_preserves_commit_messages
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    log = @pgit_repo.log
    messages = log.map { |c| c[:message] }
    
    assert_includes messages, 'First commit'
    assert_includes messages, 'Second commit'
  end
  
  def test_import_preserves_author_info
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    log = @pgit_repo.log
    
    log.each do |commit|
      assert_equal 'Test User', commit[:author_name]
      assert_equal 'test@test.com', commit[:author_email]
    end
  end
  
  def test_import_preserves_file_content
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    head = @pgit_repo.head
    blobs = @pgit_repo.db.get_tree(head)
    
    file1 = blobs.find { |b| b[:path] == 'file1.txt' }
    assert file1
    assert_equal 'content 2', file1[:content]
    
    file2 = blobs.find { |b| b[:path] == 'file2.txt' }
    assert file2
    assert_equal 'content 3', file2[:content]
  end
  
  def test_import_sets_head
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    refute_nil @pgit_repo.head
  end
  
  def test_import_with_binary_files
    # Add a binary file
    binary_data = (0..255).to_a.pack('C*')
    File.binwrite(File.join(@git_repo_path, 'binary.bin'), binary_data)
    system("git -C #{@git_repo_path} add .")
    system("git -C #{@git_repo_path} commit -m 'Add binary' --quiet")
    
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    head = @pgit_repo.head
    blobs = @pgit_repo.db.get_tree(head)
    
    binary = blobs.find { |b| b[:path] == 'binary.bin' }
    assert binary
    assert binary[:is_binary]
    assert_equal binary_data, binary[:content]
  end
  
  def test_import_with_subdirectories
    # Add files in subdirectories
    subdir = File.join(@git_repo_path, 'src')
    Dir.mkdir(subdir)
    File.write(File.join(subdir, 'main.rb'), 'puts "hello"')
    system("git -C #{@git_repo_path} add .")
    system("git -C #{@git_repo_path} commit -m 'Add subdir' --quiet")
    
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    head = @pgit_repo.head
    blobs = @pgit_repo.db.get_tree(head)
    
    paths = blobs.map { |b| b[:path] }
    assert_includes paths, 'src/main.rb'
  end
  
  def test_import_with_file_deletion
    # Delete a file
    File.delete(File.join(@git_repo_path, 'file2.txt'))
    system("git -C #{@git_repo_path} rm file2.txt")
    system("git -C #{@git_repo_path} commit -m 'Delete file' --quiet")
    
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    head = @pgit_repo.head
    blobs = @pgit_repo.db.get_tree(head)
    
    paths = blobs.map { |b| b[:path] }
    refute_includes paths, 'file2.txt'
  end
  
  def test_import_preserves_timestamps
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    importer.import_branch('main')
    
    log = @pgit_repo.log
    
    log.each do |commit|
      assert_instance_of Time, commit[:authored_at]
      assert_instance_of Time, commit[:committed_at]
    end
  end
  
  def test_import_large_repository
    # Create many commits
    20.times do |i|
      File.write(File.join(@git_repo_path, "file_#{i}.txt"), "Content #{i}")
      system("git -C #{@git_repo_path} add .")
      system("git -C #{@git_repo_path} commit -m 'Commit #{i}' --quiet")
    end
    
    importer = GitLite::GitImporter.new(@pgit_repo, @git_repo_path)
    count = importer.import_branch('main')
    
    assert count >= 20
  end
end
