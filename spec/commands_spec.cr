require "./spec_helper"

describe Memo::Commands do
  it "serves the note workflow through CrystKit typed IPC" do
    with_store do |store, root|
      app = CrystKit::App.new(CrystKit::AppConfig.new(storage_dir: Path[root], ipc: Memo::Commands::IPC_POLICY))
      app.grant(Memo::Commands::CAPABILITY)
      Memo::Commands.register(app, store, Memo::Settings.new(File.join(root, "settings.json")))
      frontend = CrystKit::Test::FakeFrontend.new(app)
      begin
        notes = frontend.state("notes")
        notes.value.as_a.should be_empty
        created = frontend.invoke("notes.create")
        created.ok?.should be_true
        id = created.value.not_nil!["id"].as_i64
        notes.value.as_a.size.should eq(1)
        updated = frontend.invoke("notes.save", JSON.parse({id: id, title: "IPC メモ", body: "本文"}.to_json))
        updated.ok?.should be_true
        updated.value.not_nil!["body"].as_s.should eq("本文")
        notes.value.as_a.first["body"].as_s.should eq("本文")
        frontend.invoke("app.info").value.not_nil!["note_count"].as_i.should eq(1)
        frontend.invoke("settings.save", JSON::Any.new(22_i64)).ok?.should be_true
        frontend.invoke("settings.get").value.not_nil!["ui"]["editor_font_size_px"].as_i.should eq(22)
        frontend.invoke("settings.save_sidebar_width", JSON::Any.new(360_i64)).ok?.should be_true
        frontend.invoke("settings.get").value.not_nil!["ui"]["sidebar_width_px"].as_i.should eq(360)
        second = frontend.invoke("notes.create").value.not_nil!
        notes.value.as_a.size.should eq(2)
        deleted = frontend.invoke("notes.delete", JSON::Any.new(id))
        deleted.ok?.should be_true
        deleted.value.not_nil!["id"].should eq(second["id"])
        notes.value.as_a.size.should eq(1)
        snapshot = notes.value.to_json
        frontend.invoke("notes.save", JSON.parse({id: id, title: "Deleted", body: ""}.to_json)).ok?.should be_false
        notes.value.to_json.should eq(snapshot)
        frontend.invoke("notes.delete", second["id"]).value.not_nil!.raw.should be_nil
        notes.value.as_a.should be_empty
      ensure
        frontend.detach
        app.shutdown
      end
    end
  end

  it "rejects missing authority, malformed payloads, and invalid operations" do
    with_store do |store, root|
      app = CrystKit::App.new(CrystKit::AppConfig.new(storage_dir: Path[root], ipc: Memo::Commands::IPC_POLICY))
      Memo::Commands.register(app, store, Memo::Settings.new(File.join(root, "settings.json")))
      frontend = CrystKit::Test::FakeFrontend.new(app)
      begin
        denied = frontend.invoke("notes.create")
        denied.ok?.should be_false
        store.count.should eq(0)
        frontend.invoke("__crystkit.state.attach", JSON::Any.new("notes")).ok?.should be_false
        frontend.invoke("settings.save_sidebar_width", JSON::Any.new(360_i64)).ok?.should be_false
        app.grant(Memo::Commands::CAPABILITY)
        frontend.invoke("notes.save", JSON.parse(%({"id":"oops"}))).ok?.should be_false
        frontend.invoke("notes.delete", JSON::Any.new(999_i64)).ok?.should be_false
        frontend.invoke("settings.save", JSON::Any.new(100_i64)).ok?.should be_false
        frontend.invoke("settings.save", JSON::Any.new("22")).ok?.should be_false
        frontend.invoke("settings.save_sidebar_width", JSON::Any.new(601_i64)).ok?.should be_false
        frontend.invoke("fs.write_text", JSON.parse(%({"path":"/tmp/no","content":"no"}))).ok?.should be_false
        frontend.invoke("unknown.command").ok?.should be_false
      ensure
        frontend.detach
        app.shutdown
      end
    end
  end
end
