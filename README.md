# runwai

runwai is a macOS menu bar app for your Codex usage runway.

It answers three things fast:

- can i keep working today?
- when should i stop?
- how much runway is left this week?

<img src="docs/assets/runwai-codex.png" alt="runwai screenshot" width="420" />

## current build

- Codex auto-refreshes from your local login, including weekly-only limits
- daily pacing first, weekly runway second
- Activity view with a larger usage chart, time ranges, and hover readouts
- local-only data

Charts track your remaining allowance, not raw token counts.

## install

- download the latest zip from GitHub Releases
- unzip it
- drag `runwai.app` into `/Applications`
- launch it

## local dev

```bash
xcodegen generate
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" build
xcodebuild -project runwai.xcodeproj -scheme Runwai -destination "platform=macOS" test
open runwai.xcodeproj
```
