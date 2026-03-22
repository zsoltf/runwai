# Oracle Advisory

Oracle is an optional advisory lane for extra judgment, research, or second-opinion review. It is not a default workflow gate.

## When to use it
- You want a plan critique before implementation.
- You are stuck after local attempts and want a stronger outside review.
- You need latest-tooling or architecture research that benefits from a large-context model.
- You want a final "did we solve the right problem?" check on a sensitive change.

## When not to use it
- Routine local edits.
- Tasks that already have enough local context and low risk.
- As a mandatory gate for ordinary work.
- As a substitute for local verification.

## Recommended model split
- GPT Pro: browser-backed Oracle on an advisor VM or another dedicated signed-in browser host.
- Gemini: API-backed advisory path first when available.
- Gemini browser fallback: optional for advisory work only when API auth is unavailable or a browser session is preferred.

## Operating rules
- Treat Oracle output as advisory, not authoritative.
- Keep the shared file bundle tight and relevant.
- Prefer resume or reattach over rerunning long advisory sessions.
- Do not store raw transcripts as the repo source of truth.
- Summarize adopted conclusions locally.

## Local artifact shape
- When Oracle materially changes the plan or implementation direction, save a short brief under `.agent/reviews/<plan-base>__oracle-brief.md`.
- Keep the brief compact:
  - question asked
  - context sent
  - key findings
  - adopted decisions
  - unresolved risks
