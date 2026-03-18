require_relative 'test_helper'

class DeltaTest < GitLite::TestCase
  def test_create_returns_nil_for_small_content
    old_data = "small"
    new_data = "tiny"
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    # Small content should return nil (store full)
    assert_nil delta
  end
  
  def test_create_and_apply_simple_delta
    old_data = "The quick brown fox jumps over the lazy dog"
    new_data = "The quick brown fox jumps over the lazy cat"
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    refute_nil delta
    assert delta.bytesize < new_data.bytesize
    
    reconstructed = GitLite::Delta.apply(old_data, delta)
    assert_equal new_data, reconstructed
  end
  
  def test_create_and_apply_large_delta
    old_data = "Line 1\nLine 2\nLine 3\n" * 100
    new_data = "Line 1\nModified Line 2\nLine 3\n" * 100
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    refute_nil delta
    assert delta.bytesize < new_data.bytesize * 0.9
    
    reconstructed = GitLite::Delta.apply(old_data, delta)
    assert_equal new_data, reconstructed
  end
  
  def test_apply_returns_delta_if_no_header
    data = "some data without delta header"
    
    result = GitLite::Delta.apply("base", data)
    assert_equal data, result
  end
  
  def test_apply_with_nil_base
    new_data = "new content"
    
    # Should return delta as-is (treated as uncompressed)
    result = GitLite::Delta.apply(nil, new_data)
    assert_equal new_data, result
  end
  
  def test_apply_with_empty_base
    new_data = "A" * 200  # Large enough to trigger delta
    
    result = GitLite::Delta.apply("", new_data)
    assert_equal new_data, result
  end
  
  def test_binary_data_delta
    old_data = "\x00\x01\x02\x03" * 100
    new_data = "\x00\x01\xFF\x03" * 100
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    if delta
      reconstructed = GitLite::Delta.apply(old_data, delta)
      assert_equal new_data, reconstructed
    end
  end
  
  def test_append_only_delta
    old_data = "Base content here"
    new_data = old_data + "\nAppended line 1\nAppended line 2"
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    refute_nil delta
    reconstructed = GitLite::Delta.apply(old_data, delta)
    assert_equal new_data, reconstructed
  end
  
  def test_prepend_only_delta
    old_data = "Base content here"
    new_data = "Prepended line\n" + old_data
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    refute_nil delta
    reconstructed = GitLite::Delta.apply(old_data, delta)
    assert_equal new_data, reconstructed
  end
  
  def test_identical_content
    data = "Identical content " * 50
    
    delta = GitLite::Delta.create(data, data)
    
    # May return nil (no benefit) or a very small delta
    if delta
      reconstructed = GitLite::Delta.apply(data, delta)
      assert_equal data, reconstructed
    end
  end
  
  def test_multiline_text_delta
    old_data = <<~TEXT
      def hello
        puts "Hello, World!"
      end
      
      def goodbye
        puts "Goodbye!"
      end
    TEXT
    
    new_data = <<~TEXT
      def hello
        puts "Hello, World!"
      end
      
      def farewell
        puts "Farewell!"
      end
    TEXT
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    refute_nil delta
    reconstructed = GitLite::Delta.apply(old_data, delta)
    assert_equal new_data, reconstructed
  end
  
  def test_delta_smaller_than_original
    old_data = "Common prefix " + ("X" * 1000) + " Common suffix"
    new_data = "Common prefix " + ("Y" * 1000) + " Common suffix"
    
    delta = GitLite::Delta.create(old_data, new_data)
    
    # Delta should be significantly smaller
    assert delta.bytesize < new_data.bytesize * 0.5
  end
end
