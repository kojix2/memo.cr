require "webview"
require "./route"

module Memo
  class App
    @server : HTTP::Server?
    @server_fiber : Fiber?
    @cleaned_up = false

    def initialize(@debug = false)
      @port = find_available_port || 3000
    end

    def run
      @server_fiber = spawn do
        begin
          @server = Kemal.run(port: @port, trap_signal: false)
        rescue ex
          puts "Server error: #{ex.message}" if @debug
        end
      end

      at_exit do
        cleanup
      end

      Signal::INT.trap do
        cleanup
        exit(0)
      end

      Signal::TERM.trap do
        cleanup
        exit(0)
      end

      # FIXME: Wait for the server to start properly
      sleep 1.second

      wv = Webview.window(1200, 800, Webview::SizeHints::NONE, "Memo App", @debug)
      wv.navigate("http://localhost:#{@port}")
      wv.run
      wv.destroy

      cleanup
    end

    private def cleanup
      return if @cleaned_up
      @cleaned_up = true

      puts "Shutting down server..." if @debug

      if server = @server
        begin
          server.close
        rescue ex
          puts "Error closing server: #{ex.message}" if @debug
        end
      end

      sleep 0.1.seconds
    end

    private def find_available_port
      TCPServer.open("localhost", 0) do |server|
        server.local_address.port
      end
    end
  end
end
