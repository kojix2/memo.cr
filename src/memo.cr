require "option_parser"
require "./memo/app"

debug = false
OptionParser.parse do |parser|
  parser.banner = "Usage: memo [--debug]"
  parser.on("--debug", "Enable WebView developer tools") { debug = true }
  parser.on("-v", "--version", "Print version") { puts Memo::VERSION; exit }
  parser.on("-h", "--help", "Show help") { puts parser; exit }
end
Memo::App.new(debug: debug).run
