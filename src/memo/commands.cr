require "crystkit"
require "./store"
require "./settings"
require "./version"

module Memo
  module Commands
    CAPABILITY = "memo:access"
    NAMES      = %w(notes.list notes.create notes.save notes.delete notes.export app.info settings.get settings.save settings.save_sidebar_width app.ready app.close)

    def self.register(app : CrystKit::App, store : Store, settings : Settings)
      # Commands expose note operations only; the frontend cannot execute SQL
      # or choose arbitrary file paths. Export uses a native save dialog.
      NAMES.each do |name|
        app.router.policy_resolver.register_override(name,
          CrystKit::IPC::CommandPolicy.new(capability: CAPABILITY))
      end

      app.command("notes.list") { store.list }
      app.command("notes.create") { store.create }
      app.command("notes.save", SaveNote) { |request| store.save(request) }
      app.command("notes.delete", Int64) { |id| store.delete(id) }
      app.command("app.info") do
        {version: VERSION, db_path: DBX.current_db_path, db_url_source: DBX.db_url_source,
         note_count: store.count, repository_url: REPOSITORY_URL}
      end
      app.command("settings.get") do
        {version: Settings::SETTINGS_VERSION, ui: {
          editor_font_size_px:     settings.editor_font_size_px,
          min_editor_font_size_px: Settings::MIN_EDITOR_FONT_SIZE_PX,
          max_editor_font_size_px: Settings::MAX_EDITOR_FONT_SIZE_PX,
          sidebar_width_px:        settings.sidebar_width_px,
        }}
      end
      app.command("settings.save", Int32) do |size|
        settings.update_editor_font_size_px(size)
        {editor_font_size_px: settings.editor_font_size_px}
      end
      app.command("settings.save_sidebar_width", Int32) do |width|
        settings.update_sidebar_width_px(width)
        {sidebar_width_px: settings.sidebar_width_px}
      end
    end
  end
end
