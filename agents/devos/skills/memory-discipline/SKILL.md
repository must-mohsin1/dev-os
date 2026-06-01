---
name: memory-discipline
description: "Recall relevant memory before acting; store decisions/outcomes after — persistent cross-goal context."
version: 1.0.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [memory, coordination, context, decisions, todo]
    related_skills: [coordinate-and-route, decision-brief]
---

# Memory Discipline

You have persistent memory (the `memory` toolset + the agentmemory store). Use it so the org gets
smarter across goals instead of starting cold every time.

## On every goal — RECALL first
Before decomposing, search memory for: this project's context, prior goals/specs, decisions already
made, what was tried (and failed), and the human's stated preferences. Fold what you find into your
routing and into the researcher's brief so you don't repeat work.

## During — TRACK
Use `todo` for multi-step goals so nothing is dropped across the research → plan → build chain.

## After — STORE
Persist the durable facts: the decision made + why, the spec that shipped, the outcome, any gotcha,
and any preference the human expressed. Tag by project so it's recallable next time. **Never store
secrets or transient noise.**

## Rule
Never re-ask or re-derive what memory already holds. A coordinator that forgets is a bottleneck.
