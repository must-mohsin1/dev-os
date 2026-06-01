---
name: spec-critic
description: "Adversarially review a draft spec before the human gate; kill vague criteria and hidden scope."
version: 1.0.0
author: dev-os
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [critique, review, spec, quality, gate]
    related_skills: [write-spec, synthesize-research]
---

# Spec Critic

Run on your own draft spec before handing it to the coordinator for the human gate. Be the harshest
reader the spec will face.

## Hunt for
1. **Vague acceptance criteria** — anything not checkable by a test/observation. Rewrite or cut.
2. **Hidden scope** — work implied but not stated; either add it as a non-goal or make it explicit.
3. **Unstated assumptions** — dependencies, data, access, environment taken for granted.
4. **Missing risks** — irreversible steps, migrations, auth, external calls, unknowns needing a spike.
5. **Goal drift** — requirements that don't serve the single stated goal (cut them).
6. **Unfaithfulness to the brief** — claims the research didn't support (send back to research).

## Output
A pass/fix list applied **inline** to the spec, then a one-line verdict: "tight — ready for gate" or
"sent back to research: <what's missing>".

## Rule
A spec the human can't verify against is not ready. No vague criterion survives this pass.
