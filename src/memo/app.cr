require "log"
require "ecr"
require "http/client"
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
    SERVER_PORT_ENV         = "MEMO_SERVER_PORT"
    SERVER_TOKEN_ENV        = "MEMO_SERVER_TOKEN"
    SERVER_DEBUG_ENV        = "MEMO_SERVER_DEBUG"
    SERVER_SHUTDOWN_TIMEOUT = 2.seconds
    SERVER_START_ATTEMPTS   =  4
    SERVER_START_CHECKS     = 20
    SERVER_START_INTERVAL   = 50.milliseconds

    @server_process : Process?
    @server_finished : Channel(Nil)?
    @cleaned_up = false
    @cleanup_mutex = Mutex.new
    @port : Int32

    def initialize(@debug = false)
      @port = 0

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

      start_server(wv)

      wv.html = startup_html(
        app_url: "http://127.0.0.1:#{@port}/?memo_token=#{Memo::Security.token}",
        health_url: "http://127.0.0.1:#{@port}/healthz"
      )

      wv.run
      wv.destroy

      cleanup
    end

    def self.run_server_from_env(debug = false) : Nil
      port = ENV[SERVER_PORT_ENV]?.try(&.to_i?) || raise "#{SERVER_PORT_ENV} is required"
      token = ENV[SERVER_TOKEN_ENV]? || raise "#{SERVER_TOKEN_ENV} is required"
      run_server(port, token, debug)
    end

    def self.run_server(port : Int32, token : String, debug = false) : Nil
      Memo::Security.token = token
      Kemal.config.host_binding = "127.0.0.1"

      Process.on_terminate do
        begin
          Kemal.stop if Kemal.config.running
        rescue ex
          STDERR.puts "Error stopping server: #{ex.message}" if debug
        ensure
          Memo::DBX.close rescue nil
          exit(0)
        end
      end

      Memo::DBX.setup
      Kemal.run(port: port, args: nil, trap_signal: false)
    ensure
      Memo::DBX.close rescue nil
    end

    private def cleanup
      process = nil
      finished = nil

      @cleanup_mutex.synchronize do
        return if @cleaned_up
        @cleaned_up = true
        process = @server_process
        finished = @server_finished
      end

      puts "Shutting down server..." if @debug

      terminate_server_process(process, finished)
    end

    private def find_available_port
      TCPServer.open("127.0.0.1", 0) do |server|
        server.local_address.port
      end
    end

    private def start_server(wv : Webview::Webview) : Nil
      executable = Process.executable_path || raise "cannot determine executable path"
      last_status = nil

      SERVER_START_ATTEMPTS.times do
        @port = find_available_port
        process, finished, exited = launch_server_process(executable, wv)

        if status = wait_for_server_start(exited)
          last_status = status
          next
        end

        @cleanup_mutex.synchronize do
          @server_process = process
          @server_finished = finished
        end
        return
      end

      detail = last_status.try { |status| ": #{status.description}" } || ""
      raise "local server failed to start#{detail}"
    end

    private def launch_server_process(executable : String, wv : Webview::Webview)
      finished = Channel(Nil).new(1)
      exited = Channel(Process::Status).new(1)

      env = {
        SERVER_PORT_ENV  => @port.to_s,
        SERVER_TOKEN_ENV => Memo::Security.token,
      }
      env[SERVER_DEBUG_ENV] = "1" if @debug

      process = Process.new(
        executable,
        ["--server"],
        env: env,
        input: Process::Redirect::Close,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )

      # wv.run owns the main thread inside the native WebView/AppKit loop. This
      # monitor intentionally uses a system thread so process.wait can complete
      # while the GUI thread is blocked; UI changes still go through wv.dispatch.
      Thread.new(name: "memo-server-monitor") do
        status = process.wait
        exited.send(status)
        should_report = @cleanup_mutex.synchronize do
          current = @server_process
          current && current.same?(process) && !@cleaned_up
        end

        finished.send(nil)

        if should_report
          wv.dispatch do
            wv.html = server_error_html(status)
          end
        end
      end

      {process, finished, exited}
    end

    private def wait_for_server_start(exited : Channel(Process::Status)) : Process::Status?
      # A nil result means "continue startup": either the server answered
      # /healthz, or it stayed alive past the short readiness window. The
      # startup page keeps polling /healthz, so slow but healthy boots still
      # show the user a loading screen instead of failing early.
      SERVER_START_CHECKS.times do
        return nil if server_healthy?

        select
        when status = exited.receive
          return status
        when timeout(SERVER_START_INTERVAL)
        end
      end

      nil
    end

    private def server_healthy? : Bool
      response = HTTP::Client.get("http://127.0.0.1:#{@port}/healthz")
      response.status_code == 200
    rescue
      false
    end

    private def terminate_server_process(process : Process?, finished : Channel(Nil)?) : Nil
      return unless process

      unless process.terminated?
        process.terminate
      end

      if finished
        select
        when finished.receive
          return
        when timeout(SERVER_SHUTDOWN_TIMEOUT)
        end
      end

      unless process.terminated?
        process.terminate(graceful: false)
      end

      if finished
        select
        when finished.receive
        when timeout(SERVER_SHUTDOWN_TIMEOUT)
          STDERR.puts "Server process did not exit after forced termination" if @debug
        end
      end
    rescue ex
      STDERR.puts "Error stopping server process: #{ex.message}" if @debug
    end

    private def startup_html(app_url : String, health_url : String) : String
      ECR.render("views/startup.ecr")
    end

    private def server_error_html(status : Process::Status) : String
      message = status.success? ? "The local server stopped." : "The local server exited: #{status.description}."
      <<-HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Memo Server Stopped</title>
        <style>
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            color: #1f2933;
            background: #f6f3ee;
          }

          main {
            width: min(30rem, calc(100vw - 3rem));
          }

          h1 {
            margin: 0 0 0.75rem;
            font-size: 1.6rem;
          }

          p {
            margin: 0;
            line-height: 1.6;
            color: #52606d;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Memo server stopped</h1>
          <p>#{HTML.escape(message)}</p>
        </main>
      </body>
      </html>
      HTML
    end
  end
end
