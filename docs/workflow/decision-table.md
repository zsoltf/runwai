# Workflow Decision Table

Use this table to keep workflow choices consistent and lightweight.

## Task mode

| Situation | Default path |
| --- | --- |
| Single-file or tightly local change, clear validation, no expected design drift | Small: inspect -> execute -> verify |
| Cross-file or multi-step change, expected to last more than one focused session, or acceptance needs to be written down | Standard: inspect -> plan -> execute -> verify |
| Architecture, security, data, infra, release-sensitive change, or the second failed implementation attempt revealed a design problem | High-risk: research -> plan -> review -> execute -> verify |

## ExecPlan required?

Skip a dated ExecPlan when all of these are true:
- the change is local and bounded
- the validation path is obvious
- no explicit rollback or containment note is needed
- the work is unlikely to span multiple sessions

Write a dated ExecPlan when any of these are true:
- the change crosses subsystems or ownership boundaries
- the work is likely to span multiple sessions
- acceptance, rollback, or containment notes need to be recorded
- the first read shows meaningful uncertainty about shape or scope

## Review required?

Formal review or external advisory becomes worthwhile when any of these are true:
- the change touches security, data integrity, production reliability, or release-sensitive behavior
- a plan has meaningful architecture tradeoffs
- two materially different implementation attempts have already failed
- the verifier can only partially validate the result

For ordinary standard work, keep review optional and lightweight.

## Turn ownership required?

Use turn ownership when any of these are true:
- the work is long-running or resumable
- multiple agents may mutate shared state
- automation or background helpers can keep acting after user intent may have changed
- canonical workflow state will keep changing without immediate user interaction

Skip turn ownership for ordinary interactive coding, docs edits, commits, and sync-only follow-through.

## Production standard required?

Read `docs/ops/production-engineering-standard.md` when the task affects:
- production behavior
- release quality
- operational reliability
- security posture
- user-visible correctness where verification must meet the production bar

Skip it for ordinary workflow-doc edits, local tooling tweaks, and small non-production code changes unless the task specifically calls for it.
