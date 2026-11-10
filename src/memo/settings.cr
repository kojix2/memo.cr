require "json"
require "random/secure"

require "./db"

module Memo
  class Settings
    SETTINGS_VERSION            =   1
    DEFAULT_EDITOR_FONT_SIZE_PX =  16
    MIN_EDITOR_FONT_SIZE_PX     =  10
    MAX_EDITOR_FONT_SIZE_PX     =  32
    DEFAULT_SIDEBAR_WIDTH_PX    = 280
    MIN_SIDEBAR_WIDTH_PX        = 150
    MAX_SIDEBAR_WIDTH_PX        = 600

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
      property sidebar_width_px : Int32 = DEFAULT_SIDEBAR_WIDTH_PX

      def initialize(@editor_font_size_px : Int32 = DEFAULT_EDITOR_FONT_SIZE_PX,
                     @sidebar_width_px : Int32 = DEFAULT_SIDEBAR_WIDTH_PX)
      end

      def normalized : UI
        size = editor_font_size_px
        if size < MIN_EDITOR_FONT_SIZE_PX || size > MAX_EDITOR_FONT_SIZE_PX
          size = DEFAULT_EDITOR_FONT_SIZE_PX
        end
        width = sidebar_width_px
        unless MIN_SIDEBAR_WIDTH_PX <= width <= MAX_SIDEBAR_WIDTH_PX
          width = DEFAULT_SIDEBAR_WIDTH_PX
        end
        UI.new(editor_font_size_px: size, sidebar_width_px: width)
      end
    end

    @mutex = Mutex.new
    @data : Data?

    getter path : String

    def initialize(@path : String = File.join(File.dirname(DBX.db_path), "settings.json"))
    end

    def load : Data
      @mutex.synchronize do
        if cached = @data
          return cached
        end

        data = load_from_disk
        @data = data
        data
      end
    end

    def editor_font_size_px : Int32
      load.ui.editor_font_size_px
    end

    def sidebar_width_px : Int32
      load.ui.sidebar_width_px
    end

    def update_editor_font_size_px(value : Int32)
      unless MIN_EDITOR_FONT_SIZE_PX <= value <= MAX_EDITOR_FONT_SIZE_PX
        raise ArgumentError.new("editor_font_size_px must be between #{MIN_EDITOR_FONT_SIZE_PX} and #{MAX_EDITOR_FONT_SIZE_PX}")
      end

      update_ui do |ui|
        ui.editor_font_size_px = value
        ui
      end
    end

    def update_sidebar_width_px(value : Int32)
      unless MIN_SIDEBAR_WIDTH_PX <= value <= MAX_SIDEBAR_WIDTH_PX
        raise ArgumentError.new("sidebar_width_px must be between #{MIN_SIDEBAR_WIDTH_PX} and #{MAX_SIDEBAR_WIDTH_PX}")
      end

      update_ui do |ui|
        ui.sidebar_width_px = value
        ui
      end
    end

    private def update_ui(&block : UI -> UI)
      @mutex.synchronize do
        updated = (@data || load_from_disk)
        updated.ui = block.call(updated.ui)
        updated = updated.normalized
        write_to_disk(updated)
        @data = updated
      end
    end

    private def load_from_disk : Data
      file_path = path
      begin
        if File.exists?(file_path)
          raw = File.read(file_path)
          data = Data.from_json(raw)
          return data.normalized
        end
      rescue
        quarantine_corrupt_file(file_path)
      end

      Data.new.normalized
    end

    private def write_to_disk(data : Data)
      file_path = path
      dir = File.dirname(file_path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      bak_path = file_path + ".bak"

      tmp_path = file_path + ".tmp.#{Random::Secure.hex(8)}"
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

    private def quarantine_corrupt_file(file_path : String)
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
