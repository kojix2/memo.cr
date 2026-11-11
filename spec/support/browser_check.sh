#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" == Darwin ]]; then
  exec sandbox-exec -D "MEMO_PRIVATE_DATA=$HOME/Library/Application Support/Memo" \
    -f spec/support/gui-sandbox.sb node spec/support/browser_check.cjs
else
  exec node spec/support/browser_check.cjs
fi
