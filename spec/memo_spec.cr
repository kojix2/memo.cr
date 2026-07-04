require "./spec_helper"
require "file_utils"
require "random/secure"

require "../src/memo/db"

describe Memo do
  it "has a version number" do
    Memo::VERSION.should be_a(String)
  end
end

describe Memo::DBX do
  it "does not report or create the default path when a runtime database URL is set" do
    old_database_url = ENV["MEMO_DATABASE_URL"]?
    old_xdg_data_home = ENV["XDG_DATA_HOME"]?

    xdg_data_home = File.join(Dir.tempdir, "memo-spec-#{Random::Secure.hex(8)}")

    ENV["MEMO_DATABASE_URL"] = "sqlite3:///%2Ftmp%2Fmemo-runtime.db?journal_mode=wal"
    ENV["XDG_DATA_HOME"] = xdg_data_home

    begin
      Memo::DBX.db_url_source.should eq("runtime_env")
      Memo::DBX.current_db_path.should be_nil
      Dir.exists?(File.join(xdg_data_home, "Memo")).should be_false
    ensure
      if old_database_url
        ENV["MEMO_DATABASE_URL"] = old_database_url
      else
        ENV.delete("MEMO_DATABASE_URL")
      end

      if old_xdg_data_home
        ENV["XDG_DATA_HOME"] = old_xdg_data_home
      else
        ENV.delete("XDG_DATA_HOME")
      end

      FileUtils.rm_rf(xdg_data_home)
    end
  end
end
