require "webview"
require "./route"

module Memo
  class App
    def initialize(@debug = false)
      @port = find_available_port || 3000
    end

    def run
      spawn do
        Kemal.run(port: @port)
      end

      sleep 1.second # Wait for server to start

      wv = Webview.window(1200, 800, Webview::SizeHints::NONE, "Memo App", @debug)
      wv.navigate("http://localhost:#{@port}")
      wv.run
      wv.destroy
    end

    private def find_available_port
      server = TCPServer.new("localhost", 0)
      port = server.local_address.port
      server.close
      port
    end
  end
end
