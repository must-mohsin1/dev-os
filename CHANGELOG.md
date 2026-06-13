# Changelog

## [0.1.3] - 2026-06-13

### Changed
- kanban-orchestrator doctrine **v3.8.0 → v3.10.0**. New rules, every one earned from a real incident in the item-10/item-11 builds: **card budget-sizing** (size each card to ≤ ~2/3 of the assignee's `max_turns`; 4 of 7 item-10 cards exhausted their budget because they were sized to "one work item" not "one budget"), **sole-decomposer rule** (exactly one decomposition pass — yours; double-decompose produced an unapproved second task set), **same-tree parallelism rule** (cards sharing a `dir:` workspace must chain or use worktrees — the dispatcher spawns same-profile siblings in parallel, and item-11 put 4 workers in one kernel checkout), **idempotent re-decomposition** (reconcile, don't re-create, on decompose-card retry — a retry created two full graphs), **guided-retry procedure** (on budget exhaustion, post a `RETRY GUIDANCE` comment with a git-status inventory + DONE/REMAINING lists; 4/4 item-10 exhausted cards completed on first guided retry), and a **late-fix-card closeout step** (gate-filed fixes that land after the integrator promoted need a follow-up integration card).
- kanban-worker doctrine **v2.4.0 → v2.5.0**: documents the shipped Item-10 T-F evidence gate (QA/integrator `kanban_complete` is kernel-rejected without `artifacts=[...]` pointing at existing non-empty files); adds the **fix-card assignee rule** (copy a real profile name verbatim, never invent — four phantom-assignee incidents across two builds), the **integrator sweep** (check for open fix cards before completing), **kanban-on-kanban test isolation** (fixtures use temp DBs / scratch boards, never the live board — an item-10 stress test ran 17 writers against production), and the **retry-guidance contract** (treat a `RETRY GUIDANCE` comment as ground truth; don't re-explore).
- `agents/planner/config.yaml` and `agents/researcher/config.yaml`: `reasoning_effort` was set to model ids (`gpt-5.3-codex-spark`, `grok-4.3`) which the kernel silently ignores — an unrecognized string falls through to the default tier. Corrected to valid effort levels (planner `high`, researcher `medium`); the model ids were already correctly set elsewhere in each config.

### Added
- `scripts/sync-doctrine.sh`: a second fan-out stanza that converges `kanban-orchestrator` copies in **every** profile, not just `kanban-worker`. Nine orchestrator copies had drifted a full minor version in worker profiles because no installer owned them; the kernel repo's upstream-tracked bundled copies are deliberately excluded. Idempotent (verified: zero drift warnings on second run).

## [0.1.2] - 2026-06-12

### Fixed
- `devos-run` hard-stops when the research or plan step fails or produces no artifact — previously it continued silently and could ship a provider error log as the brief/spec. Failures now block the tracking card with the output tail instead of leaving it open forever.
- `devos-run` deletes stale `brief.md`/`spec.md`/`report.md` at run start, so re-running a goal can no longer pass the freshness checks on a previous run's files.
- `devos-run` exports `HERMES_KANBAN_BOARD`, so planner spec retention lands on the run's board instead of the default board.

### Changed
- Per-profile turn caps sized from successful-run history: planner 40, researcher 60 (was 90, the runaway ceiling behind 13 of the 22 budget-exhaustion failures in the control-plane build). The inert `agent.gateway_timeout` keys are deliberately omitted — they only govern gateway chat sessions, not dispatched workers; wall-clock caps belong to per-task `max_runtime_seconds` (Item 10).
- kanban-worker doctrine **v2.4.0**: verification cards must capture real evidence — a tee'd `test_run.<task_id>.log` containing the exact command and exit code, with a digest mirrored to a durable comment (scratch workspaces are GC'd). Retry guidance now distinguishes the two `timed_out` causes (wall-clock vs iteration budget).
- write-spec **v1.1.0**: specs must be copied to the durable board `specs/` dir and that path cited in the completion summary — `/tmp`-only specs are incomplete.
- kanban-orchestrator **v3.8.0**: durable-spec gate rule (the retention recipe lives canonically in write-spec); planner budget-trap guidance no longer hardcodes the old 90-turn cap.
