"""Seed an isolated Memo database for the README screenshots."""

import os
from pathlib import Path
import sqlite3
from tempfile import mkdtemp
from urllib.parse import quote_plus


NOTES = [
    (26, "10/26（月） 週明け", """朝は冷えた。温かいお茶を買って出社。

午前は会議。先週から残っていた見積もりを直して、昼前に送った。
昼は同僚と近くの定食屋。いつもの焼き魚定食。

午後は問い合わせを２件返して、明日の打ち合わせ資料をまとめた。
帰りにスーパーで牛乳と卵を買った。夕飯は昨日のカレーの残り。

明日やること
・朝いちで打ち合わせ資料を共有する
・帰りにクリーニングを受け取る"""),
    (23, "10/23（金） 今週の片づけ", "週報を出して、来週の予定をカレンダーに入れた。帰りに駅前でパンを買う。"),
    (22, "10/22（木） 在宅勤務", "午前中に資料の確認が終わった。昼は残りごはんでチャーハン。仕事のあと洗濯。"),
    (21, "10/21（水） 雨", "朝の電車が少し遅れた。午後の打ち合わせは予定より早く終わった。靴を乾かしておく。"),
    (20, "10/20（火） 月末の準備", "交通費を精算。領収書が１枚見つからなかったけど、かばんの内ポケットに入っていた。"),
    (19, "10/19（月） 午後は外出", "午後は取引先。予定より早く戻れたので、帰る前にメールの返信を済ませた。"),
]


def main():
    path = Path(mkdtemp(prefix="memo-screenshot-", dir=os.environ["RUNNER_TEMP"])) / "memo.db"
    with sqlite3.connect(path) as db:
        db.execute("""CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )""")
        # Memo opens the most recently updated note first.
        for day, title, body in NOTES:
            stamp = f"2026-10-{day:02} 21:00:00.000"
            db.execute("INSERT INTO notes (title, body, created_at, updated_at) VALUES (?, ?, ?, ?)",
                       (title, body, stamp, stamp))
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as target:
        target.write(f"MEMO_DATABASE_URL=sqlite3:{quote_plus(str(path))}\n")


if __name__ == "__main__":
    main()
