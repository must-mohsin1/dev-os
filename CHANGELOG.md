# Changelog

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
