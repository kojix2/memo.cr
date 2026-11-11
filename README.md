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

See [SECURITY.md](SECURITY.md) for security details. Licensed under MIT.
