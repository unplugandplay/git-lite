# SQLite wrapper for mruby-sqlite3
# Provides hash-based results and helper methods matching CRuby sqlite3 gem API

module GitLite
  class SQLiteWrapper
    attr_reader :db

    def initialize(path)
      @path = path
      @db = nil
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
      is_query = sql.strip =~ /\A(SELECT|PRAGMA)/i

      if is_query
        if params.is_a?(Array) && params.length > 0
          rs = @db.execute(sql, *params)
        else
          rs = @db.execute(sql)
        end
        columns = rs.fields
        rows = collect_rows(rs)
        rs.close

        return rows if columns.nil? || columns.length == 0

        rows.map do |row|
          hash = {}
          columns.each_with_index do |col, i|
            hash[col] = row[i]
          end
          hash
        end
      else
        if params.is_a?(Array) && params.length > 0
          # Parameterized DML: splat params, drain and close ResultSet
          rs = @db.execute(sql, *params)
          collect_rows(rs)
          rs.close
        else
          @db.execute_batch(sql)
        end
        nil
      end
    end

    def get_first_row(sql, *params)
      results = execute(sql, params.flatten)
      results.is_a?(Array) ? results.first : nil
    end

    def get_first_value(sql, *params)
      flat = params.flatten
      if flat.length > 0
        rs = @db.execute(sql, *flat)
      else
        rs = @db.execute(sql)
      end
      rows = collect_rows(rs)
      rs.close
      return nil if rows.length == 0
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

    def collect_rows(rs)
      rows = []
      loop do
        row = rs.next
        break if row.nil?
        rows << row
      end
      rows
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
