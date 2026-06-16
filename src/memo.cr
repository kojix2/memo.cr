require "./memo/app"
require "./memo/version"

debug = ARGV.includes?("--debug") || ENV[Memo::App::SERVER_DEBUG_ENV]? == "1"

if ARGV.includes?("--server")
  Memo::App.run_server_from_env(debug: debug)
else
  app = Memo::App.new(debug: debug)
  app.run
end
