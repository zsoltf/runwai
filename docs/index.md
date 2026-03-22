# Docs Map

This file is the broader docs map, not the required first stop. Ordinary work should begin from `README.md`, then `docs/index.md`, then `docs/workflow/index.md`.

Use `$docs-list` when you want the smallest relevant doc set.

Docs catalog: `docs/catalog.json`

## Three layers

### 1. Policy
Workflow policy lives in:
- Core workflow contract: `docs/workflow/index.md`
- Detailed policy reference: `docs/workflow/policy.md`
- Role boundaries: `docs/workflow/roles.md`
- Detailed decision reference: `docs/workflow/decision-table.md`
- Execution details: `docs/workflow/planning.md`, `docs/workflow/review.md`, `docs/workflow/implementation.md`, `docs/workflow/invariants.md`

### 2. Host runtime
Machine-local setup lives in:
- `docs/ops/host-runtime.md`
- `docs/ops/oracle-advisory.md`

## Core workflow docs
- Workflow core: `docs/workflow/index.md`
- Detailed policy: `docs/workflow/policy.md`
- Detailed decision table: `docs/workflow/decision-table.md`
- Roles: `docs/workflow/roles.md`
- Planning: `docs/workflow/planning.md`
- Review: `docs/workflow/review.md`
- Implementation: `docs/workflow/implementation.md`
- Invariants: `docs/workflow/invariants.md`

## Conditional and optional references
- Production standard: `docs/ops/production-engineering-standard.md`
  - Read this for production, release, reliability, or security-sensitive work.
- macOS release signing: `docs/ops/macos-release.md`
  - Read this for Developer ID signing, notarization, and outside-App-Store distribution.
- CI workflow: `docs/ops/CICD.md`
  - Read this for GitHub Actions coverage and the local commands that match CI.
- Oracle advisory: `docs/ops/oracle-advisory.md`
  - Optional external judgment lane and local advisor playbook.
- Product spec: `docs/product/mvp-spec.md`
  - Historical source of truth for the original runwai MVP shape and pacing rules.

## Compatibility and advanced references
- Engines and compatibility: `docs/workflow/engines.md`

## Working rule
- Start from `README.md`, then `docs/index.md`, then `docs/workflow/index.md`.
- If a rule matters enough to enforce, it should live in `docs/` and in code or tests when possible.
