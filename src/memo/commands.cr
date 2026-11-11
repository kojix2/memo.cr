require "crystkit"
require "./store"
require "./settings"
require "./version"

module Memo
  module Commands
    CAPABILITY = "memo:access"
    NAMES      = %w[__crystkit.state.attach notes.create notes.save notes.delete notes.export app.info settings.save settings.save_sidebar_width app.ready app.close]
    IPC_POLICY = CrystKit::IPCConfig.new(NAMES.to_h do |name|
      {name, CrystKit::IPCCommandOverride.new(capability: CAPABILITY)}
    end)

    def self.register(app : CrystKit::App, store : Store, settings : Settings,
                      dialog : CrystKit::Features::MessageDialog)
      # SQLite is authoritative; CrystKit mirrors committed notes to the UI.
      notes = app.state("notes", Array(Note)) { store.list }
      preferences = app.state("settings", typeof(settings_snapshot(settings))) { settings_snapshot(settings) }
      refresh = -> { notes.value = store.list }
      app.command("notes.create") do
        note = store.create
        refresh.call
        note
      end
      app.command("notes.save", SaveNote) do |request|
        note = store.save(request)
        refresh.call
        note
      end
      app.command("notes.delete", Int64) do |id|
        note = store.find(id)
        # Cancellation keeps this note; deletion returns the next selection.
        next note unless dialog.confirm(CrystKit::Features::ConfirmOptions.new(
                           title: "Delete note", message: "Delete this note? This cannot be undone."))
        store.delete(id)
        refresh.call.first?
      end
      app.command("app.info") do
        {version: VERSION, db_path: DBX.current_db_path, db_url_source: DBX.db_url_source,
         note_count: store.count, repository_url: REPOSITORY_URL}
      end
      app.command("settings.save", Int32) do |size|
        settings.update_editor_font_size_px(size)
        preferences.value = settings_snapshot(settings)
        {editor_font_size_px: settings.editor_font_size_px}
      end
      app.command("settings.save_sidebar_width", Int32) do |width|
        settings.update_sidebar_width_px(width)
        preferences.value = settings_snapshot(settings)
        {sidebar_width_px: settings.sidebar_width_px}
      end
    end

    private def self.settings_snapshot(settings : Settings)
      {version: Settings::SETTINGS_VERSION, ui: {
        editor_font_size_px:     settings.editor_font_size_px,
        min_editor_font_size_px: Settings::MIN_EDITOR_FONT_SIZE_PX,
        max_editor_font_size_px: Settings::MAX_EDITOR_FONT_SIZE_PX,
        sidebar_width_px:        settings.sidebar_width_px,
      }}
    end
  end
end
