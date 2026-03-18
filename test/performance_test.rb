require_relative 'test_helper'
require 'benchmark'

class PerformanceTest < GitLite::TestCase
  def test_commit_performance
    repo = GitLite::Repo.init(@tmpdir)
    
    times = []
    
    20.times do |i|
      create_test_file("file#{i}.txt", "Content #{i}")
      repo.stage_file("file#{i}.txt")
      
      time = Benchmark.measure do
        repo.commit("Commit #{i}")
      end
      
      times << time.real
    end
    
    avg_time = times.sum / times.length
    puts "\n  Average commit time: #{avg_time.round(4)}s"
    
    # Should be reasonably fast (< 1s per commit)
    assert avg_time < 1.0, "Commit too slow: #{avg_time}s"
    
    repo.close
  end
  
  def test_large_file_storage
    repo = GitLite::Repo.init(@tmpdir)
    
    # 1MB file
    large_content = 'X' * (1024 * 1024)
    create_test_file('large.txt', large_content)
    repo.stage_file('large.txt')
    
    time = Benchmark.measure do
      repo.commit('Large file')
    end
    
    puts "\n  1MB file commit time: #{time.real.round(4)}s"
    
    # Verify content
    blob = repo.db.get_blob('large.txt', repo.head)
    assert_equal large_content.length, blob[:content].length
    
    repo.close
  end
  
  def test_many_small_files
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create 100 small files
    100.times do |i|
      create_test_file("small#{i}.txt", "Content #{i}")
      repo.stage_file("small#{i}.txt")
    end
    
    time = Benchmark.measure do
      repo.commit('Many small files')
    end
    
    puts "\n  100 files commit time: #{time.real.round(4)}s"
    
    blobs = repo.db.get_tree(repo.head)
    assert_equal 100, blobs.length
    
    repo.close
  end
  
  def test_log_performance
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create 100 commits
    100.times do |i|
      create_test_file("file#{i}.txt", "v#{i}")
      repo.stage_file("file#{i}.txt")
      repo.commit("Commit #{i}")
    end
    
    time = Benchmark.measure do
      log = repo.log(50)
      assert_equal 50, log.length
    end
    
    puts "\n  Log 50 from 100 commits time: #{time.real.round(4)}s"
    
    repo.close
  end
  
  def test_delta_compression_ratio
    db_path = File.join(@tmpdir, 'test.db')
    db = GitLite::DB.new(db_path).connect
    db.init_schema
    
    # Create base content
    base = "Line content here\n" * 1000
    
    # Store 10 versions with small changes
    10.times do |i|
      modified = base.gsub("Line", "Line#{i}")
      db.content_store.store(1, i + 1, modified)
    end
    
    stats = db.content_store.stats
    
    if stats[:deltas] > 0
      ratio = stats[:deltas].to_f / stats[:versions]
      puts "\n  Delta ratio: #{(ratio * 100).round(1)}%"
      puts "  Total bytes: #{stats[:total_bytes]}"
    end
    
    db.close
  end
  
  def test_tree_traversal_performance
    repo = GitLite::Repo.init(@tmpdir)
    
    # Create nested structure
    50.times do |i|
      path = "level1/level2/level3/file#{i}.txt"
      create_test_file(path, "content#{i}")
      repo.stage_file(path)
    end
    
    repo.commit('Nested structure')
    
    time = Benchmark.measure do
      10.times do
        blobs = repo.db.get_tree(repo.head)
        assert_equal 50, blobs.length
      end
    end
    
    puts "\n  Tree traversal (10x) time: #{time.real.round(4)}s"
    
    repo.close
  end
  
  def test_database_size_growth
    repo = GitLite::Repo.init(@tmpdir)
    
    sizes = []
    
    10.times do |i|
      # Add 10KB each commit
      create_test_file("file#{i}.txt", 'X' * 10240)
      repo.stage_file("file#{i}.txt")
      repo.commit("Commit #{i}")
      
      db_size = File.size(File.join(@tmpdir, '.git-lite', 'repo.db'))
      sizes << db_size
    end
    
    puts "\n  DB sizes: #{sizes.map { |s| "#{s / 1024}KB" }.join(', ')}"
    
    # Size should grow reasonably
    final_size = sizes.last
    puts "  Final size: #{final_size / 1024}KB"
    
    repo.close
  end
end
