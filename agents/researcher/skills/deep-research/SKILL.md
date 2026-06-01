---
name: deep-research
description: "Multi-source deep research: open web + Grok + browser + parallel sub-agents → cited, verified brief."
version: 1.1.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [research, web, grok, browser, synthesis, citations, verification, moa, delegation]
    related_skills: [parallel-cli, research-paper-writing, domain-intel]
---

# Deep Research (multi-source)

Use for any research task. You have a full research stack — **use all of it, not one tool.**

## Your tools
- **web** — `web_search` the open web + `web_extract` to FETCH and READ full pages (docs, blogs, papers). This is your default for facts.
- **x_search** (Grok) — X/social, real-time chatter, fast reasoning. Quick: `grok-4.20-reasoning`; deep: `grok-4.3`.
- **browser** — drive a real browser for JS-heavy, interactive, or login-gated sources.
- **delegation** — fan out up to **3 parallel sub-researchers**, each on a different angle.
- **moa** (Mixture of Agents) — for high-stakes synthesis, combine several models' takes.
- **memory / context_engine** — recall prior research; store durable findings.

## Procedure
1. **Decompose** into 2–3 angles (by-source, by-claim, by-time/recency).
2. **Fan out** (delegation): one sub-researcher per angle, each picking the right tool — `web_search`+`web_extract` for the open web, `x_search` for social/real-time, `browser` for JS/auth.
3. **Read primary sources.** Don't stop at snippets — `web_extract` or `browser` the actual page and quote precisely.
4. **Cross-check + adversarially verify** the load-bearing claims; note where sources disagree and how recent each is.
5. **Synthesize** (use `moa` for high-stakes) → brief: Answer → Key findings (each cited with a URL) → Disagreements/gaps → Confidence (H/M/L) + what would raise it.
6. **Store** durable findings to memory, tagged by project.

## Rules
- Use the **open web + browser**, not just Grok — a brief sourced only from X is thin.
- Every claim is cited (URL) or marked unverified. Open the source; don't trust a snippet.

## Done when
A decision-ready, multi-source, cited brief with an explicit confidence level.
