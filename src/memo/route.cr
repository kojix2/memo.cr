# src/routes.cr
require "kemal"
require "html"
require "./db"

module Memo
  Memo::DBX.setup

  private def self.h(s) : String
    HTML.escape(s.to_s)
  end

  get "/" do |env|
    notes = Memo::DBX.db.query_all <<-SQL, as: {Int64, String, String, String, String}
      select id, title, body, created_at, updated_at
      from notes order by updated_at desc
    SQL

    env.response.content_type = "text/html; charset=utf-8"
    <<-HTML
    <h1>Memo</h1>
    <form method="post" action="/notes" style="margin-bottom:1rem">
      <input name="title" placeholder="title">
      <br><textarea name="body" rows="4" placeholder="body"></textarea><br>
      <button>Add</button>
    </form>
    <hr>
    #{notes.map { |id, t, b, c, u|
        %(
        <form method="post" action="/notes/#{id}/update">
          <input name="title" value="#{h(t)}">
          <br><textarea name="body" rows="4">#{h(b)}</textarea><br>
          <small>updated: #{h(u)} / created: #{h(c)}</small>
          <button>Save</button>
        </form>
        <form method="post" action="/notes/#{id}/delete" onsubmit="return confirm('Delete?')">
          <button>Delete</button>
        </form>
        <hr>
      )
      }.join}
    HTML
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
    env.redirect "/"
  end

  post "/notes/:id/delete" do |env|
    Memo::DBX.db.exec "delete from notes where id=?", env.params.url["id"].to_i64
    env.redirect "/"
  end
end
