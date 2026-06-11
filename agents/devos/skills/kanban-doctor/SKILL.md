---
name: kanban-doctor
version: 1.1.0
description: Diagnose and recover a stuck Hermes Kanban board. Use when user says "board not moving", "kanban stuck", "frozen", "stalled", "no progress", or "check the board". Detects the review-required self-block pattern (historically the #1 cause of stalls; rare after the v2.1.0 worker doctrine — remaining blocks are often genuine) and the non-spawnable-assignee pattern, classifies blocks as genuine-concern vs false-positive, escalates the genuine ones to the human, and recovers the false positives.
---

<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. -->

# kanban-doctor

Recover a stuck Hermes Kanban board. Two patterns cause most stalls:

1. **Self-block with `review-required`** — worker ships code with passing tests, then self-blocks. Blocked parents are not `done`, so the dispatcher holds all downstream tasks. Historically the #1 cause of stalls; rare after the v2.1.0 worker doctrine — and the blocks that remain are often genuine (see step 3b).
2. **Non-spawnable assignee** — task is created or assigned to a profile that isn't registered as an active worker in this session. Dispatcher silently skips it with `Skipped (non-spawnable assignee — terminal lane, OK)`. This is the #2 cause and looks like the board isn't moving even though everything else is fine.

This skill detects both, runs verification, and recovers the affected cards.

> **READ THIS FIRST (idle-board vs dead-board):** A common false alarm is reading `hermes kanban dispatch` output as "the board is dead" when it shows `Reclaimed: 0, Crashed: 0, Timed out: 0, Stale: 0, Auto-blocked: 0, Promoted: 0, Spawned: 0`. **All zeros is the NORMAL idle state** when there is nothing new for the dispatcher to do that tick. The board is healthy if `stats` shows `running > 0` or `ready > 0` OR if `todo > 0` (dispatcher is waiting for parents). The board is sick when `todo > 0` AND `ready = 0` AND `running = 0` AND `blocked > 0` — that combination means a `blocked` parent is holding the whole chain. THIS skill is for the sick case.

## When to use

Trigger on any of:
- User says: "board not moving", "stuck", "frozen", "stalled", "no progress", "check the board", "is the board alive"
- `hermes kanban stats` shows the sick pattern: `todo > 0` AND `ready = 0` AND `running = 0` AND `blocked > 0`
- `hermes kanban dispatch` reports `Skipped (non-spawnable assignee — terminal lane, OK)` for any task
- Same `blocked` task has been in `blocked` for > 5 min with a `review-required` reason
- A worker that should be done is sleeping on a `blocked` state
- `ready > 0` but no task has been claimed for > 5 min (suggests the ready task's assignee is not spawnable)

## Procedure (run in order)

### 1. Capture board state
```bash
cd <repo-root>
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban stats
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban list | grep -E "blocked|◻|⊘|▶"
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban assignees
```

Note: the deprecated `hermes kanban daemon` no longer runs the dispatcher; the dispatcher is embedded in the gateway. Do not try to start a standalone daemon.

`hermes kanban assignees` is the **active worker pool** for this session. Profiles with `ON DISK yes` AND a presence in this list are spawnable. Profiles with `ON DISK no` are terminal lanes (legacy or registered elsewhere) and the dispatcher will skip tasks assigned to them.

### 2. Identify the failure pattern

Run `hermes kanban dispatch` once and read the output carefully:

- If you see `Skipped (non-spawnable assignee — terminal lane, OK): t_xxx, t_yyy` → **Pattern 2**. Reassign those tasks to a spawnable profile (see step 2b), then re-dispatch.
- If dispatch shows `Spawned: 0` and there are `blocked` tasks in the list → **Pattern 1**. Continue to step 3.

### 2b. Reassign non-spawnable tasks (Pattern 2 only)
```bash
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban assign <task_id> <spawnable_profile>
```
Pick a spawnable profile that fits the task's domain. For backend Python: `devcrew-backend-dev`. For frontend TS/Next.js: `devcrew-frontend-dev`. For devops/docker: `devcrew-devops`. For integration/cleanup: `devcrew-backend-dev` (or `devcrew-developer` if it's listed as spawnable in your session). Re-run `dispatch` after reassignment to confirm `Spawned: N` is non-zero.

### 3. Identify the self-blocked tasks (Pattern 1)
```bash
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban show <task_id>
```
For each `blocked` task, check the latest comment for:
- `review-required` reason
- Machine-readable handoff with `tests_run`, `tests_passed`, `changed_files`
- All listed tests pass

If the handoff claims passing tests and matches the "code is in" pattern, this is recoverable.

### 3b. Classify each block BEFORE recovering (genuine concern vs false positive)

Read each blocked card's reason string. Two classes, two different paths:

- **Genuine human-only concern** — the reason names security/credential
  changes, schema/migration changes, external-network actions (deploy, push,
  provisioning), or a concrete ambiguity/decision. **Do NOT run steps 4-8 for
  this card.** Escalate instead: post a `decision-brief` (1-3-1) to the human
  on Discord with the card id, the concern, and your recommendation, and
  leave the card blocked. The human's `unblock` is the resolution.
  Auto-completing these is the rubber-stamp anti-pattern with extra steps.
- **Legacy false positive** — the reason is generic ("needs review", "needs
  eyes", tests pass, no concrete concern named). Proceed with steps 4-8
  (verify → reclaim → unblock → comment → complete via safe-complete).

When unsure, escalate. A wrongly-escalated card costs the human one unblock;
a wrongly-completed card ships an unreviewed security or schema change.

### 4. Verify the test claims locally
Pick the relevant test files and run pytest:
```bash
uv run pytest <test_files> -q
```
For control-plane item2, the relevant files are: `tests/test_secret_resolver.py`, `tests/test_identity.py`, `tests/test_consent.py`, `tests/test_rotation.py`, `tests/test_cli.py`, `tests/test_app.py`, `tests/test_role_manager_api.py`. Run the union of what the worker touched.

If pytest passes (or the only failures are pre-existing, clearly named in the handoff), proceed.

### 5. Reclaim any still-active locks
```bash
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban reclaim <task_id>
```
`reclaim` is safe to run even if it returns "not running or unknown id" — that just means the worker has already gone to sleep.

### 6. Unblock the tasks
```bash
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban unblock <task_id> --reason "<reason>"
```

### 7. Post verification comments
For each unblocked task:
```bash
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban comment <task_id> "Closing <T-id> based on review-required handoff + re-verification. uv run pytest -q → <N> passed, 0 failed. <brief summary of work>. Reviewer (T10) / Integrator (T11) follow."
```

### 8. Complete the tasks
```bash
~/.hermes/profiles/devos/scripts/safe-complete <task_id> <board>   # one id at a time; refuses cards with live review markers
```

### 9. Trigger dispatch
```bash
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban dispatch
```
Watch `Spawned: N` — non-zero means downstream tasks are now claimable.

### 10. Report
Post a short status to the user with:
- Tasks unblocked + completed (with evidence) — Pattern 1
- Tasks reassigned + spawned (with new profile) — Pattern 2
- Current `stats` snapshot
- What spawned next

## Pitfalls

(In the bullets below, `complete` refers to the underlying `hermes kanban complete` semantics — safe-complete wraps that command, so its quirks apply through the guard too.)

- **`hermes kanban daemon` is deprecated.** Do not run it. Dispatcher lives in the gateway. If `hermes gateway status` says the service is stale, report to the user — do not restart it without consent.
- **`Spawned: 0` does not mean the board is dead.** It only means the dispatcher had nothing new to spawn this tick. Read all six counters together: Reclaimed, Crashed, Timed out, Stale, Auto-blocked, Promoted, Spawned.
- **`complete` requires the task to be unblocked first.** If `complete` returns "not in done-able state", run `unblock` and retry.
- **Reclaim before unblock.** A task in `blocked` with an active lock is a different shape than a sleeping blocked. Reclaim first to avoid race with the worker.
- **`reclaim` only takes a SINGLE task id, but `unblock` and `complete` take multiple.** This asymmetry is a real footgun. Chained `hermes kanban reclaim t_a t_b` fails with "unrecognized arguments: t_b" because the parser treats the second id as a top-level arg. Run `reclaim` per task. (Verified on control-plane item2: `unblock t_a t_b --reason "..."` works, `complete t_a t_b` works, `reclaim t_a t_b` does not.)
- **`complete` with multiple ids is unreliable when states are mixed.** A multi-id `complete t_a t_b` exit 0's and silently no-ops on the ids that aren't in a completable state. If one card is `ready` and another is `running` (or in any disallowed mix), only the ready one closes; the running one returns `cannot complete <id> (unknown id or terminal state)` on the next try. **When mixing states, run `complete` one id at a time.** Use multi-id `complete` only when you've confirmed all targets are in the same completable state. Verified on control-plane item3.
- **`hermes kanban link A B` makes A the PARENT of B (not the other way around).** Output reads "Linked A -> B" meaning A is parent, B is child. If you call `link gate plan` thinking gate is the child of plan, you make gate the parent of plan and the gate immediately becomes claimable (and runs prematurely). Verify after linking: `hermes kanban show <child>` should list the parent in its `parents:` line. Verified on control-plane item4 (had to unlink + relink to fix the chain). The orchestrator-skill phrase "hermes kanban link <child> <parent>" is misleading; the system treats the first positional arg as the parent.
- **`complete` on a card that was just `unblock`ed can fail with "unknown id or terminal state" if the dispatcher already moved the card.** Check `show <id>` to see actual state before retrying. If the card is already `done`, the work is done — no retry needed. Verified on control-plane item3 (final-integration card) and item4 (planner v2).
- **`promote --force` does NOT bypass parent-done checks** for cards in `todo` with running parents. It prints `Promoted <id> -> ready` and exits 0, but the next `show <id>` reports the same `todo` status. The dep engine reverts it on the next tick. The right path for self-blocked cards is `unblock + complete` (single id for the complete), not `promote --force`. Don't waste a turn on `promote --force` for stuck `todo` cards — it lies. Verified on control-plane item3.
- **A task assigned to a non-spawnable profile is silently skipped, not failed.** The dispatcher message `Skipped (non-spawnable assignee — terminal lane, OK): t_xxx` is the only signal. There is no error. The fix is `assign` to a spawnable profile (use `hermes kanban assignees` to find one), not `unblock` or `reclaim`.
- **Some legacy assignee names from old workstreams are not in the active pool.** `devcrew-developer`, `devcrew-backend`, `devcrew-integration`, `devcrew-architect` (and others) may appear with `ON DISK no` in the assignees list. Tasks assigned to them will never run. Reassign to a known-spawnable profile (typically `devcrew-backend-dev` for code work).
- **Do not mass-complete tasks you have not verified.** Only close tasks whose handoff is in front of you and whose claimed tests pass locally. If evidence is missing, leave the task `blocked` and report.
- **Reviewer / QA blocker findings can be transient.** A reviewer card may list "CRITICAL" blockers (indentation errors, contract mismatches, missing endpoints) that don't actually exist in the current working tree at the moment you check. Workers run in parallel, so the reviewer's snapshot is taken at a specific moment in time; the underlying worker may have already fixed the issue, or the file may not have been written yet. **Always verify the reviewer's findings against the actual working tree before acting on them** — run `git status --short`, `git diff -- <path>`, `grep <expected> <file>`, and the test suite. If the issue doesn't reproduce, treat the finding as transient: post a comment on the reviewer's card with the verification output, unblock with reason, and complete. The kanban-orchestrator skill covers this in "Stale QA fix cards (mid-write false positives)."
- **Final integrator cards can be false alarms about "no code to push."** When the build mandate is "verify what's in the working tree and ship," the integrator may self-block claiming all scratch workspaces were GC'd and the code is lost. **Verify directly first:** `git status --short` will show the uncommitted files if they're in the main working tree. If yes, do the orchestrator-side final integration yourself (filter junks → `git add` selective → `git commit` → `git push` → report SHA). Don't re-dispatch the integrator; don't try to "recover" scratch workspaces that don't exist. See "Orchestrator does the final integration" below for the full procedure.
- **Multi-id `reclaim` is invalid CLI.** `hermes kanban reclaim t_a t_b` errors with `unrecognized arguments: t_b`. Run `reclaim` per task. (Already covered above; restating because it's the most common misshapen invocation.)

## Why this happens

The doctrine is "workers must not self-block; they should ship and let the reviewer/QA lane pick up the work." This is now codified in `kanban-worker`'s "Coding task that needs human review (review-required)" section — workers should `kanban_complete` when their tests pass and the handoff is complete, not self-block. The v2.1.0 worker doctrine and the framework KANBAN_GUIDANCE now codify this behaviour; kanban-doctor handles the remaining cases — older workers, stale profile copies, or edge conditions that still produce a false self-block.

The non-spawnable-assignee pattern has a different cause: the workstream's creator (often the orchestrator or a worker) used a profile name that looks right but isn't registered as a worker in this session. This is a small but real footgun when the creator and the executor operate in different profile contexts.

The integrator false-alarm pattern (Pattern 3) is a side effect of dispatcher's workspace model: workers run in isolated scratch workspaces but **write their changes back to the main working tree** (via `git add`/`git mv` or by direct file writes), so the integrator's "no code to push" claim is based on inspecting the scratch paths, not the main tree. Verify with `git status --short` first.

The reviewer transient-findings pattern (Pattern 4) is the worker's-snapshot-of-mid-write state. Reviewers run while code is still being written, so their `git diff` / `grep` / `cat` operations can catch transient states that don't exist when the orchestrator checks a few minutes later. This is a known false-positive mode; the kanban-orchestrator's "Stale QA fix cards" pitfall already covers the general case. The same fix shape applies: verify before re-implementing.

## Why you should also design graphs that avoid the pattern

Recovery is a tax, not a fix. When you decompose a multi-lane workstream, design the dep graph so a code-lane self-block can't hold the whole chain. Two structural choices that reduce the recovery load:

- **Reviewer/QA/Integrator lanes should NOT be children of every code card.** They should be siblings of the code lanes (gated only on the original spec/research card, not on every implementation card). That way code-lane self-blocks don't cascade.
- **When in doubt, link in `parallel` mode for review/QA/integrator cards.** They need a snapshot of "all code is in", not "every parent card is `done`". If your kanban supports a per-link dep mode, set reviewer/QA to "parent `running` OR `done`". A pending feature for the kanban is per-link mode; until then, prefer the structural-graph fix (siblings, not children) over the per-link fix.

If the user reports "board not moving" repeatedly across runs, this is the design fix to push them toward — not just another round of doctor recovery.

**Reference build that applied this pattern correctly: control-plane item2 final build pass.** When the user invoked devcrew-run with a "build pass" prompt (workstream complete, mandate = commit + push + report SHA, "do NOT redo implementation work"), the architect produced a tight 3-card build where the integrator (D3, commit+push) was the PARENT of the reviewer (D1) and QA (D2) cards. D3 ran first, committed and pushed, and D1/D2 then validated the actual push — not just the working tree. This is the structural pattern that prevents code-lane self-blocks from holding up delivery: integration happens once, then the gates run on what's actually delivered. When decomposing a final-build run, force this shape: integrator is the root, reviewer and QA are children. Ship the commit, then validate.

## Related
- `references/pattern-2-non-spawnable-assignee.md` — non-spawnable profile recovery.
- `references/patterns-3-and-4-integrator-and-reviewer-false-alarms.md` — final-integration false alarm + reviewer transient findings.
- `references/junk-file-filter.md` — recurring junks workers leave in the working tree (verified across item2, item3, item4) and the orchestrator-side filter recipe for final-integration.
- `references/patterns-5-and-6-researcher-and-planner-stalls.md` — researcher/Planner 90-iteration stalls: file written but worker silent (P5) and planner stuck in a stale "research missing" loop (P6).

## Frequency signal

If you load this skill and the affected card is the *5th+* self-block on the same workstream, the design is wrong. Mention to the user:

- The dep graph still has code-lane self-blocks gating reviewer/QA/integrator lanes.
- The structural fix (siblings, not children, for reviewer/QA/integrator; or per-link `parallel` dep mode) is needed.
- Until then, every item2-style workstream will trigger this skill multiple times.

On control-plane item2 the skill fired 7 times (T3, T5, T4, T7, T9, t_65718678, t_75de7405) plus one non-spawnable-assignee recovery (the integrator's 3 cleanup follow-ups needed reassignment from `devcrew-developer` to `devcrew-backend-dev` before the dispatcher would touch them). On control-plane item3 the skill fired 16+ times (every implementation card self-blocked at least once; multiple fix-cards and bug-fix follow-ups also self-blocked). The repeated firing IS the design signal, not a transient issue. The structural fix (per-link dep mode with `parallel` for review/QA/integrator, OR siblings-not-children graph design, OR a new `review-handoff` status that doesn't gate downstream) is a separate project — track it in the kanban-workflow-fixes board.

## Quick reference: the 5-step shape

**Classify first (section 3b): if the block reason names a genuine human-only concern (security/credential, schema/migration, external-network action, concrete ambiguity), STOP — escalate via decision-brief and leave it blocked. The steps below are for false positives only.**

When you're under time pressure, the minimal recovery is:

1. `hermes kanban show <id>` — read the handoff
2. `uv run pytest -q` — verify locally
3. `hermes kanban reclaim <id>` (single id only)
4. `hermes kanban unblock <id> --reason "..."`
5. `~/.hermes/profiles/devos/scripts/safe-complete <id> <board>` (one id at a time; refuses cards with live review markers)

Then `hermes kanban dispatch` and watch `Spawned: N`. If the task was assigned to a non-spawnable profile, swap step 1 for `hermes kanban assign <id> <spawnable_profile>` and re-dispatch.

## Orchestrator does the final integration (Pattern 3)

Trigger: a final-build integrator card (typically T8 or T9 in a devcrew graph) self-blocks with a message like "no code to push — all scratch workspaces GC'd" or "implementation is missing from working tree." This is a real false alarm: the workers all wrote to the main repo working tree, not scratch workspaces (or the dispatcher merged into main).

**Don't try to "recover" the scratch workspaces. Don't re-dispatch the implementation tasks.** Verify directly and do the integration yourself.

Procedure (verified on control-plane item3, 2026-06-11):

1. `cd <repo-root> && git status --short` — capture uncommitted items. If you see a long list of `M` (modified) and `??` (untracked) files in the directories the workstream touched, the code is in the main tree.
2. Run the project's verification gate locally. For the control-plane monorepo:
   - `uv run pytest -q` — full Python test suite
   - `cd web && npm run typecheck` — TS clean check
   - `cd web && npm run build` — Next.js production build
   If any of these fail, create new fix cards for the actual failures and dispatch them. Don't paper over real test/build errors.
3. Identify junk files to exclude: editor tempfiles (e.g. `=23.1`), worker debug scripts (`_debug_*.py`), shared-memory SQLite sidecars (`file::memory:?cache=shared`), `web/tsconfig.tsbuildinfo`. Delete them with `rm` first, then `git add` the curated set:
   ```bash
   git add -A -- 'src/' 'tests/' 'web/src/' 'web/package.json' 'web/package-lock.json' 'web/next.config.ts' 'web/tsconfig.json' 'web/.env.local.example' 'pyproject.toml' 'uv.lock' '.env.local.example' 'deploy/'
   ```
4. Verify the staging set: `git status --short` — should be the right files only. Then commit:
   ```bash
   git commit -m "feat: <workstream-tag> — <one-line summary>
   - <bullet of major deliverable 1>
   - <bullet of major deliverable 2>
   - Tests: N pass (M new for this workstream, K retained)
   - Frontend: typecheck clean, build clean
   - Backward compat: <list of unchanged routes/contracts>"
   ```
5. `git push origin <branch>` — capture the SHA. `git log --oneline -3` to confirm.
6. Unblock + complete the integrator card with a comment containing the SHA, the test count, the file count, and the push result (complete via `safe-complete`, as in step 8).
7. Archive the original integrator card body if it referenced scratch-workspace paths; the orchestrator's final-integration procedure supersedes it.

This is the right call when: the workstream is "verify and ship" not "implement from scratch." The architecture is "do not redo implementation work" + the integrator's job is the final commit+push. If verification fails, you fall back to creating fix cards and re-dispatching; you don't try to commit a half-broken build.

## Reviewer/QA transient findings (Pattern 4)

A reviewer or QA worker running on a still-being-written codebase can file "CRITICAL" blocker findings that are actually snapshots of mid-write state. Common examples:
- "Indentation error in app.py lines 405–542" — the worker was looking at a transient state where the file was being written by another worker, not the final state.
- "Signup page sends `{name, slug}` but BFF expects `{orgName, email, teamName}`" — the architecture was redesigned after the reviewer read it; the new flow is correct.
- "Missing Stripe webhook endpoint" — the file exists at a different path or in a different BFF tree branch.

**Before acting on reviewer findings, verify the actual state.** Don't re-implement; verify.

```bash
# Does the indentation error reproduce?
uv run python -c "from <package>.app import app; print('OK')"

# Does the endpoint exist?
find <src> -name "*.ts" -path "*<endpoint-name>*"

# Does the page send the right shape?
grep -A2 "request.json" <bff-route-file>
```

If verification shows the issue is gone (or never existed), treat the finding as transient:
1. Post a comment on the reviewer's card explaining the verification: which command you ran, what it printed, why the finding doesn't apply.
2. Unblock the reviewer with reason: "Of 8 findings: 6 were transient (verified <commands>). 2 real findings filed as fix cards <t_a, t_b>."
3. Create fix cards for the real findings (if any), assigned to the appropriate dev profile.
4. Complete the reviewer with a summary that the 2 real findings are tracked (via `safe-complete`).

This combines the kanban-orchestrator's "Stale QA fix cards (mid-write false positives)" pitfall with the same false-positive-recovery shape as the worker self-block pattern: verify → unblock with reason → comment → complete.
