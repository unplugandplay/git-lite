# test/test_helper.rb - mruby-mtest based test setup

$LOAD_PATH.unshift File.expand_path('../lib', __dir__) if defined?($LOAD_PATH)

require 'git-lite'

module GitLite
  class TestCase < MTest::Unit::TestCase
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
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) if path.include?('/')
      File.write(path, content)
    end

    def capture_io
      old_stdout = $stdout
      $stdout = StringIO.new
      yield
      [$stdout.string, '']
    ensure
      $stdout = old_stdout
    end

    def assert_in_delta(expected, actual, delta = 0.001)
      assert (expected - actual).abs <= delta,
        "Expected #{expected} to be within #{delta} of #{actual}"
    end

    def assert_includes(collection, item, msg = nil)
      assert collection.include?(item), msg || "Expected collection to include #{item}"
    end

    def refute_includes(collection, item, msg = nil)
      refute collection.include?(item), msg || "Expected collection to not include #{item}"
    end

    def assert_empty(collection, msg = nil)
      assert collection.empty?, msg || "Expected collection to be empty"
    end

    def refute_empty(collection, msg = nil)
      refute collection.empty?, msg || "Expected collection to not be empty"
    end

    def assert_instance_of(klass, obj, msg = nil)
      assert obj.is_a?(klass), msg || "Expected #{obj.class} to be #{klass}"
    end

    def assert_match(pattern, string, msg = nil)
      if pattern.is_a?(String)
        assert string.include?(pattern), msg || "Expected '#{string}' to match '#{pattern}'"
      else
        assert pattern.match(string), msg || "Expected '#{string}' to match #{pattern}"
      end
    end

    def assert_nil(obj, msg = nil)
      assert obj.nil?, msg || "Expected nil but got #{obj.inspect}"
    end

    def refute_nil(obj, msg = nil)
      refute obj.nil?, msg || "Expected non-nil"
    end

    def assert_raises(exception_class = StandardError)
      begin
        yield
        assert false, "Expected #{exception_class} to be raised"
      rescue => e
        if exception_class
          assert e.is_a?(exception_class), "Expected #{exception_class} but got #{e.class}: #{e.message}"
        end
      end
    end

    def refute(test, msg = nil)
      assert !test, msg || "Expected false but got true"
    end
  end
end
