require "db"
require "sqlite3"

module Memo
  module DBX
    DB_URL = ENV["DATABASE_URL"]? || "sqlite3://./memo.db?journal_mode=wal&synchronous=normal"
    @@db : DB::Database?

    def self.db : DB::Database
      @@db ||= DB.open(DB_URL)
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
