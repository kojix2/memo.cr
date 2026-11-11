#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/flatpak" <<'SH'
#!/usr/bin/env bash
case "$MEMO_TEST_RUNTIME" in
  missing) echo 'libexample.so => not found' ;;
  abi) echo "version 'GLIBC_9.9' not found" >&2; exit 1 ;;
  ready) echo 'libc.so.6 => /usr/lib/libc.so.6' ;;
esac
SH
chmod +x "$test_dir/flatpak"

for mode in missing abi; do
    if PATH="$test_dir:$PATH" MEMO_TEST_RUNTIME="$mode" bash "$repo_root/scripts/check-flatpak-runtime.sh" >"$test_dir/result" 2>&1; then
        echo "Accepted a broken Flatpak runtime: $mode" >&2
        exit 1
    fi
done
PATH="$test_dir:$PATH" MEMO_TEST_RUNTIME=ready bash "$repo_root/scripts/check-flatpak-runtime.sh"
echo "Flatpak runtime checks passed: missing libraries, incompatible ABI, and ready runtime"
