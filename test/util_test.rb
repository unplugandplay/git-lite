require_relative 'test_helper'

class UtilTest < Minitest::Test
  def test_hash_path
    hash = GitLite::Util.hash_path('/home/user/project')
    
    assert_equal 16, hash.length
    assert_match /^[a-f0-9]+$/, hash
  end
  
  def test_hash_path_consistency
    hash1 = GitLite::Util.hash_path('/same/path')
    hash2 = GitLite::Util.hash_path('/same/path')
    
    assert_equal hash1, hash2
  end
  
  def test_format_bytes_zero
    assert_equal "0 B", GitLite::Util.format_bytes(0)
    assert_equal "0 B", GitLite::Util.format_bytes(nil)
  end
  
  def test_format_bytes_bytes
    assert_equal "500 B", GitLite::Util.format_bytes(500)
  end
  
  def test_format_bytes_kilobytes
    assert_equal "1.95 KB", GitLite::Util.format_bytes(2000)
  end
  
  def test_format_bytes_megabytes
    assert_equal "2.0 MB", GitLite::Util.format_bytes(2 * 1024 * 1024)
  end
  
  def test_format_bytes_gigabytes
    assert_equal "1.5 GB", GitLite::Util.format_bytes(1.5 * 1024 * 1024 * 1024)
  end
  
  def test_binary_nil
    refute GitLite::Util.binary?(nil)
  end
  
  def test_binary_empty
    refute GitLite::Util.binary?("")
  end
  
  def test_binary_text
    refute GitLite::Util.binary?("Hello, World!")
    refute GitLite::Util.binary?("Line 1\nLine 2\nLine 3")
  end
  
  def test_binary_with_null_bytes
    assert GitLite::Util.binary?("Hello\x00World")
  end
  
  def test_binary_with_many_non_printable
    data = "\x00\x01\x02\x03\x04\x05" * 20
    assert GitLite::Util.binary?(data)
  end
  
  def test_binary_unicode_text
    refute GitLite::Util.binary?("Hello 世界 🌍")
    refute GitLite::Util.binary?("Café résumé")
  end
  
  def test_generate_id_format
    id = GitLite::Util.generate_id
    
    assert_equal 26, id.length
    assert_match /^[a-z0-9]+$/, id
  end
  
  def test_generate_id_unique
    ids = 100.times.map { GitLite::Util.generate_id }
    
    assert_equal ids.uniq.length, ids.length
  end
  
  def test_id_to_time
    id = GitLite::Util.generate_id
    time = GitLite::Util.id_to_time(id)
    
    assert_instance_of Time, time
    assert_in_delta Time.now.to_i, time.to_i, 2
  end
  
  def test_truncate_short_text
    text = "Short"
    
    assert_equal "Short", GitLite::Util.truncate(text, 100)
  end
  
  def test_truncate_long_text
    text = "This is a very long text that needs truncation"
    
    result = GitLite::Util.truncate(text, 20)
    
    assert result.length <= 20
    assert result.end_with?("...")
  end
  
  def test_pluralize_one
    assert_equal "1 item", GitLite::Util.pluralize(1, 'item')
  end
  
  def test_pluralize_many
    assert_equal "5 items", GitLite::Util.pluralize(5, 'item')
  end
  
  def test_pluralize_zero
    assert_equal "0 items", GitLite::Util.pluralize(0, 'item')
  end
  
  def test_pluralize_custom
    assert_equal "1 child", GitLite::Util.pluralize(1, 'child', 'children')
    assert_equal "3 children", GitLite::Util.pluralize(3, 'child', 'children')
  end
  
  def test_binary_image_data
    # Simulate JPEG header
    jpeg = "\xFF\xD8\xFF\xE0\x00\x10JFIF" + ("\x00" * 100)
    assert GitLite::Util.binary?(jpeg)
  end
  
  def test_binary_pdf_data
    pdf = "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n>>\nendobj\n" + ("\x00" * 50)
    assert GitLite::Util.binary?(pdf)
  end
  
  def test_text_source_code
    code = <<~CODE
      def hello_world
        puts "Hello, World!"
      end
    CODE
    
    refute GitLite::Util.binary?(code)
  end
  
  def test_text_json
    json = '{"name": "test", "value": 123}'
    refute GitLite::Util.binary?(json)
  end
  
  def test_text_xml
    xml = '<?xml version="1.0"?><root><item>value</item></root>'
    refute GitLite::Util.binary?(xml)
  end
end
