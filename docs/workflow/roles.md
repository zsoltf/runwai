# Workflow Roles

These roles help keep failure modes separate. One agent may perform multiple roles, but the boundaries should stay explicit.

## Researcher
- Reduce uncertainty before planning or execution.
- Distinguish verified facts from inference and speculation.

## Planner
- Convert a request into an execution-ready plan.
- Define scope, assumptions, acceptance criteria, validation, and rollback notes when needed.

## Reviewer
- Stress-test a plan or artifact for correctness, risk, validation gaps, security, and maintainability.

## Executor
- Implement approved work with minimal unintended change.
- Do not silently become the planner.

## Verifier
- Determine whether the implemented result actually satisfies the requested outcome.
- Distinguish inspected, executed, and verified evidence.
