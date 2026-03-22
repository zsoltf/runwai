#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/runwai.xcodeproj}"
PROJECT_SPEC_PATH="${PROJECT_SPEC_PATH:-$ROOT_DIR/project.yml}"
SCHEME_NAME="${SCHEME_NAME:-Runwai}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-runwai}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/$APP_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_ROOT/export}"
DIST_PATH="${DIST_PATH:-$BUILD_ROOT/dist}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS_PATH:-$BUILD_ROOT/ExportOptions.plist}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"
APP_STORE_CONNECT_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
SKIP_NOTARIZE=0
PREFLIGHT_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  scripts/release_macos.sh --preflight
  APPLE_TEAM_ID=TEAMID APPLE_NOTARY_PROFILE=PROFILE scripts/release_macos.sh

Options:
  --preflight      Only validate the local signing and notarization setup.
  --skip-notarize  Export a Developer ID app without submitting it for notarization.
  --help           Show this help.

Environment:
  APPLE_TEAM_ID                 Apple Developer team ID used for archive/export.
  APPLE_NOTARY_PROFILE          Keychain profile name created with:
                                xcrun notarytool store-credentials

Optional App Store Connect API key auth for xcodebuild:
  APP_STORE_CONNECT_KEY_PATH
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
EOF
}

note() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

append_missing() {
  local message="$1"
  MISSING_REQUIREMENTS+=("$message")
}

check_auth_key_inputs() {
  local any_key_input=0

  if [[ -n "$APP_STORE_CONNECT_KEY_PATH" || -n "$APP_STORE_CONNECT_KEY_ID" || -n "$APP_STORE_CONNECT_ISSUER_ID" ]]; then
    any_key_input=1
  fi

  if [[ "$any_key_input" -eq 0 ]]; then
    return
  fi

  [[ -n "$APP_STORE_CONNECT_KEY_PATH" ]] || append_missing "APP_STORE_CONNECT_KEY_PATH is required when using App Store Connect API key authentication."
  [[ -n "$APP_STORE_CONNECT_KEY_ID" ]] || append_missing "APP_STORE_CONNECT_KEY_ID is required when using App Store Connect API key authentication."
  [[ -n "$APP_STORE_CONNECT_ISSUER_ID" ]] || append_missing "APP_STORE_CONNECT_ISSUER_ID is required when using App Store Connect API key authentication."

  if [[ -n "$APP_STORE_CONNECT_KEY_PATH" && ! -f "$APP_STORE_CONNECT_KEY_PATH" ]]; then
    append_missing "App Store Connect key file not found: $APP_STORE_CONNECT_KEY_PATH"
  fi
}

preflight() {
  MISSING_REQUIREMENTS=()

  require_command security
  require_command xcodegen
  require_command xcodebuild
  require_command xcrun
  require_command ditto
  require_command codesign
  require_command spctl

  if [[ ! -f "$PROJECT_SPEC_PATH" ]]; then
    append_missing "Project spec not found: $PROJECT_SPEC_PATH"
  fi

  local identities
  identities="$(security find-identity -v -p codesigning || true)"
  note "Available code signing identities"
  printf '%s\n' "$identities"

  if ! grep -q "Developer ID Application" <<<"$identities"; then
    append_missing "No 'Developer ID Application' certificate found in the active keychains."
  fi

  [[ -n "$APPLE_TEAM_ID" ]] || append_missing "APPLE_TEAM_ID is not set."
  check_auth_key_inputs

  if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    if [[ -z "$APPLE_NOTARY_PROFILE" ]]; then
      append_missing "APPLE_NOTARY_PROFILE is not set."
    elif ! xcrun notarytool history --keychain-profile "$APPLE_NOTARY_PROFILE" >/dev/null 2>&1; then
      append_missing "Notary profile '$APPLE_NOTARY_PROFILE' is missing or cannot talk to Apple."
    fi
  fi

  if [[ "${#MISSING_REQUIREMENTS[@]}" -gt 0 ]]; then
    printf '\nMissing release prerequisites:\n' >&2
    printf '  - %s\n' "${MISSING_REQUIREMENTS[@]}" >&2
    return 1
  fi

  note "Preflight passed."
}

build_auth_args() {
  AUTH_ARGS=()

  if [[ -n "$APP_STORE_CONNECT_KEY_PATH" ]]; then
    AUTH_ARGS+=(
      -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
      -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
      -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
    )
  fi
}

write_export_options() {
  mkdir -p "$BUILD_ROOT"

  cat >"$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --preflight)
        PREFLIGHT_ONLY=1
        ;;
      --skip-notarize)
        SKIP_NOTARIZE=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

archive_app() {
  note "Generating Xcode project"
  (cd "$ROOT_DIR" && xcodegen generate)

  note "Archiving $APP_NAME"
  rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DIST_PATH"
  mkdir -p "$EXPORT_PATH" "$DIST_PATH"

  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    "${AUTH_ARGS[@]}" \
    -allowProvisioningUpdates
}

export_app() {
  note "Exporting Developer ID app"
  write_export_options

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    "${AUTH_ARGS[@]}" \
    -allowProvisioningUpdates
}

notarize_app() {
  local app_path="$EXPORT_PATH/$APP_NAME.app"
  local upload_zip="$DIST_PATH/$APP_NAME-notary-upload.zip"

  note "Preparing app archive for notarization"
  ditto -c -k --keepParent "$app_path" "$upload_zip"

  note "Submitting app to Apple notarization"
  xcrun notarytool submit "$upload_zip" \
    --keychain-profile "$APPLE_NOTARY_PROFILE" \
    --wait

  note "Stapling notarization ticket"
  xcrun stapler staple "$app_path"
}

verify_output() {
  local app_path="$EXPORT_PATH/$APP_NAME.app"
  local final_zip="$DIST_PATH/$APP_NAME-macos.zip"

  note "Verifying code signature"
  codesign --verify --deep --strict --verbose=2 "$app_path"

  note "Verifying Gatekeeper assessment"
  spctl --assess --type execute --verbose=4 "$app_path"

  note "Creating distributable zip"
  ditto -c -k --keepParent "$app_path" "$final_zip"

  note "Release artifact ready: $final_zip"
}

main() {
  parse_args "$@"
  build_auth_args

  if ! preflight; then
    exit 1
  fi

  if [[ "$PREFLIGHT_ONLY" -eq 1 ]]; then
    exit 0
  fi

  archive_app
  export_app

  if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    notarize_app
  else
    warn "Skipping notarization. Gatekeeper may still warn on other Macs."
  fi

  verify_output
}

main "$@"
