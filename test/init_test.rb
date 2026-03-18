require_relative 'test_helper'

class InitTest < GitLite::TestCase
  def test_init_creates_directory
    repo = GitLite::Repo.init(@tmpdir)

    assert File.directory?(File.join(@tmpdir, '.git-lite'))
    assert File.exist?(File.join(@tmpdir, '.git-lite', 'config.json'))
    assert File.exist?(File.join(@tmpdir, '.git-lite', 'repo.db'))
  end

  def test_init_raises_on_existing_repo
    GitLite::Repo.init(@tmpdir)

    assert_raises(GitLite::AlreadyInitializedError) do
      GitLite::Repo.init(@tmpdir)
    end
  end

  def test_open_finds_repo
    GitLite::Repo.init(@tmpdir)

    # Create subdirectory
    subdir = File.join(@tmpdir, 'subdir')
    Dir.mkdir(subdir)
    Dir.chdir(subdir)

    repo = GitLite::Repo.open
    assert_equal @tmpdir, repo.root
  end

  def test_open_raises_when_not_repo
    assert_raises(GitLite::NotARepoError) do
      GitLite::Repo.open
    end
  end
end

MTest::Unit.new.run
