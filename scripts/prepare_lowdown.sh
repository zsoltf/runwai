#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 3 ]]; then
  printf '%s\n' 'Usage: scripts/prepare_lowdown.sh /absolute/path/to/lowdown SHA256 SOURCE_COMMIT' >&2
  exit 1
fi
binary="$1"
expected="$2"
revision="$3"
[[ "$binary" == /* && -x "$binary" ]] || { printf '%s\n' 'Executable must be an absolute path.' >&2; exit 1; }
[[ "$expected" =~ ^[a-f0-9]{64}$ && "$revision" =~ ^[a-f0-9]{40}$ ]] || { printf '%s\n' 'Expected SHA-256 and source commit are required.' >&2; exit 1; }
actual="$(/usr/bin/shasum -a 256 "$binary")"
[[ "${actual%% *}" == "$expected" ]] || { printf '%s\n' 'Checksum mismatch.' >&2; exit 1; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$root/build/lowdown"
mkdir -p "$destination"
/usr/bin/ditto "$binary" "$destination/lowdown"
printf '{"protocol":1,"source_revision":"%s","sha256":"%s"}\n' "$revision" "$expected" > "$destination/manifest.json"
printf 'Prepared helper: %s\n' "$destination/lowdown"
