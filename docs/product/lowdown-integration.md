# Chart-first Usage and Lowdown Activity

## Outcome

One menu-bar app, two independent views. Usage opens on the daily chart, with
Full window and Historical ranges. Burn rate is the primary metric. The old
overview and borrowed-days presentation are retired. Activity follows one
project/session through Lowdown, with cached summaries first and full originals
and final answers on expansion. Keep the existing 420-point popup, native
light/dark styling, keyboard access, and a single outer surface.

## Ownership

- Runwai owns native presentation, remembered project/session selection, and
  helper lifecycle. Existing usage sync remains independent.
- Lowdown remains an independent Rust CLI. It owns discovery, rollout parsing,
  tail reads, model calls, persistent summaries, and concurrent cache access.
- A pinned bundled executable speaks versioned NDJSON over dedicated pipes.
  No daemon, HTTP server, Swift transcript parser, or full-digest polling.
- The released Lowdown CLI has no live JSON bridge. A bridge-capable candidate
  must be built and verified before integration is considered functional.
- Shared-cache deduplication requires a matching bridge-aware CLI; older CLI
  versions do not participate in the new locking protocol.

## Implementation Sequence

1. Make Usage chart-first, keep 30 days of existing/new observations, and break
   chart lines at known quota resets. Never fabricate old readings or burn rates.
2. Agree on Lowdown's versioned protocol and extract the shared Rust engine.
   Its owning task makes all Rust changes; Runwai consumes the documented API.
3. Add an off-main-thread Swift transport, typed events, bounded buffers,
   selection generations, cancellation, and a separate Activity model.
4. Add recent projects, Choose Folder, session selection, cached-first feed,
   original/final readers, and visible fallback states. Package a pinned helper.
5. Exercise the actual app, update the README screenshot, then commit locally.
   Publishing and release changes require separate user confirmation.

## Acceptance

- Day is the default; all three ranges work. History survives new windows and
  imported snapshots. Plateau endpoints remain intact. Weekly-only sync works.
- Cached startup and project switching paint without waiting for a model.
  Slow summaries cannot block tab switching, scrolling, or cancellation.
- Activity's project dropdown lists the 10 most recently active projects plus
  Choose Folder. Each popup opening selects the newest project when Activity
  is shown; Usage alone does not start model work. Manual selection stays put
  until the popup closes, and per-project session choices remain remembered.
- New arrivals and new sessions appear without restarting. Old-generation
  events never replace the selected project's content.
- Full originals and final answers are readable, including large messages.
  Summary failure preserves original text and cached summaries.
- Final answers use the same summary/cache path as progress messages. Cards
  distinguish a summary from an original preview. Native Markdown renders
  headings, lists, quotes, code, emphasis, and links without remote images or HTML.
- Oversized source records do not make an entire project unavailable. Lowdown
  keeps bounded reads and returns recent readable messages with partial coverage;
  Runwai shows that quietly, never pretending skipped records were read.
- Missing Usage rates remain unknown, not zero. The view shows a collecting-data
  state rather than placeholder numbers while preserving available readings.
- Missing Codex, malformed output, helper restart, and slow output consumers
  are handled without interrupting Usage or leaving orphan processes.
- Routine validation uses offline fixtures. Live model work is a separate,
  bounded check. UI claims require real app observation, not only screenshots.
- A signed release must sign and verify the nested helper before notarization.

Historical data cannot recover readings discarded by previous versions.
Agent updates are reported transcript content, not proof of agent liveness or
successful execution. Model summaries are optional and consume Codex usage.
