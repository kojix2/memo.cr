# Tests

Run commands from the repository root. On Linux, source `scripts/linux-env.sh`
first. All tests generate their own SQLite and settings files; they do not read
or copy personal notes.

See the [standard checks](../README.md#checks) for formatting, lint, and unit tests.
Release validation tests require Python 3.11+. On Windows, run
`pwsh -NoProfile -File spec/support/package_checks.ps1` to check packaging failures.
Windows CI also installs the generated package and checks `--version` on both EXEs.
`bash spec/support/flatpak_runtime_test.sh` checks runtime dependency rejection.

## Browser checks

Requires Node 22.13+ and Playwright. Install the browser before running the
network-blocked macOS test sandbox:

```sh
crystal build spec/support/browser_server.cr -o bin/memo-browser-server
npm install --prefix /tmp/memo-playwright --ignore-scripts playwright@1.58.2
/tmp/memo-playwright/node_modules/.bin/playwright install chromium
NODE_PATH=/tmp/memo-playwright/node_modules bash spec/support/browser_check.sh
```

The suite drives the bundled frontend through CrystKit's JS client and command
router. It checks editing, autosave and failure recovery, IME composition,
settings, export, deletion, sidebar resizing, narrow layouts, and persistence
after replacing the executable and reopening the same fixture in a new process.

Browser requests use pipes rather than an HTTP server. Each run uses a fresh
browser profile. On macOS, `gui-sandbox.sb` also blocks network access and the
normal `~/Library/Application Support/Memo` directory. Other platforms use
isolated fixtures without that OS sandbox.

Screenshots and `report.json` go to `dist/gui-check/`. Synthetic data directories
are retained under the OS temporary directory for diagnosis.

## Native WebView checks

Requires a graphical desktop session:

```sh
crystal run spec/support/native_smoke.cr
```

This covers the native WebView, menu dispatch, typed IPC, editing, settings,
export, and native close, including save failures. Both GUI suites use
deterministic responses at the native dialog boundary; they do not automate OS
dialog windows.
