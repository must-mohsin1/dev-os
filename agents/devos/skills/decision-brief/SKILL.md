---
name: decision-brief
description: "Present a plan or decision for human approval as a tight 1-problem / 3-options / 1-rec brief."
version: 1.0.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [communication, decisions, discord, reporting, gate]
    related_skills: [coordinate-and-route, one-three-one-rule]
---

# Decision Brief

Use at the plan gate, or whenever you need a human decision on Discord.

## Format (1-3-1)
- **1 — Decision:** one sentence — what's being decided and why now.
- **3 — Options:** up to three, each one line — what it is + the key trade-off (cost / risk / speed).
- **1 — Recommendation:** your pick + a one-line reason + what happens on "yes".

Attach the spec/brief link. Ask a **closed** question ("approve option A?"), not an open one.

## Rules
- Lead with the recommendation — don't make the human read everything to find your view.
- Scannable on a phone (Discord). No walls of text.
- If the decision is reversible and low-cost, say so and default to acting.

## Done when
The human can approve or redirect in a one-line reply.
