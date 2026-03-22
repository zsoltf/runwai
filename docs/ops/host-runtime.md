# Host Runtime

This document separates host-machine setup from repository policy.

## Layers
- Policy lives in `docs/workflow/`.
- Host-machine setup lives in local Codex config, installed tools, MCP endpoints, and any local VM or browser automation setup.

## What belongs here
- installed `~/.codex` or `~/.agents` assumptions when this repo depends on them
- local MCP server wiring
- VM-backed browser or advisor setup
- sync, install, or bootstrap expectations
- host-only assumptions that should not be treated as portable repo facts

## Rule of thumb
- Put portable workflow rules in repo docs.
- Put personal machine and local network assumptions in host-runtime docs or config, not in general repo workflow docs.
