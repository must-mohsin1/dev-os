# Kanban Workflow Doctrine: Durability, Coverage, and Reconciliation

**Date:** 2026-06-11
**Status:** Draft — awaiting user review
**Repos affected:** `dev-os`, `hermes-devcrew`, local `~/.hermes` tree

## Context

A build review of control-plane item5 + item6 identified three workflow bugs
(worker self-block doctrine, permissive reviewer dependency graph, orchestrator
rubber-stamping of reviewer cards) and shipped three skill-doctrine fixes. An
audit of those fixes found they are directionally correct but incomplete in
four ways, plus one new risk discovered during the audit:

1. **Durability is backwards.** The fix report claimed the profile-local
   patches "will be picked up by the next `scripts/upgrade.sh` run." The
   opposite is true: both installers run `hermes profile install <dir> --force`
   (dev-os `install.sh:99`, hermes-devcrew `install.sh` step 5), which syncs
   **repo → profile**. `~/.hermes` is not a git repo. The next upgrade
   overwrites the patched `kanban-worker` (devcrew-backend-dev) and
   `decompose-goal` (devcrew-architect) with old doctrine. Only Fix 3
   (kanban-orchestrator, dev-os commit `f7a3700`) is durable.

2. **Coverage gap.** The new worker doctrine ("complete with evidence")
   landed in exactly 1 of 13 profile copies of `kanban-worker`. All 13 claim
   `version: 2.0.0` — the patch did not bump the version, so patched and
   unpatched copies are indistinguishable by version string. The global
   template at `~/.hermes/skills/devops/kanban-worker/SKILL.md` is also
   unpatched, so future profiles are born with old doctrine.

3. **Doctrinal contradiction.** `kanban-orchestrator` ("Designing dep graphs
   that don't bottleneck on self-block") still instructs the opposite of
   Fix 2: reviewer/QA/integrator as *siblings* of code lanes, gated on the
   brief. That advice was a workaround for worker self-blocks — the failure
   mode Fix 1 removes — but the stale text remains, so the architect
   (decompose-goal: strict fan-in REQUIRED) and the orchestrator (siblings
   advised) now disagree mid-build.

4. **The mandatory dep-graph diagram serializes the build.** decompose-goal's
   new diagram draws `T0 ──► T1 ──► T2 ──► … ──► T8` — a sequential chain of
   implementation tasks. Read literally, it destroys all build parallelism.
   The intent was a parallel fan-in to the reviewer. There is also a stray
   `|` patch artifact on step 6 and a garbled sentence in the ≤3-impl-tasks
   case ("the reviewer … still depends on QA" — inverted; QA depends on the
   reviewer).

5. **New risk found during audit: bidirectional drift with pending data
   loss.** The live devos profile copy of `kanban-orchestrator` (v3.0.0
   header) gained a "Build-watching" section and two reference docs
   (`build-watching-playbook.md`, `structural-fixes-2026-06-11.md`) on
   2026-06-11 that exist **only in the profile** — the next dev-os upgrade
   destroys them. Meanwhile the committed 3.4.0 copy has sections the profile
   lacks, and its References block lists five `control-plane-item*.md` files
   that exist in **neither** the repo nor the profile (dangling references).

## Goals

- All three doctrine fixes survive `upgrade.sh` / `install.sh` on every
  machine and fresh checkout.
- Every worker profile (all 13 local, plus future ones) runs the same
  kanban-worker doctrine.
- Exactly one dep-graph doctrine exists across decompose-goal and
  kanban-orchestrator, with the verify-and-ship exception stated explicitly.
- The live-only build-watching content is captured in git before anything
  overwrites it.
- Version strings become a reliable drift signal.

## Non-goals (follow-ups, out of scope here)

- Upstreaming kanban-worker/kanban-orchestrator into hermes-agent core
  (Approach C) — right long-term home, separate effort.
- Automated drift-detection infrastructure or profile→repo backsync tooling.
- Per-link dependency modes (`strict`/`parallel`/`evidence`) in the kanban
  engine.
- VPS/devcrew-bridge image rebuild — required for the server fleet to inherit
  this doctrine, but it follows the existing tighten_crew_caps pipeline and is
  a deployment step, not a design problem. Listed in rollout as non-blocking.

## Approach decision

- **A — commit the 13 profile copies as-is.** Rejected: preserves duplication,
  drift returns immediately.
- **B — one canonical seed per repo + install-time fan-out. CHOSEN.** Each
  repo owns one copy of each shared skill; installers copy seeds into every
  profile they install. Doctrine edits happen only in-repo, then re-install.
- **C — upstream into hermes-agent.** Deferred (non-goal above).

Accepted duplication under B: kanban-worker exists once in `hermes-devcrew`
(seeds devcrew-*) and once in `dev-os` (seeds devos*) — one copy per fleet,
kept honest by the version-bump rule below.

## Design

### 1. Canonical source layout

| Skill | Canonical home | Seeds |
|---|---|---|
| kanban-worker | `hermes-devcrew/skills/devops/kanban-worker/SKILL.md` (new shared dir) | all `devcrew-*` profiles |
| kanban-worker (devos fleet copy) | `dev-os/skills/devops/kanban-worker/SKILL.md` (new shared dir) | `devos`, `devos-planner`, `devos-researcher` |
| decompose-goal | `hermes-devcrew/agents/architect/skills/decompose-goal/SKILL.md` (existing) | devcrew-architect only |
| kanban-orchestrator | `dev-os/agents/devos/skills/kanban-orchestrator/` (existing, incl. `references/`) | devos only |
| Global template tree | `~/.hermes/skills/devops/` | new profiles at creation; synced by the sync script below |

Stray profiles that belong to no repo (atlas, web-research, youtube_research,
must-helper, psx) get the seed via the sync script in section 4.

### 2. Content reconciliation (exact changes per skill)

**kanban-worker → v2.1.0** (seed = current devcrew-backend-dev copy)

- Content of Fix 1 kept as shipped: default is `kanban_complete` with
  structured evidence; `review-required` block reserved for the four
  human-only categories (security/credentials, schema/migrations,
  external-network actions, genuine task ambiguity), each block reason must
  name the concrete `human_concern`.
- Bump `version: 2.0.0 → 2.1.0` (the shipped patch forgot this).

**decompose-goal → v1.1.0** (seed = current devcrew-architect copy, corrected)

- Remove the stray `|` prefix on step 6.
- Replace the serialized diagram with a parallel fan-in:

```
T1 (impl) ──┐
T2 (impl) ──┤   all implementation cards run in PARALLEL;
T3 (impl) ──┼─► each one is a parent of T14
 …          │
TN (impl) ──┘
            ▼
   T14-Reviewer    (parents: every implementation card)
            ▼
   T15-QA          (parents: T14; the orchestrator expands this at runtime
            ▼       with every fix card T14 creates — see closeout procedure)
   T16-Integrator  (parents: T15)
```

- Fix the garbled ≤3-impl-tasks sentence to: "the reviewer may be parented on
  the last impl card only; QA still depends on the reviewer, and the
  integrator on QA."
- Add one line: "Implementation cards are siblings unless one consumes
  another's output — never chain them by default."
- Bump `version: 1.0.0 → 1.1.0`.

**kanban-orchestrator → v3.5.0** (merge of repo 3.4.0 + live profile extras)

- Merge IN from the live profile: the "Build-watching (4-min polls,
  stuck-worker detection, force-complete)" section and both reference files
  (`build-watching-playbook.md`, `structural-fixes-2026-06-11.md`) into
  `references/`. This must land in git before any installer runs again.
- Rewrite "Designing dep graphs that don't bottleneck on self-block":
  - Delete the "make Reviewer/QA/Integrator siblings gated on the brief"
    advice, with a one-line tombstone explaining why it's gone: it was a
    workaround for routine worker self-blocks, which the v2.1.0 worker
    doctrine eliminates; with self-blocks rare, strict fan-in (decompose-goal
    rule) is the default and early review of half-written code is the bug,
    not the mitigation.
  - Keep the D3-first (ship-then-validate) pattern, reframed as the explicit
    exception for verify-and-ship final builds where the work already exists
    in the tree.
- Replace the three vague closeout options in the rubber-stamp pitfall with a
  deterministic **reviewer closeout procedure**:
  1. Verify a fix card exists for every blocking finding; create any missing
     ones, assigned to the original implementer profile.
  2. Expand the QA card's parent set to include those fix cards
     (archive-and-recreate, the already-documented mechanic for changing a
     parent set).
  3. Comment on the reviewer card mapping each finding → its fix card id.
  4. Complete the reviewer card. Its deliverable is the review; the gate
     against unfixed code is QA's parent set, not the reviewer card staying
     open. This removes the pressure that produced rubber-stamping.
- Fix the References block: list only files that exist in `references/`;
  drop or stub the five dangling `control-plane-item*.md` entries (decision:
  drop the listing lines; the lessons they pointed to already live inline in
  the Pitfalls section).
- Bump `version: → 3.5.0`.

**Unified dep-graph doctrine (single source of truth, stated identically in
both decompose-goal and kanban-orchestrator):** implementation cards parallel;
reviewer fan-in on all impl cards; QA gated on reviewer + reviewer's fix
cards; integrator gated on QA; D3-first only for verify-and-ship builds;
workers complete with evidence and block only for the four human-only
categories.

### 3. Version-bump rule

Any edit to a skill's doctrine MUST bump its minor version in the same
change. This is what makes drift visible: the audit found 13 copies all
claiming 2.0.0 with two different doctrines inside. The rule is stated in a
comment at the top of each seed file.

### 4. Propagation mechanics

- **Installer fan-out (~8 lines in each repo's `install.sh`):** after the
  per-agent `hermes profile install` loop, copy `skills/devops/kanban-worker/`
  from the repo's shared seed dir into
  `~/.hermes/profiles/<name>/skills/devops/` for every profile just installed.
  Idempotent; runs on every install/upgrade.
- **Overwrite guard (same patch):** before overwriting a profile skill file
  that differs from the incoming seed, print one warning line with the file
  path and `diff --stat` summary. Prevents a repeat of today's silent
  near-loss of the build-watching playbook. Warn-and-proceed, not prompt —
  upgrades stay non-interactive.
- **`dev-os/scripts/sync-doctrine.sh` (new, ~25 lines, idempotent):** copies
  the seed kanban-worker into the global template tree
  (`~/.hermes/skills/devops/`) and into any profile under `~/.hermes/profiles/`
  that already has a `kanban-worker` skill but isn't covered by either
  installer (today: atlas, web-research, youtube_research). Profiles without
  the skill that are also outside both fleets (must-helper, psx) are left
  untouched. Invoked from `upgrade.sh` as a final step.

### 5. Rollout order

1. Commit the merged kanban-orchestrator 3.5.0 (+ both reference files) to
   dev-os — **first**, to capture the live-only content before anything else
   touches profiles.
2. Commit corrected decompose-goal 1.1.0 and the new shared kanban-worker
   2.1.0 seed to hermes-devcrew; commit the dev-os kanban-worker seed copy +
   installer fan-out + sync script to dev-os.
3. Run both installers locally + `sync-doctrine.sh`; verify (section 6).
4. Push both repos.
5. Non-blocking follow-up: rebuild the devcrew-bridge worker image on the VPS
   so the baked `~/.hermes` seed inherits the doctrine (same pipeline as the
   turn-caps bake, PR #6/#7 precedent).

### 6. Verification

- **Static:** after step 3, `diff -r` every profile copy against its seed →
  identical; grep doctrine markers across all 13 profiles + global tree:
  "Default behavior is to `complete` with evidence" (worker),
  "Reviewer / QA / integrator dep rule" (decompose-goal),
  "reviewer closeout procedure" (orchestrator). Version strings read 2.1.0 /
  1.1.0 / 3.5.0 everywhere. Zero dangling entries in the orchestrator
  References block.
- **Durability:** run `upgrade.sh` end-to-end once more; re-run the static
  checks — patches must survive their own propagation pipeline.
- **Behavioral (next build, e.g. control-plane item7):** expect
  review-required self-blocks near zero (only the four human-only
  categories), reviewer card starts only after all impl cards are done, zero
  "code doesn't exist yet" findings, zero force-completed reviewer cards, QA
  runs only after reviewer fix cards land.

## Risks and edge cases

- **`hermes profile install --force` semantics** (full replace vs overlay)
  are unverified. If it replaces the whole profile skills dir, the installer
  fan-out must run *after* it (it does, by construction). Confirm during
  implementation with a throwaway `HERMES_HOME`.
- **Operators live-editing profile skills** remains possible; the overwrite
  guard makes the loss visible instead of silent. Full backsync is a
  non-goal.
- **Stricter fan-in lengthens the critical path:** one genuinely stuck impl
  card now delays review of everything. Accepted: the orchestrator's existing
  recovery procedures (reclaim/reassign/force-complete-with-evidence) are the
  designed mitigation, and post-Fix-1 stuck cards should be rare and real.
- **Two kanban-worker seed copies (one per repo)** can drift from each other.
  Accepted under B; the version-bump rule plus the behavioral check make
  divergence visible. Approach C eliminates this later.

## Follow-ups (explicitly deferred)

- Upstream kanban-worker / kanban-orchestrator into hermes-agent so the
  global template tree and Docker seeds are born correct (Approach C).
- VPS worker-image rebuild (rollout step 5).
- Consider drift-detection in CI (diff seeds vs a recorded manifest).
