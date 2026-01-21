# src/routes.cr
require "kemal"
require "html"
require "ecr"
require "./db"
require "./security"
require "./settings"

module Memo
  Memo::DBX.setup

  # Use the project-wide logger defined in Memo::Log (app.cr)
  LOGGER = Memo::Log

  # Per-request lightweight timing (only active when debug logging is enabled)
  before_all do |env|
    if LOGGER.level <= ::Log::Severity::Debug
      env.set "__memo_req_start_time", Time.utc.to_unix_f
      env.set "__memo_req_id", Random::Secure.hex(4)
      rid = (env.get("__memo_req_id") rescue nil)
      LOGGER.debug { "request begin id=#{rid} #{env.request.method} #{env.request.path}" }
    end
  end

  after_all do |env|
    if LOGGER.level <= ::Log::Severity::Debug
      start_time = (env.get("__memo_req_start_time") rescue nil)
      rid = (env.get("__memo_req_id") rescue nil)
      if start_time.is_a?(Float64)
        dur_ms = ((Time.utc.to_unix_f - start_time) * 1000).round(1)
        LOGGER.debug { "request end id=#{rid} status=#{env.response.status_code} duration_ms=#{dur_ms}" }
      end
    end
  end

  # Force UTF-8 encoding for all HTTP responses
  before_all do |env|
    env.response.content_type = "text/html; charset=utf-8"
  end

  def self.h(s) : String
    HTML.escape(s.to_s)
  end

  private def self.extract_token(env) : String?
    env.request.headers["X-Memo-Token"]? ||
      env.params.query["memo_token"]? ||
      env.params.body["memo_token"]?.try(&.to_s)
  rescue
    env.request.headers["X-Memo-Token"]?
  end

  private def self.token_protected?(env) : Bool
    # Protect all state-changing requests and sensitive reads.
    return true if env.request.method != "GET"
    path = env.request.path
    path == "/export.json" || path == "/api/info" || path == "/api/settings"
  end

  private def self.allowed_origins : Array(String)
    port = Kemal.config.port
    ["http://127.0.0.1:#{port}", "http://localhost:#{port}"]
  end

  private def self.same_origin?(env) : Bool
    origins = allowed_origins

    if origin = env.request.headers["Origin"]?
      return origins.includes?(origin)
    end

    if referer = env.request.headers["Referer"]?
      return origins.any? { |o| referer.starts_with?(o) }
    end

    false
  end

  before_all do |env|
    if token_protected?(env)
      # P1: Mitigate CSRF-like localhost abuse by requiring same-origin requests.
      # Enforce Origin when present; otherwise fall back to Referer.
      # If neither header exists, reject the request.
      unless same_origin?(env)
        env.response.content_type = "application/json; charset=utf-8"
        err_json = {status: "error", message: "forbidden"}.to_json
        halt env, status_code: 403, response: err_json
      end

      if sfs = env.request.headers["Sec-Fetch-Site"]?
        unless sfs == "same-origin" || sfs == "none"
          env.response.content_type = "application/json; charset=utf-8"
          err_json = {status: "error", message: "forbidden"}.to_json
          halt env, status_code: 403, response: err_json
        end
      end

      unless Memo::Security.enabled?
        env.response.content_type = "application/json; charset=utf-8"
        err_json = {status: "error", message: "security token not initialized"}.to_json
        halt env, status_code: 500, response: err_json
      end

      provided = extract_token(env)
      if provided != Memo::Security.token
        env.response.content_type = "application/json; charset=utf-8"
        err_json = {status: "error", message: "forbidden"}.to_json
        halt env, status_code: 403, response: err_json
      end
    end
  end

  get "/" do |env|
    notes = Memo::DBX.db.query_all <<-SQL, as: {Int64, String, String, String, String}
      select id, title, body, created_at, updated_at
      from notes order by updated_at desc
    SQL

    # Get selected note ID from query parameter
    selected_note_id = env.params.query["note"]?.try(&.to_i64?)

    # Find the selected note or use the first note (most recently updated)
    selected_note = if selected_note_id
                      notes.find { |note| note[0] == selected_note_id } || notes.first?
                    else
                      notes.first?
                    end

    content = ECR.render "views/index.ecr"
    ECR.render "views/layout.ecr"
  end

  # Healthcheck endpoint
  get "/healthz" do |env|
    env.response.content_type = "text/plain; charset=utf-8"
    "ok"
  end

  # Application info endpoint
  get "/api/info" do |env|
    note_count = Memo::DBX.db.query_one("select count(*) from notes", as: Int64)
    db_path = Memo::DBX.db_path
    env.response.content_type = "application/json; charset=utf-8"
    {version: Memo::VERSION, db_path: db_path, note_count: note_count, repository_url: Memo::REPOSITORY_URL}.to_json
  end

  # Application settings endpoint
  get "/api/settings" do |env|
    env.response.content_type = "application/json; charset=utf-8"
    {
      version: Memo::Settings::SETTINGS_VERSION,
      ui:      {
        editor_font_size_px:     Memo::Settings.editor_font_size_px,
        min_editor_font_size_px: Memo::Settings::MIN_EDITOR_FONT_SIZE_PX,
        max_editor_font_size_px: Memo::Settings::MAX_EDITOR_FONT_SIZE_PX,
      },
    }.to_json
  end

  post "/api/settings" do |env|
    raw = env.params.body["editor_font_size_px"]?.try(&.to_s)
    unless raw
      env.response.status_code = 400
      env.response.content_type = "application/json; charset=utf-8"
      next({status: "error", message: "missing editor_font_size_px"}.to_json)
    end

    value = raw.to_i?
    unless value
      env.response.status_code = 400
      env.response.content_type = "application/json; charset=utf-8"
      next({status: "error", message: "editor_font_size_px must be an integer"}.to_json)
    end

    begin
      Memo::Settings.update_editor_font_size_px(value)
      env.response.content_type = "application/json; charset=utf-8"
      {status: "success", ui: {editor_font_size_px: Memo::Settings.editor_font_size_px}}.to_json
    rescue ex
      env.response.status_code = 400
      env.response.content_type = "application/json; charset=utf-8"
      {status: "error", message: ex.message}.to_json
    end
  end

  # Minimal export endpoint (no auth, local desktop assumption)
  get "/export.json" do |env|
    rows = Memo::DBX.db.query_all <<-SQL, as: {Int64, String, String, String, String}
      select id, title, body, created_at, updated_at from notes order by updated_at desc
    SQL
    env.response.content_type = "application/json; charset=utf-8"
    rows.map { |id, title, body, created_at, updated_at|
      {id: id, title: title, body: body, created_at: created_at, updated_at: updated_at}
    }.to_json
  end

  get "/settings" do |_|
    content = ECR.render "views/settings.ecr"
    ECR.render "views/layout.ecr"
  end

  post "/notes" do |env|
    now = Memo::DBX.now_s
    Memo::DBX.db.exec "insert into notes(title, body, created_at, updated_at) values(?,?,?,?)",
      env.params.body["title"].to_s, env.params.body["body"].to_s, now, now
    env.redirect "/"
  end

  post "/notes/:id/update" do |env|
    started = Time.instant
    id = env.params.url["id"].to_i64
    raw_title = env.params.body["title"]?.try(&.to_s) || ""
    raw_body = env.params.body["body"]?.try(&.to_s) || ""

    # Log payload size first. Avoid logging full body; record its length only. Title preview limited to 200 chars.
    LOGGER.debug { "UPDATE begin id=#{id} title_len=#{raw_title.bytesize} body_len=#{raw_body.bytesize} title_preview=#{raw_title[0, 200].inspect}" }

    now = Memo::DBX.now_s
    begin
      affected = Memo::DBX.db.exec "update notes set title=?, body=?, updated_at=? where id=?",
        raw_title, raw_body, now, id
      duration_ms = (Time.instant - started).total_milliseconds.round(1)
      if affected == 0
        LOGGER.warn { "UPDATE noop id=#{id} (no matching row) elapsed_ms=#{duration_ms}" }
      else
        LOGGER.debug { "UPDATE ok id=#{id} affected=#{affected} elapsed_ms=#{duration_ms}" }
      end
      env.response.content_type = "application/json; charset=utf-8"
      {status: "success", id: id, updated_at: now}.to_json
    rescue ex
      duration_ms = (Time.instant - started).total_milliseconds.round(1)
      LOGGER.error(exception: ex) { "UPDATE failed id=#{id} elapsed_ms=#{duration_ms} message=#{ex.message}" }
      env.response.status_code = 400
      env.response.content_type = "application/json; charset=utf-8"
      {status: "error", message: ex.message}.to_json
    end
  end

  post "/notes/:id/delete" do |env|
    Memo::DBX.db.exec "delete from notes where id=?", env.params.url["id"].to_i64
    env.redirect "/"
  end
end
