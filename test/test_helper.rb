$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'digest'
require 'json'
require 'git-lite'

module GitLite
  class TestCase < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir('git-lite-test')
      @original_dir = Dir.pwd
      Dir.chdir(@tmpdir)
    end
    
    def teardown
      Dir.chdir(@original_dir)
      FileUtils.rm_rf(@tmpdir)
    end
    
    def create_test_file(path, content = "test content")
      FileUtils.mkdir_p(File.dirname(path)) if path.include?('/')
      File.write(path, content)
    end
    
    def capture_io
      old_stdout = $stdout
      old_stderr = $stderr
      $stdout = StringIO.new
      $stderr = StringIO.new
      yield
      [$stdout.string, $stderr.string]
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
    end
    
    def assert_in_delta(expected, actual, delta = 0.001)
      assert (expected - actual).abs <= delta, 
        "Expected #{expected} to be within #{delta} of #{actual}"
    end
  end
end

# Make sure all test files are loaded
Dir[File.expand_path('*_test.rb', __dir__)].each do |file|
  require file unless file == __FILE__
end
