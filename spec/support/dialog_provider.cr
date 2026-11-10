require "crystkit"

# Deterministic responses for CrystKit's native dialog boundary.
class TestDialogProvider < CrystKit::Features::DialogProvider
  property confirmed = true
  getter confirm_count = 0

  def initialize(@save_path : String? = nil)
  end

  def open_file(options : CrystKit::Features::OpenFileOptions) : String?
    nil
  end

  def open_files(options : CrystKit::Features::OpenFileOptions) : Array(String)
    [] of String
  end

  def save_file(options : CrystKit::Features::SaveFileOptions) : String?
    @save_path
  end

  def select_folder(options : CrystKit::Features::FolderOptions) : String?
    nil
  end

  def message(title : String, message : String, kind : Int32) : Bool
    true
  end

  def confirm(title : String, message : String) : Bool
    @confirm_count += 1
    confirmed
  end
end
