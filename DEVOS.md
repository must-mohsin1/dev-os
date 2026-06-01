# Dev OS — configuration & policy

**Purpose.** A parallel-development environment where a coordinator agent assigns research,
planning, and improvement tasks across projects, acts as an assistant, surfaces insights, and helps
make decisions — talking to the team over Discord and dispatching execution to the `hermes-devcrew`
team across isolated branches.

**Deadline.** First **Recruit** prototype: **June 6, 2026** (this week). Set 2026-06-01.

---

## 1. Provider & model policy

| Role | Provider | Model | How |
|---|---|---|---|
| **Main model** | **Codex** (personal, OAuth) | codex (OpenAI) | `hermes auth add openai-codex --type oauth` |
| Fallback #1 | OpenRouter (already authed) | `openai/gpt-5.5` | `hermes fallback add` |
| Fallback #2 | OpenRouter | `deepseek-ai/deepseek-v4-pro` | `hermes fallback add` |
| **Interim primary** (until Codex login) | OpenRouter | `openai/gpt-5.5` | set now — keeps the Dev OS working today |
| 🚫 **Disallowed by policy** | — | **Claude, Gemini** (OAuth) | never set as model/fallback |

> If the **company** Codex OAuth fails, the personal Codex OAuth or the OpenRouter account
> (`openai/gpt-5.5`, `deepseek-ai/deepseek-v4-pro`) is the sanctioned fallback. All confirmed present
> in the model catalog.

## 2. Web search — Grok (xAI)

Hermes exposes Grok search via the built-in **`x_search`** toolset (registers once xAI SuperGrok
OAuth or `XAI_API_KEY` is present **and** the toolset is enabled).

| Mode | Model | Notes |
|---|---|---|
| **Quick search** | `grok-4.20-reasoning` (`x_search.model` default) | `grok-4.20` family ✓ |
| **Deep research** | `grok-4.3` | switch `x_search.model` for deep runs |
| **3 sub-agents** | `grok-4-20-multi-agent` + Hermes subagents (`agent.subagent`, fan-out 3) | parallel research |

Setup: `hermes auth add xai-oauth --type oauth` → `hermes tools enable x_search` (CLI + Discord).

## 3. Comms — Discord (not Telegram)

Discord is the gateway (`discord.dispatch_in_gateway: true` already set). Telegram is **not** used.
Drive the Dev OS from Discord once `hermes gateway start` is running.

## 4. Parallel development (per branch)

- **`hermes -w` / `--worktree`** — run an agent in an isolated git worktree (parallel agents, one
  per branch). This is the "`/goal` for different branches" capability.
- **`devcrew` kanban swarm** — `devcrew-run "<goal>" <repo>` decomposes onto the board; the
  dispatcher runs each task in its own isolated workspace. Multiple goals/branches run concurrently.

## 5. Architecture

```
You ──Discord──► devos (coordinator)            ← Codex main · Grok search · OpenRouter fallback
                   │  research / plan / decide
                   ▼
              hermes-devcrew (9 agents)          ← executes dev work, per-branch, in parallel
              architect→designer→workers→reviewer+qa→integrator
```

- **`devos`** profile = the assistant/coordinator (this policy's models). Assigns tasks per project,
  runs Grok research, surfaces insights, drives Discord.
- **`hermes-devcrew`** = the execution team (already built, v0.3.0, OpenRouter — policy-compliant,
  no Claude/Gemini).

## 6. Setup runbook

**Install the package:** `./install.sh` (idempotent; `--with-cron` adds the nightly improvement loop).
Then drive it: `devos-run "<goal>" <repo>` (research → plan → [approve] → build → report),
`devos-run --no-gate ...` (autonomous), or `devos-improve <repo>` (propose the top improvement).
Agents: **devos** (coordinator/Codex) · **devos-researcher** (Grok) · **devos-planner** (Codex);
**devcrew** = build dependency. The installer performs:
1. `hermes auth add openai-codex --type oauth`  (Codex main — **your OAuth**; company first, else personal)
2. `hermes auth add xai-oauth --type oauth`      (Grok search — **your OAuth**)
3. create + configure the `devos` profile (model, fallbacks, `x_search`, 3 research subagents)
4. `hermes tools enable x_search` on CLI + Discord
5. verify, then `hermes --profile devos model` → pick the Codex model (post-login)

## 7. Status

| Item | State |
|---|---|
| Provider support (openai-codex, xai-oauth, openrouter) | ✅ confirmed via `hermes auth add` |
| Models exist (gpt-5.5, deepseek-v4-pro, grok-4.20, grok-4-20-multi-agent) | ✅ in catalog |
| Discord gateway | ✅ configured |
| Parallel dev (`-w` + devcrew swarm) | ✅ available |
| `devos` coordinator profile | ✅ live on **Codex** (`gpt-5.3-codex`) |
| **Codex OAuth login** | ✅ authed (`openai-codex` in credential pool) |
| Switch `devos` primary → Codex | ✅ done — main model = `gpt-5.3-codex` |
| **Grok (xai) OAuth login** | ✅ authed (`xai-oauth`); `x_search` enabled + verified end-to-end |

## 8. June 6 — Recruit prototype plan

> *Assumption:* "Recruit" = the first prototype of the Dev OS coordinator that **recruits/assigns**
> the devcrew to a project and runs it end-to-end from Discord. Confirm/adjust scope.

- **Jun 1 (done):** feasibility confirmed; `devos` coordinator stood up (interim gpt-5.5); devcrew
  v0.3.0 live; runbook + setup script written.
- **Jun 2:** you run `setup-devos.sh` → Codex + Grok OAuth; switch `devos` primary to Codex; verify
  Grok `x_search` quick + deep.
- **Jun 3:** wire `devos` → devcrew dispatch (coordinator briefs `devcrew-run` per project/branch);
  Discord drive test.
- **Jun 4:** parallel-dev proof — 2 branches/goals running concurrently via worktrees + swarm.
- **Jun 5:** research/planning loop — `devos` uses Grok deep research + 3 subagents to produce a
  project plan, assigns improvement tasks; dogfood on a real repo (e.g. MunafaIQ).
- **Jun 6:** Recruit prototype demo — one Discord message → research → plan → devcrew executes →
  PR, end to end.

## 9. Open questions
- Exact definition/scope of "Recruit" (confirm the assumption above).
- Company vs personal Codex account precedence for OAuth.
- Should the user's existing trading/psx profiles adopt this policy, or stay as-is? (Default: stay.)
