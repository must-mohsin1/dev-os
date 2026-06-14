# Kernel extension strategy — how to ship behavior in the product without a fork

**The constraint.** We install the Hermes kernel (`hermes-agent`) from upstream
(NousResearch), and we update daily. So a `hermes update` hard-resets the kernel to
upstream and **wipes any local kernel patch** (this happened: it erased the item-11
fixes from the working tree; they survived only because they were on backup refs). A
fork-with-patches is a maintenance treadmill against a repo that moves ~600 commits in
days. **We never patch or fork the kernel.**

**The rule.** Everything we need must live in a layer the daily update does NOT touch,
or in upstream itself. Decide per change:

| The change is… | Ship it as… | Where it lives | Survives `hermes update`? |
|---|---|---|---|
| Doctrine / config / skills | dev-os + hermes-devcrew repos → installer seeds `~/.hermes` | our repos | Yes (installer re-seeds; update only touches the kernel repo) |
| Agent-layer logic (verification, integration, gating) | a crew skill + scripts (e.g. the release-manager harness) | hermes-devcrew | Yes |
| **Product-specific kernel behavior, where a hook exists** | a **Hermes plugin** in our repo | our repo, loaded at runtime | Yes (loaded, not patched) |
| **Generic kernel behavior** (every Hermes user benefits) | an **upstream PR** to NousResearch | upstream | Yes (ships in the daily install once merged) |
| Kernel behavior needing a hook that doesn't exist yet | **upstream PR that adds the hook**, then a plugin on top | upstream (hook) + our repo (plugin) | Yes |
| None of the above, product-critical | patch-on-install (maintained soft-fork) | our installer | Only with conflict-resolution every update — **last resort, flag as debt** |

## The plugin mechanism (verified, the durable home for product-specific kernel behavior)

- Loader: `hermes_cli/plugins.py`. A plugin is a directory with a `plugin.yaml`
  manifest (`name`, `version`, `hooks: [...]`) + `__init__.py` exposing
  `register(ctx)`.
- Plugins live in `~/.hermes/plugins/<name>/` (user) or ship via the
  `hermes_agent.plugins` pip entry-point group; enabled in `config.yaml`
  `plugins.enabled`. We already ship one: `devos_usage` (hooks `post_api_request`
  for billing).
- `register(ctx)` can `ctx.register_hook(name, cb)`, `ctx.register_tool(...)`,
  `ctx.register_command(...)`, `ctx.inject_message(...)`.
- Our installer enables the plugin so every fresh install has it. This is the home
  for product-specific kernel behavior the hook surface supports.

## Hook catalog (extension points the kernel exposes today)

`pre_llm_call` (inject into the *user* message, not system prompt), `pre_api_request`
/ `post_api_request` (per-API-call, gives `api_call_count`), `on_session_start` /
`_end` / `_reset` / `_finalize`, `pre_tool_call` / `post_tool_call`,
`transform_llm_output`, `transform_tool_result`, `pre_gateway_dispatch`,
`subagent_start` / `_stop`, `pre_approval_request` / `post_approval_response`.
Notably **absent**: a system-prompt-assembly hook, and any hook at iteration-budget
exhaustion.

## Worked example — item-11 T-B (worker budget visibility + grace call)

Investigated 2026-06-14. Three parts, checked against the catalog:
- (a) inject budget into the worker system prompt → **needs kernel** (no
  system-prompt-assembly hook; the prompt is built once and byte-stable for the
  prefix cache).
- (b) fire a one-time ~80% warning → **plugin-able** (`pre_api_request` gives
  `api_call_count`; `ctx.inject_message` posts the warning).
- (c) grant one grace iteration on exhaustion → **needs kernel** (`_budget_grace_call`
  is private; no hook fires at the exhaustion point).

**Conclusion for T-B:** it is *generic* (every Hermes user wants workers that see
their budget and close out cleanly) and 2/3 needs kernel hooks that don't exist — so
the right path is an **upstream PR to NousResearch**, not a plugin and not a patch.
Meanwhile the v3.10.0 guided-retry doctrine is the mitigation (it rescued 4/4
budget-exhausted cards this session). T-B is not urgent; upstream it when convenient.

**Contrast:** item-11 T-A (assignee validation) and T-C (runtime caps) did NOT need the
kernel — re-homed to the release-manager `spec-verify` and to kanban-orchestrator
v3.11.0 (card-stamping) respectively. T-D became a kanban-doctor v1.3.0 backstop. Only
T-B is genuinely kernel-bound. That ratio (3 of 4 re-homable) is the norm — most
"kernel" urges are really agent-layer or doctrine in disguise.
