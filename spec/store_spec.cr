require "./spec_helper"

describe Memo::Store do
  it "opens the original schema and preserves existing notes and timestamps" do
    with_store do |store, _|
      Memo::DBX.db.exec("insert into notes(id, title, body, created_at, updated_at) values(?, ?, ?, ?, ?)",
        args: [42_i64, "既存のメモ", "本文\n😀", "2026-01-01 00:00:00.000", "2026-06-16 12:34:56.789"])
      Memo::DBX.setup
      note = store.find(42_i64)
      note.title.should eq("既存のメモ")
      note.body.should eq("本文\n😀")
      note.created_at.should eq("2026-01-01 00:00:00.000")
      note.updated_at.should eq("2026-06-16 12:34:56.789")
    end
  end

  it "creates, updates, exports, reopens, and deletes notes" do
    with_store do |store, _|
      note = store.create
      note.title.should eq(Time.local.to_s("%Y-%m-%d"))
      request = Memo::SaveNote.from_json({id: note.id, title: "<script>日本語</script>", body: "quotes: '\"\n😀 & < >"}.to_json)
      saved = store.save(request)
      saved.created_at.should eq(note.created_at)
      exported = JSON.parse(store.export_json).as_a
      exported.size.should eq(1)
      exported[0]["title"].as_s.should eq(request.title)
      exported[0]["body"].as_s.should eq(request.body)
      Memo::DBX.close
      reopened = Memo::Store.new(Memo::DBX.db)
      reopened.find(note.id).body.should eq(request.body)
      reopened.delete(note.id).should be_true
      reopened.count.should eq(0)
      reopened.export_json.should eq("[]")
    end
  end

  it "reports missing notes instead of silently succeeding" do
    with_store do |store, _|
      expect_raises(ArgumentError, "Note no longer exists") { store.find(100_i64) }
      expect_raises(ArgumentError, "Note no longer exists") { store.delete(100_i64) }
      request = Memo::SaveNote.from_json(%({"id":100,"title":"lost","body":""}))
      expect_raises(ArgumentError, "Note no longer exists") { store.save(request) }
    end
  end

  it "orders by updated time with a deterministic tie break" do
    with_store do |store, _|
      first = store.create
      second = store.create
      # Tuple(String) triggers a Crystal 1.22.2 Linux codegen bug; bind an Array.
      Memo::DBX.db.exec("update notes set updated_at = ?", args: ["2026-01-01 00:00:00.000"])
      store.list.map(&.id).should eq([second.id, first.id])
      store.save(Memo::SaveNote.from_json({id: first.id, title: "Updated", body: ""}.to_json))
      store.list.first.id.should eq(first.id)
    end
  end
end
