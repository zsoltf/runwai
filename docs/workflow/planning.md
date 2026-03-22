# Workflow Planning

## Inputs
- `.agent/PROJECT_BRIEF.md`
- `.agent/TASK_BRIEF.md`
- repository state

## When to write a plan
- Use `docs/workflow/decision-table.md` for the concrete trigger rules.
- In practice, write a dated ExecPlan for standard or high-risk work.
- Write a dated ExecPlan for multi-session work, broad refactors, or anything that needs explicit rollback or containment notes.
- Small, local tasks may skip a formal plan when scope and validation are already obvious.

## ExecPlan path
- `.agent/execplans/YYYY-MM-DD__slug.md`

## Required ExecPlan headers
- `Risk: low|medium|high`
- `DesignScope: ui-touching|backend-only`
- `WorkflowEngine: v2`
- `WorkflowPacket: required|not-required`

## Default planning path
1. Read the briefs and inspect the repository.
2. Create and activate a dated ExecPlan when the task needs a durable plan artifact.
3. Capture scope, acceptance criteria, validation steps, and rollback or containment notes when relevant.
4. Add research, review, or packet artifacts only when task risk or repository policy makes them useful.

## Fresh bootstrap repos
- If `.agent/SUMMARY.md` shows `No active plan.`, begin with:
  - `docs/index.md`
  - `docs/workflow/index.md`
  - `.agent/PROJECT_BRIEF.md`
  - `.agent/TASK_BRIEF.md`
  - `.agent/SUMMARY.md`
- Create and activate the first dated ExecPlan before broad implementation when the task is non-trivial.
- Read deeper helper details only after the plan exists or when a required command fails.

## Workflow packets
- `WorkflowPacket: required` is for high-risk workflow-system or canonical-path changes.
- Most planned work should not need a packet.
