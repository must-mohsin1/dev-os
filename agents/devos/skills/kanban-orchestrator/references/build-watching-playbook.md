# Build-watching playbook

Watching a `devcrew-run` build to completion is the orchestrator's main
active-work loop. The user expects proactive monitoring: catch stalls
before they ask, recover stuck cards without being prompted, and
report the SHA + test count when the build lands.

This playbook captures the verified patterns from control-plane
item2 / item3 / item4 / item5 builds (2026-06-09 to 2026-06-11).

## 1. Watch cadence (4-minute polls, not 60-second)

The user explicitly called this out as a recurring miss: "polls are
still not reduced to 4 minute, please do it now." Use 4-minute
sleeps, NOT 60-second loops. A 4-min cadence gives 8 polls in
~30 min, which is enough granularity to catch stalls while leaving
the orchestrator free to do other work between polls.

**Right:**
```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 240
  echo "=== poll $i ==="
  HERMES_KANBAN_BOARD=… DEVCREW_BOARD=… hermes kanban stats \
    | grep -E "running|blocked|done |todo|ready" | head -3
done
```

**Wrong:** `for i in 1..N; do sleep 60; …; done` — this is the 60-second
loop the user had to correct multiple times. Each `sleep 60` only buys
one minute; over a 30-min build that's 30 polls of low-value noise.

If you need finer granularity for a SPECIFIC stuck card, use a
single `sleep 60` once — but the default watch cadence is 4 min.

## 2. Active stuck-worker detection (don't trust "running" alone)

A single card sitting in `running` for 18+ minutes with no `done`
count increase is a stuck worker, not a slow one. The user has
called this out twice: "many tickets are stopped with no worker. this
was your task to keep an eye on the workflow, and again you missed it."

Detection signals — all four should be checked when a card stays
`running` past the expected time:

```bash
# 1. Is the worker process still alive?
ps aux | grep -E "devcrew-backend|devcrew-frontend" | grep -v grep

# 2. Has the workspace been touched recently?
ls -la ~/.hermes/kanban/boards/<board>/workspaces/<task_id>/
# (look for files modified in the last 5 min — heartbeat)

# 3. Has the worker actually changed code, or just been spinning?
cd <repo> && grep <expected-pattern> src/<expected-file>

# 4. How many runs has the task gone through? (budget check)
hermes kanban runs <task_id> 2>&1 | tail -10
# If the same task has 2 runs and the latest is at 30+ min, the
# worker is stuck in a debug loop and will likely time out.
```

If signs 1 + 2 are alive but 3 shows "code is done" + 4 shows
"approaching 90-iter budget," the worker is in a debug loop on a
non-issue. **Force-complete** (see §4).

## 3. Per-task `--skill` flag for structural defenses

`hermes kanban create` supports `--skill <name>` to force-load a
named skill into the worker's system prompt. The skill auto-loads
on every dispatch of that card. This is the **structural** fix for
researcher/worker self-rejects (gated by `HERMES_KANBAN_TASK`
env, the same mechanism the dispatcher uses for `kanban-worker`).

```bash
hermes kanban create "Item-N-research: <topic>" \
  --assignee devos-researcher \
  --body "$(cat /tmp/cp/item-N-research-body.md)" \
  --skill kanban-research-tasks
```

**The body CRITICAL block is body-level; the `--skill` flag is
system-prompt-level.** Both layers are required for grok-4.3
reliability — the model self-rejects on tool inventory unless
the assertion appears at BOTH levels. See the parent SKILL.md
"Researcher 'Missing tools' failure" pitfall for the diagnosis.

**Note on flags:** `hermes kanban create` does NOT support
`--enabled-toolsets` — toolsets come from the profile config
(`toolsets: [hermes-cli]` or explicit names). The only per-card
force-load mechanism is the repeatable `--skill` flag.

## 4. Force-complete when code is done but worker stuck

The kanban-doctor skill covers false-positive self-blocks (worker
explicitly sets `blocked` with reason `review-required`). This
playbook covers a different shape: worker is `running`, the code
IS in the working tree, but the worker is wasting iterations
debugging a non-issue (307→404 redirect, test fixture mismatch,
cosmetic flake, etc.).

Recipe (verified on item5 T2-routes, 2026-06-11):

1. Confirm the code is in. `grep` for the expected pattern in
   the target file. Run the test file (or its scope) and confirm
   the relevant tests pass.
2. Read the worker's workspace for the debug context. The
   workspace often contains a `_debug_*.py` or `debug_*.py` script
   the worker was iterating on.
3. Post a comment explaining the force-complete. Include the
   evidence (grep + test count).
4. `hermes kanban reclaim <task_id>` (single id, see kanban-doctor
   pitfall).
5. `hermes kanban complete <task_id>` — completes the card,
   promoting downstream tasks (BFF routes, dependent tests, etc.)
   to `ready`.
6. `hermes kanban dispatch` — spawn the newly-promoted tasks.

**Don't** try to debug on the worker's behalf. **Don't** push a
new body and re-dispatch — that wastes another 90-iter budget.
The worker's done; close it.

## 5. Background tasks with `notify_on_complete`

Long-running verifications (full test suite = 3-5 min) should run
in a background terminal with `notify_on_complete=true`. The
default `process wait` is clamped to 60s, so it's useless for
build watching. The right pattern:

```bash
terminal --background true --notify_on_complete true --timeout 600 \
  -- uv run pytest -q 2>&1 | tee /tmp/test-run.log
```

Then `process(action="wait", timeout=60)` returns early when the
test suite finishes. Continue with other work (kanban recovery,
next fix card) while the test runs.

The terminal tool returns a `session_id` you can poll with
`process(action="poll")` if you need to check progress without
waiting for the full timeout.

## 6. Reassign orphaned assignees (Pattern 2 recovery)

Workers sometimes create fix cards with `assignee=devcrew-dev`,
`devcrew-backend`, `devcrew-frontend`, or `devcrew-integration` —
all of which are non-spawnable in devos. The dispatcher reports
`Skipped (non-spawnable assignee — terminal lane, OK)` and the
card sits in `ready` forever.

Recovery:

```bash
for tid in <list>; do
  hermes kanban assign $tid devcrew-backend-dev
done
hermes kanban dispatch
# Verify: Spawned: N > 0
```

For frontend-style fix cards, use `devcrew-frontend-dev`. For
deploy/integration work, `devcrew-backend-dev` is the catch-all
(the devos-planner / devos-researcher don't accept
implementation cards).

## 7. Per-card verification before force-completing

Don't force-complete based on stats alone. Two verifications:

- **Code in the working tree:** `grep <expected> <path>` or
  `git diff -- <path> | head` — confirms the worker actually
  wrote something.
- **Tests pass for the worker's scope:** `uv run pytest
  tests/<worker-touched>.py -q` — confirms the worker's claim.

If either fails, the worker may not actually be done. Either let
it run (if there's budget left) or create a fix card for the
real gap (if it's exhausted).

## When to escalate to the user

Post a short status when ANY of these happen:
- 5+ tasks self-blocked on the same workstream (design signal —
  per kanban-doctor "Frequency signal" section).
- A single task has been force-completed 2+ times across
  different runs (the workstream shape is wrong).
- The build has gone 2+ hours past expected end with no
  integrator activity.
- The user says "are you still watching this?" — that's a
  meta-signal to acknowledge and resume.

Don't post status on every poll. The watch loop is silent; the
report fires on events (recoveries, force-completes, build
complete).
