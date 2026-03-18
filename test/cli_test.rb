require_relative 'test_helper'

class CLITest < GitLite::TestCase
  def setup
    super
    @original_stdout = $stdout
    $stdout = StringIO.new
  end

  def teardown
    $stdout = @original_stdout
    super
  end

  def capture_output
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  def test_init_command
    output = capture_output do
      GitLite::CLI.run(['init', @tmpdir])
    end

    assert_includes output, 'Initialized'
    assert File.directory?(File.join(@tmpdir, '.git-lite'))
  end

  def test_init_reinitializes_existing
    GitLite::CLI.run(['init', @tmpdir])

    output = capture_output do
      GitLite::CLI.run(['init', @tmpdir])
    end

    assert_includes output, 'Reinitialized'
  end

  def test_help_command
    output = capture_output do
      GitLite::CLI.run(['help'])
    end

    assert_includes output, 'git-lite'
    assert_includes output, 'init'
    assert_includes output, 'add'
    assert_includes output, 'commit'
  end

  def test_version_command
    output = capture_output do
      GitLite::CLI.run(['version'])
    end

    assert_includes output, GitLite::VERSION
  end

  def test_status_not_a_repo
    output = capture_output do
      begin
        GitLite::CLI.run(['status'])
      rescue SystemExit
      end
    end

    assert_includes output, 'Not a git-lite repository'
  end

  def test_status_empty_repo
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      GitLite::CLI.run(['status'])
    end

    assert_includes output, 'On branch main'
  end

  def test_add_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('test.txt', 'content')

    output = capture_output do
      GitLite::CLI.run(['add', 'test.txt'])
    end

    assert_includes output, 'Staged'
  end

  def test_add_no_args
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      GitLite::CLI.run(['add'])
    end

    assert_includes output, 'Nothing specified'
  end

  def test_rm_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      GitLite::CLI.run(['rm', 'old.txt'])
    end

    assert_includes output, 'Removed'
  end

  def test_mv_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      GitLite::CLI.run(['mv', 'old.txt', 'new.txt'])
    end

    assert_includes output, 'Renamed'
  end

  def test_mv_missing_args
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    assert_raises(SystemExit) do
      GitLite::CLI.run(['mv', 'only_one'])
    end
  end

  def test_commit_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('test.txt', 'content')
    GitLite::CLI.run(['add', 'test.txt'])

    output = capture_output do
      GitLite::CLI.run(['commit', '-m', 'Test commit'])
    end

    assert_includes output, 'Test commit'
    assert_includes output, '[main'
  end

  def test_commit_no_message
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      begin
        GitLite::CLI.run(['commit'])
      rescue SystemExit
      end
    end

    assert_includes output, 'empty commit message'
  end

  def test_commit_nothing_staged
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      begin
        GitLite::CLI.run(['commit', '-m', 'Empty'])
      rescue SystemExit
      end
    end

    assert_includes output, 'Nothing to commit'
  end

  def test_log_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('test.txt', 'content')
    GitLite::CLI.run(['add', 'test.txt'])
    GitLite::CLI.run(['commit', '-m', 'Test'])

    output = capture_output do
      GitLite::CLI.run(['log'])
    end

    assert_includes output, 'commit'
    assert_includes output, 'Test'
    assert_includes output, 'Author:'
  end

  def test_branch_list
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('test.txt', 'content')
    GitLite::CLI.run(['add', 'test.txt'])
    GitLite::CLI.run(['commit', '-m', 'Initial'])

    output = capture_output do
      GitLite::CLI.run(['branch'])
    end

    assert_includes output, '* main'
  end

  def test_branch_create
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('test.txt', 'content')
    GitLite::CLI.run(['add', 'test.txt'])
    GitLite::CLI.run(['commit', '-m', 'Initial'])

    output = capture_output do
      GitLite::CLI.run(['branch', 'feature'])
    end

    assert_includes output, 'Created branch'
  end

  def test_reset_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('test.txt', 'content')
    GitLite::CLI.run(['add', 'test.txt'])

    output = capture_output do
      GitLite::CLI.run(['reset'])
    end

    assert_includes output, 'Staging area reset'
  end

  def test_config_set
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      GitLite::CLI.run(['config', 'user.name', 'Test User'])
    end

    repo = GitLite::Repo.open(@tmpdir)
    assert_equal 'Test User', repo.config.user_name
  end

  def test_config_get
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    capture_output do
      GitLite::CLI.run(['config', 'user.email', 'test@example.com'])
    end

    output = capture_output do
      GitLite::CLI.run(['config', 'user.email'])
    end

    assert_includes output, 'test@example.com'
  end

  def test_stats_command
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)

    output = capture_output do
      GitLite::CLI.run(['stats'])
    end

    assert_includes output, 'Repository Statistics'
    assert_includes output, 'Commits:'
  end

  def test_clean_dry_run
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('untracked.txt', 'untracked')

    output = capture_output do
      GitLite::CLI.run(['clean'])
    end

    assert_includes output, 'Would remove'
    assert File.exist?('untracked.txt')
  end

  def test_clean_force
    GitLite::Repo.init(@tmpdir)
    Dir.chdir(@tmpdir)
    create_test_file('tracked.txt', 'tracked')
    GitLite::CLI.run(['add', 'tracked.txt'])
    GitLite::CLI.run(['commit', '-m', 'Initial'])

    create_test_file('untracked.txt', 'untracked')

    output = capture_output do
      GitLite::CLI.run(['clean', '-f'])
    end

    assert_includes output, 'Removed'
    refute File.exist?('untracked.txt')
    assert File.exist?('tracked.txt')
  end

  def test_unknown_command
    output = capture_output do
      begin
        GitLite::CLI.run(['unknown'])
      rescue SystemExit
      end
    end

    assert_includes output, 'Unknown command'
  end

  def test_no_command_shows_help
    output = capture_output do
      GitLite::CLI.run([])
    end

    assert_includes output, 'git-lite'
    assert_includes output, 'init'
  end
end

MTest::Unit.new.run
