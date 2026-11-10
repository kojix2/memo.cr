require "./db"
require "./note"

module Memo
  # Keeps the original schema and timestamp format so existing databases work
  # without copying, conversion, or destructive migrations.
  class Store
    def initialize(@db : DB::Database)
    end

    def list : Array(Note)
      @db.query_all("select id, title, body, created_at, updated_at from notes order by updated_at desc, id desc",
        as: {Int64, String, String, String, String}).map { |row| Note.new(*row) }
    end

    def find(id : Int64) : Note
      row = @db.query_one?("select id, title, body, created_at, updated_at from notes where id = ?",
        id, as: {Int64, String, String, String, String})
      raise ArgumentError.new("Note no longer exists") unless row
      Note.new(*row)
    end

    def create : Note
      now = DBX.now_s
      result = @db.exec("insert into notes(title, body, created_at, updated_at) values(?, ?, ?, ?)",
        Time.local.to_s("%Y-%m-%d"), "", now, now)
      find(result.last_insert_id)
    end

    def save(request : SaveNote) : Note
      result = @db.exec("update notes set title = ?, body = ?, updated_at = ? where id = ?",
        request.title, request.body, DBX.now_s, request.id)
      raise ArgumentError.new("Note no longer exists") if result.rows_affected == 0
      find(request.id)
    end

    def delete(id : Int64) : Bool
      result = @db.exec("delete from notes where id = ?", id)
      raise ArgumentError.new("Note no longer exists") if result.rows_affected == 0
      true
    end

    def export_json : String
      list.to_json
    end

    def count : Int64
      @db.query_one("select count(*) from notes", as: Int64)
    end
  end
end
