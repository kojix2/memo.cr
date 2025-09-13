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
      ENV["DATABASE_URL"]? || "sqlite3://#{db_path}?journal_mode=wal&synchronous=normal"
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
