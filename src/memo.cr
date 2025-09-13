require "./memo/app"
require "./memo/version"

app = Memo::App.new(debug: ARGV.includes?("--debug"))
app.run
