# Content storage with delta compression for git-lite (mruby-compatible)

module GitLite
  class ContentStore
    KEYFRAME_EVERY = 100

    def initialize(db)
      @db = db
    end

    def store(path_id, version_id, content)
      is_keyframe = should_be_keyframe?(path_id, version_id)

      if is_keyframe || content.nil? || content.empty?
        store_keyframe(path_id, version_id, content)
      else
        base_version = find_last_keyframe(path_id, version_id)

        if base_version
          base_content = retrieve_raw_content(path_id, base_version)
          delta = Delta.create(base_content, content)

          if delta && delta.bytesize < content.bytesize * 0.8
            store_delta(path_id, version_id, delta, base_version)
          else
            store_keyframe(path_id, version_id, content)
          end
        else
          store_keyframe(path_id, version_id, content)
        end
      end
    end

    def retrieve(path_id, version_id)
      meta = @db.execute(
        "SELECT is_keyframe, base_version FROM content_meta WHERE path_id = ? AND version_id = ?",
        [path_id, version_id]
      ).first

      return nil unless meta

      packed = retrieve_raw(path_id, version_id)
      is_keyframe, content = unpack_content(packed)

      if is_keyframe || meta['base_version'].nil?
        content
      else
        base = retrieve(path_id, meta['base_version'].to_i)
        Delta.apply(base, content)
      end
    end

    def retrieve_raw(path_id, version_id)
      @db.get_content_raw(path_id, version_id)
    end

    def store_batch(items)
      return if items.empty?
      items.each do |item|
        store(item[:path_id], item[:version_id], item[:content])
      end
    end

    def stats
      result = @db.execute(
        "SELECT COUNT(*) as total_versions, SUM(CASE WHEN is_keyframe = 1 THEN 1 ELSE 0 END) as keyframes, SUM(CASE WHEN is_keyframe = 0 THEN 1 ELSE 0 END) as deltas FROM content_meta"
      ).first

      sizes = @db.execute(
        "SELECT COALESCE(SUM(LENGTH(data)), 0) as total_bytes FROM content"
      ).first

      {
        versions: (result['total_versions'] || 0).to_i,
        keyframes: (result['keyframes'] || 0).to_i,
        deltas: (result['deltas'] || 0).to_i,
        total_bytes: (sizes['total_bytes'] || 0).to_i
      }
    end

    def self.create_schema(wrapper)
      wrapper.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS content_meta (
          path_id INTEGER NOT NULL,
          version_id INTEGER NOT NULL,
          is_keyframe INTEGER NOT NULL DEFAULT 1,
          base_version INTEGER,
          PRIMARY KEY (path_id, version_id)
        )
      SQL
      wrapper.execute("CREATE INDEX IF NOT EXISTS idx_content_meta_keyframe ON content_meta(path_id, is_keyframe)")
    end

    private

    def should_be_keyframe?(path_id, version_id)
      return true if version_id == 1
      return true if version_id % KEYFRAME_EVERY == 0
      false
    end

    def find_last_keyframe(path_id, before_version)
      result = @db.execute(
        "SELECT MAX(version_id) as version FROM content_meta WHERE path_id = ? AND is_keyframe = 1 AND version_id < ?",
        [path_id, before_version]
      ).first
      result && result['version'] ? result['version'].to_i : nil
    end

    def store_keyframe(path_id, version_id, content)
      packed = pack_content(content, true)
      @db.execute(
        "INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, ?)",
        [path_id, version_id, packed]
      )
      @db.execute(
        "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 1, NULL)",
        [path_id, version_id]
      )
    end

    def store_delta(path_id, version_id, delta, base_version)
      packed = pack_content(delta, false)
      @db.execute(
        "INSERT OR REPLACE INTO content (path_id, version_id, data) VALUES (?, ?, ?)",
        [path_id, version_id, packed]
      )
      @db.execute(
        "INSERT OR REPLACE INTO content_meta (path_id, version_id, is_keyframe, base_version) VALUES (?, ?, 0, ?)",
        [path_id, version_id, base_version]
      )
    end

    def retrieve_raw_content(path_id, version_id)
      packed = retrieve_raw(path_id, version_id)
      return nil unless packed
      _, content = unpack_content(packed)
      content
    end

    def pack_content(content, is_keyframe)
      return nil if content.nil?

      flags = 0
      flags |= 0x01 if is_keyframe

      if content.bytesize > 1024
        compressed = Zlib.deflate(content)
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
      content = packed[1..-1]

      is_keyframe = (flags & 0x01) != 0
      is_compressed = (flags & 0x02) != 0

      if is_compressed
        content = Zlib.inflate(content)
      end

      [is_keyframe, content]
    end
  end
end
