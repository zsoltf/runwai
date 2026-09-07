#!/usr/bin/env bash
set -euo pipefail

# Local preparation installs a verified helper under build/lowdown. Xcode embeds
# that pinned copy; it never downloads or executes an arbitrary PATH binary.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="$root/build/lowdown/lowdown"
manifest="$root/build/lowdown/manifest.json"
destination="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/Lowdown"

if [[ ! -f "$binary" || ! -f "$manifest" ]]; then
  if [[ "${CONFIGURATION:-Debug}" == Release ]]; then
    printf '%s\n' 'error: Prepare the pinned Lowdown helper before a Release build.' >&2
    exit 1
  fi
  printf '%s\n' 'warning: Lowdown is not bundled; Activity will show an unavailable state.' >&2
  exit 0
fi

expected="$(/usr/bin/plutil -extract sha256 raw "$manifest")"
actual="$(/usr/bin/shasum -a 256 "$binary")"
[[ "${actual%% *}" == "$expected" ]] || { printf '%s\n' 'error: Lowdown checksum mismatch.' >&2; exit 1; }
for architecture in ${ARCHS:-$(uname -m)}; do
  /usr/bin/lipo "$binary" -verify_arch "$architecture" || {
    printf 'error: Lowdown does not contain required architecture %s.\n' "$architecture" >&2
    exit 1
  }
done
mkdir -p "$destination"
/usr/bin/ditto "$binary" "$destination/lowdown"
/usr/bin/ditto "$manifest" "$destination/manifest.json"
/bin/chmod 755 "$destination/lowdown"

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == YES && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$destination/lowdown"
fi
