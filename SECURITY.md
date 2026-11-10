# Security

Memo uses CrystKit's native WebView and typed in-process IPC. It does not start
an HTTP server, listen on a local port, or spawn a server subprocess.

## Frontend boundary

The bundled frontend can call only registered commands. Memo registers note
CRUD, settings, application information, export, and lifecycle commands. Each
requires the `memo:access` capability. Payloads are decoded into Crystal types;
SQL parameters are bound by the backend. There is no generic SQL, filesystem,
shell, network, or window-creation plugin exposed to JavaScript.

CrystKit mirrors committed notes through reactive state. Attaching to that
state requires the same `memo:access` capability as note commands.

Export opens a native save dialog in the backend, which requires `dialog:save`.
Only the path returned by that dialog is written. JavaScript cannot submit an
arbitrary export destination.

The executable embeds its frontend assets. Notes and error messages are rendered
with `textContent` or input values, rather than HTML interpolation. A Content
Security Policy disables network connections, external scripts, frames, objects,
forms, and base URLs. Inline scripts/styles are allowed for the embedded assets.
The UI does not render note text as HTML or turn it into navigation links.

CrystKit owns the native bridge and its lifecycle. The registered app commands
are trusted frontend authority: if arbitrary JavaScript were to execute in the
app's WebView, it could invoke those commands. Keep user data out of HTML and
script interpolation. The capability grant does not distinguish trusted scripts
from injected scripts in the same window.

## Persistence and shutdown

SQLite notes and JSON exports are plaintext. Protection against other users,
malware, or stolen disks relies on operating-system permissions and disk
protection. Memo does not provide encryption or multi-user authentication.

Save requests are serialized. Editing while a save is in flight leaves a newer
revision pending, and switching notes waits for all revisions to be saved.
Native close and application quit requests ask the frontend to flush its buffer
before exiting. A save failure leaves the window open for retry. Forced process
termination, operating-system shutdown, or power loss can still lose edits that
have not reached SQLite.

Runtime `MEMO_DATABASE_URL` takes precedence over the legacy compile-time
value. Do not set it when compiling public packages unless embedding that
configuration is intentional. Database URLs and note contents are not logged by
Memo.

## Dependencies

The CrystKit revision is fixed in `shard.yml`; `shard.lock` records the resolved
versions and commits. Use `shards install --frozen` for reproducible dependency
resolution. Native WebView security updates come from the operating system
(WebKit/WebKitGTK) or the installed WebView2 Runtime.

## Reporting

Please report security issues privately to the repository maintainer instead of
publishing notes, database files, or exploitable details in a public issue.
