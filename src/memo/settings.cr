require "json"
require "random/secure"

require "./db"

module Memo
  module Settings
    SETTINGS_VERSION            =  1
    DEFAULT_EDITOR_FONT_SIZE_PX = 16
    MIN_EDITOR_FONT_SIZE_PX     = 10
    MAX_EDITOR_FONT_SIZE_PX     = 32

    @[JSON::Serializable::Options(ignore_unknown_keys: true)]
    struct Data
      include JSON::Serializable

      property version : Int32
      property ui : UI

      def initialize(@version : Int32 = SETTINGS_VERSION, @ui : UI = UI.new)
      end

      def normalized : Data
        Data.new(
          version: SETTINGS_VERSION,
          ui: ui.normalized,
        )
      end
    end

    @[JSON::Serializable::Options(ignore_unknown_keys: true)]
    struct UI
      include JSON::Serializable

      property editor_font_size_px : Int32

      def initialize(@editor_font_size_px : Int32 = DEFAULT_EDITOR_FONT_SIZE_PX)
      end

      def normalized : UI
        size = editor_font_size_px
        if size < MIN_EDITOR_FONT_SIZE_PX || size > MAX_EDITOR_FONT_SIZE_PX
          size = DEFAULT_EDITOR_FONT_SIZE_PX
        end
        UI.new(editor_font_size_px: size)
      end
    end

    @@mutex = Mutex.new
    @@data : Data?

    def self.path : String
      # Keep settings next to the default DB (Memo::DBX.db_path).
      File.join(File.dirname(Memo::DBX.db_path), "settings.json")
    end

    def self.load : Data
      @@mutex.synchronize do
        if cached = @@data
          return cached
        end

        data = load_from_disk
        @@data = data
        data
      end
    end

    def self.editor_font_size_px : Int32
      load.ui.editor_font_size_px
    end

    def self.update_editor_font_size_px(value : Int32)
      unless MIN_EDITOR_FONT_SIZE_PX <= value <= MAX_EDITOR_FONT_SIZE_PX
        raise ArgumentError.new("editor_font_size_px must be between #{MIN_EDITOR_FONT_SIZE_PX} and #{MAX_EDITOR_FONT_SIZE_PX}")
      end

      @@mutex.synchronize do
        current = (@@data || load_from_disk)
        updated = current

        ui = updated.ui
        ui.editor_font_size_px = value
        updated.ui = ui

        updated = updated.normalized
        write_to_disk(updated)
        @@data = updated
      end
    end

    private def self.load_from_disk : Data
      file_path = path
      begin
        if File.exists?(file_path)
          raw = File.read(file_path)
          data = Data.from_json(raw)
          return data.normalized
        end
      rescue ex
        quarantine_corrupt_file(file_path)
      end

      Data.new.normalized
    end

    private def self.write_to_disk(data : Data)
      file_path = path
      dir = File.dirname(file_path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      tmp_path : String? = nil
      bak_path = file_path + ".bak"

      tmp_path = file_path + ".tmp"
      File.write(tmp_path, data.to_json)

      if File.exists?(file_path)
        begin
          File.delete(bak_path) if File.exists?(bak_path)
        rescue
        end
        begin
          File.rename(file_path, bak_path)
        rescue
          # If renaming fails, fall back to overwriting (best effort).
        end
      end

      File.rename(tmp_path, file_path)
    ensure
      begin
        if tmp_path
          File.delete(tmp_path) if File.exists?(tmp_path)
        end
      rescue
      end
    end

    private def self.quarantine_corrupt_file(file_path : String)
      return unless File.exists?(file_path)

      ts = Time.local.to_s("%Y%m%d%H%M%S")
      suffix = Random::Secure.hex(4)
      quarantined = file_path + ".corrupt.#{ts}.#{suffix}"
      begin
        File.rename(file_path, quarantined)
      rescue
        # If we cannot rename it, leave it as-is and fall back to defaults.
      end
    end
  end
end
