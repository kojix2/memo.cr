# Memo

A local notes app built with [Crystal](https://crystal-lang.org),
[CrystKit](https://github.com/naqvis/crystkit), and SQLite.
Includes autosave, a resizable sidebar, JSON export, and adjustable font size.

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

Use `bin/memo --debug` for developer tools. `MEMO_DATABASE_URL` overrides the
notes database; the older `DATABASE_URL` is still accepted as a fallback.
Existing SQLite and `settings.json` formats remain compatible
when replacing or reinstalling the app.

## Checks

Requires Ameba and Node.js in addition to the build dependencies.

```sh
crystal tool format --check src spec
ameba src spec
crystal spec
node --test spec/*_test.js
```

See [GUI test instructions](spec/README.md) for browser and native WebView checks
using isolated test data.

## Packages

```sh
./build-mac.sh       # macOS app and DMG
./build-deb.sh       # Debian/Ubuntu (fpm)
./build-rpm.sh       # Fedora/openSUSE (fpm)
./build-flatpak.sh   # Flatpak (flatpak-builder)
bash build-mingw.sh  # Windows (MSYS2 UCRT64)
```

Run `package-win.ps1` after building to create a Windows installer.

See [SECURITY.md](SECURITY.md) for data protection and IPC details. Licensed under MIT.
