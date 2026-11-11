# Memo

[![Build and release](https://github.com/kojix2/memo.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/kojix2/memo.cr/actions/workflows/ci.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fmemo.cr%2Flines)](https://tokei.kojix2.net/github/kojix2/memo.cr)

A local notes app built with [Crystal](https://crystal-lang.org),
[CrystKit](https://github.com/naqvis/crystkit), and SQLite.
Includes autosave, title and body search, a resizable sidebar, JSON export, and adjustable font size.

## Build and run

Requires Crystal 1.21+, Shards, SQLite 3, and
[CrystKit's platform dependencies](https://github.com/naqvis/crystkit/blob/main/guides/getting-started.md).

```sh
shards install --frozen
# Linux: source scripts/linux-env.sh
shards build --release
bin/memo
```

| Shortcut | Action |
| --- | --- |
| Cmd/Ctrl+N | New note |
| Cmd/Ctrl+S | Save |
| Cmd/Ctrl+, | Settings |

Use the sidebar search to filter titles and full note bodies by a case-insensitive
substring. Clear the search field or press Escape in it to show all notes.
Searching keeps the current editor open and includes unsaved edits.

Use `bin/memo --debug` for developer tools. `MEMO_DATABASE_URL` overrides the
notes database; the older `DATABASE_URL` is still accepted as a fallback.
Existing SQLite and `settings.json` formats remain compatible
when replacing or reinstalling the app.

## Checks

Requires Ameba, Node.js, and Python 3.11+ in addition to the build dependencies.

```sh
crystal tool format --check src spec
ameba src spec
crystal spec
node --test spec/*_test.js
python3 -m unittest discover -s spec/support -p '*_test.py'
```

See [GUI test instructions](spec/README.md) for browser and native WebView checks
using isolated test data.

## Packages

```sh
./build-mac.sh       # macOS app and DMG
./build-deb.sh       # Debian/Ubuntu (dpkg-dev)
./build-rpm.sh       # Fedora/openSUSE (fpm)
./build-flatpak.sh   # Optional Flatpak (flatpak-builder; runtime checks required)
bash build-mingw.sh  # Windows (MSYS2 UCRT64)
```

Run `package-win.ps1` after building to create a Windows installer.
The installer provisions WebView2 Runtime if missing (internet required).
The standalone Windows EXE requires the
[WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) to be installed separately.

CI uses stable Crystal, Node.js LTS, and the current WebView2 SDK.
`shard.lock` records the resolved application dependencies; update it with `shards update`.

CI builds macOS, Debian (on Ubuntu 26.04), and Windows packages together. A `vX.Y.Z` tag must
match `shard.yml` and AppStream metadata. Only after every build and package
check succeeds are the files and `SHA256SUMS` uploaded to a draft and published.

See [SECURITY.md](SECURITY.md) for data protection and IPC details. Licensed under MIT.
