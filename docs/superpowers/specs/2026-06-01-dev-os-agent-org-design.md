# Dev OS — autonomous agent org (research / planning / coordination) — Design

**Date:** 2026-06-01 · **Status:** Design — pending review · **Package:** `dev-os` (depends on `hermes-devcrew`)

## 1. Problem & goal

`devos` today is a *solo* coordinator doing research, planning, **and** dispatch. That's a
context bottleneck, can't parallelize, and can't be tuned per function — while implementation
already has a real 9-agent team (`devcrew`). Goal: give research and planning the same first-class
treatment as implementation, organized as a small, **shallow hierarchy** with a single human gate,
shipped as one installable package.

### Success criteria
1. A goal stated on Discord flows **research → plan → (human-approve) → build → improve** with each
   stage handled by a tuned specialist, coordinated on the kanban board.
2. `researcher` and `planner` are independent, tuned, **shippable** Hermes profiles (like devcrew agents).
3. The human is asked exactly once per goal — to **approve the plan** — and nowhere else by default.
4. The whole thing installs with one command and **depends on** (not duplicates) `hermes-devcrew`.

## 2. Non-goals (YAGNI)
- No full "research crew" or "planning crew" — research = 1 lead + ≤3 sub-searchers; planning = 1 planner + 1 critic pass.
- No deep org chart (no "department heads" tier). Max 3 tiers.
- No second/third human gate by default (plan-gate only; opt-in merge-gate later).
- No new orchestration engine — use Hermes kanban + daemon + cron.
- `improvement` is **not** a standalone crew — it's a cron loop reusing researcher+planner.

## 3. Locked decisions
- **Granularity:** lean specialists + coordinator (not full crews per function).
- **Control:** gated at the plan (research+planning autonomous → human approves plan → autonomous build → cron improvement).
- **Shipping:** a new `dev-os` package; `hermes-devcrew` consumed as the implementation dependency.

## 4. Architecture (3 tiers + a loop)

```
            Human (Mohsin) ── Discord
                    │ goal
                    ▼
        ┌─────────  devos  ─────────┐        Tier 1 · coordinator (Codex gpt-5.3-codex)
        │  decompose · route · gate · track · decide   (does not do the work itself)
        ▼            ▼               ▼
   researcher     planner        devcrew              Tier 2 · specialists + crew(dependency)
   (Grok)         (Codex)        (9 agents)
   +≤3 sub-       +critic        architect→designer→workers→reviewer+qa→integrator
   searchers
        └──────── kanban board (shared, dependency-ordered) ────────┘   Tier 3 · workers
                    ▲
              cron: improvement loop  →  re-runs research+plan on "improve project X"
```

## 5. Components

Each is a Hermes **profile** (own `SOUL.md` + `config.yaml` + `skills/`), independently installable.

### 5.1 `devos` — coordinator (Codex)
- **Does:** receives a goal (Discord), decomposes it into a `research → plan → [gate] → build → improve`
  task graph on the board, assigns each task to the right specialist, surfaces the plan for approval,
  tracks progress, reports. **Never** does research/planning/impl itself.
- **Uses:** `hermes kanban` (create/link/assign/block/unblock/dispatch), `devcrew-run` for impl.
- **Depends on:** researcher, planner profiles; the `hermes-devcrew` package.

### 5.2 `researcher` — research specialist (Grok)
- **Does:** gathers + synthesizes information into a **cited brief**. Spawns up to **3 parallel
  sub-searchers** for breadth; quick lookups use `grok-4.20-reasoning`, deep dives `grok-4.3`.
- **Uses:** `x_search` (xAI OAuth), `deep-research` skill, sub-agent fan-out.
- **Output contract:** a brief (kanban comment / file) — findings + sources + a confidence note.
- **Depends on:** xAI Grok OAuth.

### 5.3 `planner` — planning specialist (Codex)
- **Does:** turns goal + research brief into a **spec**: problem, goals, non-goals, constraints,
  **acceptance criteria**, risks. Runs a **critic** pass (self-review or sub-agent) before handing up.
- **Boundary:** product/project planning (what to build + why + criteria). *Technical* decomposition
  (spec → impl tasks) stays with devcrew's `architect`. No overlap.
- **Output contract:** an approval-ready spec the human reviews and devcrew can execute.

### 5.4 improvement — cron loop (not a profile)
- **Does:** on a schedule, devos re-runs researcher+planner on "what should project X improve?",
  files improvement **goals** onto the board (which then flow through the same pipeline).
- **Uses:** `hermes cron` on devos; reuses researcher + planner.

### 5.5 `devcrew` — implementation (external dependency)
- The shipped 9-agent package. Invoked via `devcrew-run "<spec>" <repo>`. Not part of `dev-os`.

## 6. Control flow & data flow

```
goal ─► devos.decompose ─► board:
   T1 research      (researcher)                       ready
   T2 plan          (planner)     depends-on T1        blocked→ready
   T3 approve-plan  (devos→human) depends-on T2        blocked (HUMAN GATE)
   T4 build         (devcrew)     depends-on T3        blocked until approve
   T5 report        (devos)       depends-on T4
   (cron) improve   (devos)       → emits new goals
```
- Artifacts ride on tasks: research **brief** (T1 output) → consumed by T2; **spec** (T2 output) →
  shown at T3, executed at T4.
- **The gate:** T3 stays `blocked`; devos posts the spec to Discord; on "approve" devos `unblock`s
  T3→T4; on "changes" it re-queues T2 with feedback.
- The **dispatcher daemon** runs ready tasks; dependencies enforce order; parallel goals/branches
  run concurrently (worktrees).

## 7. Models & policy
| Agent | Model | Provider |
|---|---|---|
| devos | `gpt-5.3-codex` | Codex OAuth |
| researcher | `grok-4.20-reasoning` (quick) / `grok-4.3` (deep) | xAI OAuth (x_search) |
| planner | `gpt-5.3-codex` (+critic) | Codex OAuth |
| fallback (any) | `openai/gpt-5.5`, `deepseek/deepseek-v4-flash` | OpenRouter |
**Never Claude or Gemini.** Comms: Discord.

## 8. Shipping — `dev-os` package
```
dev-os/
├── install.sh        # install devos+researcher+planner profiles; set models (Codex/Grok);
│                     #   wire board + cron; ensure hermes-devcrew is installed (dependency)
├── team.yaml         # roster + hierarchy + gate points + improvement schedule
├── agents/
│   ├── devos/        # distribution.yaml + SOUL.md + config.yaml + skills/
│   ├── researcher/
│   └── planner/
├── cron/             # improvement-loop schedule(s)
├── DEVOS.md          # policy + runbook (exists)
└── docs/
```
- Each agent = a profile distribution (same format as devcrew agents) → installable/updatable.
- `install.sh` checks for `hermes-devcrew` and installs it if missing (dependency).
- Publicly releasable like devcrew (no secrets; OAuth/keys are user-supplied).

## 9. Error handling & guardrails
- Single human gate at the plan; destructive/networked impl actions still gated inside devcrew (`--yolo` off).
- `hermes kanban` `--failure-limit` auto-blocks a task after repeated failures; isolated workspaces per task.
- Auditable event stream (`hermes kanban tail`/`log`). devos reports failures to Discord rather than silently retrying forever.
- Researcher must cite sources; planner must produce checkable acceptance criteria (else the gate has nothing to verify against).

## 10. Testing / verification
- Unit: each profile installs; `hermes -p <agent> -z "ping"` runs on its model.
- Integration (the acceptance test): a real goal → researcher brief (cited) → planner spec → devos
  posts plan → approve → `devcrew-run` builds → devos reports. Run on a throwaway repo/worktree.
- Improvement loop: a cron tick files at least one improvement goal for a target project.

## 11. Risks & open questions
| # | Risk / question | Mitigation |
|---|---|---|
| R1 | Codex/Grok OAuth are user-gated | already authed this session; install.sh documents re-auth |
| R2 | planner ↔ devcrew-architect overlap | explicit boundary (product vs technical) in both SOULs |
| R3 | cross-package dispatch (dev-os → devcrew) coupling | dispatch via the stable `devcrew-run` CLI, not internals |
| R4 | cost of autonomous research/plan per goal | quick Grok by default; deep only when flagged; one gate caps wasted build |
| Q1 | improvement: cron loop vs a tiny `analyst` profile | **decided: cron loop** (revisit if it needs its own persona) |
| Q2 | should devos auto-pick the target repo, or always be told? | default: told per goal; infer later |

## 12. Build phases (June 6 Recruit prototype)
1. Author `researcher` + `planner` profiles (SOUL + skills + config); promote `devos` into the package.
2. Wire the kanban control-flow + devos dispatch + plan-gate (block/unblock on Discord approval).
3. Cron improvement loop.
4. `install.sh` + `team.yaml` + docs; **end-to-end verify** (goal → brief → plan → approve → devcrew → report).
5. Public release.
**Jun 6 MVP = phases 1–2 + one live end-to-end demo.**

## 13. Success = the demo
One Discord message ("research X, plan it, build it in repo Y") → cited brief → spec → you approve →
devcrew ships a PR → devos reports — with researcher and planner as distinct, shippable agents.
