module Memo::EditMenu
  Log = ::Log.for(self)

  # The Webview shard supplies the WebKitGTK linker flags for the selected ABI.
  {% if flag?(:linux) %}
    lib LibWebKitEditing
      fun webkit_web_view_execute_editing_command(view : Void*, command : UInt8*) : Nil
    end
  {% elsif flag?(:windows) %}
    lib LibWebView2Editing
      fun memo_webview2_edit(controller : Void*, parameters : UInt16*) : Int32
    end
  {% end %}

  def self.perform(window : CrystKit::Core::Window, command : String) : Nil
    {% if flag?(:darwin) %}
      runtime = NativeDesktop::Platform::MacOS::ObjCRuntime
      native_app = runtime.msg(runtime.get_class("NSApplication"), "sharedApplication")
      target = runtime.msg(native_app, "targetForAction:", runtime.sel("#{command}:"))
      runtime.msg_void(target, "#{command}:", Pointer(Void).null) unless target.null?
    {% else %}
      # Run after the native menu callback returns and target this WebView only.
      window.dispatch do
        controller = window.native_handle(Webview::NativeHandleKind::BROWSER_CONTROLLER)
        unless controller.null?
          {% if flag?(:linux) %}
            LibWebKitEditing.webkit_web_view_execute_editing_command(controller, command.camelcase)
          {% elsif flag?(:windows) %}
            parameters = {type: "rawKeyDown", commands: [command.camelcase]}.to_json
            NativeDesktop::Platform::Windows::StringHelpers.with_utf16_bytes(parameters) do |wide|
              result = LibWebView2Editing.memo_webview2_edit(controller, wide)
              Log.warn { "WebView2 rejected editing command #{command} (#{result})" } if result < 0
            end
          {% end %}
        end
      end
    {% end %}
  end
end
