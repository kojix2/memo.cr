#!/usr/bin/env bash
set -euo pipefail

if ! report="$(flatpak build --runtime "${1:-build-dir}" ldd /app/bin/memo 2>&1)"; then
    printf '%s\n' "$report" >&2
    exit 1
fi
if [[ "$report" == *"not found"* ]]; then
    printf '%s\n' "$report" >&2
    echo "Flatpak runtime dependencies are missing; rebuild against the SDK or bundle the missing libraries." >&2
    exit 1
fi
