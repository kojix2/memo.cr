# src/routes.cr
require "kemal"
require "html"
require "ecr"
require "./db"

module Memo
  Memo::DBX.setup

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
    id = env.params.url["id"].to_i64
    now = Memo::DBX.now_s
    Memo::DBX.db.exec "update notes set title=?, body=?, updated_at=? where id=?",
      env.params.body["title"].to_s, env.params.body["body"].to_s, now, id
    env.response.content_type = "application/json; charset=utf-8"
    {status: "success", id: id, updated_at: now}.to_json
  rescue ex
    env.response.status_code = 400
    env.response.content_type = "application/json; charset=utf-8"
    {status: "error", message: ex.message}.to_json
  end

  post "/notes/:id/delete" do |env|
    Memo::DBX.db.exec "delete from notes where id=?", env.params.url["id"].to_i64
    env.redirect "/"
  end
end
