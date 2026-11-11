# Optional integration check: requires an interactive desktop session.
# Run: crystal run spec/support/native_smoke.cr
require "file_utils"
require "random/secure"
require "../../src/memo/app"

require "./dialog_provider"

root = File.join(Dir.tempdir, "memo-native-smoke-#{Random::Secure.hex(8)}")
Dir.mkdir_p(root)
ENV["MEMO_DATABASE_URL"] = "sqlite3://#{root}/memo.db"
result = "No result received from the WebView"
export_path = File.join(root, "export.json")
settings = Memo::Settings.new(File.join(root, "settings.json"))
settings.update_sidebar_width_px(320)
dialogs = TestDialogProvider.new(export_path)
app = Memo::App.new(settings: settings, dialog_provider: dialogs).build
# Fail a real database write, keeping the application's state publication path.
Memo::DBX.db.exec <<-SQL
  create trigger smoke_save_failure before update on notes
  when new.body = 'Simulated failing save'
  begin select raise(abort, 'Simulated database write failure'); end;
  SQL
app.command("smoke.confirm_delete", Bool) { |confirmed| dialogs.confirmed = confirmed }
app.command("smoke.confirm_count") { dialogs.confirm_count }
app.command("smoke.result", String) { |message| result = message }
app.command("smoke.quit") { app.quit; true }
app.command("smoke.native_close") do
  app.primary_window.not_nil!.native.handle_close_request
end
app.command("smoke.resize", Int32) do |width|
  app.primary_window.not_nil!.size(width, 700)
  true
end
app.primary_window.not_nil!.init(<<-'JS')
  document.addEventListener('DOMContentLoaded', async () => {
    const ipc = window.__CRYSTKIT_IPC__;
    const $ = id => document.getElementById(id);
    const wait = async check => {
      for (let i = 0; i < 250; i++) {
        if (await check()) return;
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
      const sidebar = $('notes-sidebar');
      const splitter = $('sidebar-resizer');
      const width = () => Math.round(sidebar.getBoundingClientRect().width);
      if (width() !== 320) throw new Error('Saved sidebar width was not restored');
      // Capture rejection must not prevent document-level drag tracking.
      const capture = splitter.setPointerCapture;
      splitter.setPointerCapture = () => { throw new DOMException('Capture unavailable', 'NotFoundError'); };
      const drag = delta => {
        const start = sidebar.getBoundingClientRect().right;
        const pointer = { pointerId: 1, isPrimary: true, button: 0, buttons: 1, bubbles: true };
        splitter.dispatchEvent(new PointerEvent('pointerdown', { ...pointer, clientX: start }));
        document.dispatchEvent(new PointerEvent('pointermove', { ...pointer, clientX: start + delta }));
        document.dispatchEvent(new PointerEvent('pointerup', { ...pointer, clientX: start + delta }));
      };
      drag(80);
      if (width() !== 400) throw new Error('Sidebar drag did not resize');
      drag(10000);
      if (width() !== 600) throw new Error('Sidebar drag exceeded maximum');
      drag(-10000);
      if (width() !== 150) throw new Error('Sidebar drag exceeded minimum');
      drag(210);
      splitter.setPointerCapture = capture;
      splitter.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight' }));
      if (width() !== 370) throw new Error('Sidebar keyboard resize failed');
      splitter.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft' }));
      await wait(async () => (await ipc.invoke('settings.get')).ui.sidebar_width_px === 360);
      await ipc.invoke('smoke.resize', 500);
      await wait(() => window.innerWidth === 500 && width() <= 254);
      await ipc.invoke('smoke.resize', 1000);
      await wait(() => window.innerWidth === 1000 && width() === 360);
      $('new-note').click();
      await wait(() => !$('editor').hidden && !$('new-note').disabled);
      edit('note-title', '<script>日本語😀</script>');
      edit('note-body', 'First note\nquotes & < > 😀');
      $('new-note').click();
      await wait(() => document.querySelectorAll('.note-item').length === 2 && !$('new-note').disabled);
      if (document.querySelector('.note-item script')) throw new Error('Note rendered as HTML');
      const first = (await ipc.state('notes')).value.find(n => n.body.startsWith('First note'));
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
      await ipc.invoke('smoke.confirm_delete', false);
      const cancelledTitle = $('note-title').value;
      const cancelledBody = $('note-body').value;
      $('delete-note').click();
      await wait(async () => (await ipc.invoke('smoke.confirm_count')) === 1 && !$('delete-note').disabled);
      if (document.querySelectorAll('.note-item').length !== 2 || $('note-title').value !== cancelledTitle || $('note-body').value !== cancelledBody) {
        throw new Error('Cancelling delete changed the note');
      }
      await ipc.invoke('smoke.confirm_delete', true);
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
  restored_width = Memo::Settings.new(File.join(root, "settings.json")).sidebar_width_px
  raise "Sidebar width did not persist" unless restored_width == 360
  puts "Native smoke passed: sidebar resize and persistence, UI, IPC, Unicode, navigation saves, settings, export, confirmed and cancelled delete, failed close recovery, and close flush"
ensure
  Memo::DBX.close
  FileUtils.rm_rf(root)
end
