require_relative 'test_helper'

class EdgeCasesTest < GitLite::TestCase
  def setup
    super
    @repo = GitLite::Repo.init(@tmpdir)
  end

  def teardown
    @repo.close if @repo
    super
  end

  def test_empty_file
    create_test_file('empty.txt', '')
    @repo.stage_file('empty.txt')
    commit = @repo.commit('Add empty file')

    blob = @repo.db.get_blob('empty.txt', commit)
    assert_equal '', blob[:content]
  end

  def test_very_long_filename
    long_name = 'a' * 200 + '.txt'
    create_test_file(long_name, 'content')
    @repo.stage_file(long_name)
    commit = @repo.commit('Long filename')

    blob = @repo.db.get_blob(long_name, commit)
    assert_equal 'content', blob[:content]
  end

  def test_deeply_nested_path
    deep_path = 'a/b/c/d/e/f/g/h/i/j/deep.txt'
    create_test_file(deep_path, 'deep content')
    @repo.stage_file(deep_path)
    commit = @repo.commit('Deep path')

    blob = @repo.db.get_blob(deep_path, commit)
    assert_equal 'deep content', blob[:content]
  end

  def test_special_characters_in_content
    special = "Special: \t\n\r\\\"'<>"
    create_test_file('special.txt', special)
    @repo.stage_file('special.txt')
    commit = @repo.commit('Special chars')

    blob = @repo.db.get_blob('special.txt', commit)
    assert_equal special, blob[:content]
  end

  def test_multiline_commit_message
    message = "First line\n\nSecond paragraph\nThird line"
    create_test_file('test.txt', 'test')
    @repo.stage_file('test.txt')
    commit = @repo.commit(message)

    retrieved = @repo.get_commit(commit)
    assert_equal message, retrieved[:message]
  end

  def test_single_character_files
    ('a'..'z').each do |char|
      create_test_file("#{char}.txt", char)
      @repo.stage_file("#{char}.txt")
    end

    commit = @repo.commit('Alphabet')

    ('a'..'z').each do |char|
      blob = @repo.db.get_blob("#{char}.txt", commit)
      assert_equal char, blob[:content]
    end
  end

  def test_large_number_of_files
    100.times do |i|
      create_test_file("file#{i}.txt", "content#{i}")
      @repo.stage_file("file#{i}.txt")
    end

    commit = @repo.commit('Many files')

    blobs = @repo.db.get_tree(commit)
    assert_equal 100, blobs.length
  end

  def test_file_with_only_whitespace
    create_test_file('whitespace.txt', "   \n\t\n  ")
    @repo.stage_file('whitespace.txt')
    commit = @repo.commit('Whitespace')

    blob = @repo.db.get_blob('whitespace.txt', commit)
    assert_equal "   \n\t\n  ", blob[:content]
  end

  def test_symlink
    target = File.join(@tmpdir, 'target.txt')
    File.write(target, 'target content')

    link = File.join(@tmpdir, 'link.txt')
    File.symlink(target, link)

    @repo.stage_file('link.txt')
    commit = @repo.commit('Symlink')

    blob = @repo.db.get_blob('link.txt', commit)
    assert blob[:is_symlink]
    assert_equal target, blob[:symlink_target]
  end

  def test_executable_file
    create_test_file('script.sh', '#!/bin/bash\necho hello')
    File.chmod(0755, File.join(@tmpdir, 'script.sh'))

    @repo.stage_file('script.sh')
    commit = @repo.commit('Executable')

    blob = @repo.db.get_blob('script.sh', commit)
    assert_equal 0755, blob[:mode]
  end

  def test_repeated_add_same_file
    create_test_file('test.txt', 'v1')
    @repo.stage_file('test.txt')
    @repo.commit('First')

    # Modify and add again
    create_test_file('test.txt', 'v2')
    @repo.stage_file('test.txt')

    staged = @repo.staged_changes
    assert_equal 1, staged.length
  end

  def test_checkout_nonexistent_commit
    assert_raises { @repo.checkout('nonexistent123') }
  end

  def test_log_with_no_commits
    log = @repo.log
    assert_empty log
  end

  def test_status_with_untracked_in_subdir
    subdir = File.join(@tmpdir, 'subdir')
    Dir.mkdir(subdir)
    create_test_file('subdir/nested.txt', 'nested')

    untracked = @repo.untracked_files
    assert_includes untracked, 'subdir/nested.txt'
  end

  def test_content_with_null_bytes
    data = "before\x00after"
    create_test_file('binary.bin', data)
    @repo.stage_file('binary.bin')
    commit = @repo.commit('Null bytes')

    blob = @repo.db.get_blob('binary.bin', commit)
    assert blob[:is_binary]
    assert_equal data, blob[:content]
  end

  def test_very_large_commit_message
    message = 'A' * 10000
    create_test_file('test.txt', 'test')
    @repo.stage_file('test.txt')
    commit = @repo.commit(message)

    retrieved = @repo.get_commit(commit)
    assert_equal message, retrieved[:message]
  end

  def test_dotfile
    create_test_file('.hidden', 'secret')
    @repo.stage_file('.hidden')
    commit = @repo.commit('Hidden file')

    blob = @repo.db.get_blob('.hidden', commit)
    assert_equal 'secret', blob[:content]
  end

  def test_filename_with_spaces
    create_test_file('file with spaces.txt', 'content')
    @repo.stage_file('file with spaces.txt')
    commit = @repo.commit('Spaces')

    blob = @repo.db.get_blob('file with spaces.txt', commit)
    assert_equal 'content', blob[:content]
  end
end

MTest::Unit.new.run
