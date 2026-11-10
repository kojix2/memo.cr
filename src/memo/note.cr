require "json"

module Memo
  struct Note
    include JSON::Serializable

    getter id : Int64
    getter title : String
    getter body : String
    getter created_at : String
    getter updated_at : String

    def initialize(@id, @title, @body, @created_at, @updated_at)
    end
  end

  struct SaveNote
    include JSON::Serializable

    getter id : Int64
    getter title : String
    getter body : String
  end
end
