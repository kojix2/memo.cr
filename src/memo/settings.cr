require "json"
require "crystkit"

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
    @files : CrystKit::Features::FileSystem

    getter path : String

    def initialize(@path : String = File.join(File.dirname(DBX.db_path), "settings.json"))
      security = CrystKit::Security::Context.new
      security.capabilities.grant("fs:read")
      security.capabilities.grant("fs:write")
      security.scopes.persist(Path[path].expand(home: true).parent, CrystKit::Security::Permission::Write)
      @files = CrystKit::Features::FileSystem.new(security)
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

      update_ui do |preferences|
        preferences.editor_font_size_px = value
        preferences
      end
    end

    def update_sidebar_width_px(value : Int32)
      unless MIN_SIDEBAR_WIDTH_PX <= value <= MAX_SIDEBAR_WIDTH_PX
        raise ArgumentError.new("sidebar_width_px must be between #{MIN_SIDEBAR_WIDTH_PX} and #{MAX_SIDEBAR_WIDTH_PX}")
      end

      update_ui do |preferences|
        preferences.sidebar_width_px = value
        preferences
      end
    end

    private def update_ui(&block : UI -> UI)
      @mutex.synchronize do
        updated = (@data || load_from_disk)
        updated.ui = block.call(updated.ui)
        updated = updated.normalized
        @files.create_dir(Path[path].expand(home: true).parent, recursive: true)
        @files.write_text(Path[path], updated.to_json)
        @data = updated
      end
    end

    private def load_from_disk : Data
      return Data.new unless @files.exists?(Path[path])
      Data.from_json(@files.read_text(Path[path])).normalized
    rescue JSON::ParseException | JSON::SerializableError
      Data.new
    end
  end
end
