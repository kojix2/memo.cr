require "db"
require "sqlite3"

module Memo
  module DBX
    @@db : DB::Database?

    def self.data_dir : String
      {% if flag?(:windows) %}
        ENV["APPDATA"]? || ENV["USERPROFILE"]? || "."
      {% elsif flag?(:darwin) %}
        home = ENV["HOME"]? || "."
        File.join(home, "Library", "Application Support")
      {% else %}
        ENV["XDG_DATA_HOME"]? || File.join(ENV["HOME"]? || ".", ".local", "share")
      {% end %}
    end

    def self.db_path : String
      app_data_dir = File.join(data_dir, "Memo")
      Dir.mkdir_p(app_data_dir) unless Dir.exists?(app_data_dir)
      File.join(app_data_dir, "memo.db")
    end

    def self.db_url : String
      if env = ENV["DATABASE_URL"]?
        return env
      end

      # Build a cross-platform, URI-safe sqlite3 URL.
      # Crystal's URI expects absolute file paths as: sqlite3:///path/to/file
      # On Windows, also convert backslashes to forward slashes (e.g., C:/Users/...)
      path = db_path
      {% if flag?(:windows) %}
        path = path.gsub("\\", "/")
      {% end %}

      # Ensure we have exactly three slashes after the scheme by removing leading slashes from the path
      # and then prefixing with sqlite3///
      path = path.sub(/^\/+/, "")
      "sqlite3:///#{path}?journal_mode=wal&synchronous=normal"
    end

    def self.db : DB::Database
      @@db ||= DB.open(db_url)
    end

    def self.setup
      db.exec <<-SQL
        create table if not exists notes(
          id integer primary key autoincrement,
          title text not null,
          body  text not null,
          created_at text not null,
          updated_at text not null
        )
      SQL
    end

    def self.now_s
      Time.local.to_s(SQLite3::DATE_FORMAT_SUBSECOND)
    end
  end
end
