# Content storage with delta compression for git-lite

module GitLite
  class ContentStore
    KEYFRAME_EVERY = 100  # Full copy every N versions
    
    def initialize(db)
      @db = db
    end
    
    # Store content with delta compression
    def store(path_id, version_id, content)
      # Determine if this should be a keyframe
      is_keyframe = should_be_keyframe?(path_id, version_id)
      
      if is_keyframe || content.nil? || content.empty?
        # Store full content (keyframe)
        @db.create_content_raw(path_id, version_id, pack_content(content, true))
        @db.execute(
          "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 1, NULL)",
          [path_id, version_id]
        )
      else
        # Store delta from previous keyframe
        base_version = find_last_keyframe(path_id, version_id)
        
        if base_version
          base_content = retrieve_raw(path_id, base_version)
          delta = Delta.create(base_content, content)
          
          if delta && delta.bytesize < content.bytesize * 0.8
            # Delta is beneficial
            @db.create_content_raw(path_id, version_id, pack_content(delta, false))
            @db.execute(
              "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 0, ?)",
              [path_id, version_id, base_version]
            )
          else
            # Store as keyframe instead
            @db.create_content_raw(path_id, version_id, pack_content(content, true))
            @db.execute(
              "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 1, NULL)",
              [path_id, version_id]
            )
          end
        else
          # No base, store full
          @db.create_content_raw(path_id, version_id, pack_content(content, true))
          @db.execute(
            "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 1, NULL)",
            [path_id, version_id]
          )
        end
      end
    end
    
    # Retrieve content, applying deltas as needed
    def retrieve(path_id, version_id)
      # Check if this is a keyframe or delta
      meta = @db.execute(
        "SELECT is_keyframe, base_version FROM content_meta WHERE path_id = ? AND version_id = ?",
        [path_id, version_id]
      ).first
      
      return nil unless meta
      
      packed = retrieve_raw(path_id, version_id)
      is_keyframe, content = unpack_content(packed)
      
      if is_keyframe || meta['base_version'].nil?
        # This is a keyframe
        content
      else
        # This is a delta, need to reconstruct
        base = retrieve(meta['base_version'], find_nearest_keyframe(path_id, version_id))
        Delta.apply(base, content)
      end
    end
    
    # Get content without delta reconstruction (for migration)
    def retrieve_raw(path_id, version_id)
      @db.get_content_raw(path_id, version_id)
    end
    
    # Batch store for import performance
    def store_batch(items)
      return if items.empty?
      
      @db.instance_variable_get(:@db).transaction do
        items.each do |item|
          store(item[:path_id], item[:version_id], item[:content])
        end
      end
    end
    
    # Storage statistics
    def stats
      result = @db.execute(<<-SQL).first
        SELECT 
          COUNT(*) as total_versions,
          SUM(CASE WHEN is_keyframe = 1 THEN 1 ELSE 0 END) as keyframes,
          SUM(CASE WHEN is_keyframe = 0 THEN 1 ELSE 0 END) as deltas
        FROM content_meta
      SQL
      
      sizes = @db.execute(<<-SQL).first
        SELECT COALESCE(SUM(LENGTH(data)), 0) as total_bytes
        FROM content
      SQL
      
      {
        versions: result['total_versions'].to_i,
        keyframes: result['keyframes'].to_i,
        deltas: result['deltas'].to_i,
        total_bytes: sizes['total_bytes'].to_i
      }
    end
    
    # Create content_meta table
    def self.create_schema(db)
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS content_meta (
          path_id INTEGER NOT NULL,
          version_id INTEGER NOT NULL,
          is_keyframe INTEGER NOT NULL DEFAULT 1,
          base_version INTEGER,
          PRIMARY KEY (path_id, version_id)
        )
      SQL
      
      db.execute("CREATE INDEX IF NOT EXISTS idx_content_meta_keyframe ON content_meta(path_id, is_keyframe)")
    end
    
    private
    
    def should_be_keyframe?(path_id, version_id)
      # First version is always a keyframe
      return true if version_id == 1
      
      # Every Nth version is a keyframe
      return true if version_id % KEYFRAME_EVERY == 0
      
      false
    end
    
    def find_last_keyframe(path_id, before_version)
      result = @db.execute(<<-SQL, [path_id, before_version]).first
        SELECT MAX(version_id) as version
        FROM content_meta
        WHERE path_id = ? AND is_keyframe = 1 AND version_id < ?
      SQL
      
      result ? result['version'].to_i : nil
    end
    
    def find_nearest_keyframe(path_id, version_id)
      result = @db.execute(<<-SQL, [path_id, version_id]).first
        SELECT MAX(version_id) as version
        FROM content_meta
        WHERE path_id = ? AND is_keyframe = 1 AND version_id <= ?
      SQL
      
      result ? result['version'].to_i : 1
    end
    
    # Pack content with header
    # Header: 1 byte flags
    #   bit 0: is_keyframe
    #   bit 1: is_compressed (zstd)
    def pack_content(content, is_keyframe)
      return nil if content.nil?
      
      flags = 0
      flags |= 0x01 if is_keyframe
      
      # Try compression for large content
      if content.bytesize > 1024
        compressed = Delta.compress(content)
        if compressed.bytesize < content.bytesize * 0.9
          content = compressed
          flags |= 0x02
        end
      end
      
      [flags].pack('C') + content
    end
    
    def unpack_content(packed)
      return [true, nil] if packed.nil?
      
      flags = packed.getbyte(0)
      content = packed.byteslice(1..-1)
      
      is_keyframe = (flags & 0x01) != 0
      is_compressed = (flags & 0x02) != 0
      
      if is_compressed
        content = Delta.decompress(content)
      end
      
      [is_keyframe, content]
    end
  end
end
