# Kanban Workflow Doctrine: Durability, Coverage, and Reconciliation

**Date:** 2026-06-11
**Status:** Draft, Revision 2 — awaiting user review
**Revision 2:** Re-grounded in the actual responsibility model after auditing all
repos (dev-os, hermes-devcrew, devcrew-bridge, hermes-agent). Rev 1 analyzed
only the skills layer; that was wrong in two places (root cause of bug 1,
reviewer/QA topology) and missing three things (KANBAN_GUIDANCE, kanban-doctor
interaction, doctrine-layer hierarchy).
**Repos affected:** `dev-os`, `hermes-devcrew`, `~/.hermes/hermes-agent`
(local checkout), local `~/.hermes` tree

## The responsibility model (ground truth from the repos)

**The orchestrator is `devos`** — the Tier-1 coordinator defined in
`dev-os/team.yaml` and `DEVOS.md`. Its charter, from `coordinate-and-route`,
`kanban-orchestrator`, and `kanban-doctor`:

1. Own the pipeline `research → plan → [human approve] → build → report` and
   route every task to a specialist; never do the work itself.
2. Enforce **exactly one human gate, at the plan** ("Only the plan is
   human-gated. Don't add gates" — coordinate-and-route; "gated exactly once,
   at the plan" — team.yaml).
3. On approval, dispatch the build via `devcrew-run "<spec>" <repo>`.
4. Monitor proactively, recover stuck boards (kanban-doctor), report status
   unsolicited.
5. Verify deliverables against briefs ("done is not done right"), close out
   builds, report PR + summary. Force-completes, gate decisions, and closeouts
   are devos actions — the rubber-stamp failure was a devos failure.

**Inside a build** (hermes-devcrew/team.yaml, the canonical topology):
architect = anchor/decomposer; designer upstream of frontend-dev; workers
parallel; **reviewer = static gate and qa = dynamic gate, in PARALLEL**;
integrator = synthesizer, sole owner of shared wiring files (devcrew-run
briefing, OWNERSHIP DISCIPLINE).

**Doctrine lives in four layers.** The bugs came from layers contradicting
each other, and any fix must say which layer wins:

| Layer | Artifact | Authority |
|---|---|---|
| L1 Manifests | `dev-os/team.yaml` + `DEVOS.md` (pipeline, one gate), `hermes-devcrew/team.yaml` (build topology) | **Canonical intent** |
| L2 Run briefings | `devcrew-run` architect prompt (line ~79) | Must restate L1 |
| L3 Skills | kanban-worker, decompose-goal, kanban-orchestrator, kanban-doctor | Must derive from L1 |
| L0 Framework injection | `hermes-agent/agent/prompt_builder.py` `KANBAN_GUIDANCE` — auto-injected into **every** worker's system prompt | Strongest at runtime; must not contradict L1 |

## Context: the audited findings

A build review of control-plane item5+item6 shipped three skill-doctrine
fixes. Auditing them against the responsibility model:

1. **Bug 1's root cause is L0, not L3.** `KANBAN_GUIDANCE` step 5 tells every
   worker: *"if your output is a code change that needs human review before
   counting as merged/done (most coding tasks) … end with
   `kanban_block(reason="review-required: …")`"*. This directly violates the
   one-gate architecture (L1) and contradicts the devcrew-run briefing (L2),
   which already mandated "Each worker MUST call kanban_complete (NOT
   kanban_block) … Do NOT self-block for review." The old kanban-worker skill
   (L3) sided with L0. Fix 1 patched L3 in **1 of 13 profile copies** and left
   L0 untouched — workers still receive the block-for-review instruction in
   their system prompt on every dispatch. The fix report's "~80% of
   false-positive self-blocks eliminated" is unverified and optimistic while
   L0 stands.

2. **Fix 2 contradicts the canonical topology.** It mandates a serial
   `reviewer → QA → integrator` chain. L1 says reviewer (static) and QA
   (dynamic) are parallel verification gates feeding the integrator. Fix 2
   also ships a diagram that draws implementation tasks as a sequential chain
   (`T0 ──► T1 ──► …`), a stray `|` artifact, an inverted sentence in the
   ≤3-impl-tasks case, and omits the designer→frontend-dev ordering.

3. **Fix 3 is correctly placed (devos's skill, devos's responsibility) but
   incomplete.** Its three closeout options (wait / ask / comment) leave a
   judgment call, and it never touched **kanban-doctor** — devos's recovery
   tool, whose procedure is "verify → unblock → complete in one shot" for
   review-required blocks. Once Fix 1/L0 land, the only remaining
   review-required blocks are *genuine human concerns* (security, schema,
   deploys, ambiguity) — and kanban-doctor as written would auto-complete
   exactly those, rebuilding the rubber-stamp inside devos's own tooling.
   Its "#1 cause of stalls" framing also goes stale.

4. **Durability is backwards.** Both installers run
   `hermes profile install --force` (repo → profile). `~/.hermes` is not a
   git repo; the checked-in decompose-goal copy is old. The next upgrade
   overwrites the kanban-worker and decompose-goal patches. Only Fix 3
   (dev-os `f7a3700`) is durable.

5. **Bidirectional drift with pending data loss.** The live devos profile
   copy of kanban-orchestrator (v3.0.0) carries a "Build-watching" section
   and two reference docs (`build-watching-playbook.md`,
   `structural-fixes-2026-06-11.md`) that exist only in the profile; the
   committed 3.4.0 has sections the profile lacks and lists five
   `control-plane-item*.md` references that exist nowhere. The next dev-os
   upgrade destroys the live-only content.

6. **Version strings are useless for drift detection today:** all 13
   kanban-worker copies claim 2.0.0 while carrying two different doctrines.

## Goals

- All four doctrine layers state the same rules, derived from L1.
- The worker-completion doctrine is enforced at L0 (the layer workers actually
  obey) and consistent at L2/L3.
- Every fix survives `upgrade.sh` / `install.sh` on every machine and fresh
  checkout; live-only content is captured in git first.
- devos's recovery tooling (kanban-doctor, 5-step recovery) escalates genuine
  human-concern blocks instead of auto-completing them.
- Version strings become a reliable drift signal.

## Non-goals (follow-ups)

- Upstreaming the KANBAN_GUIDANCE patch to NousResearch/hermes-agent (PR) —
  the local checkout already carries local work commits; a PR is the durable
  end-state but not this change.
- Automated drift-detection infrastructure or profile→repo backsync.
- Per-link dependency modes in the kanban engine.
- VPS/devcrew-bridge image rebuild — required for the server fleet (its image
  bakes hermes-agent + profiles), follows the tighten_crew_caps precedent;
  listed in rollout as a non-blocking follow-up.

## Approach decision

- **A — commit the 13 profile copies as-is.** Rejected: duplication, drift
  returns immediately.
- **B — one canonical seed per repo + install-time fan-out, PLUS the L0 patch
  in the hermes-agent checkout. CHOSEN.** Rev 1 chose B without L0; Rev 2
  adds it because L0 is the root cause and the strongest runtime signal.
- **C — full upstreaming into hermes-agent.** Deferred to a PR follow-up.

Accepted duplication under B: kanban-worker exists once per fleet repo
(hermes-devcrew seeds devcrew-*, dev-os seeds devos*), kept honest by the
version-bump rule.

## Design

### 1. Canonical source layout

| Artifact | Canonical home | Propagates to |
|---|---|---|
| KANBAN_GUIDANCE (L0) | `~/.hermes/hermes-agent/agent/prompt_builder.py` (local commit) | every kanban worker spawn; VPS via image rebuild |
| kanban-worker seed | `hermes-devcrew/skills/devops/kanban-worker/` (new shared dir) | all `devcrew-*` profiles |
| kanban-worker seed (devos fleet) | `dev-os/skills/devops/kanban-worker/` (new shared dir) | `devos`, `devos-planner`, `devos-researcher` |
| decompose-goal | `hermes-devcrew/agents/architect/skills/decompose-goal/` | devcrew-architect |
| kanban-orchestrator (+references) | `dev-os/agents/devos/skills/kanban-orchestrator/` | devos |
| kanban-doctor | `dev-os/agents/devos/skills/kanban-doctor/` | devos |
| Global template tree | `~/.hermes/skills/devops/` | new profiles; synced by sync script |

Stray profiles outside both fleets that carry the skill (atlas, web-research,
youtube_research) get the seed via the sync script. Profiles without it
(must-helper, psx) are left untouched.

### 2. Content changes per artifact

**L0 — KANBAN_GUIDANCE (prompt_builder.py), the root-cause fix.** Rewrite the
step-5 exception. Old: "most coding tasks" → block with review-required. New:
complete with structured evidence by default; block with
`review-required: <concrete human_concern>` ONLY for security/credential
changes, schema/migration changes, external-network actions (deploys, pushes,
provisioning), or genuine ambiguity in the task body. One human gate exists at
the plan; mid-build blocks are escalations, not gates. Keep step 4 ("block on
genuine ambiguity") as is — it already matches. Local commit in the
hermes-agent checkout; PR upstream as follow-up.

**kanban-worker → v2.1.0** (seed = current devcrew-backend-dev copy). Keep
Fix 1 content; anchor it explicitly to the one-gate architecture ("the
pipeline is human-gated once, at the plan; your block is an escalation to the
orchestrator, not a review gate"); bump version.

**decompose-goal → v1.1.0** (corrected to L1 topology):

- Remove the stray `|`; fix the inverted ≤3-impl-tasks sentence.
- Replace the serial chain and the serialized diagram with the manifest
  topology:

```
T-design (designer) ──► frontend impl cards        (designer is upstream
                                                    of frontend-dev only)
T1 (impl) ──┐
T2 (impl) ──┤   all implementation cards PARALLEL;
 …          ┼─► each is a parent of BOTH gates
TN (impl) ──┘
        ▼                    ▼
  T14-Reviewer (static)   T15-QA (dynamic)     ← parallel gates, each
        └──────────┬──────────┘                  parented on every impl card
                   ▼
        T16-Integrator (parents: T14, T15; the orchestrator expands this
                        at runtime with every fix card the gates create)
```

- Add: "Implementation cards are siblings unless one consumes another's
  output — never chain them by default."
- Mirror the briefing's OWNERSHIP DISCIPLINE: every card body lists its
  `Files:`; shared wiring files (barrels, route registries, package.json,
  lockfiles, shared config) belong only to the integrator card.
- Bump version.

**kanban-orchestrator → v3.5.0** (merge repo 3.4.0 + live profile extras):

- Merge IN the live-only "Build-watching" section and both reference files —
  this must land before any installer runs again.
- Delete the "make Reviewer/QA/Integrator siblings gated on the brief" advice
  (tombstone: it was a workaround for routine self-blocks, which the L0+L3
  fix eliminates). Keep D3-first as the explicit verify-and-ship exception.
- Replace the vague closeout options with a deterministic **gate-card
  closeout procedure** targeting the integrator:
  1. Verify a fix card exists for every blocking finding from reviewer/QA;
     create missing ones, assigned to the original implementer.
  2. Expand the **integrator's** parent set with those fix cards
     (archive-and-recreate, the documented mechanic).
  3. Comment on the gate card mapping finding → fix card id.
  4. Complete the gate card. The gate against unfixed code is the
     integrator's parent set, not an open reviewer card.
- Fix the References block: list only files that exist; drop the five
  dangling `control-plane-item*.md` lines.
- State the layer hierarchy: this skill derives from team.yaml/DEVOS.md; on
  conflict, the manifests win.
- Bump version.

**kanban-doctor → v1.1.0 (new in Rev 2).** Split the review-required recovery
into two branches:

- *Legacy/false-positive block* (no concrete human concern in the reason):
  existing 5-step verify → unblock → reclaim → comment → complete.
- *Genuine human-concern block* (reason names security/schema/deploy/
  ambiguity): **never auto-complete.** Post a decision-brief (1-3-1) to the
  human on Discord and leave the card blocked; the human's unblock is the
  resolution. Update the "#1 cause of stalls" framing to past tense with a
  pointer to the doctrine change.

### 3. Version-bump rule

Any doctrine edit bumps the skill's minor version in the same change, stated
in a comment at the top of each seed. (The audit found 13 copies claiming
2.0.0 with two doctrines.)

### 4. Propagation mechanics

- **Installer fan-out (~8 lines per repo `install.sh`):** after the per-agent
  `hermes profile install` loop, copy the repo's shared
  `skills/devops/kanban-worker/` into every installed profile's
  `skills/devops/`.
- **Overwrite guard:** before overwriting a profile skill that differs from
  the incoming seed, print a one-line warning with `diff --stat`.
  Warn-and-proceed, non-interactive.
- **`dev-os/scripts/sync-doctrine.sh` (~25 lines, idempotent):** sync the
  seed into `~/.hermes/skills/devops/` and into stray profiles that already
  carry the skill. Invoked from `upgrade.sh` as a final step.

### 5. Rollout order

1. Commit merged kanban-orchestrator 3.5.0 + reference files to dev-os —
   first, to capture live-only content.
2. Commit the L0 KANBAN_GUIDANCE patch in the hermes-agent checkout.
3. Commit decompose-goal 1.1.0 + kanban-worker 2.1.0 seed to hermes-devcrew;
   kanban-worker seed + kanban-doctor 1.1.0 + installer fan-out + sync script
   to dev-os.
4. Run both installers + sync-doctrine.sh; verify (section 6).
5. Push dev-os and hermes-devcrew.
6. Follow-ups: hermes-agent upstream PR; VPS worker-image rebuild (bakes
   hermes-agent + profiles, tighten_crew_caps precedent).

### 6. Verification

- **Static:** every profile copy `diff -r`-identical to its seed; doctrine
  markers present in all 13 profiles + global tree; versions read 2.1.0 /
  1.1.0 / 3.5.0 / 1.1.0; `grep "most coding tasks" prompt_builder.py` returns
  nothing; no dangling References entries.
- **Durability:** run `upgrade.sh` once more; re-run static checks — the
  patches must survive their own propagation pipeline.
- **Behavioral (next build, e.g. item7):** self-blocks ≈ 0 outside the four
  genuine categories; reviewer and QA start together, only after all impl
  cards; zero "code doesn't exist yet" findings; zero force-completed gate
  cards; integrator runs only after gate fix cards land; any genuine block
  surfaces as a Discord decision-brief instead of an auto-complete.

## Risks and edge cases

- **hermes-agent upgrade rebase burden:** the L0 patch is a local commit on
  an upstream checkout; future `git pull` may conflict. Accepted — the
  checkout already carries local work commits; the upstream PR follow-up is
  the durable end-state.
- **`hermes profile install --force` semantics** (replace vs overlay)
  unverified; fan-out runs after it by construction. Confirm with a throwaway
  `HERMES_HOME` during implementation.
- **Stricter fan-in lengthens the critical path:** one genuinely stuck impl
  card delays both gates. Accepted: post-fix stuck cards should be rare and
  real; devos's recovery procedures are the mitigation.
- **Two kanban-worker seed copies** (one per fleet repo) can drift from each
  other; version-bump rule + behavioral checks make it visible.
- **Live-edited profiles** remain possible; the overwrite guard makes loss
  visible. Full backsync is a non-goal.

## Follow-ups (explicitly deferred)

- Upstream PR to NousResearch/hermes-agent for the KANBAN_GUIDANCE change.
- VPS worker-image rebuild so the server fleet inherits L0+L3.
- Drift-detection in CI (diff seeds vs a recorded manifest).
