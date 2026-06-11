---
name: kanban-orchestrator
description: Decomposition playbook + anti-temptation rules for an orchestrator profile routing work through Kanban. The "don't do the work yourself" rule and the basic lifecycle are auto-injected into every kanban worker's system prompt; this skill is the deeper playbook when you're specifically playing the orchestrator role.
version: 3.1.0
platforms: [linux, macos, windows]
environments: [kanban]
metadata:
  hermes:
    tags: [kanban, multi-agent, orchestration, routing]
    related_skills: [kanban-worker]
---

# Kanban Orchestrator — Decomposition Playbook

> The **core worker lifecycle** (including the `kanban_create` fan-out pattern and the "decompose, don't execute" rule) is auto-injected into every kanban process via the `KANBAN_GUIDANCE` system-prompt block. This skill is the deeper playbook when you're an orchestrator profile whose whole job is routing.

## Profiles are user-configured — not a fixed roster

Hermes setups vary widely. Some users run a single profile that does everything; some run a small fleet (`docker-worker`, `cron-worker`); some run a curated specialist team they've named themselves. There is **no default specialist roster** — the orchestrator skill does not know what profiles exist on this machine.

Before fanning out, you must ground the decomposition in the profiles that actually exist. The dispatcher silently fails to spawn unknown assignee names — it doesn't autocorrect, doesn't suggest, doesn't fall back. So a card assigned to `researcher` on a setup that only has `docker-worker` just sits in `ready` forever.

**Step 0: discover available profiles before planning.**

Use one of these:

- `hermes profile list` — prints the table of profiles configured on this machine. Run it through your terminal tool if you have one; otherwise ask the user.
- `kanban_list(assignee="<some-name>")` — sanity-check a single name. Returns an empty list (rather than an error) for an unknown assignee, so this only confirms a name you're already considering.
- **Just ask the user.** "What profiles do you have set up?" is a fine first turn when the goal needs more than one specialist.

Cache the result in your working memory for the rest of the conversation. Re-asking every turn wastes a tool call.

## When to use the board (vs. just doing the work)

Create Kanban tasks when any of these are true:

1. **Multiple specialists are needed.** Research + analysis + writing is three profiles.
2. **The work should survive a crash or restart.** Long-running, recurring, or important.
3. **The user might want to interject.** Human-in-the-loop at any step.
4. **Multiple subtasks can run in parallel.** Fan-out for speed.
5. **Review / iteration is expected.** A reviewer profile loops on drafter output.
6. **The audit trail matters.** Board rows persist in SQLite forever.

If *none* of those apply — it's a small one-shot reasoning task — use `delegate_task` instead or answer the user directly.

## The anti-temptation rules

Your job description says "route, don't execute." The rules that enforce that:

- **Do not execute the work yourself.** Your restricted toolset usually doesn't even include terminal/file/code/web for implementation. If you find yourself "just fixing this quickly" — stop and create a task for the right specialist.
- **For any concrete task, create a Kanban task and assign it.** Every single time.
- **Split multi-lane requests before creating cards.** A user prompt can contain several independent workstreams. Extract those lanes first, then create one card per lane instead of bundling unrelated work into a single implementer card.
- **Run independent lanes in parallel.** If two cards do not need each other's output, leave them unlinked so the dispatcher can fan them out. Link only true data dependencies.
- **Never create dependent work as independent ready cards.** If a card must wait for another card, pass `parents=[...]` in the original `kanban_create` call. Do not create it first and link it later, and do not rely on prose like "wait for T1" inside the body.
- **If no specialist fits the available profiles, ask the user which profile to create or which existing profile to use.** Do not invent profile names; the dispatcher will silently drop unknown assignees.
- **Decompose, route, and summarize — that's the whole job.**

## Decomposition playbook

### Step 1 — Understand the goal

Ask clarifying questions if the goal is ambiguous. Cheap to ask; expensive to spawn the wrong fleet.

### Step 2 — Sketch the task graph

Before creating anything, draft the graph out loud (in your response to the user). Treat every concrete workstream as a candidate card:

1. Extract the lanes from the request.
2. Map each lane to one of the profiles you discovered in Step 0. If a lane doesn't fit any existing profile, ask the user which to use or create.
3. Decide whether each lane is independent or gated by another lane.
4. Create independent lanes as parallel cards with no parent links.
5. Create synthesis/review/integration cards with parent links to the lanes they depend on. A child created with unfinished parents starts in `todo`; the dispatcher promotes it to `ready` only after every parent is done.

Examples of prompts that should fan out (using placeholder profile names — substitute whatever exists on the user's setup):

- "Build an app" → one card to a design-oriented profile for product/UI direction, one or two cards to engineering profiles for implementation, plus a later integration/review card if the user has a reviewer profile.
- "Fix blockers and check model variants" → one implementation card for the blocker fixes plus one discovery/research card for config/source verification. A final reviewer card can depend on both.
- "Research docs and implement" → a docs-research card can run in parallel with a codebase-discovery card; implementation waits only if it truly needs those findings.
- "Analyze this screenshot and find the related code" → one card to a vision-capable profile for the visual analysis while another searches the codebase.

Words like "also," "finally," or "and" do not automatically imply a dependency. They often mean "make sure this is covered before reporting back." Only link tasks when one card cannot start until another card's output exists.

Show the graph to the user before creating cards. Let them correct it — including which actual profile name should own each lane.

### Step 3 — Create tasks and link

Use the profile names from Step 0. The example below uses placeholders `<profile-A>`, `<profile-B>`, `<profile-C>` — replace them with what the user actually has.

```python
t1 = kanban_create(
    title="research: Postgres cost vs current",
    assignee="<profile-A>",  # whichever profile handles research on this setup
    body="Compare estimated infrastructure costs, migration costs, and ongoing ops costs over a 3-year window. Sources: AWS/GCP pricing, team time estimates, current Postgres bills from peers.",
    tenant=os.environ.get("HERMES_TENANT"),
)["task_id"]

t2 = kanban_create(
    title="research: Postgres performance vs current",
    assignee="<profile-A>",  # same profile, run in parallel
    body="Compare query latency, throughput, and scaling characteristics at our expected data volume (~500GB, 10k QPS peak). Sources: benchmark papers, public case studies, pgbench results if easy.",
)["task_id"]

t3 = kanban_create(
    title="synthesize migration recommendation",
    assignee="<profile-B>",  # whichever profile does synthesis/analysis
    body="Read the findings from T1 (cost) and T2 (performance). Produce a 1-page recommendation with explicit trade-offs and a go/no-go call.",
    parents=[t1, t2],
)["task_id"]

t4 = kanban_create(
    title="draft decision memo",
    assignee="<profile-C>",  # whichever profile drafts user-facing prose
    body="Turn the analyst's recommendation into a 2-page memo for the CTO. Match the tone of previous decision memos in the team's knowledge base.",
    parents=[t3],
)["task_id"]
```

`parents=[...]` gates promotion — children stay in `todo` until every parent reaches `done`, then auto-promote to `ready`. No manual coordination needed; the dispatcher and dependency engine handle it.

If the task graph has dependencies, create the parent cards first, capture their returned ids, and include those ids in the child card's `parents` list during the child `kanban_create` call. Avoid creating all cards in parallel and linking them afterward; that creates a window where the dispatcher can claim a child before its inputs exist.

### Step 4 — Complete your own task

If you were spawned as a task yourself (e.g. a planner profile was assigned `T0: "investigate Postgres migration"`), mark it done with a summary of what you created:

```python
kanban_complete(
    summary="decomposed into T1-T4: 2 research lanes in parallel, 1 synthesis on their outputs, 1 prose draft on the recommendation",
    metadata={
        "task_graph": {
            "T1": {"assignee": "<profile-A>", "parents": []},
            "T2": {"assignee": "<profile-A>", "parents": []},
            "T3": {"assignee": "<profile-B>", "parents": ["T1", "T2"]},
            "T4": {"assignee": "<profile-C>", "parents": ["T3"]},
        },
    },
)
```

### Step 5 — Report back to the user

Tell them what you created in plain prose, naming the actual profiles you used:

> I've queued 4 tasks:
> - **T1** (`<profile-A>`): cost comparison
> - **T2** (`<profile-A>`): performance comparison, in parallel with T1
> - **T3** (`<profile-B>`): synthesizes T1 + T2 into a recommendation
> - **T4** (`<profile-C>`): turns T3 into a CTO memo
>
> The dispatcher will pick up T1 and T2 now. T3 starts when both finish. You'll get a gateway ping when T4 completes. Use the dashboard or `hermes kanban tail <id>` to follow along.

## Build-watching (4-min polls, stuck-worker detection, force-complete)

See `references/build-watching-playbook.md` for the full playbook.
Key corrections captured 2026-06-11 on control-plane item5:

- **Use 4-minute watch polls, not 60-second loops.** The user has
  corrected this multiple times ("polls are still not reduced to 4
  minute, please do it now"). 60-second loops burn orchestrator time
  on low-value noise; 4-minute polls give 8 polls in 30 min, enough
  to catch stalls while staying quiet.
- **A single "running" card for 18+ minutes with no `done` count
  increase is a stuck worker, not a slow one.** Don't trust
  `stats` alone. Check 4 signals: worker process alive (`ps`),
  workspace touched recently, code actually changed (`grep`),
  budget state (`hermes kanban runs`). If the worker is alive
  but the code is done, force-complete — don't wait for the
  90-iter budget.
- **Per-card `--skill` flag is the structural fix for researcher
  self-rejects.** `hermes kanban create` supports repeatable
  `--skill <name>` to force-load a skill into the worker's
  system prompt. Combined with a v2 body CRITICAL block, this
  is the A+C defense for grok-4.3 self-reject. `--skill` is
  system-prompt-level; the body CRITICAL is body-level; both
  layers are required.
- **Reassign orphaned assignees** (`devcrew-dev`, `devcrew-backend`,
  `devcrew-frontend`) to `devcrew-backend-dev` /
  `devcrew-frontend-dev`. These are non-spawnable in devos; the
  dispatcher silently skips tasks assigned to them.
- **Force-complete when code is done but worker stuck in a debug
  loop.** Different from a self-block (which kanban-doctor
  covers). When the code IS in the working tree and tests pass,
  but the worker is wasting iterations on a non-issue, reclaim +
  complete the card. Don't try to debug on the worker's behalf.
- **Worker test counts lie — always re-run the full suite yourself
  before force-completing.** Workers report the count of tests
  they ran (often just their own new file). The full suite can
  have more failures. Caught on item6-T10-fe-team-reports
  (t_2459ec26) — worker claimed "11/11 tests pass" but the full
  suite was 600/601 with 1 flaky test in a different file. The
  "passes manager roles" test in teams/[id]/page.test.tsx was
  broken because the worker used undefined variables
  (`okJson(sessionResponse)` without defining `sessionResponse`).
  Lesson: when force-completing a self-block, run the full
  `uv run pytest -q` (backend) AND `cd web && npm test -- --run`
  (frontend, vitest) and confirm 0 failures. If the worker said
  "X/X" but the full suite has different totals, the worker
  miscounted — recover via safe-complete override but document
  the discrepancy in a comment.
- **Terminal "hang" vs real pytest hang** — when a pytest run
  appears stuck at the same % for 5+ min via `tee` or a
  backgrounded `tail -f`, first check whether pytest itself is
  still running (`ps aux | grep pytest`). Hit on item6:
  proc_60211fc9cdb5 and proc_9bf2095ab245 both appeared "stuck
  at 83%" via tee, but proc_9a320aa6282a (the same `uv run pytest
  -v` command without tee buffering) completed in 3:17 with
  1212/1212 passing. The lesson: `tee`/tail-of-a-tail pipelines
  buffer output, so the percent display can lag. When in doubt,
  read the actual pytest output file (`/tmp/item6-*.log`) and
  check the process is alive. If pytest is genuinely stuck, run
  with `-v` to see the last test name and bisect.
- **Route conflict recovery (Next.js duplicate page resolution).**
  When a new worker creates a page at a path that already exists
  in the legacy tree (e.g., new `src/app/(app)/(admin)/teams/[id]/page.tsx`
  vs legacy `src/app/teams/[id]/page.tsx` — both resolve to
  `/teams/[id]`), Next.js build fails with "You cannot have two
  parallel pages that resolve to the same path." Three recovery
  options: (a) DELETE the legacy file (the user may block this
  as a destructive action against real code), (b) RENAME the
  new file with `.bak` extension (preserves code as evidence,
  removes from build, `mv` not `rm`), (c) MERGE the unique
  content from the new file into the legacy file and make the
  new file a thin redirect. Hit on item6-t_2459ec26: option (b)
  was the safest — `mv 'web/src/app/(app)/(admin)/teams/[id]/page.tsx'
  'web/src/app/(app)/(admin)/teams/[id]/page.tsx.bak'` resolved
  the conflict in one step, preserved the 401-line file for
  future reference, and `npm run build` passed. File a follow-up
  card to merge the new content into the legacy file later.
- **NEVER force-complete a card that contains unaddressed review
  findings.** Reviewer/QA cards that list blocking issues must be
  either: (a) addressed by completing the fix cards they created,
  (b) escalated to the user, or (c) explicitly archived with a
  documented decision. Closing a reviewer card without addressing
  the findings is a rubber-stamp and breaks the build. The user
  caught me doing this on item6-T14-reviewer (t_841c2622) which
  flagged 6 real issues — 3 of which were still in flight and 3
  of which were addressed by not-yet-started cards. The right
  move was to comment, leave it open, and let the fix cards run.
  Use this rule.
- **ALWAYS run `safe-complete` instead of `hermes kanban complete`
  directly.** The script ships in this skill at
  `scripts/safe-complete` (and is mirrored to
  `~/.hermes/profiles/devos/scripts/safe-complete` and
  `~/projects/mustCompany/must-dev-agents/dev-os/scripts/safe-complete`
  for direct invocation). It scans the card's recent comments for
  review-required markers (`review-required`, `blocking issues`,
  `needs eyes`, `design decision`, `Option A`, `Option B`, `needs
  human`, `rubber-stamp`, etc.) and refuses to complete the card if
  any are found. The script prints the offending comments so you
  can address them. Use this as a hard guard against the
  rubber-stamp anti-pattern (caught twice on item6: t_841c2622 and
  t_fd63cd4c — both were review-required handoffs that I
  force-completed by hand instead of using the guard). If
  `safe-complete` refuses, your options are: (a) address the
  findings, (b) escalate to the user, (c) explicitly archive with
  a documented decision, or (d) do the manual `hermes kanban
  complete` ONLY after posting a comment that documents why you're
  overriding the guard. The guard exists because I (the model)
  drift from skill text under pressure; the guard is
  documentation-as-code that enforces the rule for every call.
  See `references/rubber-stamp-recovery.md` for the full
  3-step recovery pattern and `references/structural-fixes-2026-06-11.md`
  for the 3-bug analysis that produced this rule.

## v2 research body (Layer 1) + auto-loaded skill (Layer 2) defense

For grok-4.3 researchers that self-reject with "Only kanban_*
tools are available" before starting, the A+C defense is now
shipped. **A** = v2 body template with CRITICAL tool-inventory
block (in `references/research-body-template.md`, v2 is the
default). **C** = `kanban-research-tasks` skill auto-loaded via
`--skill kanban-research-tasks` on the create call. Both layers
are required.

## Common patterns

**Fan-out + fan-in (research → synthesize):** N research-style cards with no parents, one synthesis card with all of them as parents.

**Parallel implementation + validation:** one implementer card makes the change while one explorer/researcher card verifies config, docs, or source mapping. A reviewer card can depend on both. Do not make the implementer own unrelated verification just because the user mentioned both in one sentence.

**Pipeline with gates:** `planner → implementer → reviewer`. Each stage's `parents=[previous_task]`. Reviewer blocks or completes; if reviewer blocks, the operator unblocks with feedback and respawns.

**Same-profile queue:** N tasks, all assigned to the same profile, no dependencies between them. Dispatcher serializes — that profile processes them in priority order, accumulating experience in its own memory.

**Human-in-the-loop:** Any task can `kanban_block()` to wait for input. Dispatcher respawns after `/unblock`. The comment thread carries the full context.

## Pitfalls

**Inventing profile names that don't exist.** The dispatcher silently fails to spawn unknown assignees — the card just sits in `ready` forever. Always assign to a profile from your Step 0 discovery; ask the user if you're unsure.

**Bundling independent lanes into one card.** If the user asks for two independent outcomes, create two cards. Example: "fix blockers and check model variants" is not one fixer task; create a fixer/engineer card for the fixes and an explorer/researcher card for the variant check, then optionally gate review on both.

**Over-linking because of wording.** "Finally check X" may still be parallel with implementation if X is static config, docs, or source discovery. Link it after implementation only when the check depends on the implementation result.

**Forgetting dependency links.** If the task graph says `research -> implement -> review`, do not create all tasks as independent ready cards. Use parent links so implement/review cannot run before their inputs exist.

**Reassignment vs. new task.** If a reviewer blocks with "needs changes," create a NEW task linked from the reviewer's task — don't re-run the same task with a stern look. The new task is assigned to the original implementer profile.

**Argument order for links.** `kanban_link(parent_id=..., child_id=...)` — parent first. Mixing them up demotes the wrong task to `todo`.

**Don't pre-create the whole graph if the shape depends on intermediate findings.** If T3's structure depends on what T1 and T2 find, let T3 exist as a "synthesize findings" task whose own first step is to read parent handoffs and plan the rest. Orchestrators can spawn orchestrators.

**Tenant inheritance.** If `HERMES_TENANT` is set in your env, pass `tenant=os.environ.get("HERMES_TENANT")` on every `kanban_create` call so child tasks stay in the same namespace.

## Goal-mode cards (persistent workers)

By default a dispatched worker gets **one shot** at its card: it does its work, calls `kanban_complete`/`kanban_block`, and exits. For open-ended cards where one turn rarely finishes the job, pass `goal_mode=True` to wrap that worker in a Ralph-style goal loop — the same engine behind the `/goal` slash command:

```python
kanban_create(
    title="Translate the full docs site to French",
    body="Acceptance: every page translated, no English left, links intact.",
    assignee="<translator-profile>",
    goal_mode=True,        # judge re-checks the card after each turn
    goal_max_turns=15,     # optional budget (default 20)
)["task_id"]
```

How it behaves:
- After each worker turn, an auxiliary judge evaluates the worker's response against the card's **title + body** (treated as the acceptance criteria).
- Not done + budget remains → the worker keeps going **in the same session** (full context retained — not a fresh respawn).
- Worker calls `kanban_complete`/`kanban_block` itself → loop stops, normal lifecycle.
- Budget exhausted without completion → the card is **blocked** for human review (sticky), never a silent exit.

When to use it: long, multi-step, or "keep going until X is true" cards. When NOT to: cheap one-shot cards (translation of a single string, a quick lookup) — the judge overhead isn't worth it, and the dispatcher's existing retry/circuit-breaker already handles transient worker failures.

Write the body as **explicit acceptance criteria** — the judge is only as good as the goal text. "Translate the README" is weaker than "Translate every section of the README to French; no English sentences remain."

## Recovering stuck workers

When a worker profile keeps crashing, hallucinating, or getting blocked by its own mistakes (usually: wrong model, missing skill, broken credential), the kanban dashboard flags the task with a ⚠ badge and opens a **Recovery** section in the drawer. Three primary actions:

1. **Reclaim** (or `hermes kanban reclaim <task_id>`) — abort the running worker immediately and reset the task to `ready`. The existing claim TTL is ~15 min; this is the fast path out.
2. **Reassign** (or `hermes kanban reassign <task_id> <new-profile> --reclaim`) — switch the task to a different profile (one that exists on this setup) and let the dispatcher pick it up with a fresh worker.
3. **Change profile model** — the dashboard prints a copy-paste hint for `hermes -p <profile> model` since profile config lives on disk; edit it in a terminal, then Reclaim to retry with the new model.

Hallucination warnings appear on tasks where a worker's `kanban_complete(created_cards=[...])` claim included card ids that don't exist or weren't created by the worker's profile (the gate blocks the completion), or where the free-form summary references `t_<hex>` ids that don't resolve (advisory prose scan, non-blocking). Both produce audit events that persist even after recovery actions — the trail stays for debugging.

## How to use this skill's resources

This skill ships three reference files and one script. Read them in the
order they appear in the pitfalls/anti-temptation rules above, or jump
straight to one when you need it.

- `references/build-watching-playbook.md` — 4-min poll cadence, stuck-worker detection, when to force-complete.
- `references/rubber-stamp-recovery.md` — the 3-step pattern for closing review-required handoffs without rubber-stamping. Read this BEFORE you use `hermes kanban complete` on any reviewer/QA card.
- `references/structural-fixes-2026-06-11.md` — the 3-bug analysis that produced the safe-complete guard.
- `references/item6-build-learnings.md` — three concrete patterns from the item6 build: worker test counts lie, terminal "hang" vs real pytest hang (tee buffers progress), Next.js route conflict recovery (mv to .bak).
- `references/research-body-template.md` — the v2 research body template with the CRITICAL tool-inventory block (default for new research cards).
- `scripts/safe-complete` — the runnable guard for the rubber-stamp rule. Use this INSTEAD of `hermes kanban complete` for every card. It scans the card's recent comments for review-required markers and refuses to complete if any are found.
