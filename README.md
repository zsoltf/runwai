# runwai

runwai keeps Codex usage and project updates in your macOS menu bar.

It answers three things fast:

- how fast am i burning through my allowance?
- how has that changed today and this week?
- what is my agent working on?

<img src="docs/assets/runwai-codex.png" alt="runwai daily burn-rate chart with example readings" width="420" />

## development build

- Codex auto-refreshes from your local login, including weekly-only limits
- chart-first Usage: Day, Full window, and 30-day Historical views
- Activity: one project's updates, powered by [Lowdown](https://github.com/zsoltf/lowdown)
- expandable originals and final answers; cached summaries appear without model waits

Charts track allowance, not raw token counts. Burn rate averages recorded intervals,
including breaks. History stays on your Mac; optional summaries use Codex usage.

## install

- download the latest zip from [GitHub Releases](https://github.com/zsoltf/runwai/releases)
- unzip it
- drag `runwai.app` into `/Applications`
- launch it

## local dev

Activity needs the pinned bridge-capable helper, not Lowdown 0.1.0.
See [helper setup](docs/ops/lowdown-helper.md). Usage builds without it in Debug.

```bash
xcodegen generate
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" build
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" test
open runwai.xcodeproj
```
