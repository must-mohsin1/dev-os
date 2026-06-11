# Structural Workflow Fixes — 2026-06-11

This reference documents the 3-bug analysis that produced the "complete with
evidence / reviewer-must-depend-on-all-impl / never-rubber-stamp-reviewer-findings"
doctrine. Read it when you're about to force-complete a card, when you're about to
decompose a goal with a reviewer lane, or when the user asks you to "audit the
workflow" / "fix the kanban" / "the same thing keeps happening."

## When the user says "fix the workflow"

Three signals mean the workflow has a structural bug, not a one-off:

1. **The same recovery action happens 3+ times per build.** On control-plane
   item5+item6, the orchestrator (me) was doing 16+ false-positive recoveries per
   build: `unblock + complete` on cards that were correctly blocked, force-completing
   reviewers without addressing findings, reassigning orphaned assignees. Each recovery
   is a tax; the tax reveals a doctrine bug.
2. **The user says "same case with other tickets" or "this is happening again."** That's
   not an isolated incident — it's the user telling you to step back and find the
   pattern.
3. **A reviewer/QA card with N blocking findings gets closed without anyone doing the
   findings.** That's the rubber-stamp anti-pattern. Recovery: never do that; see Rule
   3 below.

## The 3 bugs identified 2026-06-11

### Bug 1: `kanban-worker` doctrine encouraged self-block for every code task

- **Symptom:** Every code card landed in `blocked` with `review-required: ...` even
  when work was done, tests passed, and there was no genuine human-only concern.
  Orchestrator force-completed 16+ per build.
- **Root cause:** The `kanban-worker` skill said: "For most code-changing tasks, the
  work isn't truly done until a human reviewer has eyes on it. Block instead of
  complete." Wrong for our setup because we have a `devcrew-reviewer` lane (T14-style
  card) whose job IS to do the review.
- **Fix:** Changed doctrine to "complete with evidence" by default. Block with
  `review-required` ONLY for genuine human-only concerns (security, schema, external
  network, genuine ambiguity). When blocking, MUST spell out the concrete
  `human_concern` in the reason string. "Needs review" without a concrete concern is
  a rubber-stamp — don't.
- **File:** `~/.hermes/profiles/devcrew-backend-dev/skills/devops/kanban-worker/SKILL.md`
  (profile-local; not in the dev-os repo, but the doctrine applies to all kanban
  workers via the auto-injected KANBAN_GUIDANCE block).

### Bug 2: `decompose-goal` skill let reviewer run too early

- **Symptom:** Reviewer ran in parallel with implementation tasks and flagged
  "this code doesn't exist yet" issues. Created false-positive fix cards for code
  that was about to be written.
- **Root cause:** The `decompose-goal` skill said: "link only where order truly
  matters; leave the rest independent." Architect interpreted "where order matters"
  narrowly — reviewer got parent=T13-devops only, not parent=T6+T7+T11+T13.
- **Fix:** Added mandatory "Reviewer / QA / integrator dep rule" section. Reviewer
  card must depend on EVERY implementation card (`link T6 T14`, `link T7 T14`,
  `link T8 T14`, ...). QA depends on reviewer. Integrator depends on QA.
- **File:** `~/.hermes/profiles/devcrew-architect/skills/decompose-goal/SKILL.md`
  (profile-local; not in the dev-os repo).

### Bug 3: `kanban-orchestrator` skill had no rule against force-completing reviewer cards

- **Symptom:** I (orchestrator) closed t_841c2622 (T14-reviewer, item6) with 6
  unaddressed blocking issues. The user caught it: "why you moved this in complete
  blocked."
- **Root cause:** The skill had the "force-complete when worker stuck" rule but no
  rule against closing reviewer cards with unaddressed findings. So I rubber-stamped.
- **Fix:** Added pitfall entry with explicit rule — if a reviewer/QA card's last
  comment lists N blocking issues, you must (a) wait for fix cards, (b) ask the user,
  or (c) post a follow-up comment BEFORE closing. Never just `complete` it.
- **File:** `~/.hermes/profiles/devos/skills/devops/kanban-orchestrator/SKILL.md`
  (also in the dev-os repo at
  `agents/devos/skills/kanban-orchestrator/SKILL.md`).

## Diagnostic procedure when the user says "audit the workflow"

Run these in order; the goal is to find the pattern, not fix the symptoms:

```bash
# 1. List the last 20-30 cards that the orchestrator touched
hermes kanban list --board <board> | grep -E "blocked|archived"

# 2. For each blocked card, look at the latest comment + status transition
hermes kanban show <task_id> | grep -A1 "summary\|Diagnostics"

# 3. Look for the most common patterns:
#    a. "review-required: ... tests pass, needs eyes" → Bug 1 (worker self-block)
#    b. "Skipped (non-spawnable assignee — terminal lane, OK)" → Bug 4 (orphaned
#       assignee) — covered separately
#    c. "Stale Claim TTL" or worker at run 3+ of same task → Bug 5 (stuck worker)
#    d. Reviewer card closed with N findings, fix cards not yet done → Bug 3
#       (rubber-stamp)
#    e. "missing code" / "BFF target nonexistent endpoint" findings in reviewer
#       output → Bug 2 (reviewer ran early)

# 4. Categorize: how many of each pattern? If any is > 20% of cards, structural fix
#    needed, not just symptom recovery.

# 5. For each pattern, identify the doctrine in the relevant skill that produced it
#    (kanban-worker for self-block, decompose-goal for premature reviewer,
#    kanban-orchestrator for rubber-stamp).
```

## The 3 rules the orchestrator must follow (summary)

1. **Workers default to `complete` with evidence.** The T14 reviewer is the real
   review lane. Workers should only self-block with `review-required` for genuine
   human-only concerns (security, schema, external network, ambiguity), and the
   reason string MUST spell out the concrete concern.

2. **Reviewer / QA / integrator are downstream gates, not parallel lanes.** The
   decompose-goal must wire reviewer as child of every impl card, QA as child of
   reviewer, integrator as child of QA. Per-id link loop; multi-id is silent on
   latter ids.

3. **Never rubber-stamp reviewer findings.** If a reviewer/QA card's last comment
   lists N blocking issues, you must (a) wait for fix cards, (b) ask the user, or
   (c) post a follow-up comment. Never just `complete` it.

## Force-complete decision tree (replace this with the actual decision)

When a card is blocked or running too long, follow this order:

```
Is the work actually done? (code committed, tests pass)
├── No  → reclaim + let the worker retry
└── Yes → Does the card contain unaddressed review findings?
    ├── Yes → wait for fix cards OR ask the user OR archive with a doc decision
    │         DO NOT force-complete.
    └── No  → is the worker stuck in a debug loop?
        ├── Yes → reclaim + complete (with verification comment)
        └── No  → is the budget exhausted?
            ├── Yes → if 90-iter budget hit and work is partial, reclaim + respawn
            │         (don't force-complete partial work)
            └── No  → wait one more poll cycle
```

## Reference commits (control-plane + dev-os)

- `must-mohsin1/control-plane`:
  - `381dde6` — item4 catalog + composition
  - `5e912b8` — item5 deploy options
  - `9facbfc` — item5 T3 provisioner dispatch
  - (item6 will land after the build completes)
- `must-mohsin1/dev-os`:
  - `1a8010d` — kanban-doctor + kanban-orchestrator + kanban-research-tasks ship
  - `444feef` — devos-researcher v4-flash fallback
  - `f7a3700` — workflow fixes (the commit that shipped Bug 3's rule to dev-os)

## When to revisit this document

- When the same force-complete pattern recurs 3+ times in a new build.
- When the user again says "fix the workflow" or "audit the ticket mechanism."
- When a new orchestrator/worker profile is added and the doctrine needs to be
  re-applied.
- When item6 (self-improvement infrastructure for agents) ships — the
  aggregator in item6 may surface a class of issues that need doctrine updates.

End of structural-fixes reference.
