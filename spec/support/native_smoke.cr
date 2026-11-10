# Optional integration check: requires an interactive desktop session.
# Run: crystal run spec/support/native_smoke.cr
require "file_utils"
require "random/secure"
require "../../src/memo/app"

class SmokeDialog < CrystKit::Features::DialogProvider
  def initialize(@path : String)
  end

  def open_file(options : CrystKit::Features::OpenFileOptions) : String?
    nil
  end

  def open_files(options : CrystKit::Features::OpenFileOptions) : Array(String)
    [] of String
  end

  def save_file(options : CrystKit::Features::SaveFileOptions) : String?
    @path
  end

  def select_folder(options : CrystKit::Features::FolderOptions) : String?
    nil
  end

  def message(title : String, message : String, kind : Int32) : Bool
    true
  end

  def confirm(title : String, message : String) : Bool
    true
  end
end

root = File.join(Dir.tempdir, "memo-native-smoke-#{Random::Secure.hex(8)}")
Dir.mkdir_p(root)
ENV["MEMO_DATABASE_URL"] = "sqlite3://#{root}/memo.db"
result = "No result received from the WebView"
export_path = File.join(root, "export.json")
app = Memo::App.new(settings: Memo::Settings.new(File.join(root, "settings.json")),
  dialog_provider: SmokeDialog.new(export_path)).build
failed_once = false
app.router.unregister_command("notes.save")
app.command("notes.save", Memo::SaveNote) do |request|
  if request.body == "Simulated failing save" && !failed_once
    failed_once = true
    raise "Simulated database write failure"
  end
  Memo::Store.new(Memo::DBX.db).save(request)
end
app.command("smoke.result", String) { |message| result = message }
app.command("smoke.quit") { app.quit; true }
app.command("smoke.native_close") do
  app.primary_window.not_nil!.native.handle_close_request
end
app.primary_window.not_nil!.init(<<-'JS')
  document.addEventListener('DOMContentLoaded', async () => {
    const ipc = window.__CRYSTKIT_IPC__;
    const $ = id => document.getElementById(id);
    const wait = async check => {
      for (let i = 0; i < 250; i++) {
        if (check()) return;
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      throw new Error('Timed out: ' + check.toString() + '; ' + $('message').textContent);
    };
    const edit = (id, value) => {
      $(id).value = value;
      $(id).dispatchEvent(new Event('input', { bubbles: true }));
    };
    try {
      await wait(() => !$('new-note').disabled);
      $('new-note').click();
      await wait(() => !$('editor').hidden && !$('new-note').disabled);
      edit('note-title', '<script>日本語😀</script>');
      edit('note-body', 'First note\nquotes & < > 😀');
      $('new-note').click();
      await wait(() => document.querySelectorAll('.note-item').length === 2 && !$('new-note').disabled);
      if (document.querySelector('.note-item script')) throw new Error('Note rendered as HTML');
      const first = (await ipc.invoke('notes.list')).find(n => n.body.startsWith('First note'));
      if (!first || first.title !== '<script>日本語😀</script>') throw new Error('Navigation lost edits');
      document.querySelectorAll('.note-item')[1].click();
      await wait(() => $('note-title').value === first.title && !$('new-note').disabled);
      $('open-settings').click();
      await wait(() => !$('settings-page').hidden && !$('back-to-notes').disabled);
      $('editor-font-size').value = '23';
      $('font-form').dispatchEvent(new Event('submit', { cancelable: true }));
      await wait(() => $('font-status').textContent === 'Saved');
      $('export-notes').click();
      await wait(() => $('export-status').textContent.startsWith('Saved to'));
      $('back-to-notes').click();
      $('delete-note').click();
      $('delete-note').click();
      await wait(() => document.querySelectorAll('.note-item').length === 1 && !$('new-note').disabled);
      edit('note-body', 'Simulated failing save');
      await ipc.invoke('smoke.native_close');
      await wait(() => !$('message').hidden && $('message').textContent.includes('Simulated database write failure') && !$('new-note').disabled);
      if ($('note-body').value !== 'Simulated failing save') throw new Error('Failed close lost the buffer');
      edit('note-body', 'Saved by native close 日本語😀');
      await ipc.invoke('smoke.result', 'ok');
      await ipc.invoke('smoke.native_close');
    } catch (error) {
      await ipc.invoke('smoke.result', error.message);
      await ipc.invoke('app.close');
    }
  });
JS
# A watchdog bounds a broken bridge or frontend startup without user action.
Thread.new do
  sleep 15.seconds
  STDERR.puts "Native smoke timed out"
  Process.exit(1)
end
begin
  app.run
  raise result unless result == "ok"
  exported = JSON.parse(File.read(export_path)).as_a
  raise "Export did not contain both notes" unless exported.size == 2
  Memo::DBX.setup
  notes = Memo::Store.new(Memo::DBX.db).list
  raise "Delete did not persist" unless notes.size == 1
  raise "Native close lost edits" unless notes.first.body == "Saved by native close 日本語😀"
  size = Memo::Settings.new(File.join(root, "settings.json")).editor_font_size_px
  raise "Settings did not persist" unless size == 23
  puts "Native smoke passed: UI, IPC, Unicode, navigation saves, settings, export, delete, failed close recovery, and close flush"
ensure
  Memo::DBX.close
  FileUtils.rm_rf(root)
end
