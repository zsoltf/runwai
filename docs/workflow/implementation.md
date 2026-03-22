# Workflow Implementation

## Implementation readiness
- Small task:
  - scope is clear
  - validation path is clear
- Standard task:
  - the active plan exists when a plan artifact is needed
  - relevant docs have been read
  - validation approach is defined
- High-risk or gated task:
  - required planning, research, review, or design prerequisites are satisfied before implementation starts

## Entry discipline
- Prefer repo-native validation commands.
- If the repository uses readiness helpers, run them before non-`.agent` writes.
- Do not hand-edit canonical workflow state when repository helpers exist for that purpose.

## Verification
- Always distinguish between inspected, executed, and verified.
- Prefer deterministic test, build, lint, or smoke-check commands over ad hoc manual checks.
- If verification is partial, say so explicitly and record the gap.

## Completion
- A task is complete only when the requested scope is implemented or an explicit blocker is recorded.
- Do not call work done just because files changed.
