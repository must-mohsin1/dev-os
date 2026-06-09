# dev-os ☤

**An autonomous agent org that researches, plans, and ships — one command, gated once.**

<p align="center">
  <img src="docs/media/demo.gif" alt="dev-os: one goal → research (Grok) → plan (Codex) → approve → build (devcrew) → report" width="100%">
</p>

You give it a goal; it **researches** with Grok, **plans** a spec, asks you to **approve once**, then
hands the build to [`hermes-devcrew`](https://github.com/must-mohsin1/hermes-devcrew) and reports back.
Runs on the [Hermes](https://hermes-agent.nousresearch.com) agent platform.

---

## Install

### ⚡ One command (recommended)
Installs everything it needs — Hermes (if missing), the Codex + Grok logins, the `hermes-devcrew`
build team, and the three dev-os agents:

```bash
curl -fsSL https://raw.githubusercontent.com/must-mohsin1/dev-os/main/install.sh | bash
```

It'll open your browser twice (Codex, then Grok) to sign in, and prompt before installing anything.
When it finishes:

```bash
devos-run "Add OAuth login with tests" /path/to/your/repo
```

### 🤖 Or: ask your agent to install it
Paste this to any capable agent (a Hermes agent, Claude Code, etc.):

> Install the **dev-os** autonomous agent org from https://github.com/must-mohsin1/dev-os.
> Make sure Hermes is installed (`curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash`),
> then run `hermes auth add openai-codex --type oauth` and `hermes auth add xai-oauth --type oauth`,
> then `git clone https://github.com/must-mohsin1/dev-os && cd dev-os && ./install.sh` (it also installs
> the hermes-devcrew build team). Verify with `devos-run --help`.

<details>
<summary>🔧 Or: manual steps</summary>

```bash
# 1. Hermes (skip if you have it)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
# 2. sign in to the two models (opens your browser)
hermes auth add openai-codex --type oauth     # Codex — coordinator + planner
hermes auth add xai-oauth     --type oauth     # Grok  — researcher / web search
# 3. install dev-os (also installs the hermes-devcrew build team)
git clone https://github.com/must-mohsin1/dev-os && cd dev-os && ./install.sh
```
</details>

### What you need
- **macOS / Linux / WSL2** (Windows native works too — Hermes installs the deps).
- A **Codex** (ChatGPT) account for the coordinator/planner, and a **SuperGrok / xAI** account for research.
- That's it — the installer handles Hermes, the devcrew dependency, and wiring. *(OpenRouter is an optional fallback — `gpt-5.5` / `deepseek/deepseek-v4-flash`.)*

---

## Use it
```bash
devos-run "Add a CSV export endpoint with tests" ./api   # research → plan → [approve] → build → report
devos-run --no-gate "..." ./api                          # fully autonomous (no approval)
devos-improve ./api                                      # propose the highest-value improvement (no build)
hermes gateway start                                     # then talk to devos on Discord
```
Artifacts land in `~/.dev-os-runs/<goal>/` (`brief.md`, `spec.md`, `report.md`).

**Every project gets its own kanban board** — auto-named after the repo (`/path/to/MunafaIQ` → board
`munafaiq`), so work never mixes. Inspect with `hermes kanban --board <name> ls`; override the name
with `DEVCREW_BOARD=myname`.

## The team
| Agent | Model | Job |
|---|---|---|
| **devos** | Codex `gpt-5.3-codex` | coordinator — decompose · route · **gate at the plan** · track · report |
| **devos-researcher** | Grok `grok-4.20-reasoning` (deep `grok-4.3`) | cited web-research briefs, ≤3 parallel sub-searchers |
| **devos-planner** | Codex `gpt-5.3-codex` | approval-ready specs with checkable acceptance criteria |
| **hermes-devcrew** | (separate package) | the 9-agent build team it dispatches to |

Each is a Hermes profile distribution with tuned skills (21 total). **Codex + Grok; never Claude or Gemini.**

## Tools & capabilities

Every agent runs on Hermes and inherits a shared toolset; the researcher adds the research/synthesis
power tools. Scope:

| Toolset | Scope | Emphasis |
|---|---|---|
| `web` | web search + fetch/read pages (`web_search`, `web_extract`) | researcher, planner |
| `browser` | headless browser automation (JS, forms, login-gated pages) | researcher |
| `x_search` | X/Twitter + real-time search via **Grok** | researcher |
| `moa` | **Mixture of Agents** — multi-model synthesis | researcher, devos |
| `context_engine` | retrieval/RAG over large context | researcher |
| `delegation` | spawn parallel sub-agents (≤3 sub-searchers) | researcher, devos |
| `memory` | persistent recall/store across goals (+ `agentmemory` MCP) | devos, planner |
| `todo` | multi-step task tracking | devos |
| `cronjob` | scheduled tasks (the nightly improvement loop) | devos |
| `messaging` | Discord / Slack / etc. (drive + report) | devos |
| `code_execution`, `file`, `terminal` | run code, files, shell | all |
| `vision`, `image_gen` | image analysis + generation | all |
| `session_search`, `clarify`, `computer_use`, `tts` | recall sessions · ask the human · macOS control · speech | all |

**MCP servers:** `agentmemory` (`@agentmemory/mcp`) — persistent cross-session memory, shared by all agents.
Add more with `hermes mcp add`.

**Per agent**
- **devos** — `memory` + `delegation` + `todo` + `moa` + `web`: recall project context, route, decide, track.
- **devos-researcher** — `web` + `browser` + `x_search` + `delegation` + `moa` + `context_engine`: multi-source cited briefs.
- **devos-planner** — `web` (fact-check) + `memory` (recall) on top of its planning skills.

**Skills (libraries)** are listed in [The team](#the-team) table; models are Codex / Grok / OpenRouter.
Inspect or change any agent's tools with `hermes --profile <name> tools list` / `tools enable <toolset>`.

## Safety
One human gate at the plan (`--no-gate` removes it); destructive build steps stay gated inside devcrew;
isolated workspaces per task; an auditable kanban event stream.

## License
MIT — see [LICENSE](LICENSE). Design notes: [`docs/superpowers/specs/`](docs/superpowers/specs/).
Build team: **[hermes-devcrew →](https://github.com/must-mohsin1/hermes-devcrew)**
