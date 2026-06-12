---
name: write-spec
description: "Turn a goal + research brief into an approval-ready spec with checkable acceptance criteria."
version: 1.1.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [spec, planning, product, requirements, acceptance-criteria]
    related_skills: [synthesize-research, spec-critic, writing-plans]
---

# Write a Spec

Use to convert a goal (+ the researcher's brief) into a spec a human can approve and devcrew can run.

## The spec (scale to the goal)
1. **Problem** — what's broken/missing and for whom (1–2 sentences).
2. **Goal** — the single outcome that means success.
3. **Non-goals** — explicitly out of scope (kills scope creep).
4. **Constraints** — stack, compatibility, perf/security budgets, deadline.
5. **Acceptance criteria** — concrete, checkable statements; each maps to a test or an observation
   QA/reviewer can verify. "Works well" is not a criterion; "p95 < 200ms at N=1k" is.
6. **Risks / unknowns** — and which need a `spike` first.

## Rules
- **Product planning, not technical.** Decide *what* + *why*; leave *how* (impl task breakdown) to
  devcrew's architect.
- **Ground in the brief.** If a decision needs facts you lack, send it back to research — don't guess.
- **YAGNI.** Cut every requirement not needed for the goal.
- If the goal hides multiple independent deliverables, split into separate specs.

## Spec retention (mandatory)
/tmp is not storage — specs written only to /tmp have been lost between runs.
After spec-critic passes, copy the spec to the durable board location and cite
that path in your completion summary:

    mkdir -p ~/.hermes/kanban/boards/${HERMES_KANBAN_BOARD:-control-plane}/specs
    cp <spec>.md ~/.hermes/kanban/boards/${HERMES_KANBAN_BOARD:-control-plane}/specs/<item>-spec.md

A completion summary that cites only a /tmp path is incomplete — the durable
path is the deliverable.

## Done when
Every acceptance criterion is checkable, scope is explicit, `spec-critic` has passed, and the spec is copied to the durable `specs/` dir with that path cited in your summary.
