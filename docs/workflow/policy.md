# Workflow Policy

This document captures the durable workflow rules for a bootstrapped repository.

## Core principles
- Solve the real problem with the lightest process that preserves trust.
- Prefer action over ceremony, but never overclaim.
- Separate planning, execution, and verification.
- Keep artifacts only when they materially improve resumability, reviewability, or safety.

## Honesty and verification
- Never claim commands ran, tests passed, files were reviewed, or facts were verified unless that actually happened.
- Distinguish clearly between `changed`, `inspected`, `executed`, `tested`, and `verified`.
- If verification is partial, say so explicitly.

## Queueing and focus
- Queue new ideas during active work instead of switching context immediately.
- Prefer serialized edits within one repo unless the workflow explicitly supports safe parallel lanes.

## Turn ownership
- Treat turn ownership as a narrow safeguard, not a default ritual.
- Use it for long-running, multi-agent, automation-driven, or shared-state workflow work.
- Use it when background work, helpers, or resumable state could keep mutating repo state after the user's intent may have changed.
- Skip it for ordinary interactive coding, docs edits, commits, and sync-only follow-through unless a repo-specific workflow explicitly requires it.

## Escalation
- Escalate to a stronger research or review step after two materially different failed implementation attempts.
- Escalate when scope expands materially, architecture risk changes, or verification reveals a design problem instead of a local bug.

## Refactors
- Multi-hour refactors are allowed only when there is written scope, invariants, validation, and rollback or containment notes.
