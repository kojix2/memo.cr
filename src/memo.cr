require "./memo/app"
require "crystkit/features/cli"

parser = CrystKit::Features::CLIParser.new("memo", "Local notes")
parser.option("debug", "Enable WebView developer tools", CrystKit::Features::OptionType::Bool)
parser.option("version", "Print version", CrystKit::Features::OptionType::Bool, short: "v")
begin
  args = parser.parse(ARGV)
rescue error : CrystKit::Core::ValidationError
  if error.field == "help"
    puts error.message
    exit
  end
  STDERR.puts error.message
  exit 1
end
if args.get_bool("version")
  puts Memo::VERSION
  exit
end
Memo::App.new(debug: args.get_bool("debug")).run
