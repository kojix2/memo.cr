require "./spec_helper"

describe Memo::Commands do
  it "serves the note workflow through CrystKit typed IPC" do
    with_store do |store, root|
      app = CrystKit::App.new(CrystKit::AppConfig.new(storage_dir: Path[root]))
      app.grant(Memo::Commands::CAPABILITY)
      Memo::Commands.register(app, store, Memo::Settings.new(File.join(root, "settings.json")))
      frontend = CrystKit::Test::FakeFrontend.new(app)
      begin
        created = frontend.invoke("notes.create")
        created.ok?.should be_true
        id = created.value.not_nil!["id"].as_i64
        updated = frontend.invoke("notes.save", JSON.parse({id: id, title: "IPC メモ", body: "本文"}.to_json))
        updated.ok?.should be_true
        updated.value.not_nil!["body"].as_s.should eq("本文")
        frontend.invoke("notes.list").value.not_nil!.as_a.size.should eq(1)
        frontend.invoke("app.info").value.not_nil!["note_count"].as_i.should eq(1)
        frontend.invoke("settings.save", JSON::Any.new(22_i64)).ok?.should be_true
        frontend.invoke("settings.get").value.not_nil!["ui"]["editor_font_size_px"].as_i.should eq(22)
        frontend.invoke("notes.delete", JSON::Any.new(id)).ok?.should be_true
        frontend.invoke("notes.list").value.not_nil!.as_a.should be_empty
      ensure
        frontend.detach
        app.shutdown
      end
    end
  end

  it "rejects missing authority, malformed payloads, and invalid operations" do
    with_store do |store, root|
      app = CrystKit::App.new(CrystKit::AppConfig.new(storage_dir: Path[root]))
      Memo::Commands.register(app, store, Memo::Settings.new(File.join(root, "settings.json")))
      frontend = CrystKit::Test::FakeFrontend.new(app)
      begin
        denied = frontend.invoke("notes.create")
        denied.ok?.should be_false
        store.count.should eq(0)
        app.grant(Memo::Commands::CAPABILITY)
        frontend.invoke("notes.save", JSON.parse(%({"id":"oops"}))).ok?.should be_false
        frontend.invoke("notes.delete", JSON::Any.new(999_i64)).ok?.should be_false
        frontend.invoke("settings.save", JSON::Any.new(100_i64)).ok?.should be_false
        frontend.invoke("settings.save", JSON::Any.new("22")).ok?.should be_false
        frontend.invoke("fs.write_text", JSON.parse(%({"path":"/tmp/no","content":"no"}))).ok?.should be_false
        frontend.invoke("unknown.command").ok?.should be_false
      ensure
        frontend.detach
        app.shutdown
      end
    end
  end
end
