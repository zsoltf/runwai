# runwai MVP Spec

Date: 2026-03-19
Status: Historical MVP spec, later expanded beyond the first codex-only scaffold

Note: this document describes the original codex-first MVP framing. The current app has since grown into `runwai`, a multi-provider pacing tool for codex, codex spark, and gemini. For the current release/distribution path, see `docs/ops/macos-release.md`.


## Problem

Codex usage on a ChatGPT Pro subscription is easy to burn through and awkward to pace manually. The user keeps checking the weekly usage limit, estimating how many days remain, and dividing the remaining budget by the time left.

The product goal is not "usage analytics" in the enterprise sense. The goal is a small personal tool that turns a fuzzy weekly cap into a clear daily budget.

## Product direction

- Primary surface: macOS menu bar app
- Secondary surface: widget later, only after the menu bar app is solid
- MVP data source: manual entry
- Future experimental data source: private subscription sync, clearly marked unsupported

## Target user

- Individual ChatGPT Pro subscriber
- Heavy Codex user
- Wants a fast glance, not a dashboard safari

## MVP outcomes

The user should be able to answer these questions in under 3 seconds:

1. How much of my weekly Codex budget is left?
2. When does the current window reset?
3. How much can I safely use per day from here?
4. Am I ahead of pace, on pace, or behind pace?

## MVP scope

### In

- Menu bar app with a popover
- Manual entry of:
  - total weekly budget
  - used amount
  - reset date and time
- Automatic pacing calculations
- Local persistence
- Settings window
- A clear future seam for `manual` vs `experimental sync`

### Out

- Real private endpoint sync
- Widget target
- Notifications
- Historical charts
- Multi-account support
- Signing, notarization, release automation

## Information architecture

### Menu bar label

- Default: short remaining signal, for example `65%`
- Semantic meaning: percentage remaining in the current weekly window
- Color is not relied on in the menu bar label itself

### Menu bar popover

Sections, top to bottom:

1. Header
   - product name
   - source mode badge: `Manual`
   - last updated timestamp

2. Primary budget block
   - remaining percentage
   - remaining units vs total units
   - progress bar / gauge

3. Time block
   - reset date/time
   - relative time remaining
   - days remaining

4. Pacing block
   - safe units per day
   - safe percent per day
   - pace status: `Ahead`, `On pace`, `Behind`, or `Exhausted`

5. Actions
   - `Settings`
   - `Refresh`
   - `Quit`

### Settings window

Sections:

1. Weekly Budget
   - total weekly units
   - used units
   - reset date/time

2. Source Strategy
   - current mode: `Manual`
   - note that experimental private sync is planned, not active

3. Preview
   - mirrors the most important current pacing values

## UI sketch

```text
+--------------------------------------+
| runwai                 Manual        |
| Last updated: 9:58 AM                |
|                                      |
| 65% left                             |
| 65 / 100 units remaining             |
| [#############-------]               |
|                                      |
| Resets Tue Mar 24, 2:00 PM           |
| 4d 7h remaining                      |
|                                      |
| Safe to use: 15.9 units/day          |
| Safe to use: 15.9% / day             |
| Status: Ahead of pace                |
|                                      |
| Settings   Refresh   Quit            |
+--------------------------------------+
```

## Data model

### Manual usage snapshot

- `weeklyBudgetUnits: Double`
- `usedUnits: Double`
- `resetAt: Date`
- `lastUpdatedAt: Date`

### Source mode

- `manual`
- `experimentalPrivateSync`

Only `manual` is active in the MVP scaffold.

This document reflects the original single-provider MVP. The current app has expanded into a multi-provider menu bar utility for codex, codex spark, and gemini while keeping the same local-first pacing model.

## Pacing math

Assume a 7-day window ending at `resetAt`.

- `windowDuration = 7 days`
- `windowStart = resetAt - windowDuration`
- `remainingUnits = max(weeklyBudgetUnits - usedUnits, 0)`
- `usedFraction = clamp(usedUnits / weeklyBudgetUnits, 0...1)`
- `remainingFraction = 1 - usedFraction`
- `timeRemaining = max(resetAt - now, 0)`
- `daysRemaining = timeRemaining / 86400`
- `safeUnitsPerDay = remainingUnits / max(daysRemaining, 1 / 24)`
- `safePercentPerDay = (remainingFraction * 100) / max(daysRemaining, 1 / 24)`

### Pace status

Expected usage by now:

- `elapsedFraction = clamp((now - windowStart) / windowDuration, 0...1)`
- `expectedUsedUnits = weeklyBudgetUnits * elapsedFraction`
- `delta = usedUnits - expectedUsedUnits`

Status:

- `Exhausted` if `remainingUnits == 0`
- `Ahead` if `delta < -tolerance`
- `Behind` if `delta > tolerance`
- `On pace` otherwise

Default tolerance:

- `tolerance = max(weeklyBudgetUnits * 0.03, 1)`

## Persistence

- Store manual snapshot locally with UserDefaults-backed JSON
- Do not store credentials in the MVP

## Technical direction

- Swift 6.2
- SwiftUI app lifecycle
- `MenuBarExtra` for the primary surface
- `Settings` scene for configuration
- Observation-based app model
- XcodeGen to generate the project from a repo-owned `project.yml`

## Future phases

### Phase 2: experimental sync

- Add a data source protocol
- Implement an unsupported private-sync adapter separately
- Make staleness and failure obvious in the UI
- Never silently pretend sync is working if it is not

### Phase 3: widget

- Add a widget extension that mirrors the latest persisted snapshot
- Keep the menu bar app as the state owner
- Avoid auth and networking in the widget layer

## MVP success criteria

- App builds and runs locally
- User can change the weekly budget, used units, and reset time
- Menu bar popover immediately reflects updated pacing values
- The app feels faster and easier than doing the math by hand
