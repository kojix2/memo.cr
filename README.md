# Memo

A local notes app built with [Crystal](https://crystal-lang.org),
[CrystKit](https://github.com/naqvis/crystkit), and SQLite.
Supports autosave, JSON export, and adjustable editor font size.
Existing notes and settings remain compatible.

## Build and run

Requires Crystal 1.21+, Shards, SQLite 3, and
[CrystKit's platform dependencies](https://github.com/naqvis/crystkit/blob/main/guides/getting-started.md).

```sh
shards install --frozen
# On Linux: source scripts/linux-env.sh
shards build --release
bin/memo
```

Use `--debug` for developer tools, **Cmd/Ctrl+N** for a new note,
and **Cmd/Ctrl+S** to save. `MEMO_DATABASE_URL` overrides the database location.

## Packages

```sh
./build-mac.sh       # macOS app and DMG
./build-deb.sh       # Debian/Ubuntu (fpm)
./build-rpm.sh       # Fedora/openSUSE (fpm)
./build-flatpak.sh   # Flatpak (flatpak-builder)
bash build-mingw.sh  # Windows (MSYS2 UCRT64)
```

Run `package-win.ps1` after building to create a Windows installer.

## Tests

```sh
crystal spec
node --test spec/*_test.js
```

On Linux, source `scripts/linux-env.sh` first. With a graphical session,
`crystal run spec/support/native_smoke.cr` also tests the native UI.

## CrystKit integration

Memo uses CrystKit's typed IPC and reactive state for notes and settings,
native menus and their keyboard accelerators, file and confirmation dialogs,
scoped filesystem access for exports, application-data directories, CLI parsing,
and window/application lifecycle events. **Cmd/Ctrl+,** opens settings.

The sidebar splitter remains a DOM control because CrystKit does not provide
an in-page splitter. It supports dragging without pointer capture, keyboard
adjustment, and saved widths. The editor's save queue remains application logic
so navigation and close wait for every edit to reach SQLite.

Settings are read and written through CrystKit's scoped FileSystem feature.
The existing `settings.json` path, version 1 JSON format, and SQLite schema are
unchanged, so reinstalling the app keeps existing notes and preferences usable.
Invalid JSON falls back to defaults; filesystem failures reach the UI. The old
custom backup, temporary-file, and quarantine implementation has been removed.
The packaging scripts also retain dependency bundling and platform-specific
runtime dependency lists that CrystKit's current builder does not supply.

See [SECURITY.md](SECURITY.md) for security details. Licensed under MIT.
