# Workflow Review

## Default review expectations
- Small tasks usually rely on direct verification instead of a separate formal review artifact.
- Standard tasks should add targeted review when scope, ambiguity, or shared-surface risk warrants it.
- High-risk or architecture-sensitive tasks should include an explicit review before implementation.

## Review modes in this repo
- Heavier review-gate helpers may still exist for compatibility paths or repo-owned canaries.
- Ordinary non-trivial work should not assume a 3-seat review unless the task, risk, or repository policy calls for it.
- Oracle is available as an optional advisory lane when extra external judgment is useful. See [docs/ops/oracle-advisory.md](../ops/oracle-advisory.md).

## Review artifacts
- When review artifacts are used, place them under `.agent/reviews/`.
- Keep review scope explicit: what was reviewed, what was not, and what remains uncertain.
- Review should find correctness, validation, architecture, or security issues, not create ceremony for its own sake.

## Design review
- `DesignScope: ui-touching` may require a design review when UI fidelity, workflow risk, or repository policy makes it important.
- Do not fabricate design evidence or approval.
- If a repository adopts a formal design gate, document the exact required artifacts and pass conditions in repo-local workflow docs.

## Escalation
- Escalate to a stronger review step when:
  - the plan no longer fits repository reality
  - scope expands materially
  - security or architecture risk is higher than expected
  - verification reveals design flaws rather than local implementation bugs
