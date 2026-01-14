require "log"
require "webview"
require "random/secure"
require "./security"

# Configure logging from LOG_LEVEL (default info); relies on Crystal's std Log.setup_from_env
Log.setup_from_env

module Memo
  # Project-wide logger root source "memo"
  Log = ::Log.for("memo")
end

::Log.info { "Memo starting; LOG_LEVEL=#{ENV["LOG_LEVEL"]? || "(default info)"}" }

require "./route"

module Memo
  class App
    @server_fiber : Fiber?
    @cleaned_up = false
    @port : Int32

    def initialize(@debug = false)
      @port = find_available_port

      # P0: Generate a per-launch secret token and force loopback binding.
      Memo::Security.token = Random::Secure.hex(32)
      Kemal.config.host_binding = "127.0.0.1"
    end

    def run
      {% if flag?(:execution_context) %}
        kemal_context = Fiber::ExecutionContext::Parallel.new("workers", 4)
        @server_fiber = kemal_context.spawn do
          begin
            Kemal.run(port: @port, args: nil, trap_signal: false)
          rescue ex
            puts "Server error: #{ex.message}" if @debug
          end
        end
      {% else %}
        @server_fiber = spawn do
          begin
            Kemal.run(port: @port, args: nil, trap_signal: false)
          rescue ex
            puts "Server error: #{ex.message}" if @debug
          end
        end
      {% end %}

      at_exit do
        cleanup
      end

      Process.on_terminate do
        cleanup
        exit(0)
      end

      wait_for_server_start

      wv = Webview.window(900, 600, Webview::SizeHints::NONE, "Memo App", @debug)
      wv.navigate("http://127.0.0.1:#{@port}")
      wv.run
      wv.destroy

      cleanup
    end

    private def cleanup
      return if @cleaned_up
      @cleaned_up = true

      puts "Shutting down server..." if @debug

      begin
        Kemal.stop if Kemal.config.running
      rescue ex
        puts "Error stopping server: #{ex.message}" if @debug
      end
      # Attempt to close DB connection politely.
      Memo::DBX.close rescue nil
      sleep 0.1.seconds
    end

    private def find_available_port
      TCPServer.open("localhost", 0) do |server|
        server.local_address.port
      end
    end

    private def wait_for_server_start
      timeout = 10.seconds
      start_time = Time.monotonic

      until server_listening?
        if (Time.monotonic - start_time) > timeout
          raise "Server failed to start within #{timeout}"
        end
        Fiber.yield
      end
    end

    private def server_listening?
      TCPSocket.new("127.0.0.1", @port).close
      true
    rescue Socket::ConnectError
      false
    end
  end
end
