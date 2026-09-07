# Lowdown Helper

Runwai embeds a versioned Lowdown CLI inside its app bundle. No separate install
or background daemon is needed by app users. The bridge is currently development
work: the public Lowdown 0.1.0 executable does not implement it.

## Prepare A Local Build

Current development pin:

- Source: `d894a3d643c106fb1b3fc4c95dc2eb4ac8e1e8b9`
- Target: `aarch64-apple-darwin` (Apple Silicon only)
- SHA-256: `d8bfaba3c26f027e05d5120ac3eeb5bbc9e745e11e2ca108b3a28a581a354294`

This candidate is not the public 0.1.0 release. Intel/universal packaging and
notarization remain release work.

Obtain a bridge-capable binary and its source commit and SHA-256 from the
independent Lowdown build. Do not substitute an arbitrary `lowdown` on PATH.

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
  missing Codex path to exercise cache, live arrivals, full text and fallback.
  Without an embedded helper, that test is skipped; unit tests still run.
- Oversized transcript records are skipped within bounded reads; recent readable
  updates stay available. Activity marks partial history without an error panel.
- Both progress and final answers use Lowdown's existing summary/cache pipeline.
- Shared deduplication requires the updated CLI; released older CLIs do not
  participate in the bridge's locking protocol.

Exceptionally large originals stream to private temporary text files and open
in the system reader. They are not silently clipped to fit the popup.
