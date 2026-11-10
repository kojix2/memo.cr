require "spec"
require "file_utils"
require "random/secure"
require "../src/memo/commands"
require "./support/dialog_provider"

# Every persistence test owns a temporary database and settings file.
# Neither the user's notes nor their default application-data directory is used.
def with_store(&)
  root = File.join(Dir.tempdir, "memo-spec-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(root)
  previous = ENV["MEMO_DATABASE_URL"]?
  Memo::DBX.close
  ENV["MEMO_DATABASE_URL"] = "sqlite3://#{root}/memo.db"
  Memo::DBX.setup
  begin
    yield Memo::Store.new(Memo::DBX.db), root
  ensure
    Memo::DBX.close
    if previous
      ENV["MEMO_DATABASE_URL"] = previous
    else
      ENV.delete("MEMO_DATABASE_URL")
    end
    FileUtils.rm_rf(root)
  end
end
