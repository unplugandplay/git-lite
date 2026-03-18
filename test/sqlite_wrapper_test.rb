# Test SQLite wrapper
class SQLiteWrapperTest < MTest::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir('gl-test')
    @db_path = "#{@tmpdir}/test.db"
    @wrapper = GitLite::SQLiteWrapper.new(@db_path).connect
    @wrapper.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, value TEXT)")
  end

  def teardown
    @wrapper.close if @wrapper
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  def test_execute_insert_and_select
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    rows = @wrapper.execute("SELECT * FROM test")
    assert_equal 1, rows.length
    assert_equal 'key1', rows[0]['name']
  end

  def test_get_first_row
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    row = @wrapper.get_first_row("SELECT * FROM test WHERE name = ?", 'key1')
    assert_equal 'key1', row['name']
    assert_equal 'val1', row['value']
  end

  def test_get_first_value
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    val = @wrapper.get_first_value("SELECT value FROM test WHERE name = ?", 'key1')
    assert_equal 'val1', val
  end

  def test_get_first_row_returns_nil_for_missing
    row = @wrapper.get_first_row("SELECT * FROM test WHERE name = ?", 'missing')
    assert_nil row
  end

  def test_last_insert_row_id
    @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['key1', 'val1'])
    id = @wrapper.last_insert_row_id
    assert_equal 1, id.to_i
  end

  def test_transaction_commits
    @wrapper.transaction do
      @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['k1', 'v1'])
      @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['k2', 'v2'])
    end
    val = @wrapper.get_first_value("SELECT COUNT(*) FROM test")
    assert_equal 2, val.to_i
  end

  def test_transaction_rolls_back_on_error
    begin
      @wrapper.transaction do
        @wrapper.execute("INSERT INTO test (name, value) VALUES (?, ?)", ['k1', 'v1'])
        raise "test error"
      end
    rescue
    end
    val = @wrapper.get_first_value("SELECT COUNT(*) FROM test")
    assert_equal 0, val.to_i
  end
end

MTest::Unit.new.run
