# Test-only stdio transport for the real CrystKit JS client and command router.
# This executable is never required by the application or shipped in packages.
require "ecr"
require "random/secure"
require "../../src/memo/commands"
require "./dialog_provider"

# Always create or reuse an explicitly supplied test fixture under the OS temp
# directory. Never resolve Settings' default path or open the user's database.
root = ARGV[0]? || File.join(Dir.tempdir, "memo-browser-#{Random::Secure.hex(8)}")
root = File.expand_path(root)
unless root.starts_with?(File.expand_path(Dir.tempdir) + "/memo-browser-") || root.starts_with?("/private/tmp/memo-browser-")
  abort "The fixture must be a memo-browser-* directory under the OS temp directory"
end
Dir.mkdir_p(root)
ENV["MEMO_DATABASE_URL"] = Memo::DBX.sqlite_url(File.join(root, "memo.db"))
Memo::DBX.setup
store = Memo::Store.new(Memo::DBX.db)
settings = Memo::Settings.new(File.join(root, "settings.json"))
app = CrystKit::App.new(CrystKit::AppConfig.new(storage_dir: Path[root], ipc: Memo::Commands::IPC_POLICY))
app.grant(Memo::Commands::CAPABILITY)
dialogs = TestDialogProvider.new(File.join(root, "export.json"))
Memo::Commands.register(app, store, settings, CrystKit::Features::MessageDialog.new(dialogs))
frontend = CrystKit::Test::FakeFrontend.new(app)
app.command("app.ready") { true }
app.command("app.close") { true }
app.command("notes.export") do
  if File.exists?(File.join(root, "cancel-export"))
    nil
  else
    path = File.join(root, "export.json")
    File.write(path, store.export_json)
    path
  end
end
Memo::DBX.db.exec <<-SQL
  create trigger if not exists browser_save_failure before update on notes
  when new.body = 'Simulated failing save'
  begin select raise(abort, 'Simulated database write failure'); end;
  SQL

# Use the framework's complete JS client, replacing only the native transport.
transport = <<-JS
  window.__crystal_ipc_invoke = async raw => {
    const response = await fetch('/__ipc', { method: 'POST', body: raw });
    const data = await response.json();
    for (const patch of data.patches) window.__CRYSTKIT_IPC__._dispatchEvent('__crystkit.state.patch', patch);
    return data.envelope;
  };
  window.__crystal_ipc_invoke_sync = window.__crystal_ipc_invoke;
  JS
html = ECR.render("views/app.ecr")
html = html.sub("connect-src 'none'", "connect-src 'self'")
html = html.sub("<body>", "<body><script>#{transport}\n#{CrystKit::IPC::IPC_JS_CLIENT}</script>")

puts({ready: true, fixture: root}.to_json)
STDOUT.flush
begin
  while line = STDIN.gets
    request = JSON.parse(line)
    content_type = "text/plain"
    body = case request["path"].as_s
           when "/"
             content_type = "text/html"
             html
           when "/__ipc"
             call = JSON.parse(request["body"].as_s)
             envelope = frontend.invoke(call["command"].as_s, call["params"]? || JSON::Any.new(nil))
             patches = frontend.state_patches.uniq
             frontend.state_patches.clear
             content_type = "application/json"
             {envelope: envelope, patches: patches}.to_json
           when "/__confirm"
             dialogs.confirmed = request["body"].as_s == "true"
             "ok"
           when "/__cancel_export"
             if request["body"].as_s == "true"
               File.write(File.join(root, "cancel-export"), "")
             else
               File.delete?(File.join(root, "cancel-export"))
             end
             "ok"
           else
             raise "Unexpected test request"
           end
    puts({body: body, content_type: content_type}.to_json)
    STDOUT.flush
  end
ensure
  frontend.detach
  app.shutdown
  Memo::DBX.close
end
