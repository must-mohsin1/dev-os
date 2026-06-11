# Research Task Body Template

A copy-and-modify template for research task bodies. Default is now **v2 (tool-inventory-aware)**, which appends the CRITICAL tool block to every research body. The v1 (default) form is preserved as a documented opt-out below.

**Why v2 is the default now:** the devos-researcher profile runs on grok-4.3 (xAI), which has a documented self-reject pattern on open-ended research bodies. v1 self-blocks with "Missing tools" ~1-in-5 runs; v2 has not self-rejected in the current session (verified control-plane item5 v2, item3, item4). The cost of the CRITICAL block is one extra paragraph; the cost of a v1 self-reject is a wasted dispatch + 60s timeout + v2 re-queue. Always v2 unless you have a specific reason to opt out.

## v2 — Default research body (USE THIS)

```
Research the platform requirements for item N (<one-line summary>).

Goal: produce a cited brief at /tmp/cp/item-N-<topic>-research.md that
the planner can consume.

Scope of research:
1. Current state in the repo (with file paths and line numbers):
   - <list the files/dirs to inspect>
2. Inventory current <feature> state:
   - <what's there now>
3. <Target patterns> — for each, document:
   - <one bullet per pattern>
4. Gaps vs. the item-N vision: '<user's intent in their own words>'
5. Design choices the planner must make (each with pros/cons + a recommendation):
   - <list 4-8 design decisions>
6. Risks and open questions for the spec to resolve.

Be thorough but compact. ~300-500 lines is fine. Output to
/tmp/cp/item-N-<topic>-research.md.

CRITICAL: This card has full tool access. Your tool inventory includes:
- terminal + process (for shell commands and process management)
- read_file, write_file, patch, search_files (for repo exploration)
- web_search, web_extract, browser_* (for web research)
- vision_analyze (for image analysis)
- session_search, todo, memory, skills (for session context)
- kanban_show, kanban_list, kanban_complete, kanban_block, kanban_heartbeat,
  kanban_comment, kanban_create, kanban_link, kanban_unblock (for board
  coordination)

DO NOT self-evaluate your tool inventory before starting work. Begin
the research immediately: read the relevant files, run the searches,
write the brief. If a specific tool fails at call time, fall back to
the next one and keep going.
```

**MANDATORY create flag for the v2 body:** every research card you create with this body MUST also pass `--skill kanban-research-tasks` so the structural Layer 2 anchor is auto-injected into the worker's system prompt. Without the flag, only the body-level Layer 1 anchor is in play, which has proven insufficient for grok-4.3.

```python
hermes kanban create "Item-N-research: <topic>" --assignee devos-researcher \
  --body "<the v2 body above>" --skill kanban-research-tasks
```

The `--skill` flag is repeatable and force-loads the named skill into the worker's context. The dispatcher ALSO auto-loads `kanban-worker` for the lifecycle contract, so the worker gets both: lifecycle (kanban-worker) + tool-inventory assertion (kanban-research-tasks) + body-level inventory (v2 CRITICAL block). Three layers of defense.

The CRITICAL block is what makes research tasks reliable on grok-4.3. The enumeration anchors the model's tool list; the "DO NOT self-evaluate" line short-circuits the conservative pre-flight check.

## v1 — Open-ended body (DEPRECATED, opt-out only)

The original v1 form below is preserved for reference. It is **not** the default; it triggers a "Missing tools" self-reject on roughly 1-in-5 runs with grok-4.3. Use it only if you have empirical evidence v1 is fine for a specific model / setup (e.g., a non-grok model that's tool-savvy by default).

```
Research the platform requirements for item N (<one-line summary>).

Goal: produce a cited brief at /tmp/cp/item-N-<topic>-research.md that
the planner can consume.

Scope of research:
1. Current state in the repo (with file paths and line numbers):
   - <list the files/dirs to inspect>
2. Inventory current <feature> state:
   - <what's there now>
3. <Target patterns> — for each, document:
   - <one bullet per pattern>
4. Gaps vs. the item-N vision: '<user's intent in their own words>'
5. Design choices the planner must make (each with pros/cons + a recommendation):
   - <list 4-8 design decisions>
6. Risks and open questions for the spec to resolve.

Be thorough but compact. ~300-500 lines is fine. Output to
/tmp/cp/item-N-<topic>-research.md.
```

## Structural defense: research-tasks skill

The devos-researcher profile auto-loads the `research-tasks` skill on every dispatch. That skill restates the tool inventory and "DO NOT self-evaluate" directive in the system prompt — a second layer of defense so even if a v1 body (or a custom body without the CRITICAL block) reaches the worker, the system-prompt level prevents the self-reject. See the `research-tasks` skill at `~/.hermes/profiles/devos-researcher/skills/research/research-tasks/SKILL.md`.

The skill auto-loads because the devos-researcher profile's `skills:` config in `config.yaml` includes it. The dispatcher also auto-injects `--skills kanban-worker` for lifecycle guidance, but the profile-local `research-tasks` skill is what carries the tool-inventory assertion.

## When to deviate from the v2 default

Use v1 (open-ended, no CRITICAL block) ONLY when:
- You're running a non-grok model that's tool-savvy by default (e.g., deepseek-v4-flash, gpt-5.x, claude).
- You have a custom body that already includes a tool inventory assertion in a different form.
- The body is short enough (< 200 words) that the self-check trigger is unlikely.

For grok-4.3 (the current devos-researcher default), **always use v2**. The empirical evidence is in the parent skill's pitfall section.

## What NOT to do

- **Don't omit the CRITICAL block for grok-4.3.** Verified: v1 self-rejects ~1-in-5.
- **Don't change profile config without first checking if Cause A applies.** The model may be fine; the body may be wrong. See the parent skill's pitfall.
- **Don't retry v1 with the same body.** The LLM context is fixed at the start of the run; the same body will produce the same self-rejection. The body change is the recovery.
- **Don't force-close a research card before the artifact is on disk.** See the parent skill's "force-close-research-card pitfall" section.

## Why this works (mechanism)

The model's self-reject is a one-shot pre-flight check. It evaluates its tool inventory against the body once at the start of the run, then commits to "I don't have these tools" and refuses to begin. Re-running with the same body re-does the same check. Two ways to break the loop:

1. **(A) Body-level fix** — include an explicit tool enumeration in the body so the model has a concrete list to commit to. This is what v2 does.
2. **(C) System-prompt-level fix** — the research-tasks skill is auto-loaded into the system prompt, restating the tool inventory and "DO NOT self-evaluate" directive. This is a stronger anchor than the body because the system prompt is processed before the body.

Doing both (A + C) means the model gets the tool enumeration from two independent sources at two different processing stages. The self-reject trigger is much harder to fire.
