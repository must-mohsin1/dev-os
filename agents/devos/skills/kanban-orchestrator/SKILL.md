---
name: kanban-orchestrator
description: Decomposition playbook + anti-temptation rules for an orchestrator profile routing work through Kanban. The "don't do the work yourself" rule and the basic lifecycle are auto-injected into every kanban worker's system prompt; this skill is the deeper playbook when you're specifically playing the orchestrator role.
version: 3.5.0
platforms: [linux, macos, windows]
environments: [kanban]
metadata:
  hermes:
    tags: [kanban, multi-agent, orchestration, routing]
    related_skills: [kanban-worker]
---
<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. -->

# Kanban Orchestrator — Decomposition Playbook

> The **core worker lifecycle** (including the `kanban_create` fan-out pattern and the "decompose, don't execute" rule) is auto-injected into every kanban process via the `KANBAN_GUIDANCE` system-prompt block. This skill is the deeper playbook when you're an orchestrator profile whose whole job is routing.

> **Doctrine hierarchy:** this skill derives from the team manifests —
> `dev-os/team.yaml` + `DEVOS.md` (pipeline; ONE human gate, at the plan) and
> `hermes-devcrew/team.yaml` (build topology: parallel workers → reviewer ∥ QA →
> integrator). On any conflict between this text and the manifests, the
> manifests win.

## References
- `references/research-body-template.md` — copy-and-modify templates for research task bodies; v2 (default; includes the CRITICAL tool-inventory assertion block) and v1 (legacy opt-in for non-grok models).
- `references/build-watching-playbook.md` — 4-minute poll cadence, stuck-worker detection signals, force-complete decision tree.
- `references/structural-fixes-2026-06-11.md` — the 3-bug analysis (self-block doctrine, reviewer dep graph, rubber-stamp) behind the v2.1.0 worker doctrine and the safe-complete guard.
- `references/rubber-stamp-recovery.md` — the pattern for closing review-required handoffs without rubber-stamping.

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

### Step 0.5 — Pick and PIN the project board FIRST (CLI orchestrators)

**Before creating a single card, decide which board the project lives on and pin it.** Operators organize one board per project and *will* correct you if cards land on a leftover board from another project (this happened: "you created task in wrong board, you should use control plane board"). Board choice is not cosmetic.

For a new project: `hermes kanban boards create <slug>`, then pass `--board <slug>` (the flag goes **between `kanban` and the subcommand**) on **every** create/show/complete/unblock — `boards switch` does NOT persist across separate terminal calls. Do not start creating cards and "sort out the board later" — there is no move-between-boards command, so a misplaced graph means archiving + recreating. See the CLI footguns section below before your first `create`.

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

## Common patterns

**Fan-out + fan-in (research → synthesize):** N research-style cards with no parents, one synthesis card with all of them as parents.

**Parallel implementation + validation:** one implementer card makes the change while one explorer/researcher card verifies config, docs, or source mapping. A reviewer card can depend on both. Do not make the implementer own unrelated verification just because the user mentioned both in one sentence.

**Pipeline with gates:** `planner → implementer → reviewer`. Each stage's `parents=[previous_task]`. Reviewer blocks or completes; if reviewer blocks, the operator unblocks with feedback and respawns.

**Same-profile queue:** N tasks, all assigned to the same profile, no dependencies between them. Dispatcher serializes — that profile processes them in priority order, accumulating experience in its own memory.

**Human-in-the-loop:** Any task can `kanban_block()` to wait for input. Dispatcher respawns after `/unblock`. The comment thread carries the full context.

## v2 research body (Layer 1) + auto-loaded skill (Layer 2) defense

For grok-4.3 researchers that self-reject with "Only kanban_*
tools are available" before starting, the A+C defense is now
shipped. **A** = v2 body template with CRITICAL tool-inventory
block (in `references/research-body-template.md`, v2 is the
default). **C** = `kanban-research-tasks` skill auto-loaded via
`--skill kanban-research-tasks` on the create call. Both layers
are required.

## Pitfalls

**Inventing profile names that don't exist.** The dispatcher silently fails to spawn unknown assignees — the card just sits in `ready` forever. Always assign to a profile from your Step 0 discovery; ask the user if you're unsure.

**Planner budget trap — archive + re-queue with pre-loaded evidence.** The "devos-planner iteration budget trap" pitfall above gives four mitigations (a)-(d). When (b) doesn't apply — i.e. the planner burned its 90-iteration budget on EVIDENCE GATHERING and never wrote the spec — the right move is to archive the failed card and re-queue a tighter card with the planner's findings inlined. Worked procedure (verified on control-plane item3):

1. `hermes kanban --board <slug> log <failed_card_id> --tail 200` — capture the planner's evidence findings (file paths, current-state observations, design tensions it identified). These are real; don't lose them.
2. `hermes kanban archive <failed_card_id>`. If a downstream gate card (e.g. human-approve) is parented on the failed card, archive that too — you'll recreate it parented on the new plan card.
3. Create a new plan card parented on the upstream research card: `hermes kanban create "Item3-plan: ..." --assignee devos-planner --parent <research_id>`. Auto-promotes to `ready` because the research is `done`.
4. In the new card body, INLINE the planner's prior findings verbatim under a `== EVIDENCE (do not re-gather) ==` header. This is the critical move: the planner no longer needs to read source files, so its budget goes to writing the spec, not gathering evidence. Include the file paths, current-state observations, and the key design tensions (e.g. "frontend uses `/api/cp/*`, BFF tree has `/api/bff/*`, spec must pick one and document migration").
5. Reduce the spec section count (collapse 15 → ~12 by merging low-value sections like "deferred scope" and "dependencies" into the problem statement or scope section). Aim for ~600-900 lines of dense spec.
6. The new card body MUST explicitly say: "DO NOT re-read the research brief or the prior plan log; use the inline evidence above." Otherwise the planner re-derives everything and hits the budget again.
7. Recreate the gate card parented on the new plan: `hermes kanban create "Item3-approve: ..." --assignee devos --parent <new_plan_id> --initial-status blocked`.
8. `hermes kanban --board <slug> dispatch`. Watch `Spawned: N` — N>0 means the new plan is claimed.

Why this works: the prior run's evidence IS the deliverable for the gather phase; the new run only needs to execute the write phase. Splitting "gather" and "write" across two planner runs is faster than asking one run to do both within 90 iterations.

**Planner stale-summary cache — file exists but LLM keeps re-posting "research brief missing."** Distinct from the budget-trap above. The planner successfully writes the spec to disk (e.g. `/tmp/cp/item-X-spec.md`, 27KB, lines correct), but its LLM context has a cached "research brief missing" or "waiting for upstream" comment that it keeps re-posting as the "Latest summary" in its heartbeat. The card is `running`, the worker is alive, the file is on disk — but every dispatcher tick shows the same stale text. Seen on control-plane item4: the first planner attempt looped on "Research brief missing: /tmp/cp/item4-agent-catalog-research.md doesn't exist yet. Upstream researcher task t_X is still running." even after the researcher had produced the file 5+ minutes earlier. The dispatcher's "I see the card is running" signal was correct; the planner was just stuck in a stale-state comment loop. Detection:
- Card stays `running` for > 5 min with the same `Latest summary` text byte-for-byte
- The expected upstream artifact EXISTS on disk and is reasonable size
- `hermes kanban show <id> | grep -A1 "Latest summary"` returns the same stale text across multiple `hermes kanban show` calls

Recovery (don't try to unstick the running worker — they can't see the new file state because their LLM context is fixed at the time of the stale comment):
1. Verify the artifact on disk: `ls -la <expected-path>` and `wc -l <expected-path>`. If both look right, the work is done — the worker just can't see it.
2. `hermes kanban reclaim <planner_id>` — single id only, multi-id reclaim is invalid CLI. Expect `cannot reclaim (not running or unknown id)` if the worker has already gone to sleep; that's fine.
3. `hermes kanban comment <planner_id> "<path> IS available (N lines, M bytes, written at <timestamp> by <upstream_id>). Worker card is being closed by orchestrator; proceed to read it and write the spec."` — the comment is for the audit trail, not for the worker (they won't see it).
4. `hermes kanban complete <planner_id>` — single id. May return `cannot complete (unknown id or terminal state)` if the dispatcher's stale-cache reclaimed it first; verify with `hermes kanban list | grep <id>` to confirm it's actually done.
5. Archive the stale card if complete refused: `hermes kanban archive <planner_id>`.
6. Create the replacement plan card with a body that EXPLICITLY references the existing artifact: e.g. "Read /tmp/cp/item4-agent-catalog-research.md (486 lines, 32KB) — DO NOT check upstream state, the researcher card is closed. If you hit the 90-iteration budget, write what you can to /tmp/cp/item4-agent-catalog-spec.md. Partial output is salvageable." This body text is what makes the new run succeed — it removes the upstream-check step that caused the original loop.
7. Wire the new plan card: `hermes kanban link <research_id> <new_plan_id>` (remember FIRST_ARG = PARENT, so research is parent). Recreate the gate parented on the new plan if it was already linked to the old one: archive the gate, recreate with `hermes kanban create "...approve..." --parent <new_plan_id> --initial-status blocked`.
8. `hermes kanban --board <slug> dispatch`. Verify `Spawned: N > 0`.

Why this works: the original worker's LLM context has the file-not-found belief baked in. Even if you `reclaim` and respawn the same card id, the new worker inherits a comment thread full of "missing" — they may re-derive the same loop. Creating a fresh card id with a body that explicitly says "the file exists, do not check" is the most reliable way to break out. Verified on control-plane item4: the v2 plan card (t_de41010c) wrote the spec in 3 minutes flat because its body told it exactly what to do without re-checking state.

**Non-spawnable assignee is silent, not loud.** Even when a profile name *does* exist somewhere (a legacy worker ran on it once, or it's listed in the broader fleet), the dispatcher will skip tasks assigned to it if that profile isn't registered as a worker in the *current* session. `hermes kanban dispatch` prints `Skipped (non-spawnable assignee — terminal lane, OK): t_xxx, t_yyy, ...` — no error, no failure event, no retry. Detection: any `ready` task with age > 60s and zero `runs` rows is a strong signal. Cross-reference `hermes kanban assignees` (the active worker pool) against your card graph. The `ON DISK no` profiles are terminal lanes (legacy or registered in another session) — anything assigned to them will never run. Recovery: `hermes kanban assign <task_id> <spawnable_profile>` per skipped card, then re-dispatch. Choose the spawnable profile by domain (e.g. for backend Python cleanup: `devcrew-backend-dev`; for Next.js/TS: `devcrew-frontend-dev`; for docker/deploy: `devcrew-devops`). Hit on control-plane item2 when the integrator spawned 3 cleanup follow-ups assigned to `devcrew-developer` — that profile has only one historical task and no on-disk runtime in the devos session, so the dispatcher skipped all 3. Reassigning to `devcrew-backend-dev` unblocked all three in one tick. See the `kanban-doctor` skill for the full recovery procedure; this pitfall is the proactive prevention — when you're the one creating or assigning cards, verify the assignee is spawnable here.

**Bundling independent lanes into one card.** If the user asks for two independent outcomes, create two cards. Example: "fix blockers and check model variants" is not one fixer task; create a fixer/engineer card for the fixes and an explorer/researcher card for the variant check, then optionally gate review on both.

**Over-linking because of wording.** "Finally check X" may still be parallel with implementation if X is static config, docs, or source discovery. Link it after implementation only when the check depends on the implementation result.

**Forgetting dependency links.** If the task graph says `research -> implement -> review`, do not create all tasks as independent ready cards. Use parent links so implement/review cannot run before their inputs exist.

**Reassignment vs. new task.** If a reviewer blocks with "needs changes," create a NEW task linked from the reviewer's task — don't re-run the same task with a stern look. The new task is assigned to the original implementer profile.

**Force-completion of reviewer cards with unaddressed findings = rubber-stamp.** Reviewer and QA cards that list blocking issues must be either: (a) addressed by completing the fix cards they created, (b) escalated to the user, or (c) explicitly archived with a documented decision. Closing a reviewer card without addressing the findings is a rubber-stamp and breaks the build. Hit on control-plane item6-T14-reviewer (t_841c2622) which flagged 6 real issues — 3 of which were still in flight and 3 of which were addressed by not-yet-started cards. The right move was to comment, leave it open, and let the fix cards run. Closing it as "done" without addressing the findings was wrong, and the user caught it. **Rule: run the gate-card closeout procedure (below) and complete gate cards only via `scripts/safe-complete`. Never raw-`complete` a gate card.**

**ALWAYS run `safe-complete` instead of `hermes kanban complete` directly.** The script ships in this skill at `scripts/safe-complete` (and is mirrored to `~/.hermes/profiles/devos/scripts/safe-complete` and `~/projects/mustCompany/must-dev-agents/dev-os/scripts/safe-complete` for direct invocation). It scans the card's recent comments for review-required markers (`review-required`, `blocking issues`, `needs eyes`, `design decision`, `Option A`, `Option B`, `needs human`, `rubber-stamp`, etc.) and refuses to complete the card if any are found. The script prints the offending comments so you can address them. Use this as a hard guard against the rubber-stamp anti-pattern (caught twice on item6: t_841c2622 and t_fd63cd4c — both were review-required handoffs that I force-completed by hand instead of using the guard). If `safe-complete` refuses, your options are: (a) address the findings, (b) escalate to the user, (c) explicitly archive with a documented decision, or (d) do the manual `hermes kanban complete` ONLY after posting a comment that documents why you're overriding the guard. The guard exists because I (the model) drift from skill text under pressure; the guard is documentation-as-code that enforces the rule for every call. See `references/rubber-stamp-recovery.md` for the full 3-step recovery pattern and `references/structural-fixes-2026-06-11.md` for the 3-bug analysis that produced this rule.

**Gate-card closeout procedure (deterministic).** When a reviewer or QA card
finishes with N blocking findings:

1. Verify a fix card exists for every blocking finding; create the missing
   ones, assigned to the original implementer profile, parented on the gate
   card.
2. Expand the **integrator's** parent set with those fix cards
   (archive-and-recreate — see "Inserting a new step into an ALREADY-BUILT,
   running graph"). The gate against unfixed code is the integrator's parent
   set, not an open gate card.
3. Comment on the gate card mapping each finding → its fix card id.
4. Complete the gate card via `scripts/safe-complete`. Its deliverable is the
   review, which now exists; keeping it open adds rubber-stamp pressure
   without protection.

**Argument order for links.** `kanban_link(parent_id=..., child_id=...)` — parent first. Mixing them up demotes the wrong task to `todo`.

**CLI `hermes kanban link` direction is FIRST_ARG = PARENT (not child).** Unlike the Python API where parent/child are explicit kwargs, the CLI is `hermes kanban link A B` and treats `A` as the **parent** of `B`. The output line `Linked t_X -> t_Y` confirms this: the arrow points parent → child. Common failure mode (verified twice on control-plane item3 and item4 setup): orchestrator wants the research card to be parent of the plan card, types `hermes kanban link t_research t_plan` thinking "research is the child of plan", and ends up with research as the PARENT of plan — the whole chain runs backwards, the plan starts before research is done, and downstream gates don't fire in the right order. Easy to spot after the fact with `hermes kanban show <child_id>` and reading the `parents:` / `children:` fields. The fix: `hermes kanban unlink <wrong_parent> <wrong_child>` and `hermes kanban link <actual_parent> <actual_child>`. To avoid the trap, the mnemonic is "the arrow in the output points parent → child, so the LEFTMOST arg is the parent." If you find yourself typing it, pause and re-read the line you want.

**Don't pre-create the whole graph if the shape depends on intermediate findings.** If T3's structure depends on what T1 and T2 find, let T3 exist as a "synthesize findings" task whose own first step is to read parent handoffs and plan the rest. Orchestrators can spawn orchestrators.

**Tenant inheritance.** If `HERMES_TENANT` is set in your env, pass `tenant=os.environ.get("HERMES_TENANT")` on every `kanban_create` call so child tasks stay in the same namespace.

**Researcher "Missing tools" failure has two distinct causes — diagnose before assuming a config fix.** Verified twice on control-plane item5. The worker's last heartbeat may read: *"Missing tools: this research task needs bash (repo exploration), web_search/web_fetch (platform research with URL citations), and read/write (file I/O to produce /tmp/cp/...). Only kanban_* tools are available — all three capability classes are absent."* Two causes, two different fixes:

- **Cause A — profile config is wrong.** The researcher's `toolsets` list in `~/.hermes/profiles/<name>/config.yaml` does NOT include `terminal` / `web` / `file` / `search` / `read_file` / `write_file`. Verify with `cat ~/.hermes/profiles/<name>/config.yaml | grep -A2 ^toolsets` — if the only entry is `hermes-cli` and you want the worker to use it as-is, the cause is the model's self-check (Cause B), not config. If the entry is bare or restricted, fix the config.
- **Cause B — model self-reports incorrectly (the more common case).** The profile config IS correct (`hermes-cli` includes `_HERMES_CORE_TOOLS` = `terminal`, `web_search`, `web_extract`, `read_file`, `write_file`, `patch`, `search_files`, etc.) but the LLM — particularly Grok-4.3 / xAI models — self-evaluates its tool inventory at the start of the run, looks at the open-ended body, and concludes it only has `kanban_*` tools. The work is rejected before it starts. Symptom: v1 fails with the error above; v2 with the same model + same config + slightly different body succeeds and writes a full brief. This is model behavior, not config.

**Two layers of defense (both shipped for control-plane item5+ workstreams):**

- **Layer 1 — body-level (the v2 default body).** Every research body now includes a `CRITICAL` block that enumerates the worker's tool inventory and says "DO NOT self-evaluate." v2 is the default in `references/research-body-template.md`; v1 (open-ended) is preserved as a documented opt-out for non-grok models. Use v2 unless you have empirical evidence v1 is fine for your model. See the template for the full reusable body.

- **Layer 2 — system-prompt-level (the research-tasks skill).** The devos-researcher profile auto-loads the `research-tasks` skill on every dispatch. The skill restates the tool inventory and the "DO NOT self-evaluate" directive in the system prompt — a stronger anchor than the body because the system prompt is processed before the body. See `~/.hermes/profiles/devos-researcher/skills/research/research-tasks/SKILL.md`.

**Why both:** the model's self-reject is a one-shot pre-flight check that fires at the start of the run. Anchoring the tool inventory in two places (body AND system prompt) makes the trigger much harder to fire. A + C together, not either alone.

**Fix for Cause A** (config genuinely missing — unusual):
1. Pass `enabled_toolsets` on the create call if your session supports it: `--enabled-toolsets web terminal file search` on `cronjob create`, or the equivalent flag on `hermes kanban create` (check `--help`). Per-card override.
2. Edit the researcher's profile config to include the missing toolsets in the default `toolsets:` list. Find the config at `~/.hermes/profiles/<name>/config.yaml` and update it. Project-wide fix.

**If a v1 self-reject still happens** despite the v2 default and the research-tasks skill:
1. Confirm the skill is actually auto-loading — `cat ~/.hermes/profiles/devos-researcher/skills/research/research-tasks/SKILL.md` should exist. If it doesn't, the install was incomplete; re-run the skill creation.
2. Confirm the body includes the CRITICAL block. If a custom body omitted it, the system-prompt anchor is the only defense — should still work, but if the model re-rejects, append the block.
3. As a last resort, archive the failed card and create v2 with the same body but a fresh id. Sometimes a different model invocation breaks the cached self-reject.

**Don't re-create the card with a different id and assume the model will behave differently** unless you also change the body OR ensure the research-tasks skill is loading. The body/skill change is what breaks the loop, not the card id.

**Don't force-close a research card before the artifact is on disk.** Verified on control-plane item5. The v1 research card was self-blocked with the "Missing tools" error above. The orchestrator (me) decided to "salvage" by completing the v1 card and creating a v2 card with a body that said "use these toolsets". This created a brief-less interval where the planner (which auto-promoted because its parent t_d04c5bc0 was now `done`) ran for several minutes without a research brief on disk, and the planner's stale-summary-cache pattern almost kicked in. The lesson: when a research card fails (missing tools, budget, anything), the order is **(1) fix the underlying cause (config, toolset, body), (2) re-dispatch the SAME card id, (3) only force-close + create v2 as a last resort**. Force-closing research cards before the artifact exists creates a window where downstream workers race with the replacement. If you must force-close, archive the original first and create v2 with a body that explicitly says "research brief is at /tmp/cp/... (N lines, M bytes); DO NOT re-derive from scratch" so the planner doesn't burn its budget re-exploring.

**Force-load skills into a worker via the per-task `--skill` flag.** The dispatcher auto-loads only one skill by default: `kanban-worker` (the lifecycle contract). If you want any other skill injected into a worker's context (e.g., `kanban-research-tasks` for the tool-inventory assertion, or a domain-specific skill like `osint-investigation` for an OSINT research task), pass `--skill <name>` on the `hermes kanban create` call. The flag is **singular** (not `--skills`), **repeatable** (one per skill), and the value is the skill's `name:` field — not a path.

```python
# Example: research card that needs the tool-inventory anchor in its system prompt
hermes kanban create "Item-N-research: <topic>" --assignee devos-researcher \
  --body "<the v2 body>" --skill kanban-research-tasks
```

What the worker sees: `kanban-worker` (lifecycle, auto-injected) + `kanban-research-tasks` (the `--skill` flag) + the body. Use this whenever a card body is too short to embed the right framing on its own, or when a research/planning task needs a domain primer that would be noise in a code-work body. Note: the new skill must be **registered** in the profile's skill manifest — pass `--skill foo` for a skill that has YAML errors (e.g., unquoted colons in description) returns `Unknown skill(s): foo` and the worker spawn fails. Validate the skill first via `hermes -p <profile> skills list | grep <name>`.

**Per-task `skills:` is different from the profile's `skills.external_dirs` config.** The profile config sets the *search path* for skill discovery (which directories are scanned). The per-task `--skill` flag sets the *force-loaded set* for that one card. They compose: the skill must be in a discovered directory AND explicitly named in `--skill` to be force-loaded. Don't expect `--skill foo` to work for a skill that lives outside the profile's `external_dirs` and the default `~/.hermes/skills/` tree.

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

## Driving Kanban from the `hermes kanban` CLI (coordinator with terminal access)

When you orchestrate from a coordinator profile that has a terminal tool (rather than the `kanban_*` Python helpers), you use the `hermes kanban` CLI. It behaves differently from the in-process API and has its own footguns — verified the hard way:

- **Title is POSITIONAL, not a flag.** `hermes kanban create "research: foo" --assignee devos-researcher --body "..."`. There is **no `--title`** — passing `--title` dumps the usage banner and creates nothing. Other flags: `--assignee`, `--parent <id>` (repeatable for multi-parent), `--initial-status blocked|running`, `--json`, `--priority`, `--triage`, `--goal`.
- **Build dependency chains with repeated `--parent`.** A child gated on two parents: `hermes kanban create "plan: spec" --assignee devos-planner --parent t_aaa --parent t_bbb`. The child starts in `todo` and auto-promotes to `ready` only when ALL parents reach `done`. Create parents first, capture their ids from `--json`, then create the child — never create-then-link, same rule as the API.
- **The human gate = a `--initial-status blocked` card** parented to the plan card. Nothing downstream of it can run until you `hermes kanban unblock <id>` on explicit human approval. Don't create the build card until the gate clears.
- **`hermes kanban comment` takes positional args, not `--body`.** Signature: `hermes kanban [--board <slug>] comment <task_id> "<text>"`. Passing `--body` dumps the usage banner and adds nothing. The text is still bash-eval'd, so keep it backtick-free (same rule as `--body` on `create`). (Contrast with `create`, where the title IS positional but the body IS `--body`.)
- **The standalone `hermes kanban daemon` is DEPRECATED — the gateway runs the embedded dispatcher.** If you run `hermes kanban daemon` it prints a deprecation notice and exits immediately. This is relevant to you as an orchestrator because: (a) when `devcrew-run` execs the daemon, its process exits quickly while the build continues via the gateway — do NOT watch the devcrew-run PID for completion, watch the board; (b) the gateway dispatches all profiles, not just this build — do NOT kill the gateway to stop a build, just mark the build cards `complete` (see the `unblock vs complete` trap below); (c) if no gateway is running, start it with `hermes gateway start` — the embedded dispatcher ticks every 60s by default (`config.yaml: kanban.dispatch_interval_seconds`). For per-project dispatch details, see the coordinate-and-route skill's "Dispatching the build to devcrew" and "Monitoring & closing out a devcrew build" sections.
- **`hermes kanban list` is UNRELIABLE across separate terminal calls; `hermes kanban show <id>` is the source of truth.** Each terminal call is a fresh shell, and the "current board" persisted by `boards switch`/`boards use` flaps between calls — so `list` may return rows from a different board, return empty, or show a stale current board, and the `COUNTS` column hides `done` cards (shows "(empty)" for a board full of done tasks). **`hermes kanban show <id>` is board-independent** — it resolves a card by id regardless of current board and prints status + parents + children. Verify your graph with `show`, track cards by id, and do NOT trust `list` for "did my card land / what board is it on".
- **`boards use` / `boards switch` does not reliably persist to the next terminal call.** Each terminal call is a fresh shell and the persisted "current board" flaps. **The reliable fix: pin the board on EVERY command with the global `--board <slug>` flag, which goes BETWEEN `kanban` and the subcommand** — `hermes kanban --board control-plane create "..."`, `hermes kanban --board control-plane show t_xxx`. Putting `--board` AFTER the subcommand (`hermes kanban show t_xxx --board ...`) errors with "unrecognized arguments". You can also export `HERMES_KANBAN_BOARD=<slug>` but the explicit flag is safest in a multi-call session. (Switching inside one chained command -- `hermes kanban boards switch X >/dev/null 2>&1; hermes kanban create ...` -- also works but is fragile; prefer the flag.)

  You can also use the `HERMES_KANBAN_BOARD=<slug>` env var as a default-board override. This is critical when launching devcrew-run: the architect runs many implicit kanban commands, and without HERMES_KANBAN_BOARD they may land on a stale board. Set BOTH DEVCREW_BOARD and HERMES_KANBAN_BOARD for reliable placement.
- **Pick the project's board BEFORE creating any cards — this is a real user expectation, not cosmetic.** For a new project, create and use a dedicated board first (`hermes kanban boards create <slug>`), then pass `--board <slug>` on every create. The user corrected exactly this when cards landed on a leftover board from a different project ("you created task in wrong board, you should use control plane board"). Don't assume the board name is throwaway — operators organize one board per project and will call out cards on the wrong one.
- **There is NO "move card between boards" command.** If cards land on the wrong board, you cannot relocate them. Recovery: if the work hasn't started, `hermes kanban archive <id>` the strays and recreate the graph on the correct board with `--board`. If a card already COMPLETED with valuable output, don't discard it — capture its output (read the comment thread / brief), then recreate a `[DONE]`-marked reference card on the correct board seeded with that output and `hermes kanban --board <slug> complete <id> --summary "..."`, so the downstream plan card can parent off it.
- **Card `--body` text must avoid backticks and unbalanced quotes.** The CLI body is interpolated through bash `eval`, so backticks in a body (common in markdown code spans) trigger `unexpected EOF while looking for matching` and create nothing — even when the body is `json.dumps`-quoted. Keep create bodies plain-prose and backtick-free; put long/marked-up briefs in a file (`/tmp/...`) or attach via `hermes kanban comment`, and have the card body point to that path.
- **Profile-home vs real-home `$HOME` mismatch.** Under a named Hermes profile, the shell's `$HOME` may point at the profile home (`~/.hermes/profiles/<name>/home`) while the `hermes kanban` CLI resolves its store from the real user `~/.hermes/kanban`. So `~`-relative paths and direct `sqlite3` reads of the board DB can point at the wrong tree or hit "disk image malformed" (uncheckpointed WAL held by the daemon). **Don't reach into the SQLite DB directly** — use the CLI (`show`/`list`/`create`), which always targets the right store.
- **Shell parentheses in Next.js route group paths.** Next.js uses parenthesized directory names for route groups: `src/app/(app)/(admin)/teams/page.tsx`. Passing these paths through shell commands without quoting causes `syntax error near unexpected token '('`. Fix: quote the path — `"src/app/(app)/(admin)/teams/page.tsx"` — or use `find ... -path '*/(admin)/*'` with quoted glob patterns. Python's `os.walk` / `pathlib.Path.rglob` in `execute_code` avoids the shell entirely.
- **`promote --force` reports success but does not change state for cards with running parents.** A card whose parents are `running` (not `done`) is held in `todo` by the dispatcher. `hermes kanban promote <id> --force` prints `Promoted <id> -> ready` and exits 0, but the next `show <id>` reports the same `todo` status. The `--force` flag is documented to bypass parent-done checks, but in practice the dep engine re-asserts on the next tick and reverts. Verified on control-plane item3: 4 unblocked cards all stayed in `todo` after `promote --force`; they only moved to `done` after a follow-up `complete` (which itself was rejected with `cannot complete <id> (unknown id or terminal state)` while parents were running). **The right path for self-blocked cards is `unblock + complete` (not `promote --force).`** Don't waste a turn on `promote --force` — it lies. (This is different from `promote` for `ready` cards in a stuck state: there `promote` works. The trap is specifically for cards in `todo` with running parents.)
- **Multi-id `complete` and `unblock` are asymmetric and partially broken.** `hermes kanban unblock t_a t_b --reason "..."` works fine — both cards get unblocked. `hermes kanban complete t_a t_b` is officially documented to take multiple ids, but in practice it silently fails on a subset of them — exit 0, no error, but `stats` shows the cards still in `running` and a subsequent `complete <id>` returns `cannot complete <id> (unknown id or terminal state)`. The actual rule (verified on item3): when one of the multi-id targets is in a state that allows completion and another is not, the CLI silently no-ops on the not-allowed ones. **Always run `complete` one id at a time when mixing states** (e.g. after an unblock that reverted some cards to `todo` but kept others in `ready`). For pure `unblock` the multi-id form is reliable; for `complete` it is not.
- **`hermes kanban show <id>` is the only reliable state probe.** `list` filters by current board (which flaps across shells), counts hide `done`, and grep over `list` output can miss cards in unexpected states. **`show` is board-independent and prints the full event log with reasons.** When debugging a stuck card, `show <id>` first, then `runs <id>`, then `log <id> --tail 200` for the comment thread. The handoff comment is what you read to decide whether to unblock+complete.

### Control-plane / multi-repo monorepo guardrails

When orchestrating `devcrew-run` for the Control Plane-style monorepo (Python backend + `web/` Next.js frontend), bake these hard rules into your graph:

- **Board isolation first.** Use one board per project and pass `--board`/`HERMES_KANBAN_BOARD` + `DEVCREW_BOARD` for every build command. Create a single upstream `human approval` gate before scheduling the build task.
- **Do not schedule `item2-build` (or equivalent integration build) while review-required prerequisites are blocked/todo.** Even if code compiles partially, blocked subtasks (e.g., `review-required` on role/rotation work) block reliable completion.
- **Run prerequisite backend checks before build handoff.** Keep evidence-driven gates:
  - `uv run pytest tests/test_secret_resolver.py tests/test_identity.py tests/test_consent.py tests/test_rotation.py`
  - targeted API coverage tests for new endpoints/role-manager paths
- **Run monorepo frontend checks in the `web` directory.**
  - `cd web && npm run typecheck`
  - `cd web && npm run build`
- **Use `hermes kanban show <id>` as the state source of truth.** `list` can be noisy in terminal sessions; `show` gives parents/children/events with deterministic status for proof.
- **`hermes kanban runs` requires a task id.** Use `hermes kanban dispatch` for queue movement, then check status by id; don't assume `runs` is a bulk-run command.

### Control-plane-like CLI footguns

- **`hermes kanban runs` requires a task id argument.** `hermes kanban runs` without `<task_id>` returns usage error.
- **`npm run tsc -- --noEmit` is not portable across this repo.** `web/package.json` uses `typecheck`; run `npm run typecheck` from `web`.

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

## Unblocking review-required parents that gate the whole chain

A common stall pattern: a worker marks its card `blocked` with reason `review-required: <handoff summary>`, then sits waiting for a human reviewer. The dispatcher respects `blocked` and will NOT promote any downstream children, even if every dependency is otherwise met. If the parent card is the root of a long chain (e.g. role-hierarchy, secret-resolver, integration bridge), the whole pipeline can sit idle for hours. Verify-by-asking the user is the wrong move when YOU can re-run the verification yourself with the test commands the handoff names.

**The recovery procedure (orchestrator-side, no human in the loop needed):**

1. **Re-run the verification the handoff names.** Don't trust the worker's self-reported pass count — re-execute it and capture the result.
   - For backend: `uv run pytest <paths> -q` from the repo root
   - For frontend: `cd web && npm run typecheck && npm run build`
   - If 9/55 fails are listed as "pre-existing, unrelated", confirm by running the failing test in isolation; if they actually trace to a different task, treat that as a separate fix card.

2. **Unblock with reason.** `hermes kanban --board <slug> unblock <task_id> --reason "<verification result>: <summary of why the work is good>"`. The reason text becomes the audit-trail comment and is what a future session will see first.

3. **Watch for a fresh spawn — the dispatcher will claim the now-ready card immediately.** Verify with `hermes kanban runs <task_id>` and look for a new `(running)` row.

4. **Reclaim the re-spawn.** The worker is about to re-do work that's already verified. `hermes kanban reclaim <task_id>` aborts it. The run history will show two outcomes: the original `blocked` and the new `reclaimed`.

5. **Post a verification comment + complete.** `hermes kanban comment <task_id> "Closing based on re-verification: <paste the pytest output, file paths changed, test counts>."` Then `hermes kanban complete <task_id>`. The comment+complete pair is the auditable "I closed this, here's why" trail.

6. **Dispatch downstream.** `hermes kanban --board <slug> dispatch`. Auto-promoted children will spawn on the next tick.

**Why this works and not a "stale loop"**: review-required is a one-shot `blocked` outcome, not a retry storm. The pattern is: verify → unblock → kill the now-redundant re-spawn → close with evidence. Re-running the worker (or "let it re-do and check") wastes 5–15 minutes of LLM time per card and risks the worker touching verified code.

**Read the board before assuming it's sick.** `hermes kanban dispatch` returning `Reclaimed: 0, Crashed: 0, Timed out: 0, Stale: 0, Auto-blocked: 0, Promoted: 0, Spawned: 0` is the NORMAL idle-board state — there was nothing new to dispatch that tick. The board is sick only when `stats` shows the "blocked parents holding children" pattern: `todo > 0` AND `ready = 0` AND `running = 0` AND `blocked > 0`. For the user-triggered recovery path, use the `kanban-doctor` skill.

**Default to staged completion over immediate build.** When given a "approve and run the integration build" choice and there are still review-required prereqs, the user has consistently chosen to finish the staged work first ("Option 2" pattern). Don't push for the build card until the prereq chain is done — even if the code-level tests pass. The integrator card is cheap to run later; running it on unverified prereqs wastes the most expensive card in the graph.

## The canonical dep graph (per hermes-devcrew/team.yaml)

Historical note: this section previously advised making the Reviewer / QA /
Integrator cards siblings of the code lanes, gated on the brief. That advice
is retired — it was a workaround for routine worker self-blocks, which the
v2.1.0 worker doctrine and the framework KANBAN_GUIDANCE fix eliminate. With
self-blocks rare and genuine, early review of half-written code is the bug,
not the mitigation.

The canonical topology (`hermes-devcrew/team.yaml` — on conflict, the
manifest wins):

- Implementation cards run in PARALLEL (siblings), linked only where one
  truly consumes another's output (designer card upstream of frontend impl).
- Reviewer (static gate) and QA (dynamic gate) run in PARALLEL — each
  parented on EVERY implementation card.
- Integrator is parented on BOTH gates. When the gates produce fix cards,
  expand the integrator's parent set with them (archive-and-recreate) before
  it runs — see the gate-card closeout procedure in Pitfalls.
- Per-link dep modes (`strict` / `parallel` / `evidence`) remain a pending
  engine feature; mention it if the user reports recurring stalls.

- **D3-first pattern for verify-and-ship builds.** When the build mandate is "verify what's in the working tree and ship it" (especially when the work is already done before the build runs), invert the usual reviewer-then-integrator ordering. Make the integrator's commit+push card the **parent** of the reviewer and QA cards, not their child. Concrete shape (used on the control-plane item2 final build):
  - `t_D3` — integrator — Final integration — commit, push, report SHA (no parents; starts immediately on dispatch)
  - `t_D1` — reviewer — Static review + test verification (parent: D3)
  - `t_D2` — qa — Dynamic QA end-to-end (parent: D3)
  D3 ships within minutes and you have a SHA on `origin/main`. D1 and D2 stay in `todo` until D3 reports done, then auto-promote and run in parallel to validate the actual delivery. Net effect: the build is shipped first, then validated, then any issues become follow-up fix cards on a known SHA. This avoids the failure mode where reviewer/QA unblock themselves with "looks good" but the integrator never gets a clean run, or where the build stalls because the code-lane parent of a self-blocking reviewer never reaches `done`. When the user invokes `devcrew-run` with a "do NOT redo implementation work" prompt, the architect may produce this shape on its own — but if you're sketching the graph manually for a final-build, force this shape. A SHA on `origin/main` is a stronger deliverable than a row of `done` cards on a board.

## Verify the deliverable against the brief — `done` is not "done right"

A worker marking a card `done` means *it decided it was finished*, not that it fulfilled the brief. Workers routinely:
- **Complete only part of a multi-part brief.** Seen this session: a "UX spike" card asked for (1) a competitive survey AND (2) a page-level map; the worker delivered a thorough competitor study, declared victory, and never produced the page map. The summary read confidently; only reading the actual artifact revealed the gap.
- **Save the artifact to a different path than instructed.** The card said save to `/tmp/cp/dashboard-ux-spike.md`; the worker saved `~/vercel-linear-ux-research.md` instead. Always check the completion event's `artifacts: [...]` and the summary for the real path before assuming the requested file exists — `ls` it.

**Before you present a worker's output to the user or promote downstream work, READ the actual artifact (or comment thread) and check it against every numbered ask in the card body.** Don't relay the worker's self-summary as if it were verified. This is the verification-before-completion rule applied to delegated work.

**When a worker half-finishes, create a FOLLOW-UP COMPLETION card — do not re-run the original.** Parent the new card on the partial one, point its body at what the partial card already produced (file paths), and scope it to *only the missing half* with an explicit "DO NOT re-do the part that's done" instruction. Re-point any downstream gate to depend on the follow-up card instead of the partial one (archive the old gate, recreate it with the new `--parent`). This is the same "new task, not a stern re-run" rule as reviewer-blocked work.

## Inserting a new step into an ALREADY-BUILT, running graph

The operator will sometimes add a requirement mid-flight — e.g. after the spec is done they ask for a "dashboard UX spike" before approving the build. The graph already exists and the gate is already created. There is **no add-parent-to-existing-card command**, so you cannot simply graft a new dependency onto the existing gate.

The pattern that works:
1. Create the new intermediate card, parented on the appropriate upstream card (e.g. spike with `--parent <plan_id>`). It promotes to `ready` immediately since its parent is `done`.
2. The downstream gate must now wait on BOTH the original parent AND the new card. Since you can't edit its parents, **archive the existing gate and recreate it** with the full `--parent A --parent B` set. Capture the new gate id.
3. Tell the user the gate now blocks on both, and that the old archived gate is a harmless dangling card that will never promote.

Same mechanic underlies the half-finished-worker recovery above: when the parent set of a gate/synthesis card needs to change, archive-and-recreate is the only path. Don't hunt for an `edit --parent` flag — it isn't there. Keep the recreated card's body identical except for the expanded parent list, then re-confirm the whole chain with `hermes kanban --board <slug> show <id>`.

## Proactive status reporting (unsolicited) — don't wait to be asked

When you've dispatched a graph and the build/research/plan is running, **check in on progress periodically and report status without being prompted.** The background poll-watcher (above) is for when the user says "ping me"; beyond that, you own the cadence of status delivery.

The user made this explicit: "why didn't you report back yet, why every time I have to check the status myself, it's your job to keep looking at the job and works."

Rules of thumb:
- **For short tasks (< 30 sec):** wait for completion, deliver result immediately.
- **For medium tasks (1-5 min):** check once at ~2 min. If done, deliver. If still running, say "still working, will report when done."
- **For long tasks (build graph, devcrew-run, planner runs):** check every 3-5 min. On EACH check, if the state changed (new cards appeared, a card blocked, a card completed), **deliver a brief unsolicited status update** — one paragraph: what's running, what completed, what's blocked, ETA if estimable. Use the board display as source of truth.
- **If a card blocks (review-required, error, etc.):** don't wait for the user to notice — investigate immediately, diagnose the block, and either fix it or report it with the one-line status.
- **If you catch a problem mid-flight** (wrong board, wrong assignee, budget hit): fix it and report the fix, don't ask permission. The user profile says "fix-then-report."

Periodically running `hermes kanban --board <slug> show <active-card-id>` or watching the `list` for count changes is what "looking at the job" means. Use the background poll-watcher to get notified on terminal states, but between checkpoints you're the one driving.

When writing a status paragraph, keep it tight: **current state. what's running. what just completed. what's blocked. what you're doing about it.** Max 4 lines. The user wants delivered status, not offered status.

When the user asks to be notified the moment a long-running card finishes, don't sit and block. Launch a tiny background shell loop that polls `hermes kanban --board <slug> show <card_id>` for a terminal status (`done`/`blocked`/`cancelled`) and exits, started with `terminal(background=true, notify_on_complete=true)`. The poll script (10-90 iterations of `sleep 20`) keeps the watch cheap and the `notify_on_complete` flag wakes the orchestrator on exit so it can read the artifact and deliver results. Grep the status line with `grep -m1 "^  status:" | awk '{print $2}'`.

## How to use this skill's resources

This skill ships three reference files and one script. Read them in the
order they appear in the pitfalls/anti-temptation rules above, or jump
straight to one when you need it.

- `references/build-watching-playbook.md` — 4-min poll cadence, stuck-worker detection, when to force-complete.
- `references/rubber-stamp-recovery.md` — the 3-step pattern for closing review-required handoffs without rubber-stamping. Read this BEFORE you use `hermes kanban complete` on any reviewer/QA card.
- `references/structural-fixes-2026-06-11.md` — the 3-bug analysis that produced the safe-complete guard.
- `references/research-body-template.md` — the v2 research body template with the CRITICAL tool-inventory block (default for new research cards).
- `scripts/safe-complete` — the runnable guard for the rubber-stamp rule. Use this INSTEAD of `hermes kanban complete` for every card. It scans the card's recent comments for review-required markers and refuses to complete if any are found.
