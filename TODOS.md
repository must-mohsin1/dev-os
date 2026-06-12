# TODOS

## devos-run
- **Decide on report-step leniency** — step 5 still accepts the error-log fallback for report.md (documented in-line as intentional: the build is already dispatched). Revisit if reports gain downstream consumers. **Priority:** P3

## scripts
- **verify_code_landed.sh rewrite or retirement** — excluded from the v0.1.2 ship: unexpanded glob makes it exit 2 on every run, BSD sed `\s` breaks Files-scope parsing on macOS, the advertised diff-against-base fallback does not exist (fails open), the baseline is HEAD not the card's base commit (committed work falsely refused), no board context on `kanban show`, and nothing references it. The verified findings were filed onto the Item 10 plan card (control-plane board, t_9c206b33) as requirements for the kernel-side completion gate (T-F). Rewrite here only if T-F stalls. **Priority:** P2
- **Fan-out test coverage** — `install.sh` §4a/§5 and `scripts/sync-doctrine.sh` are the only mechanisms distributing doctrine/configs to live profiles and have zero automated tests; a silent-skip regression would strand stale doctrine fleet-wide. Minimal test: run the fan-out against a temp HERMES_HOME with fake profiles and assert byte-identical copies + drift warning. **Priority:** P2

## agents
- **Real wall-clock caps via per-task max_runtime_seconds** — `agent.gateway_timeout` is inert for dispatched kanban workers (it only governs gateway chat-session inactivity), which is why it is deliberately absent from the profile configs. Dispatcher-side per-profile `max_runtime_seconds` defaults are Item 10 scope. **Priority:** P2
- **reasoning_effort values are model ids** (planner: `gpt-5.3-codex-spark`, researcher: `grok-4.3`) — likely falling back to a default tier. Verify Hermes semantics before changing; the codex/ChatGPT-account quirks documented in the config comments may make this deliberate. **Priority:** P3

## Completed
