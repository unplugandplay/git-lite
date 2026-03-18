require_relative 'test_helper'

class RepoTest < GitLite::TestCase
  def setup
    super
    @repo = GitLite::Repo.init(@tmpdir)
  end

  def teardown
    @repo.close if @repo
    super
  end

  def test_init_creates_repo
    assert File.directory?(File.join(@tmpdir, '.git-lite'))
    assert File.exist?(File.join(@tmpdir, '.git-lite', 'repo.db'))
  end

  def test_open_finds_repo
    repo = GitLite::Repo.open(@tmpdir)
    assert_equal @tmpdir, repo.root
    repo.close
  end

  def test_head_is_nil_initially
    assert_nil @repo.head
  end

  def test_current_branch
    assert_equal 'main', @repo.current_branch
  end

  def test_branches
    assert_includes @repo.branches, 'main'
  end

  def test_stage_file
    create_test_file('test.txt', 'content')
    @repo.stage_file('test.txt')

    staged = @repo.staged_changes
    assert_equal 1, staged.length
    assert_equal 'test.txt', staged[0][:path]
    assert_equal :added, staged[0][:status]
  end

  def test_stage_multiple_files
    create_test_file('file1.txt', 'content1')
    create_test_file('file2.txt', 'content2')

    @repo.stage_file('file1.txt')
    @repo.stage_file('file2.txt')

    staged = @repo.staged_changes
    assert_equal 2, staged.length
  end

  def test_stage_deletion
    @repo.stage_deletion('old_file.txt')

    staged = @repo.staged_changes
    assert_equal 1, staged.length
    assert_equal :deleted, staged[0][:status]
  end

  def test_move_file
    @repo.move_file('old.txt', 'new.txt')

    staged = @repo.staged_changes
    assert_equal 2, staged.length

    paths = staged.map { |s| s[:path] }
    assert_includes paths, 'old.txt'
    assert_includes paths, 'new.txt'
  end

  def test_reset_staging
    create_test_file('test.txt', 'content')
    @repo.stage_file('test.txt')

    @repo.reset_staging

    staged = @repo.staged_changes
    assert_empty staged
  end

  def test_staged_changes_returns_empty_when_no_staging
    assert_empty @repo.staged_changes
  end

  def test_commit_creates_commit
    create_test_file('test.txt', 'Hello World')
    @repo.stage_file('test.txt')

    commit_id = @repo.commit('Initial commit')

    refute_nil commit_id
    assert_equal 26, commit_id.length  # ULID-like format

    commit = @repo.get_commit(commit_id)
    assert_equal 'Initial commit', commit[:message]
    assert_equal commit_id, @repo.head
  end

  def test_commit_requires_staged_changes
    assert_raises { @repo.commit('Empty commit') }
  end

  def test_commit_requires_message
    create_test_file('test.txt', 'content')
    @repo.stage_file('test.txt')

    assert_raises { @repo.commit('') }
  end

  def test_commit_sets_parent
    create_test_file('file1.txt', 'content1')
    @repo.stage_file('file1.txt')
    first_commit = @repo.commit('First')

    create_test_file('file2.txt', 'content2')
    @repo.stage_file('file2.txt')
    second_commit = @repo.commit('Second')

    second = @repo.get_commit(second_commit)
    assert_equal first_commit, second[:parent_id]
  end

  def test_log_returns_commits
    create_test_file('file.txt', 'v1')
    @repo.stage_file('file.txt')
    @repo.commit('First')

    create_test_file('file.txt', 'v2')
    @repo.stage_file('file.txt')
    @repo.commit('Second')

    log = @repo.log
    assert_equal 2, log.length
    assert_equal 'Second', log[0][:message]
    assert_equal 'First', log[1][:message]
  end

  def test_log_respects_limit
    5.times do |i|
      create_test_file("file#{i}.txt", "content#{i}")
      @repo.stage_file("file#{i}.txt")
      @repo.commit("Commit #{i}")
    end

    log = @repo.log(3)
    assert_equal 3, log.length
  end

  def test_log_empty_repo
    assert_empty @repo.log
  end

  def test_create_branch
    create_test_file('test.txt', 'content')
    @repo.stage_file('test.txt')
    @repo.commit('Initial')

    @repo.create_branch('feature')

    ref = @repo.db.get_ref('feature')
    refute_nil ref
    assert_equal @repo.head, ref[:commit_id]
  end

  def test_create_branch_without_commits_raises
    assert_raises { @repo.create_branch('feature') }
  end

  def test_checkout_restores_files
    create_test_file('test.txt', 'version 1')
    @repo.stage_file('test.txt')
    commit1 = @repo.commit('First')

    create_test_file('test.txt', 'version 2')
    @repo.stage_file('test.txt')
    @repo.commit('Second')

    @repo.checkout(commit1)

    content = File.read(File.join(@tmpdir, 'test.txt'))
    assert_equal 'version 1', content
  end

  def test_checkout_updates_head
    create_test_file('test.txt', 'v1')
    @repo.stage_file('test.txt')
    commit1 = @repo.commit('First')

    create_test_file('test.txt', 'v2')
    @repo.stage_file('test.txt')
    @repo.commit('Second')

    @repo.checkout(commit1)

    assert_equal commit1, @repo.head
  end

  def test_untracked_files
    create_test_file('tracked.txt', 'tracked')
    @repo.stage_file('tracked.txt')
    @repo.commit('Add tracked')

    create_test_file('untracked.txt', 'untracked')

    untracked = @repo.untracked_files

    assert_includes untracked, 'untracked.txt'
    refute_includes untracked, 'tracked.txt'
  end

  def test_untracked_files_empty_repo
    assert_empty @repo.untracked_files
  end

  def test_unstaged_changes_detects_modifications
    create_test_file('test.txt', 'original')
    @repo.stage_file('test.txt')
    @repo.commit('Initial')

    File.write(File.join(@tmpdir, 'test.txt'), 'modified')

    unstaged = @repo.unstaged_changes

    assert_equal 1, unstaged.length
    assert_equal 'test.txt', unstaged[0][:path]
    assert_equal :modified, unstaged[0][:status]
  end

  def test_unstaged_changes_detects_deletions
    create_test_file('test.txt', 'content')
    @repo.stage_file('test.txt')
    @repo.commit('Initial')

    File.delete(File.join(@tmpdir, 'test.txt'))

    unstaged = @repo.unstaged_changes

    assert_equal 1, unstaged.length
    assert_equal :deleted, unstaged[0][:status]
  end

  def test_commit_preserves_file_modes
    create_test_file('script.sh', '#!/bin/bash')
    File.chmod(0755, File.join(@tmpdir, 'script.sh'))
    @repo.stage_file('script.sh')
    @repo.commit('Add script')

    mode = File.stat(File.join(@tmpdir, 'script.sh')).mode & 0o7777
    assert_equal 0755, mode
  end

  def test_binary_file_handling
    binary_data = (0..255).to_a.pack('C*')
    create_test_file('binary.bin', binary_data)
    @repo.stage_file('binary.bin')
    @repo.commit('Add binary')

    commit_id = @repo.head
    blobs = @repo.db.get_blobs_at_commit(commit_id)
    blob = blobs.find { |b| b[:path] == 'binary.bin' }

    assert blob[:is_binary]
  end

  def test_generate_diff
    diff = @repo.generate_diff('test.txt', 'line 1\nline 2', 'line 1\nmodified line 2')

    assert_includes diff, '-line 2'
    assert_includes diff, '+modified line 2'
  end

  def test_generate_diff_with_nil_old
    diff = @repo.generate_diff('new.txt', nil, 'new content')

    assert_includes diff, '+new content'
  end
end

MTest::Unit.new.run
