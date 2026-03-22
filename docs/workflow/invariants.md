# Workflow Invariants

- Use one active dated ExecPlan at a time.
- Canonical runtime state lives in `.agent/artifacts/workflow-summary-state.json`.
- `SUMMARY.md` and `TASK_BRIEF.md` are generated projections, not independent sources of truth.
- UI-touching plans must satisfy the design gate before implementation.
- Required review gates fail closed when artifacts or external seats are unavailable.
