require "log"
require "ecr"
require "webview"
require "random/secure"
require "./security"

{% unless flag?(:execution_context) %}
  {% raise "Memo requires -Dexecution_context. Build with: shards build --release -Dpreview_mt -Dexecution_context" %}
{% end %}

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
      at_exit do
        cleanup
      end

      Process.on_terminate do
        cleanup
        exit(0)
      end

      wv = Webview.window(900, 600, Webview::SizeHints::NONE, "Memo App", @debug)

      # Under execution_context, yielding here can resume this fiber on a worker
      # thread. AppKit/WebView must be initialized before that happens.
      wv.html = startup_html(
        app_url: "http://127.0.0.1:#{@port}/?memo_token=#{Memo::Security.token}",
        health_url: "http://127.0.0.1:#{@port}/healthz"
      )

      # Start the embedded server after WebView initialization to reduce the
      # chance that startup side effects move this fiber off the main thread.
      start_server

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

    private def start_server
      kemal_context = Fiber::ExecutionContext::Parallel.new("workers", 4)
      @server_fiber = kemal_context.spawn do
        begin
          Memo::DBX.setup
          Kemal.run(port: @port, args: nil, trap_signal: false)
        rescue ex
          puts "Server error: #{ex.message}" if @debug
        end
      end
    end

    private def startup_html(app_url : String, health_url : String) : String
      ECR.render("views/startup.ecr")
    end
  end
end
