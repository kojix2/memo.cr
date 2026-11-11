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
  it "round-trips Unix and Windows database filenames without treating + or % as URL syntax" do
    ["/tmp/Memo notes+100%/メモ.db", "C:\\Users\\A B+100%\\メモ.db"].each do |path|
      url = Memo::DBX.sqlite_url(path)
      SQLite3::Connection.filename(URI.parse(url)).should eq(path)
    end
  end

  it "opens a database whose filename contains spaces, plus signs, percent signs and Unicode" do
    with_store do |_, root|
      path = File.join(root, "notes +100% 日本語.db")
      DB.open(Memo::DBX.sqlite_url(path)) do |database|
        database.exec("create table compatibility (id integer)")
      end
      File.file?(path).should be_true
    end
  end

  it "reopens the legacy DATABASE_URL and gives MEMO_DATABASE_URL precedence" do
    previous_legacy_url = ENV["DATABASE_URL"]?
    begin
      with_store do |store, root|
        note = store.create
        legacy_url = ENV["MEMO_DATABASE_URL"]
        Memo::DBX.close
        ENV["DATABASE_URL"] = " #{legacy_url} "
        ENV.delete("MEMO_DATABASE_URL")
        Memo::DBX.db_url_source.should eq("legacy_runtime_env")
        Memo::DBX.db_url.should eq(legacy_url)
        Memo::DBX.current_db_path.should be_nil
        Memo::DBX.setup
        Memo::Store.new(Memo::DBX.db).find(note.id).title.should eq(note.title)

        ENV["MEMO_DATABASE_URL"] = Memo::DBX.sqlite_url(File.join(root, "override.db"))
        Memo::DBX.db_url_source.should eq("runtime_env")
        Memo::DBX.db_url.should eq(ENV["MEMO_DATABASE_URL"])
      end
    ensure
      if previous_legacy_url
        ENV["DATABASE_URL"] = previous_legacy_url
      else
        ENV.delete("DATABASE_URL")
      end
    end
  end

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
