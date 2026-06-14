---
name: kanban-worker
description: Pitfalls, examples, and edge cases for Hermes Kanban workers. The lifecycle itself is auto-injected into every worker's system prompt as KANBAN_GUIDANCE (from agent/prompt_builder.py); this skill is what you load when you want deeper detail on specific scenarios.
version: 2.6.0
platforms: [linux, macos, windows]
environments: [kanban]
metadata:
  hermes:
    tags: [kanban, multi-agent, collaboration, workflow, pitfalls]
    related_skills: [kanban-orchestrator]
---
<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. This file is a repo seed; edit it HERE, never in ~/.hermes/profiles/ (installers overwrite profile copies). -->

# Kanban Worker — Pitfalls and Examples

> You're seeing this skill because the Hermes Kanban dispatcher spawned you as a worker with `--skills kanban-worker` — it's loaded automatically for every dispatched worker. The **lifecycle** (6 steps: orient → work → heartbeat → block/complete) also lives in the `KANBAN_GUIDANCE` block that's auto-injected into your system prompt. This skill is the deeper detail: good handoff shapes, retry diagnostics, edge cases.

## Workspace handling

Your workspace kind determines how you should behave inside `$HERMES_KANBAN_WORKSPACE`:

| Kind | What it is | How to work |
|---|---|---|
| `scratch` | Fresh tmp dir, yours alone | Read/write freely; it gets GC'd when the task is archived. |
| `dir:<path>` | Shared persistent directory | Other runs will read what you write. Treat it like long-lived state. Path is guaranteed absolute (the kernel rejects relative paths). |
| `worktree` | Git worktree at the resolved path | If `.git` doesn't exist, run `git worktree add <path> ${HERMES_KANBAN_BRANCH:-wt/$HERMES_KANBAN_TASK}` from the main repo first, then cd and work normally. Commit work here. |

## Tenant isolation

If `$HERMES_TENANT` is set, the task belongs to a tenant namespace. When reading or writing persistent memory, prefix memory entries with the tenant so context doesn't leak across tenants:

- Good: `business-a: Acme is our biggest customer`
- Bad (leaks): `Acme is our biggest customer`

## Good summary + metadata shapes

The `kanban_complete(summary=..., metadata=...)` handoff is how downstream workers read what you did. Patterns that work:

**Coding task:**
```python
kanban_complete(
    summary="shipped rate limiter — token bucket, keys on user_id with IP fallback, 14 tests pass",
    metadata={
        "changed_files": ["rate_limiter.py", "tests/test_rate_limiter.py"],
        "tests_run": 14,
        "tests_passed": 14,
        "decisions": ["user_id primary, IP fallback for unauthenticated requests"],
    },
)
```

**Coding task that needs human review (review-required) — USE SPARINGLY:**

The orchestrator has a downstream `devcrew-reviewer` lane (the T14-style "review all of item N" card) whose job is to catch issues. Self-blocking with `review-required` on every code card creates a rubber-stamp anti-pattern: the orchestrator force-completes 16+ "review-required" cards per build because the work is genuinely done and the downstream reviewer is the real review lane. **Default behavior is to `complete` with evidence, not to `block`.**

The pipeline is human-gated exactly once, at the plan (`dev-os/team.yaml`).
A `review-required` block is an **escalation to the orchestrator** for one of
the four concerns below — not a review gate. The reviewer and QA lanes
downstream are the review path (card ids like "T14" you may see in examples
are labels from past builds, not fixed numbers).

**Default: complete with evidence.** For the common case (tests pass, change is small/medium, no security/correctness cliff), call `kanban_complete` with a structured summary. The T14 reviewer will catch any real issues via the artifact. The orchestrator's force-complete loop goes away.

**Block with `review-required` ONLY for genuine human-only concerns:**
- Security or credential changes (auth tokens, secret rotation, RBAC matrix)
- Schema or migration changes that can't be easily rolled back
- External-network actions (deploys, pushes, provisioning)
- A genuine ambiguity in the task body you couldn't resolve

For these: drop the structured metadata (changed files, test counts, diff/PR url) into a comment first, since `kanban_block` only carries the human-readable reason — comments are the durable annotation channel. Then block with `reason` prefixed `review-required: `.

```python
import json

kanban_comment(
    body="review-required handoff:\n" + json.dumps({
        "changed_files": ["rate_limiter.py", "tests/test_rate_limiter.py"],
        "tests_run": 14,
        "tests_passed": 14,
        "diff_path": "/path/to/worktree",  # or PR url if pushed
        "decisions": ["user_id primary, IP fallback for unauthenticated requests"],
        "human_concern": "user_id vs IP precedence choice affects abuse detection",  # NEW: spell out the genuine concern
    }, indent=2),
)
kanban_block(
    reason="review-required: rate limiter shipped, 14/14 tests pass — user_id vs IP precedence affects abuse detection, need human eyes on the policy choice",
)
```

**Decision rule:** If you'd be comfortable merging the change yourself right now without any other human in the loop, `complete` it. If not, `block` it AND spell out the concrete human-only concern in the reason string. "Needs review" without a concrete concern is a rubber-stamp — don't.

Use `kanban_complete` for: code changes with tests passing, one-line typo fixes, docs changes, research tasks where the artifact IS the writeup, and any work where the T14 reviewer will be the real review lane.

**Research task:**
```python
kanban_complete(
    summary="3 competing libraries reviewed; vLLM wins on throughput, SGLang on latency, Tensorrt-LLM on memory efficiency",
    metadata={
        "sources_read": 12,
        "recommendation": "vLLM",
        "benchmarks": {"vllm": 1.0, "sglang": 0.87, "trtllm": 0.72},
    },
)
```

**Review task:**
```python
kanban_complete(
    summary="reviewed PR #123; 2 blocking issues found (SQL injection in /search, missing CSRF on /settings)",
    metadata={
        "pr_number": 123,
        "findings": [
            {"severity": "critical", "file": "api/search.py", "line": 42, "issue": "raw SQL concat"},
            {"severity": "high", "file": "api/settings.py", "issue": "missing CSRF middleware"},
        ],
        "approved": False,
    },
)
```

Shape `metadata` so downstream parsers (reviewers, aggregators, schedulers) can use it without re-reading your prose.

## Evidence artifact — mandatory for verification cards

If your card is a review, QA, or integration card — or ANY card whose summary
claims tests ran or passed, in any phrasing ("tests pass", "suite green",
"27/27", "verified working") — write the proof to disk BEFORE calling
`kanban_complete`:

1. Capture, don't transcribe: run your verification through `tee` so the log is
   the real output, e.g.
   `pytest -q 2>&1 | tee "$HERMES_KANBAN_WORKSPACE/test_run.$HERMES_KANBAN_TASK.log"; echo "exit=$?" >> ...same file`.
   The file MUST contain the exact command line(s), the full unedited output,
   and the exit code line. The task-id suffix prevents collisions on shared
   `dir:` workspaces and stops a worker citing a stale log another card wrote.
2. Pass the resolved absolute path in the `artifacts` field of
   `kanban_complete(artifacts=["/abs/path/to/test_run.<task>.log"])` AND cite
   it in your completion summary (resolve the variables — downstream readers
   run in different workspaces).
3. Mirror a digest into a `kanban_comment` (last ~10 lines + the exit line):
   `scratch` workspaces are GC'd at archive, so the comment is the durable copy
   an auditor can still read after cleanup.

**The kernel enforces this for QA and integrator profiles** (item 10 T-F,
shipped): `kanban_complete` from a profile whose name contains `qa` or
`integrator` is REJECTED unless `artifacts` lists at least one existing,
non-empty file. Don't fight the gate — produce the tee'd log and pass its
path. For reviewer and other cards the gate doesn't fire, but the doctrine is
identical and the orchestrator audits: a verification summary with no evidence
artifact, a 0-byte artifact, or an artifact with no command/exit lines is
unverified and will be treated as false until proven. A hand-typed
"1987 passed" summary file is fabrication, and the parent-commit re-run rule
from Classify-and-file applies to auditing it. (This rule exists because the
item 9 build shipped a 0-byte QA_VERDICT.md while the summary claimed a full
pass.)

## Pre-completion hygiene (impl workers producing a branch/PR)

If your card produced code on a branch that will become a PR, run the release-harness
hygiene gate on your workspace BEFORE `kanban_complete` — it is the source-level stop
for the "git add -A pushed 18 debris files into a merged PR" class:

```bash
python3 -m release_harness.pr_hygiene_gate "$HERMES_KANBAN_WORKSPACE" \
  --base origin/main --evidence "$HERMES_KANBAN_WORKSPACE/test_run.$HERMES_KANBAN_TASK.log"
```

- exit 0 → clean; proceed to complete.
- exit 1 → a tracked-but-gitignored debris file, a missing/empty evidence log, or a
  stale base. Fix it (untrack the debris, attach the real test log, rebase) before
  completing — do not ship the debris.
- exit 2 → the gate could not run; escalate via `kanban_block`, never treat as pass.

(Where `release_harness` isn't on the path, the principle still holds: no
gitignored/debris paths tracked in your branch, and a real tee'd evidence log per the
evidence-artifact rule above.)

## Claiming cards you actually created

If your run produced new kanban tasks (via `kanban_create`), pass the ids in `created_cards` on `kanban_complete`. The kernel verifies each id exists and was created by your profile; any phantom id blocks the completion with an error listing what went wrong, and the rejected attempt is permanently recorded on the task's event log. **Only list ids you captured from a successful `kanban_create` return value — never invent ids from prose, never paste ids from earlier runs, never claim cards another worker created.**

```python
# GOOD — capture return values, then claim them.
c1 = kanban_create(title="remediate SQL injection", assignee="security-worker")
c2 = kanban_create(title="fix CSRF middleware", assignee="web-worker")

kanban_complete(
    summary="Review done; spawned remediations for both findings.",
    metadata={"pr_number": 123, "approved": False},
    created_cards=[c1["task_id"], c2["task_id"]],
)
```

```python
# BAD — claiming ids you don't have captured return values for.
kanban_complete(
    summary="Created remediation cards t_a1b2c3d4, t_deadbeef",  # hallucinated
    created_cards=["t_a1b2c3d4", "t_deadbeef"],                   # → gate rejects
)
```

If a `kanban_create` call fails (exception, tool_error), the card was NOT created — do not include a phantom id for it. Retry the create, or omit the id and mention the failure in your summary. The prose-scan pass also catches `t_<hex>` references in your free-form summary that don't resolve; these don't block the completion but show up as advisory warnings on the task in the dashboard.

## Block reasons that get answered fast

Bad: `"stuck"` — the human has no context.

Good: one sentence naming the specific decision you need. Leave longer context as a comment instead.

```python
kanban_comment(
    task_id=os.environ["HERMES_KANBAN_TASK"],
    body="Full context: I have user IPs from Cloudflare headers but some users are behind NATs with thousands of peers. Keying on IP alone causes false positives.",
)
kanban_block(reason="Rate limit key choice: IP (simple, NAT-unsafe) or user_id (requires auth, skips anonymous endpoints)?")
```

The block message is what appears in the dashboard / gateway notifier. The comment is the deeper context a human reads when they open the task.

## Classify and file — never bare-block

When verification (review / QA / integration) finds a failing test or defect,
classify it BEFORE doing anything else. Three classes, three routes:

1. **In-scope** — introduced by this card's changes. Fix it in this card,
   re-run the failing test, attach the pass output as evidence.
2. **Pre-existing** — present before this card's changes. File a fix card on
   the same board (payload below), comment this card with the fix-card ID,
   and CONTINUE. A pre-existing defect never blocks this card.
3. **Cross-item** — architectural, spans items. File a roadmap follow-up,
   link it, continue.

**Evidence rule (mandatory for class 2):** "pre-existing" is proven, not
asserted. Re-run the exact failing test against the pre-card state (stash
this card's diff or check out the parent commit) and paste BOTH outputs —
failing identically before and after — on the fix card. If it passes on the
pre-card state, it is class 1: yours. No evidence, no class-2 claim.

**Fix-card minimum payload:** failing test name(s), error excerpt (≤20
lines), suspected file:line, the before/after evidence, link to this card.

**Fix-card assignee rule — copy, never invent.** Assign fix cards ONLY to a
profile name you copied verbatim from an existing card on this board
(`kanban_list` and read the `assignee` column). Never invent, abbreviate, or
"correct" a profile name — the dispatcher silently skips cards assigned to
non-spawnable names; they sit open forever with zero runs and no error.
Four real incidents of this across two builds: `devcrew-developer`,
`devos-backend`, `devos-*` spec names, `events-worker` — all phantom, all
silent.

**Fix cards must gate the integrator.** If an integrator card exists
downstream and is not yet done, your fix card has to land before integration
or the item ships unfixed. You can't edit the integrator's parent set, so do
the two things you can: (1) post a comment ON the integrator card naming your
fix-card id ("fix card t_xxx must land before this integrates"), and (2) list
the fix-card ids in your own completion via `created_cards` so the
orchestrator sees them and expands the integrator's parents. (Verified
failure: the item-10 build's QA filed two fix cards after the integrator had
already promoted — the fixes ran but were never integrated until the operator
hand-landed them.)

**The only legitimate self-block from verification work:** a class-1 failure
you cannot fix within your turn budget — block WITH the classification table
and evidence attached. (The four genuine human-only concerns above —
security/credential, schema/migration, external-network actions, task
ambiguity — remain valid block reasons at handoff, with the concrete concern
named; this rule governs verification findings, not those escalations.)
A bare self-block (no classification, no evidence, no fix-card IDs) is a
protocol violation.

**Why this exists:** the worker-claim-lies pattern (item 6+item 7+item 9
builds) showed that reviewers/QA/integrators can fabricate self-blocks for
issues they did not actually verify. The classify-and-file doctrine makes the
worker do the verification work (the parent-commit re-run) and the
classification is the receipt.

## Integrator: sweep for open fix cards before completing

If you are the integrator, your completion asserts "everything in this item is
integrated" — so before `kanban_complete`, sweep the board: `kanban_list` and
look for open (todo/ready/running/blocked) fix cards that reference your item
or name your card in their body/comments, and read your own comment thread for
"fix card t_xxx must land" notes from the gates. If any exist, do NOT
complete. Comment which cards you're waiting on; if they're still running,
that comment plus a heartbeat is enough — the orchestrator will re-dispatch
you after they land. Completing past an open fix card ships the defect with a
green board.

## Kanban-on-kanban test isolation

If your card's work involves creating kanban tasks AS TEST FIXTURES (stress
tests, acceptance tests of kanban features themselves), never create them on
the live board you were dispatched from. A live board is production state for
every other profile — fixture cards trigger real dispatches to real workers
and leak debris the operator has to archive by hand. Instead:

- pytest fixtures: point the kanban DB at a temp path (`tmp_path`) — never
  `~/.hermes/kanban`.
- Live-process fixtures (CLI or tools): create a scratch board first
  (`hermes kanban boards create test-$HERMES_KANBAN_TASK`) and pass
  `--board test-$HERMES_KANBAN_TASK` on every fixture command; assign
  fixtures to a non-dispatchable placeholder only on that scratch board.
- Cleanup is part of the test: archive every fixture card (pass or fail)
  before you complete.

(The item-10 build's stress test ran 17 concurrent writer fixtures against the
LIVE production board. It happened to survive — that is luck, not isolation.)

## Heartbeats worth sending

Good heartbeats name progress: `"epoch 12/50, loss 0.31"`, `"scanned 1.2M/2.4M rows"`, `"uploaded 47/120 videos"`.

Bad heartbeats: `"still working"`, empty notes, sub-second intervals. Every few minutes max; skip entirely for tasks under ~2 minutes.

## Retry scenarios

If you open the task and `kanban_show` returns `runs: [...]` with one or more closed runs, you're a retry. The prior runs' `outcome` / `summary` / `error` tell you what didn't work. Don't repeat that path.

**If the comment thread contains a `RETRY GUIDANCE` comment from the
orchestrator, treat its inventory as ground truth.** It lists what the prior
run already landed (git status/log of the workspace) and which acceptance
criteria remain. Do not re-explore, re-read the whole codebase, or re-derive
the plan — start from the DONE/REMAINING lists, finish only REMAINING, commit
early. Re-exploring is what exhausted the previous run's budget.

Typical retry diagnostics:

- `outcome: "timed_out"` — two distinct causes; read the run's `error` string to tell them apart. (a) Wall-clock: the attempt hit `max_runtime_seconds` — chunk or shorten the work. (b) Iteration budget: `error` says "Iteration budget exhausted (N/N)" — the worker ran out of `max_turns`, not time; re-planning the same breadth will exhaust again, so narrow scope or inline the prior attempt's findings instead of re-gathering.
- `outcome: "crashed"` — OOM or segfault. Reduce memory footprint.
- `outcome: "spawn_failed"` + `error: "..."` — usually a profile config issue (missing credential, bad PATH). Ask the human via `kanban_block` instead of retrying blindly.
- `outcome: "reclaimed"` + `summary: "task archived..."` — operator archived the task out from under the previous run; you probably shouldn't be running at all, check status carefully.
- `outcome: "blocked"` — a previous attempt blocked; the unblock comment should be in the thread by now.

## Notification routing

You can configure the gateway to receive cross-profile Kanban task notifications by adding `notification_sources` to `~/.hermes/config.yaml`.
- `notification_sources: ['*']` accepts subscriptions from all profiles.
- `notification_sources: ['default', 'zilor-ppt']` or `"default,zilor-ppt"` restricts subscriptions to specified profiles.
- Omitting the key keeps the default behavior (profile isolation).

## Do NOT

- Call `delegate_task` as a substitute for `kanban_create`. `delegate_task` is for short reasoning subtasks inside YOUR run; `kanban_create` is for cross-agent handoffs that outlive one API loop.
- Call `clarify` to ask the human a question. You are running headless — there is no live user to answer. The call will time out (default ~120s) and the task will sit silently in `running` with no signal that it needs input. Use `kanban_comment` (context) + `kanban_block(reason=...)` (decision needed) instead — the task surfaces on the board as blocked, the operator sees it, unblocks with their answer in a comment, and you respawn with the thread.
- Modify files outside `$HERMES_KANBAN_WORKSPACE` unless the task body says to.
- Create follow-up tasks assigned to yourself — assign to the right specialist.
- Complete a task you didn't actually finish. Block it instead.

## Pitfalls

**Task state can change between dispatch and your startup.** Between when the dispatcher claimed and when your process actually booted, the task may have been blocked, reassigned, or archived. Always `kanban_show` first. If it reports `blocked` or `archived`, stop — you shouldn't be running.

**Workspace may have stale artifacts.** Especially `dir:` and `worktree` workspaces can have files from previous runs. Read the comment thread — it usually explains why you're running again and what state the workspace is in.

**Don't rely on the CLI when the guidance is available.** The `kanban_*` tools work across all terminal backends (Docker, Modal, SSH). `hermes kanban <verb>` from your terminal tool will fail in containerized backends because the CLI isn't installed there. When in doubt, use the tool.

## CLI fallback (for scripting)

Every tool has a CLI equivalent for human operators and scripts:
- `kanban_show` ↔ `hermes kanban show <id> --json`
- `kanban_complete` ↔ `hermes kanban complete <id> --summary "..." --metadata '{...}'`
- `kanban_block` ↔ `hermes kanban block <id> "reason"`
- `kanban_create` ↔ `hermes kanban create "title" --assignee <profile> [--parent <id>]`
- etc.

Use the tools from inside an agent; the CLI exists for the human at the terminal.
