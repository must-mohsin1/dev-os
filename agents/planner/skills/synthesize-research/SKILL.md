---
name: synthesize-research
description: "Turn a research brief into spec inputs faithfully — decisions, constraints, open questions."
version: 1.0.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [synthesis, research, planning, decisions]
    related_skills: [write-spec, grok-deep-research]
---

# Synthesize Research

Use to convert the researcher's brief into the raw material for a spec — without distorting it.

## Procedure
1. **Extract decisions the brief supports.** What does the evidence let you decide now? Cite which
   finding backs each.
2. **Extract constraints.** Facts that bound the solution (limits, costs, compatibility, deadlines).
3. **Separate fact from inference.** Mark what's verified (high confidence) vs. assumed; assumptions
   become risks or spikes in the spec.
4. **List open questions.** Anything the spec needs but the brief doesn't answer → route back to
   research before committing, not a guess.
5. Feed the result into `write-spec`.

## Rules
- Be faithful: don't upgrade a low-confidence finding into a firm decision.
- If the brief is thin on a load-bearing point, say so and send it back — a spec built on a guess
  fails at the gate or in QA.

## Done when
Spec inputs are clearly tagged decision / constraint / assumption / open-question, each traceable
to the brief.
