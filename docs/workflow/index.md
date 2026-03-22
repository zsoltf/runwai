# Workflow Core

Repository-local docs are the workflow source of truth. If you read only one workflow doc, read this one.

## Default workflow modes
- Small task: inspect -> execute -> verify
- Standard task: inspect -> plan -> execute -> verify
- High-risk task, or ambiguity that still changes architecture or validation shape after initial scoping: research -> plan -> review -> execute -> verify

Use the lightest workflow that preserves trust.

## Core rules
- Keep planning, execution, and verification distinct.
- Distinguish clearly between `changed`, `inspected`, `executed`, `tested`, and `verified`.
- Queue new ideas during active work instead of switching context immediately.
- Treat turn ownership as a narrow safeguard for long-running or shared-state work, not a default ritual.

## Scale-up triggers
- Write a dated ExecPlan when scope crosses subsystems, work is likely to span sessions, or rollback and containment notes need to be recorded.
- Add review when security, data integrity, production reliability, release sensitivity, architecture tradeoffs, or repeated failed attempts make extra scrutiny worthwhile.
- Read the production standard when production behavior, release quality, reliability, or security posture are in play.
- Use `docs/workflow/decision-table.md` for the exact triggers and edge cases.

## Supporting workflow references
- Detailed policy reference: `docs/workflow/policy.md`
- Role boundaries: `docs/workflow/roles.md`
- Planning path: `docs/workflow/planning.md`
- Review path: `docs/workflow/review.md`
- Implementation path: `docs/workflow/implementation.md`
- Hard invariants: `docs/workflow/invariants.md`

## Ops-backed optional lanes
- Oracle advisory playbook: `docs/ops/oracle-advisory.md`

## Compatibility and advanced references
- Engines and compatibility: `docs/workflow/engines.md`
