# Security

## Data and saving

Notes, settings, and JSON exports are plaintext. Their protection depends on OS
permissions and disk encryption. Memo does not encrypt data or authenticate users.

The editor serializes saves and flushes pending edits before switching notes or
closing. Save failures keep the window open for retry. Forced termination or
power loss can still lose edits that have not reached SQLite.

Settings use CrystKit's scoped FileSystem API and retain the existing
`settings.json` format. Runtime `MEMO_DATABASE_URL` takes priority over legacy
`DATABASE_URL`, then the compile-time `MEMO_DATABASE_URL` value. Leave
`MEMO_DATABASE_URL` unset when compiling public packages.
Memo does not log note contents or database URLs.

## Frontend boundary

The app embeds its frontend and uses CrystKit's native WebView and typed IPC,
without a local HTTP server. Registered commands and reactive-state attachment
require `memo:access`; SQL values use bound parameters. Generic SQL, filesystem,
shell, network, and window-creation commands are not exposed to JavaScript.

Export requires a native save dialog (`dialog:save`) and scoped filesystem
access (`fs:write`) to its selected path. JavaScript cannot supply a destination.

Notes and errors are rendered as text or input values. The Content Security
Policy blocks network access, external scripts, frames, objects, and form
submission; embedded scripts and styles are allowed. Arbitrary JavaScript
running in the WebView could still invoke the registered commands, so user data
must stay out of HTML and script interpolation.

## Dependencies and reporting

CrystKit is pinned in `shard.yml`; `shard.lock` records resolved dependencies.
Use `shards install --frozen`. WebView security updates come from the OS or the
installed WebView2 Runtime.

Report vulnerabilities privately to the maintainer. Do not publish personal
notes, databases, or exploit details in public issues.
