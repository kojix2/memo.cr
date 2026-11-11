require "log"
require "ecr"
require "crystkit"
require "./commands"

module Memo
  class App
    # Inline assets are compiled into the executable, so packaged apps run
    # independently of the current working directory or a frontend directory.
    private def frontend : String
      ECR.render("views/app.ecr")
    end

    def initialize(@debug = false, @settings : Settings = Settings.new,
                   @dialog_provider : CrystKit::Features::DialogProvider = CrystKit::Features::NativeDialogProvider.new)
      @frontend_ready = false
      @allow_close = false
    end

    def run
      build.run
    ensure
      DBX.close
    end

    def build : CrystKit::App
      Log.setup_from_env
      DBX.setup
      store = Store.new(DBX.db)
      settings = @settings
      config = CrystKit::AppConfig.new(
        name: "Memo",
        version: VERSION,
        identifier: "com.github.kojix2.memo",
        storage_dir: Path[File.dirname(settings.path)],
        ipc: Commands::IPC_POLICY,
        asset_protocol_enabled: false,
      )
      app = CrystKit::App.new(config)
      app.grant(Commands::CAPABILITY, "dialog:save")
      Commands.register(app, store, settings, CrystKit::Features::MessageDialog.new(@dialog_provider))
      app.on_shutdown { DBX.close }

      dialog = CrystKit::Features::FileDialog.new(app.security, @dialog_provider)
      app.command("notes.export") do
        path = dialog.save_file(CrystKit::Features::SaveFileOptions.new(
          title: "Export notes",
          default_name: "memo-#{Time.local.to_s("%Y-%m-%d")}.json",
          default_extension: "json",
          filters: [CrystKit::Features::FileFilter.new("JSON", ["json"])],
          owner: app.primary_window.try(&.window),
        ))
        if path
          File.write(path, store.export_json)
          path.to_s
        end
      end
      app.command("app.ready") { @frontend_ready = true }
      app.command("app.close") do
        @allow_close = true
        app.quit
        true
      end

      menu = CrystKit::Features::MenuBar.new
      app_menu = CrystKit::Features::Menu.new("Memo")
      modifier = {% if flag?(:darwin) %} "Cmd" {% else %} "Ctrl" {% end %}
      app_menu.add_item("Settings…", "#{modifier}+,") { app.emit("settings:open", nil) }
      app_menu.add_separator
      app_menu.add_item("Quit Memo", "#{modifier}+Q") { app.quit }
      menu.add(app_menu)
      menu.menu("File") do |file|
        file.add_item("New Note", "#{modifier}+N") { app.emit("notes:new", nil) }
        file.add_item("Save", "#{modifier}+S") { app.emit("notes:save", nil) }
        file.add_item("Export JSON…") { app.emit("notes:export", nil) }
        file.add_separator
        file.add_item("Close", "#{modifier}+W") { app.emit("app:close-requested", nil) }
      end
      edit_menu = CrystKit::Features::Menu.new("Edit")
      {"Undo" => "undo", "Redo" => "redo", "Cut" => "cut", "Copy" => "copy", "Paste" => "paste", "Select All" => "selectAll"}.each do |label, command|
        edit_menu.add_item(label) do
          app.primary_window.try(&.eval("document.execCommand(#{command.to_json})"))
        end
      end
      menu.add(edit_menu)
      app.menu_bar = menu

      window = app.window(title: "Memo", width: 1000, height: 700,
        label: "main", debug: @debug, html: frontend)
      window.on_close { request_close(app) }
      app.on_before_quit { request_close(app) }
      app
    end

    private def request_close(app : CrystKit::App) : Bool
      return true if @allow_close || !@frontend_ready
      # Native close is synchronous. Veto it, ask JS to finish its save queue,
      # and let app.close retry only after persistence has succeeded.
      app.emit("app:close-requested", nil)
      false
    end
  end
end
