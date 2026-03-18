require_relative 'test_helper'

class ContentStoreTest < GitLite::TestCase
  def setup
    super
    @db_path = File.join(@tmpdir, 'test.db')
    @db = GitLite::DB.new(@db_path).connect
    @db.init_schema
    @store = @db.content_store
  end

  def teardown
    @db.close if @db
    super
  end

  def test_store_and_retrieve_keyframe
    @store.store(1, 1, "First version of content")

    result = @store.retrieve(1, 1)
    assert_equal "First version of content", result
  end

  def test_store_and_retrieve_delta
    # Store keyframe
    @store.store(1, 1, "Base content for the file")

    # Store delta
    @store.store(1, 2, "Base content for the file with modifications")

    result = @store.retrieve(1, 2)
    assert_equal "Base content for the file with modifications", result
  end

  def test_retrieve_reconstructs_from_keyframe
    content1 = "Line 1\nLine 2\nLine 3"
    content2 = "Line 1\nModified Line 2\nLine 3"
    content3 = "Line 1\nModified Line 2\nModified Line 3"

    @store.store(1, 1, content1)
    @store.store(1, 2, content2)
    @store.store(1, 3, content3)

    assert_equal content1, @store.retrieve(1, 1)
    assert_equal content2, @store.retrieve(1, 2)
    assert_equal content3, @store.retrieve(1, 3)
  end

  def test_multiple_paths_independent
    @store.store(1, 1, "File A version 1")
    @store.store(2, 1, "File B version 1")
    @store.store(1, 2, "File A version 2")
    @store.store(2, 2, "File B version 2")

    assert_equal "File A version 1", @store.retrieve(1, 1)
    assert_equal "File A version 2", @store.retrieve(1, 2)
    assert_equal "File B version 1", @store.retrieve(2, 1)
    assert_equal "File B version 2", @store.retrieve(2, 2)
  end

  def test_nil_content
    @store.store(1, 1, nil)

    result = @store.retrieve(1, 1)
    assert_nil result
  end

  def test_empty_content
    @store.store(1, 1, "")

    result = @store.retrieve(1, 1)
    assert_equal "", result
  end

  def test_large_content_compression
    large_content = "X" * 10000

    @store.store(1, 1, large_content)

    result = @store.retrieve(1, 1)
    assert_equal large_content, result
  end

  def test_binary_content
    binary_data = (0..255).to_a.pack('C*') * 50

    @store.store(1, 1, binary_data)
    modified = binary_data.dup
    modified[100] = 0xFF.chr
    modified[200] = 0x00.chr
    @store.store(1, 2, modified)

    assert_equal binary_data, @store.retrieve(1, 1)
    assert_equal modified, @store.retrieve(1, 2)
  end

  def test_stats
    @store.store(1, 1, "Keyframe")
    @store.store(1, 2, "Delta 1")
    @store.store(1, 3, "Delta 2")
    @store.store(2, 1, "Another keyframe")

    stats = @store.stats

    assert stats[:versions] >= 3
    assert stats[:keyframes] >= 2
    assert stats[:total_bytes] > 0
  end

  def test_version_numbering
    # Simulate many versions to trigger keyframe
    content = "Base content"

    (1..105).each do |v|
      @store.store(1, v, "#{content} version #{v}")
    end

    # Every 100th should be a keyframe
    stats = @store.stats
    assert stats[:keyframes] >= 1
  end

  def test_store_batch
    items = [
      { path_id: 1, version_id: 1, content: "Content 1" },
      { path_id: 1, version_id: 2, content: "Content 2" },
      { path_id: 2, version_id: 1, content: "Content 3" }
    ]

    @store.store_batch(items)

    assert_equal "Content 1", @store.retrieve(1, 1)
    assert_equal "Content 2", @store.retrieve(1, 2)
    assert_equal "Content 3", @store.retrieve(2, 1)
  end

  def test_unicode_content
    content = "Hello 世界"
    modified = "Hello 世界!"

    @store.store(1, 1, content)
    @store.store(1, 2, modified)

    assert_equal content, @store.retrieve(1, 1)
    assert_equal modified, @store.retrieve(1, 2)
  end

  def test_same_content_multiple_versions
    content = "Unchanged content"

    @store.store(1, 1, content)
    @store.store(1, 2, content)
    @store.store(1, 3, content)

    assert_equal content, @store.retrieve(1, 1)
    assert_equal content, @store.retrieve(1, 2)
    assert_equal content, @store.retrieve(1, 3)
  end
end

MTest::Unit.new.run
