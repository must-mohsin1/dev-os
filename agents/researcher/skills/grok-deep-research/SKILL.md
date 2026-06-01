---
name: grok-deep-research
description: "Run quick or deep Grok web research with parallel sub-searchers; produce a cited, verified brief."
version: 1.0.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [research, grok, x_search, synthesis, citations, verification]
    related_skills: [parallel-cli, research-paper-writing, domain-intel]
---

# Grok Deep Research

Use for any research task. Powered by Grok `x_search`.

## Choose depth
- **Quick** (default): `x_search` with `grok-4.20-reasoning` — a few targeted queries.
- **Deep**: switch `x_search.model` to `grok-4.3` and fan out (below) — for scoping, landscape
  surveys, or high-stakes claims.

## Procedure
1. **Decompose** the question into 2–3 angles (by-source, by-claim, by-time/recency).
2. **Fan out**: spawn up to **3 parallel sub-searchers** (`parallel-cli`), one per angle; each
   returns findings + sources. Don't serialize what can run wide.
3. **Merge + dedupe.** Where do sources disagree? What's stale?
4. **Adversarially verify** the load-bearing claims — try to disprove them; downgrade or drop the
   unverifiable.
5. **Write the brief**: Answer → Key findings (each **cited**) → Disagreements/gaps → Confidence
   (High/Med/Low) + what would raise it.

## Rules
- Every claim is cited or explicitly marked unverified. Note dates — recency matters.
- Synthesize for a decision; don't dump links.

## Done when
A decision-ready, cited brief with an explicit confidence level.
