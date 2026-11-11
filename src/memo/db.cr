require "db"
require "sqlite3"
require "uri"
require "crystkit/features/system_info"

module Memo
  module DBX
    @@db : DB::Database?

    private def self.build_time_db_url : String?
      {% if env("MEMO_DATABASE_URL") %}
        {{ env("MEMO_DATABASE_URL") }}
      {% else %}
        nil
      {% end %}
    end

    def self.data_dir : String
      CrystKit::Features::SystemInfo.new.app_data_directories.data
    end

    def self.db_path : String
      app_data_dir = File.join(data_dir, "Memo")
      Dir.mkdir_p(app_data_dir) unless Dir.exists?(app_data_dir)
      File.join(app_data_dir, "memo.db")
    end

    def self.db_url_source : String
      configured_db.try { |config| config[:source] } || "default_path"
    end

    def self.db_url : String
      configured_db.try { |config| config[:url] } || default_db_url
    end

    def self.current_db_path : String?
      return db_path if db_url_source == "default_path"

      nil
    end

    private def self.configured_db
      # Keep URL selection and its diagnostic source in the same precedence order.
      # DATABASE_URL is the setting used by versions through 0.0.13.
      [
        {"runtime_env", ENV["MEMO_DATABASE_URL"]?},
        {"legacy_runtime_env", ENV["DATABASE_URL"]?},
        {"build_env", build_time_db_url},
      ].each do |source, value|
        url = value.try(&.strip)
        return {source: source, url: url} if url && !url.empty?
      end
      nil
    end

    def self.sqlite_url(path : String) : String
      # The SQLite driver form-decodes hostname + path. Encode the whole
      # filename so Windows drive letters, spaces, + and % round-trip safely.
      "sqlite3:#{URI.encode_www_form(path)}"
    end

    private def self.default_db_url : String
      # Add busy_timeout to reduce SQLITE_BUSY errors if multiple connections overlap.
      "#{sqlite_url(db_path)}?journal_mode=wal&synchronous=normal&encoding=utf8&busy_timeout=5000"
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
      db.exec "create index if not exists notes_updated_at_idx on notes(updated_at)"
    end

    def self.now_s
      Time.utc.to_s(SQLite3::DATE_FORMAT_SUBSECOND)
    end

    # Gracefully close and reset the cached DB connection.
    def self.close
      if db = @@db
        begin
          db.close
        rescue ex
          STDERR.puts "DB close error: #{ex.message}"
        ensure
          @@db = nil
        end
      end
    end
  end
end
