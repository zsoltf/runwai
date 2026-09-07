# Lowdown Helper

Runwai embeds a versioned Lowdown CLI inside its app bundle. No separate install
or background daemon is needed by app users. The bridge is currently development
work: the public Lowdown 0.1.0 executable does not implement it.

## Prepare A Local Build

Current development pin:

- Source: `484411ef6f6f890c3a0dfb6330ae2d2643b89c0b`
- Target: `universal-apple-darwin` (`arm64` and `x86_64`)
- SHA-256: `948992ade3cea7fe2b9db080f144a765312233338f34788bb0edd3f90b8cbc1f`

This candidate is not the public 0.1.0 release. App release validation, signing
and notarization remain separate work.

Obtain a bridge-capable binary and its source commit and SHA-256 from the
independent Lowdown build. Do not substitute an arbitrary `lowdown` on PATH.
Lowdown owns the local build script `scripts/build-macos-bridge.sh`. From its
clean checkout at the source commit above, run `bash scripts/build-macos-bridge.sh`
with both Rust macOS targets and Xcode command-line tools available. It builds
offline from `Cargo.lock` and creates
`target/runwai-bridge/<source-commit>/universal-apple-darwin/lowdown`, refusing to
overwrite an existing pin. Use the supplied artifact hash above for this
candidate; architecture membership alone does not prove either slice runs.

```bash
scripts/prepare_lowdown.sh /absolute/path/to/lowdown EXPECTED_SHA256 SOURCE_COMMIT
xcodegen generate
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" build
```

Preparation checks the supplied hash and writes the helper plus manifest under
ignored `build/lowdown/`. Xcode checks the hash again and embeds both in
`Contents/Resources/Lowdown`. Debug without a helper shows an unavailable state;
Release requires it. For a universal release, prepare a universal helper, not
an architecture-specific binary.

The helper is signed with the app's build identity before outer app signing.
Verify both signatures and architectures, then notarize and staple the final app
using the normal [release process](macos-release.md). Include Lowdown's bundled
license and review dependency notices before distribution. Never modify a helper
inside an already notarized app.

## Runtime

- Stdout is versioned NDJSON; diagnostics are drained without transcript logging.
- Rust owns transcripts, discovery, summaries, and its shared cache.
- Runwai owns selected projects/sessions, presentation, and helper lifecycle.
- Model summaries can be disabled in Settings. Missing Codex preserves originals
  and cached summaries. No extra provider credentials are stored by Runwai.
- Development checks set `LOWDOWN_SUMMARY_PROVIDER=fallback` and use isolated
  fixture data. Keep live model smoke tests separate and bounded.
- `LowdownIntegrationTests` uses the embedded executable and an explicitly
  missing Codex path to exercise cache, live arrivals, full text, paging and
  fallback. Fixtures require canonical final/completion echoes to share one
  message identity while equal-text finals in distinct turns remain separate.
  Without an embedded helper, these tests are skipped; unit tests still run.
- Oversized transcript records are skipped within bounded reads; recent readable
  updates stay available. Activity marks partial history without an error panel.
- Both progress and final answers use Lowdown's existing summary/cache pipeline.
- Shared deduplication requires the updated CLI; released older CLIs do not
  participate in the bridge's locking protocol.

Exceptionally large originals stream to private temporary text files and open
in the system reader. They are not silently clipped to fit the popup.
