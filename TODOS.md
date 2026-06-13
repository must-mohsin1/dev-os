# TODOS

## devos-run
- **Decide on report-step leniency** — step 5 still accepts the error-log fallback for report.md (documented in-line as intentional: the build is already dispatched). Revisit if reports gain downstream consumers. **Priority:** P3

## scripts
- **verify_code_landed.sh rewrite or retirement** — excluded from the v0.1.2 ship: unexpanded glob makes it exit 2 on every run, BSD sed `\s` breaks Files-scope parsing on macOS, the advertised diff-against-base fallback does not exist (fails open), the baseline is HEAD not the card's base commit (committed work falsely refused), no board context on `kanban show`, and nothing references it. The verified findings were filed onto the Item 10 plan card (control-plane board, t_9c206b33) as requirements for the kernel-side completion gate (T-F). Rewrite here only if T-F stalls. **Priority:** P2
- **Fan-out test coverage** — `install.sh` §4a/§5 and `scripts/sync-doctrine.sh` are the only mechanisms distributing doctrine/configs to live profiles and have zero automated tests; a silent-skip regression would strand stale doctrine fleet-wide. Minimal test: run the fan-out against a temp HERMES_HOME with fake profiles and assert byte-identical copies + drift warning. **Priority:** P2

## agents
- **Real wall-clock caps via per-task max_runtime_seconds** — `agent.gateway_timeout` is inert for dispatched kanban workers (it only governs gateway chat-session inactivity), which is why it is deliberately absent from the profile configs. Kernel groundwork exists (`enforce_max_runtime` terminates over-cap workers, but only when the per-task value is set); per-profile defaults are Item 11 scope on the control-plane board. **Priority:** P2

## telemetry
- **Per-item cost rollup has no data source** — `show_cost` only affects chat display; board DBs persist zero cost/usage columns (verified against `task_runs` schema 2026-06-12). A rollup needs the kernel to stamp per-run usage into `task_runs.metadata` (or a usage table) at completion — file with a future kernel item, then build the report script here. **Priority:** P2

## Completed
- **reasoning_effort values were model ids** (planner: `gpt-5.3-codex-spark`, researcher: `grok-4.3`) — verified against kernel semantics: the value feeds effort selection (`xhigh/high/medium/low/minimal/none`) and an unrecognized string is silently ignored, no codex quirk involved (the model ids were already correctly set as models elsewhere in each config). Fixed 2026-06-12: planner `high`, researcher `medium`, seeds + live profiles.
