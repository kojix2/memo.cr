# Exercise Cocoa's actual menu key-equivalent dispatch without posting input
# to the desktop or requiring Accessibility permission.
{% if flag?(:darwin) %}
  @[Link(framework: "ApplicationServices")]
  lib LibSmokeKeyboard
    fun create = CGEventCreateKeyboardEvent(source : Void*, key : UInt16, down : Bool) : Void*
    fun set_flags = CGEventSetFlags(event : Void*, flags : UInt64)
    fun release = CFRelease(object : Void*)
  end

  module NativeSmokeShortcuts
    alias SetClipboardData = Proc(Void*, Void*, Void*, Void*, Int8)

    # Materialize every pasteboard representation before the copy test, then
    # restore it afterwards (including non-text formats).
    def self.snapshot_clipboard : Void*
      runtime = NativeDesktop::Platform::MacOS::ObjCRuntime
      runtime.with_autorelease_pool do
        pasteboard = runtime.msg(runtime.get_class("NSPasteboard"), "generalPasteboard")
        originals = runtime.msg(pasteboard, "pasteboardItems")
        saved = runtime.msg(runtime.msg(runtime.get_class("NSMutableArray"), "alloc"), "init")
        set_data = SetClipboardData.new(runtime.msg_send_addr, Pointer(Void).null)
        runtime.msg_long(originals, "count").times do |index|
          original = runtime.msg_object_at(originals, "objectAtIndex:", index.to_u64)
          item = runtime.msg(runtime.msg(runtime.get_class("NSPasteboardItem"), "alloc"), "init")
          types = runtime.msg(original, "types")
          runtime.msg_long(types, "count").times do |type_index|
            type = runtime.msg_object_at(types, "objectAtIndex:", type_index.to_u64)
            data = runtime.msg(original, "dataForType:", type)
            set_data.call(item, runtime.sel("setData:forType:"), data, type) unless data.null?
          end
          runtime.msg_void(saved, "addObject:", item)
          runtime.msg_void(item, "release")
        end
        saved
      end
    end

    def self.restore_clipboard(saved : Void*) : Nil
      runtime = NativeDesktop::Platform::MacOS::ObjCRuntime
      runtime.with_autorelease_pool do
        pasteboard = runtime.msg(runtime.get_class("NSPasteboard"), "generalPasteboard")
        runtime.msg_long(pasteboard, "clearContents")
        runtime.msg_bool_object(pasteboard, "writeObjects:", saved)
        runtime.msg_void(saved, "release")
      end
    end

    def self.press(key : String) : Bool
      code = {"a" => 0_u16, "z" => 6_u16, "x" => 7_u16, "c" => 8_u16, "v" => 9_u16}[key.split("+").last]
      flags = 1_u64 << 20 # Command
      flags |= 1_u64 << 17 if key.starts_with?("shift+")
      event = LibSmokeKeyboard.create(Pointer(Void).null, code, true)
      raise "Could not create keyboard event" if event.null?
      begin
        LibSmokeKeyboard.set_flags(event, flags)
        runtime = NativeDesktop::Platform::MacOS::ObjCRuntime
        native_event = runtime.msg(runtime.get_class("NSEvent"), "eventWithCGEvent:", event)
        native_app = runtime.msg(runtime.get_class("NSApplication"), "sharedApplication")
        native_menu = runtime.msg(native_app, "mainMenu")
        runtime.msg_bool_object(native_menu, "performKeyEquivalent:", native_event)
      ensure
        LibSmokeKeyboard.release(event)
      end
    end
  end
{% end %}
