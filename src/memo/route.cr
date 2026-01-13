# src/routes.cr
require "kemal"
require "html"
require "ecr"
require "./db"

module Memo
  Memo::DBX.setup

  # Use the project-wide logger defined in Memo::Log (app.cr)
  LOGGER = Memo::Log

  # Per-request lightweight timing (only active when debug logging is enabled)
  before_all do |env|
    if LOGGER.level <= ::Log::Severity::Debug
      # Store monotonic timestamp as Int64 nanoseconds (allowed StoreTypes)
      env.set "__memo_req_start_ns", Time.monotonic.total_nanoseconds
      env.set "__memo_req_id", Random::Secure.hex(4)
      rid = (env.get("__memo_req_id") rescue nil)
      LOGGER.debug { "request begin id=#{rid} #{env.request.method} #{env.request.path}" }
    end
  end

  after_all do |env|
    if LOGGER.level <= ::Log::Severity::Debug
      start_ns = (env.get("__memo_req_start_ns") rescue nil)
      rid = (env.get("__memo_req_id") rescue nil)
      if start_ns.is_a?(Int64)
        now_ns = Time.monotonic.total_nanoseconds
        dur_ms = ((now_ns - start_ns) / 1_000_000.0).round(1)
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
    started = Time.monotonic
    id = env.params.url["id"].to_i64
    raw_title = env.params.body["title"]?.try(&.to_s) || ""
    raw_body = env.params.body["body"]?.try(&.to_s) || ""

    # Log payload size first. Avoid logging full body; record its length only. Title preview limited to 200 chars.
    LOGGER.debug { "UPDATE begin id=#{id} title_len=#{raw_title.bytesize} body_len=#{raw_body.bytesize} title_preview=#{raw_title[0, 200].inspect}" }

    now = Memo::DBX.now_s
    begin
      affected = Memo::DBX.db.exec "update notes set title=?, body=?, updated_at=? where id=?",
        raw_title, raw_body, now, id
      duration_ms = ((Time.monotonic - started).total_milliseconds).round(1)
      if affected == 0
        LOGGER.warn { "UPDATE noop id=#{id} (no matching row) elapsed_ms=#{duration_ms}" }
      else
        LOGGER.debug { "UPDATE ok id=#{id} affected=#{affected} elapsed_ms=#{duration_ms}" }
      end
      env.response.content_type = "application/json; charset=utf-8"
      {status: "success", id: id, updated_at: now}.to_json
    rescue ex
      duration_ms = ((Time.monotonic - started).total_milliseconds).round(1)
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
