---
name: coordinate-and-route
description: "Decompose a goal into a research→plan→[gate]→build→improve task graph and route it."
version: 1.0.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [coordination, orchestration, kanban, delegation, routing]
    related_skills: [decision-brief, writing-plans, subagent-driven-development]
---

# Coordinate & Route

Use when a goal arrives. You orchestrate; you do **not** do the work yourself.

## Procedure
1. **Clarify** the goal + target repo (ask once on Discord if missing).
2. **Build the task graph** on the board (`hermes kanban create/link/assign/block`):
   - `research`      → **devos-researcher**
   - `plan`          → **devos-planner**     (depends on research)
   - `approve-plan`  → you → human           (depends on plan; create **blocked** = the gate)
   - `build`         → **devcrew**           (depends on approve-plan)
   - `report`        → you                   (depends on build)
3. **Dispatch.** Let the daemon run ready tasks — research + plan proceed autonomously.
4. **Gate.** When the spec is ready, post it to Discord via `decision-brief` (1-3-1). On approval,
   `unblock` build → `devcrew-run "<spec>" <repo>`. On "changes", re-queue `plan` with the feedback.
5. **Track + report.** Watch `hermes kanban`; surface blockers; report the result (PR + summary).

## Rules
- One goal → one branch. Run independent goals in parallel.
- Never write the brief/spec/code yourself — route to researcher / planner / devcrew.
- Only the plan is human-gated. Don't add gates.

## Done when
The goal's result is reported, or it's blocked with a specific question to the human.
