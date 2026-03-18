# SQLite wrapper for mruby-sqlite3
# Provides hash-based results and helper methods matching CRuby sqlite3 gem API

module GitLite
  class SQLiteWrapper
    attr_reader :db

    def initialize(path)
      @path = path
      @db = nil
      @column_cache = {}
    end

    def connect
      @db = SQLite3::Database.new(@path)
      execute("PRAGMA foreign_keys = ON")
      execute("PRAGMA journal_mode = WAL")
      execute("PRAGMA synchronous = NORMAL")
      execute("PRAGMA busy_timeout = 5000")
      self
    end

    def close
      @db.close if @db
      @db = nil
    end

    def execute(sql, params = [])
      if params.empty?
        rows = @db.execute(sql)
      else
        # Flatten single-element arrays for mruby-sqlite3
        params = [params] unless params.is_a?(Array)
        rows = @db.execute(sql, params)
      end

      # Convert to array of hashes if SELECT query
      return rows unless sql.strip.upcase.start_with?('SELECT') || sql.strip.upcase.start_with?('PRAGMA')
      return [] if rows.nil? || rows.empty?

      # Get column names from the query
      columns = get_columns_for_query(sql)
      return rows unless columns && !columns.empty?

      rows.map do |row|
        hash = {}
        columns.each_with_index do |col, i|
          hash[col] = row[i] if row[i] != nil || true
        end
        hash
      end
    end

    def get_first_row(sql, *params)
      results = execute(sql, params.flatten)
      results.is_a?(Array) ? results.first : nil
    end

    def get_first_value(sql, *params)
      rows = @db.execute(sql, params.flatten)
      return nil if rows.nil? || rows.empty?
      row = rows.first
      row.is_a?(Array) ? row.first : row
    end

    def last_insert_row_id
      get_first_value("SELECT last_insert_rowid()")
    end

    def transaction
      execute("BEGIN")
      begin
        yield
        execute("COMMIT")
      rescue => e
        execute("ROLLBACK")
        raise e
      end
    end

    def prepare(sql)
      # mruby-sqlite3 doesn't support prepared statements
      # Return a simple wrapper that executes immediately
      PreparedStatement.new(self, sql)
    end

    private

    def get_columns_for_query(sql)
      # Extract column names from SQL
      # For SELECT * queries, use PRAGMA table_info
      normalized = sql.strip.gsub(/\s+/, ' ')

      if normalized =~ /SELECT\s+\*\s+FROM\s+(\w+)/i
        table = $1
        get_table_columns(table)
      elsif normalized =~ /SELECT\s+(.+?)\s+FROM/i
        cols = $1
        parse_select_columns(cols)
      else
        nil
      end
    end

    def get_table_columns(table)
      @column_cache[table] ||= begin
        rows = @db.execute("PRAGMA table_info(#{table})")
        rows.map { |r| r[1] }  # Column name is at index 1
      end
    end

    def parse_select_columns(cols_str)
      cols_str.split(',').map do |col|
        col = col.strip
        # Handle "expr AS alias" and "table.column"
        if col =~ /\s+[Aa][Ss]\s+(\w+)\s*$/
          $1
        elsif col =~ /\.(\w+)$/
          $1
        elsif col =~ /^\w+$/
          col
        else
          # Aggregate or complex expression - use as-is
          col.gsub(/[^a-zA-Z0-9_]/, '_')
        end
      end
    end
  end

  class PreparedStatement
    def initialize(wrapper, sql)
      @wrapper = wrapper
      @sql = sql
    end

    def execute(params = [])
      @wrapper.execute(@sql, params)
    end

    def close
      # No-op for mruby
    end
  end
end
