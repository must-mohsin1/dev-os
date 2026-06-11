# Kanban Doctrine Durability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three kanban workflow fixes durable, fleet-wide, and consistent across all four doctrine layers (framework injection, team manifests, run briefings, skills), per the approved spec at `docs/superpowers/specs/2026-06-11-kanban-doctrine-durability-design.md`.

**Architecture:** One canonical seed per repo + install-time fan-out (Approach B), plus the root-cause patch in the hermes-agent checkout (L0). Rollout order is load-bearing: capture live-only profile content into git FIRST (it is one `upgrade.sh` away from destruction), then patch L0, then content fixes, then propagation mechanics, then apply + verify locally, then push.

**Tech Stack:** Markdown skill files, bash installers, one Python string constant. No test framework in dev-os; "tests" are grep/diff assertions with expected output after every change, plus temp-dir smoke tests for scripts. hermes-devcrew has pytest but install.sh glue is verified by smoke test, not pytest (it requires the `hermes` CLI).

**Working directories (absolute, used throughout):**
- `DEVOS=/Users/mustcompanymohsin/projects/mustCompany/must-dev-agents/dev-os` (git, branch `main`)
- `DEVCREW=/Users/mustcompanymohsin/projects/mustCompany/must-dev-agents/hermes-devcrew` (git, branch `main`)
- `HAGENT=/Users/mustcompanymohsin/.hermes/hermes-agent` (git checkout of NousResearch/hermes-agent with local work commits; commit locally, NEVER push)
- `HHOME=/Users/mustcompanymohsin/.hermes` (live tree, not git)

Both repos commit directly to `main` (repo convention — see `f7a3700`, `10e90a1`).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `$DEVOS/agents/devos/skills/kanban-orchestrator/SKILL.md` | rewrite (3-way merge → v3.5.0) | devos orchestration doctrine |
| `$DEVOS/agents/devos/skills/kanban-orchestrator/references/build-watching-playbook.md` | create (copy from profile) | live-only content capture |
| `$DEVOS/agents/devos/skills/kanban-orchestrator/references/structural-fixes-2026-06-11.md` | create (copy from profile) | live-only content capture |
| `$DEVOS/agents/devos/skills/kanban-orchestrator/scripts/safe-complete` | create (copy of repo script) | skill-local guard (3.1.0 text promises it) |
| `$HAGENT/agent/prompt_builder.py` | modify (KANBAN_GUIDANCE step 5) | L0 root-cause fix |
| `$DEVCREW/agents/architect/skills/decompose-goal/SKILL.md` | modify → v1.1.0 | architect dep-graph doctrine |
| `$DEVCREW/skills/devops/kanban-worker/SKILL.md` | create (seed v2.1.0) | devcrew fleet worker doctrine |
| `$DEVOS/skills/devops/kanban-worker/SKILL.md` | create (seed v2.1.0, identical) | devos fleet worker doctrine |
| `$DEVCREW/install.sh` | modify (fan-out 5a) | propagation devcrew fleet |
| `$DEVOS/install.sh` | modify (fan-out 4b) | propagation devos fleet |
| `$DEVOS/scripts/safe-complete` | modify (tighten markers) | enforcement guard |
| `$DEVOS/scripts/sync-doctrine.sh` | create | global tree + strays + categorized duplicates |
| `$DEVOS/scripts/upgrade.sh` | modify (hook) | sync-doctrine on every upgrade |
| `$DEVOS/agents/devos/skills/kanban-doctor/SKILL.md` | modify → v1.1.0 | escalation branch |

---

### Task 1: Capture live-only orchestrator content — three-way merge base (dev-os)

The repo copy was downgraded by `10e90a1` (290 lines, v3.0.0 lineage); the full 3.4.0 content lives only in git history (`f7a3700`, 424 lines); the live profile copy (`$HHOME/profiles/devos/skills/devops/kanban-orchestrator/SKILL.md`, 305 lines, v3.1.0) has the newest safe-complete text, the Build-watching section, and two uncommitted reference docs. Merge = 3.4.0 base + profile-only additions.

**Files:**
- Modify: `$DEVOS/agents/devos/skills/kanban-orchestrator/SKILL.md`
- Create: `$DEVOS/agents/devos/skills/kanban-orchestrator/references/build-watching-playbook.md`
- Create: `$DEVOS/agents/devos/skills/kanban-orchestrator/references/structural-fixes-2026-06-11.md`
- Create: `$DEVOS/agents/devos/skills/kanban-orchestrator/scripts/safe-complete`

- [ ] **Step 1: Restore the 3.4.0 base from git history**

```bash
cd "$DEVOS"
git show f7a3700:agents/devos/skills/kanban-orchestrator/SKILL.md > agents/devos/skills/kanban-orchestrator/SKILL.md
wc -l agents/devos/skills/kanban-orchestrator/SKILL.md
```
Expected: `424`

- [ ] **Step 2: Extract the Build-watching section from the live profile**

```bash
PROFILE_SKILL="$HOME/.hermes/profiles/devos/skills/devops/kanban-orchestrator/SKILL.md"
awk '/^## Build-watching/{f=1} f && /^## / && !/^## Build-watching/{exit} f' "$PROFILE_SKILL" > /tmp/build-watching-section.md
head -1 /tmp/build-watching-section.md && wc -l /tmp/build-watching-section.md
```
Expected: first line `## Build-watching (4-min polls, stuck-worker detection, force-complete)`, ~50-60 lines.

- [ ] **Step 3: Insert the Build-watching section into the restored file, immediately BEFORE the CLI section heading**

Use Edit on `agents/devos/skills/kanban-orchestrator/SKILL.md`: find the unique line

```
## Driving Kanban from the `hermes kanban` CLI (coordinator with terminal access)
```

and replace it with the full contents of `/tmp/build-watching-section.md`, then a blank line, then that same heading line. Verify:

```bash
grep -n "^## Build-watching" agents/devos/skills/kanban-orchestrator/SKILL.md
```
Expected: exactly 1 match.

- [ ] **Step 4: Extract the safe-complete pitfall paragraph from the live profile and insert it**

Locate it in the profile (it is the paragraph whose text includes "The script ships in this skill at" and ends with the sentence referencing `references/structural-fixes-2026-06-11.md`):

```bash
grep -n "safe-complete" "$PROFILE_SKILL" | head -5
```

Copy the entire pitfall bullet/paragraph (from its opening `**` bold marker line through the `structural-fixes-2026-06-11.md` sentence) into the repo file's **Pitfalls** section, immediately AFTER the paragraph that ends with:

```
Never just `complete` it.**
```

(That is the rubber-stamp pitfall restored from 3.4.0; Task 2 rewrites its final sentence — insertion order here does not conflict.) Verify:

```bash
grep -c "safe-complete" agents/devos/skills/kanban-orchestrator/SKILL.md
```
Expected: ≥ 3.

- [ ] **Step 5: Port any remaining profile-only additions**

```bash
diff agents/devos/skills/kanban-orchestrator/SKILL.md "$PROFILE_SKILL" | grep '^>' | grep -v "^> *$" | head -30
```

Review the output. Lines already covered: the `version: 3.1.0` line (ignored — Task 2 sets 3.5.0), Build-watching content (step 3), safe-complete paragraph (step 4). If any OTHER substantive profile-only paragraph appears, insert it into the matching section of the repo file (prefer the profile's wording; never delete restored 3.4.0 content). If the diff shows only the covered material, continue.

- [ ] **Step 6: Copy the two reference docs and the skill-local script**

```bash
cp "$HOME/.hermes/profiles/devos/skills/devops/kanban-orchestrator/references/build-watching-playbook.md" agents/devos/skills/kanban-orchestrator/references/
cp "$HOME/.hermes/profiles/devos/skills/devops/kanban-orchestrator/references/structural-fixes-2026-06-11.md" agents/devos/skills/kanban-orchestrator/references/
mkdir -p agents/devos/skills/kanban-orchestrator/scripts
cp scripts/safe-complete agents/devos/skills/kanban-orchestrator/scripts/safe-complete
chmod +x agents/devos/skills/kanban-orchestrator/scripts/safe-complete
ls agents/devos/skills/kanban-orchestrator/references/ agents/devos/skills/kanban-orchestrator/scripts/
```
Expected: references/ lists `build-watching-playbook.md  research-body-template.md  structural-fixes-2026-06-11.md`; scripts/ lists `safe-complete`.

- [ ] **Step 7: Commit**

```bash
git add agents/devos/skills/kanban-orchestrator/
git commit -m "fix(orchestrator): restore 3.4.0 doctrine dropped by 10e90a1, capture live-only build-watching content

Three-way merge: f7a3700 base (424 lines) + live profile additions
(Build-watching section, safe-complete pitfall v3.1.0 wording, two
reference docs that existed only in ~/.hermes). Spec rollout step 1."
```

---

### Task 2: Orchestrator doctrine rewrites → v3.5.0 (dev-os)

**Files:**
- Modify: `$DEVOS/agents/devos/skills/kanban-orchestrator/SKILL.md`

- [ ] **Step 1: Set version 3.5.0 and add the bump-rule comment**

In the frontmatter, change `version: 3.4.0` → `version: 3.5.0`. Immediately after the closing `---` of the frontmatter, add:

```markdown
<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. -->
```

- [ ] **Step 2: Add the doctrine-hierarchy note**

Insert immediately after the existing intro blockquote (the paragraph starting `> The **core worker lifecycle**`):

```markdown
> **Doctrine hierarchy:** this skill derives from the team manifests —
> `dev-os/team.yaml` + `DEVOS.md` (pipeline; ONE human gate, at the plan) and
> `hermes-devcrew/team.yaml` (build topology: parallel workers → reviewer ∥ QA →
> integrator). On any conflict between this text and the manifests, the
> manifests win.
```

- [ ] **Step 3: Replace the retired siblings advice with the canonical-graph section**

Replace this exact block (restored from 3.4.0):

```markdown
## Designing dep graphs that don't bottleneck on self-block

The 5-step recovery is a tax, not a fix. If you find yourself running it repeatedly across runs, redesign the graph. Two structural moves that help:

- **Make the Reviewer / QA / Integrator cards siblings of the code lanes, not children.** They should be gated on the spec / research card (the brief), not on every implementation card. That way a code-lane self-block cannot stall the reviewer from starting on the parts that ARE ready.
- **Push the per-link dep mode story to the user.** A pending feature (per-link `strict` / `parallel` / `evidence` mode) would let a reviewer card claim once a parent is `running`, not `done`. Until that ships, use the structural-graph fix above. Mention both when the user reports recurring stalls — they may want to schedule the feature.
```

with:

```markdown
## The canonical dep graph (per hermes-devcrew/team.yaml)

Historical note: this section previously advised making the Reviewer / QA /
Integrator cards siblings of the code lanes, gated on the brief. That advice
is retired — it was a workaround for routine worker self-blocks, which the
v2.1.0 worker doctrine and the framework KANBAN_GUIDANCE fix eliminate. With
self-blocks rare and genuine, early review of half-written code is the bug,
not the mitigation.

The canonical topology (`hermes-devcrew/team.yaml` — on conflict, the
manifest wins):

- Implementation cards run in PARALLEL (siblings), linked only where one
  truly consumes another's output (designer card upstream of frontend impl).
- Reviewer (static gate) and QA (dynamic gate) run in PARALLEL — each
  parented on EVERY implementation card.
- Integrator is parented on BOTH gates. When the gates produce fix cards,
  expand the integrator's parent set with them (archive-and-recreate) before
  it runs — see the gate-card closeout procedure in Pitfalls.
- Per-link dep modes (`strict` / `parallel` / `evidence`) remain a pending
  engine feature; mention it if the user reports recurring stalls.
```

Keep the `- **D3-first pattern for verify-and-ship builds.**` bullet that follows — verbatim, unchanged (it is the explicit exception).

- [ ] **Step 4: Replace the rubber-stamp rule sentence and add the closeout procedure**

In the rubber-stamp pitfall, replace the final sentence:

```markdown
**Rule: if a reviewer/QA card's last comment lists N blocking issues, you must (a) wait for the fix cards to complete, (b) ask the user, or (c) post a "I'll address these in <specific follow-up card>" comment BEFORE closing. Never just `complete` it.**
```

with:

```markdown
**Rule: run the gate-card closeout procedure (next pitfall) and complete gate cards only via `scripts/safe-complete`. Never raw-`complete` a gate card.**
```

Then insert as a NEW pitfall paragraph immediately after that paragraph (and after the safe-complete pitfall inserted in Task 1 — order between those two is fine either way, both must precede the next original pitfall):

```markdown
**Gate-card closeout procedure (deterministic).** When a reviewer or QA card
finishes with N blocking findings:

1. Verify a fix card exists for every blocking finding; create the missing
   ones, assigned to the original implementer profile, parented on the gate
   card.
2. Expand the **integrator's** parent set with those fix cards
   (archive-and-recreate — see "Inserting a new step into an ALREADY-BUILT,
   running graph"). The gate against unfixed code is the integrator's parent
   set, not an open gate card.
3. Comment on the gate card mapping each finding → its fix card id.
4. Complete the gate card via `scripts/safe-complete`. Its deliverable is the
   review, which now exists; keeping it open adds rubber-stamp pressure
   without protection.
```

- [ ] **Step 5: Fix the References block**

Replace the entire `## References` list (currently 6 entries, 5 of them dangling `control-plane-item*.md` files) with:

```markdown
## References
- `references/research-body-template.md` — copy-and-modify templates for research task bodies; v1 (default) and v2 (after a "Missing tools" self-reject, appends the tool-inventory assertion block).
- `references/build-watching-playbook.md` — 4-minute poll cadence, stuck-worker detection signals, force-complete decision tree.
- `references/structural-fixes-2026-06-11.md` — the 3-bug analysis (self-block doctrine, reviewer dep graph, rubber-stamp) behind the v2.1.0 worker doctrine and the safe-complete guard.
```

- [ ] **Step 6: Verify**

```bash
cd "$DEVOS"
grep -m1 "^version:" agents/devos/skills/kanban-orchestrator/SKILL.md
grep -c "siblings of the code lanes, not children" agents/devos/skills/kanban-orchestrator/SKILL.md
grep -c "Gate-card closeout procedure" agents/devos/skills/kanban-orchestrator/SKILL.md
grep -c "D3-first pattern" agents/devos/skills/kanban-orchestrator/SKILL.md
for f in $(grep -oE 'references/[a-z0-9-]+\.md' agents/devos/skills/kanban-orchestrator/SKILL.md | sort -u); do
  test -f "agents/devos/skills/kanban-orchestrator/$f" || echo "MISSING $f"
done
```
Expected: `version: 3.5.0`; `0` (sibling advice gone — the historical-note phrasing says "siblings of the code lanes, gated on the brief", which does not match this grep); `1`; `≥1`; no `MISSING` lines.

- [ ] **Step 7: Commit**

```bash
git add agents/devos/skills/kanban-orchestrator/SKILL.md
git commit -m "feat(orchestrator): v3.5.0 — canonical parallel-gates topology, deterministic gate-card closeout, fixed references"
```

---

### Task 3: L0 root-cause fix — KANBAN_GUIDANCE (hermes-agent checkout)

**Files:**
- Modify: `$HAGENT/agent/prompt_builder.py` (the `KANBAN_GUIDANCE` constant, step 5 exception, around lines 218-227)

- [ ] **Step 1: Confirm the pre-state**

```bash
cd "$HAGENT" && git status --short --untracked-files=no
grep -c "most coding tasks" agent/prompt_builder.py
```
Expected: clean tracked tree; `1`.

- [ ] **Step 2: Replace the exception text**

Edit `agent/prompt_builder.py`. Old (exact, including string-concat quoting):

```python
    "Exception: if your output is a code change that needs human review "
    "before counting as merged/done (most coding tasks), drop the "
    "structured metadata (changed_files / tests_run / diff_path) into a "
    "`kanban_comment` first, then end with "
    "`kanban_block(reason=\"review-required: <one-line summary>\")` so a "
    "reviewer can approve+unblock or request changes. Reviewing-then-"
    "completing is more honest than auto-completing work that still needs "
    "eyes on it.\n"
```

New:

```python
    "If your task is a code change and your tests pass, completing with "
    "that evidence IS the honest handoff — downstream reviewer/QA lanes "
    "are the review path, and the pipeline is human-gated once, at the "
    "plan, not at every card. Exception — block instead of complete ONLY "
    "for genuine human-only concerns: security/credential changes, schema "
    "or migration changes, external-network actions (deploys, pushes, "
    "provisioning), or genuine ambiguity in the task body you cannot "
    "resolve. For those, drop the structured metadata (changed_files / "
    "tests_run / diff_path) into a `kanban_comment` first, then end with "
    "`kanban_block(reason=\"review-required: <the concrete human "
    "concern>\")`. A reason that names no concrete concern is a "
    "rubber-stamp request — don't send it.\n"
```

- [ ] **Step 3: Verify it compiles and the marker is gone**

```bash
cd "$HAGENT"
"$HAGENT/venv/bin/python" -m py_compile agent/prompt_builder.py && echo COMPILES
grep -c "most coding tasks" agent/prompt_builder.py
grep -c "genuine human-only concerns" agent/prompt_builder.py
```
Expected: `COMPILES`; `0`; `1`.

- [ ] **Step 4: Commit locally (do NOT push — upstream remote)**

```bash
git add agent/prompt_builder.py
git commit -m "fix(kanban): KANBAN_GUIDANCE — complete-with-evidence is the default; block only for genuine human-only concerns

The 'most coding tasks -> kanban_block(review-required)' exception caused
16+ false-positive self-blocks per devcrew build and contradicts the
one-gate pipeline (gated once, at the plan) and the devcrew-run briefing.
Workers now complete with evidence; blocking is reserved for
security/credential, schema/migration, external-network actions, or
genuine task ambiguity, with the concrete concern named in the reason."
```

---

### Task 4: decompose-goal → v1.1.0 (hermes-devcrew)

The repo copy (47 lines) never had the dep-rule section; the profile copy has a buggy version of it. Fix the repo copy; the installer overwrites the profile copy in Task 13.

**Files:**
- Modify: `$DEVCREW/agents/architect/skills/decompose-goal/SKILL.md`

- [ ] **Step 1: Bump version + add bump-rule comment**

In frontmatter: `version: 1.0.0` → `version: 1.1.0`. After the closing `---`, add:

```markdown
<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. -->
```

- [ ] **Step 2: Update step 6 of the Procedure**

Old:

```markdown
6. **Wire dependencies.** `hermes kanban link <parent> <child>` only where order truly matters;
   leave the rest independent so they run in parallel.
```

New:

```markdown
6. **Wire dependencies.** `hermes kanban link <parent> <child>` only where order truly matters;
   leave the rest independent so they run in parallel. **Reviewer, QA, and integrator lanes
   are NOT independent** — see the dep rule below.
```

- [ ] **Step 3: Append the dep-rule section at end of file (after "## Done when")**

```markdown
## Reviewer / QA / integrator dep rule (REQUIRED)

The reviewer, QA, and integrator lanes are **not** parallel workers. They are
downstream gates (`team.yaml`: verifier, dynamic-verifier, synthesizer). If
you wire them as siblings of the implementation tasks, they run while the
code is still being written and produce "this code doesn't exist yet"
findings.

Implementation cards are siblings unless one consumes another's output —
never chain them by default. The designer card is upstream of frontend
implementation cards only.

**Mandatory dep graph for any build with >3 implementation tasks:**

```
T-design (designer) ──► frontend impl cards only

T1 (impl) ──┐
T2 (impl) ──┤   all implementation cards run in PARALLEL;
 …          ┼─► each one is a parent of BOTH gates
TN (impl) ──┘
        ▼                      ▼
  T14-Reviewer (static)   T15-QA (dynamic)      ← parallel gates
        └───────────┬──────────┘
                    ▼
        T16-Integrator (parents: T14 AND T15; the orchestrator expands
                        this at runtime with every fix card the gates create)
```

Concretely, for every implementation card Tn:

- `hermes kanban link Tn T14` AND `hermes kanban link Tn T15` — one card per
  call (multi-id link is silent on latter ids; loop per-id).
- Integrator: `hermes kanban link T14 T16` and `hermes kanban link T15 T16`.
- Remember FIRST_ARG = PARENT: `link A B` makes A the parent of B.

**When a build has 3 or fewer implementation tasks**, the gates may be
parented on the last impl card only; the integrator still depends on both
gates.

**Ownership discipline (mirrors the devcrew-run briefing):** every card body
MUST list the exact files it creates or modifies under a `Files:` line.
Shared wiring files — barrel/index files, route registries, package.json,
lockfiles, shared config — belong ONLY to the integrator card, which runs
after the gates. Workers must not edit files outside their card's `Files:`
list; anything extra becomes a follow-up card.

**Why this matters:** without the rule, the gates run in parallel with the
impl cards and produce false-positive findings; with it, both gates see
complete code, the integrator sees gated code, and the build stays parallel
where it is safe (the impl cards) and serial only where it must be.
```

- [ ] **Step 4: Verify**

```bash
cd "$DEVCREW"
grep -m1 "^version:" agents/architect/skills/decompose-goal/SKILL.md
grep -c "^| 6\." agents/architect/skills/decompose-goal/SKILL.md
grep -c "parallel gates" agents/architect/skills/decompose-goal/SKILL.md
grep -c "Ownership discipline" agents/architect/skills/decompose-goal/SKILL.md
grep -c "T0  ──► T1" agents/architect/skills/decompose-goal/SKILL.md
```
Expected: `version: 1.1.0`; `0` (no stray-pipe line); `1`; `1`; `0` (no serialized chain diagram).

- [ ] **Step 5: Commit**

```bash
git add agents/architect/skills/decompose-goal/SKILL.md
git commit -m "feat(architect): decompose-goal v1.1.0 — manifest-aligned parallel gates, ownership discipline, designer ordering"
```

---

### Task 5: kanban-worker seed v2.1.0 (hermes-devcrew)

Seed = the already-patched devcrew-backend-dev profile copy, plus the one-gate anchor and version bump.

**Files:**
- Create: `$DEVCREW/skills/devops/kanban-worker/SKILL.md`

- [ ] **Step 1: Copy the patched profile copy in as the seed**

```bash
cd "$DEVCREW"
mkdir -p skills/devops/kanban-worker
cp "$HOME/.hermes/profiles/devcrew-backend-dev/skills/devops/kanban-worker/SKILL.md" skills/devops/kanban-worker/SKILL.md
grep -c "Default behavior is to" skills/devops/kanban-worker/SKILL.md
```
Expected: `1` (confirms this is the patched copy).

- [ ] **Step 2: Bump version + add bump-rule comment**

In frontmatter: `version: 2.0.0` → `version: 2.1.0`. After the closing `---`, add:

```markdown
<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. This file is a repo seed; edit it HERE, never in ~/.hermes/profiles/ (installers overwrite profile copies). -->
```

- [ ] **Step 3: Add the one-gate anchor**

After the paragraph ending:

```markdown
**Default behavior is to `complete` with evidence, not to `block`.**
```

insert as a new paragraph:

```markdown
The pipeline is human-gated exactly once, at the plan (`dev-os/team.yaml`).
A `review-required` block is an **escalation to the orchestrator** for one of
the four concerns below — not a review gate. The reviewer and QA lanes
downstream are the review path.
```

- [ ] **Step 4: Verify and commit**

```bash
grep -m1 "^version:" skills/devops/kanban-worker/SKILL.md
grep -c "human-gated exactly once" skills/devops/kanban-worker/SKILL.md
git add skills/devops/kanban-worker/
git commit -m "feat(skills): shared kanban-worker seed v2.1.0 — complete-with-evidence doctrine, one-gate anchor"
```
Expected greps: `version: 2.1.0`; `1`.

---

### Task 6: kanban-worker seed copy (dev-os)

**Files:**
- Create: `$DEVOS/skills/devops/kanban-worker/SKILL.md`

- [ ] **Step 1: Copy the seed from hermes-devcrew (they must be byte-identical)**

```bash
cd "$DEVOS"
mkdir -p skills/devops/kanban-worker
cp "$DEVCREW/skills/devops/kanban-worker/SKILL.md" skills/devops/kanban-worker/SKILL.md
diff -q skills/devops/kanban-worker/SKILL.md "$DEVCREW/skills/devops/kanban-worker/SKILL.md" && echo IDENTICAL
```
Expected: `IDENTICAL`

- [ ] **Step 2: Commit**

```bash
git add skills/devops/kanban-worker/
git commit -m "feat(skills): kanban-worker seed v2.1.0 for the devos fleet (mirror of hermes-devcrew seed)"
```

---

### Task 7: Installer fan-out + overwrite guard (hermes-devcrew)

**Files:**
- Modify: `$DEVCREW/install.sh` (insert section 5a after the install loop)

- [ ] **Step 1: Insert the fan-out block**

Edit `install.sh`. Old (exact, end of section 5):

```bash
[ -n "$INSTALLED" ] || die "No agents installed."
say "Installed:$INSTALLED"
```

New:

```bash
[ -n "$INSTALLED" ] || die "No agents installed."
say "Installed:$INSTALLED"

# --- 5a) Shared doctrine skills — fan repo seeds into every installed profile ---
# Seeds live in skills/devops/<name>/ at the repo root. Edit doctrine THERE,
# never in ~/.hermes/profiles/ — this block overwrites profile copies (with a
# drift warning) on every install/upgrade.
if [ -d "$SRC/skills/devops/kanban-worker" ]; then
  for d in $AGENT_DIRS; do
    role="$(basename "$d")"; name="devcrew-$role"
    [ -d "$HERMES_HOME_DIR/profiles/$name" ] || continue
    pdir="$HERMES_HOME_DIR/profiles/$name/skills/devops/kanban-worker"
    if [ -f "$pdir/SKILL.md" ] && ! diff -q "$pdir/SKILL.md" "$SRC/skills/devops/kanban-worker/SKILL.md" >/dev/null 2>&1; then
      echo "  ! overwriting drifted skill: $pdir/SKILL.md"
    fi
    mkdir -p "$pdir" && cp -R "$SRC/skills/devops/kanban-worker/." "$pdir/"
    say "skills: $name += kanban-worker (seed)"
  done
fi
```

- [ ] **Step 2: Syntax check and commit**

```bash
cd "$DEVCREW"
bash -n install.sh && echo SYNTAX-OK
git add install.sh
git commit -m "feat(install): fan shared kanban-worker seed into every devcrew profile, warn on drifted copies"
```
Expected: `SYNTAX-OK`

---

### Task 8: Tighten safe-complete markers (dev-os)

Per spec 2b: drop the generic markers that false-positive on ordinary research/decision cards; fix the stale jq comment. Both repo copies (root + skill-local) and the profile mirror get the same content.

**Files:**
- Modify: `$DEVOS/scripts/safe-complete`
- Modify: `$DEVOS/agents/devos/skills/kanban-orchestrator/scripts/safe-complete`

- [ ] **Step 1: Edit the PATTERNS list in `scripts/safe-complete`**

Old:

```bash
PATTERNS=(
  "review-required"
  "blocking issues"
  "needs eyes"
  "needs review"
  "needs human"
  "design decision"
  "option A"
  "option B"
  "needs explicit"
  "needs decision"
  "needs approval"
  "rubber-stamp"
)
```

New:

```bash
# Markers scoped to real gate-card evidence (item5/item6 block reasons).
# Deliberately dropped as too generic: "needs review", "option A", "option B"
# — they false-positive on ordinary research/decision cards.
PATTERNS=(
  "review-required"
  "blocking issues"
  "needs eyes"
  "needs human"
  "design decision"
  "needs explicit"
  "needs decision"
  "needs approval"
  "rubber-stamp"
)
```

- [ ] **Step 2: Fix the stale comment**

Old:

```bash
# Fetch the card. We use the JSON output of `hermes kanban show` so we can
# parse it cleanly with jq.
```

New:

```bash
# Fetch the card. We parse the text output of `hermes kanban show`
# (comments block, latest summary, diagnostics lines) with awk/grep.
```

- [ ] **Step 3: Propagate to the skill-local copy and the profile mirror; verify all three identical**

```bash
cd "$DEVOS"
cp scripts/safe-complete agents/devos/skills/kanban-orchestrator/scripts/safe-complete
cp scripts/safe-complete "$HOME/.hermes/profiles/devos/scripts/safe-complete"
bash -n scripts/safe-complete && echo SYNTAX-OK
diff -q scripts/safe-complete agents/devos/skills/kanban-orchestrator/scripts/safe-complete && \
diff -q scripts/safe-complete "$HOME/.hermes/profiles/devos/scripts/safe-complete" && echo ALL-IDENTICAL
grep -c '"option A"' scripts/safe-complete
```
Expected: `SYNTAX-OK`; `ALL-IDENTICAL`; `0`.

- [ ] **Step 4: Commit**

```bash
git add scripts/safe-complete agents/devos/skills/kanban-orchestrator/scripts/safe-complete
git commit -m "fix(safe-complete): drop generic markers that false-positive on ordinary cards; fix stale jq comment"
```

---

### Task 9: Installer fan-out + overwrite guard (dev-os)

**Files:**
- Modify: `$DEVOS/install.sh` (insert section 4b; `HOME_DIR` is defined at line 19, `SRC` at lines 66-71)

- [ ] **Step 1: Insert the fan-out block**

Edit `install.sh`. Old (exact, the start of section 5):

```bash
# 5) Wire: descriptions, Grok tool, fallback key, runners ---------------------------------------
```

New:

```bash
# 4b) Shared doctrine skills — fan the repo seed into the three profiles ------------------------
# Seed lives in skills/devops/kanban-worker/. Edit doctrine THERE, never in
# ~/.hermes/profiles/ — this block overwrites profile copies (with a drift
# warning) on every install/upgrade.
if [ -d "$SRC/skills/devops/kanban-worker" ]; then
  for p in devos devos-researcher devos-planner; do
    [ -d "$HOME_DIR/profiles/$p" ] || continue
    pdir="$HOME_DIR/profiles/$p/skills/devops/kanban-worker"
    if [ -f "$pdir/SKILL.md" ] && ! diff -q "$pdir/SKILL.md" "$SRC/skills/devops/kanban-worker/SKILL.md" >/dev/null 2>&1; then
      echo "  ! overwriting drifted skill: $pdir/SKILL.md"
    fi
    mkdir -p "$pdir" && cp -R "$SRC/skills/devops/kanban-worker/." "$pdir/"
    say "skills: $p += kanban-worker (seed)"
  done
fi

# 5) Wire: descriptions, Grok tool, fallback key, runners ---------------------------------------
```

- [ ] **Step 2: Syntax check and commit**

```bash
cd "$DEVOS"
bash -n install.sh && echo SYNTAX-OK
git add install.sh
git commit -m "feat(install): fan kanban-worker seed into devos fleet profiles, warn on drifted copies"
```
Expected: `SYNTAX-OK`

---

### Task 10: sync-doctrine.sh + upgrade.sh hook (dev-os)

Covers what the installers don't: the global template tree (`~/.hermes/skills/devops/`), stray profiles outside both fleets (atlas, web-research, youtube_research), and the devos profile's CATEGORIZED duplicate copies (`skills/devops/kanban-orchestrator`, `skills/devops/kanban-worker`) which `hermes profile install` does not touch (it writes the flat `skills/<name>/` layout).

**Files:**
- Create: `$DEVOS/scripts/sync-doctrine.sh`
- Modify: `$DEVOS/scripts/upgrade.sh`

- [ ] **Step 1: Write the script**

Create `scripts/sync-doctrine.sh`:

```bash
#!/usr/bin/env bash
# sync-doctrine — converge every off-repo copy of the kanban doctrine skills
# onto the repo seeds. Covers what the installers don't:
#   1. the global skill template tree (~/.hermes/skills/devops/)
#   2. stray profiles outside both fleets that already carry kanban-worker
#   3. the devos profile's CATEGORIZED duplicates under skills/devops/
#      (hermes profile install only writes the flat skills/<name>/ layout)
# Idempotent. Invoked by scripts/upgrade.sh; safe to run by hand.
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HHOME="${HERMES_HOME:-$HOME/.hermes}"

sync_dir() {  # $1 = seed dir, $2 = destination dir
  seed="$1"; dest="$2"
  [ -d "$seed" ] || return 0
  if [ -f "$dest/SKILL.md" ] && ! diff -q "$dest/SKILL.md" "$seed/SKILL.md" >/dev/null 2>&1; then
    echo "  ! overwriting drifted copy: $dest/SKILL.md"
  fi
  mkdir -p "$dest" && cp -R "$seed/." "$dest/"
  echo "synced: $dest"
}

# 1) Global template tree
sync_dir "$SRC_DIR/skills/devops/kanban-worker"                  "$HHOME/skills/devops/kanban-worker"
sync_dir "$SRC_DIR/agents/devos/skills/kanban-orchestrator"      "$HHOME/skills/devops/kanban-orchestrator"

# 2) Stray profiles outside both fleets that already carry kanban-worker
for pdir in "$HHOME"/profiles/*/; do
  name="$(basename "$pdir")"
  case "$name" in devos|devos-researcher|devos-planner|devcrew-*) continue ;; esac
  [ -f "$pdir/skills/devops/kanban-worker/SKILL.md" ] || continue
  sync_dir "$SRC_DIR/skills/devops/kanban-worker" "$pdir/skills/devops/kanban-worker"
done

# 3) devos profile categorized duplicates (flat copies are installer-managed)
if [ -d "$HHOME/profiles/devos" ]; then
  sync_dir "$SRC_DIR/agents/devos/skills/kanban-orchestrator" "$HHOME/profiles/devos/skills/devops/kanban-orchestrator"
  sync_dir "$SRC_DIR/agents/devos/skills/kanban-doctor"       "$HHOME/profiles/devos/skills/kanban-doctor"
fi

echo "sync-doctrine: done"
```

```bash
chmod +x scripts/sync-doctrine.sh && bash -n scripts/sync-doctrine.sh && echo SYNTAX-OK
```
Expected: `SYNTAX-OK`

- [ ] **Step 2: Smoke-test against a temp tree**

```bash
cd "$DEVOS"
TMP=$(mktemp -d /tmp/sync-doctrine-test.XXXX)
mkdir -p "$TMP/profiles/atlas/skills/devops/kanban-worker" "$TMP/profiles/psx" "$TMP/profiles/devos/skills/devops/kanban-orchestrator"
echo "old content" > "$TMP/profiles/atlas/skills/devops/kanban-worker/SKILL.md"
HERMES_HOME="$TMP" bash scripts/sync-doctrine.sh
diff -q "$TMP/profiles/atlas/skills/devops/kanban-worker/SKILL.md" skills/devops/kanban-worker/SKILL.md && echo STRAY-SYNCED
test ! -d "$TMP/profiles/psx/skills" && echo PSX-UNTOUCHED
diff -q "$TMP/profiles/devos/skills/devops/kanban-orchestrator/SKILL.md" agents/devos/skills/kanban-orchestrator/SKILL.md && echo DEVOS-DUP-SYNCED
diff -q "$TMP/skills/devops/kanban-worker/SKILL.md" skills/devops/kanban-worker/SKILL.md && echo GLOBAL-SYNCED
rm -rf "$TMP"
```
Expected output includes: one `! overwriting drifted copy` warning (atlas), then `STRAY-SYNCED`, `PSX-UNTOUCHED`, `DEVOS-DUP-SYNCED`, `GLOBAL-SYNCED`.

- [ ] **Step 3: Hook into upgrade.sh**

Edit `scripts/upgrade.sh`. Old (final line):

```bash
echo "dev-os upgrade: done ($(cat VERSION 2>/dev/null || echo unknown))"
```

New:

```bash
# Propagate doctrine seeds (global tree + stray profiles + categorized duplicates)
bash "$INSTALL_DIR/scripts/sync-doctrine.sh" || echo "sync-doctrine completed with warnings"

echo "dev-os upgrade: done ($(cat VERSION 2>/dev/null || echo unknown))"
```

- [ ] **Step 4: Commit**

```bash
bash -n scripts/upgrade.sh && echo SYNTAX-OK
git add scripts/sync-doctrine.sh scripts/upgrade.sh
git commit -m "feat(scripts): sync-doctrine — converge global tree, stray profiles, and devos categorized duplicates onto repo seeds"
```

---

### Task 11: kanban-doctor → v1.1.0 escalation branch (dev-os)

**Files:**
- Modify: `$DEVOS/agents/devos/skills/kanban-doctor/SKILL.md`

- [ ] **Step 1: Add version + update the description**

The frontmatter has no `version:` field — add `version: 1.1.0` after the `name:` line, and add the bump-rule comment immediately after the closing `---`:

```markdown
<!-- Doctrine rule: any edit to this file MUST bump the minor version — drift detection across profile copies depends on it. -->
```

In the `description:` line, replace the fragment:

```
Detects the review-required self-block pattern (the #1 cause of stalls on devcrew workstreams) and the non-spawnable-assignee pattern (the #2 cause), runs verification, and unblocks/reassigns/completes the affected cards in one shot.
```

with:

```
Detects the review-required self-block pattern (historically the #1 cause of stalls; rare after the v2.1.0 worker doctrine — remaining blocks are often genuine) and the non-spawnable-assignee pattern, classifies blocks as genuine-concern vs false-positive, escalates the genuine ones to the human, and recovers the false positives.
```

- [ ] **Step 2: Insert the classification step**

Insert a new section immediately AFTER the `### 3. Identify the self-blocked tasks (Pattern 1)` section ends (i.e., immediately before the `### 4. Verify the test claims locally` heading):

```markdown
### 3b. Classify each block BEFORE recovering (genuine concern vs false positive)

Read each blocked card's reason string. Two classes, two different paths:

- **Genuine human-only concern** — the reason names security/credential
  changes, schema/migration changes, external-network actions (deploy, push,
  provisioning), or a concrete ambiguity/decision. **Do NOT run steps 4-8 for
  this card.** Escalate instead: post a `decision-brief` (1-3-1) to the human
  on Discord with the card id, the concern, and your recommendation, and
  leave the card blocked. The human's `unblock` is the resolution.
  Auto-completing these is the rubber-stamp anti-pattern with extra steps.
- **Legacy false positive** — the reason is generic ("needs review", "needs
  eyes", tests pass, no concrete concern named). Proceed with steps 4-8
  (verify → reclaim → unblock → comment → complete via safe-complete).

When unsure, escalate. A wrongly-escalated card costs the human one unblock;
a wrongly-completed card ships an unreviewed security or schema change.
```

- [ ] **Step 3: Route step 8 through the guard**

In `### 8. Complete the tasks`, replace the command:

```
HERMES_KANBAN_BOARD=<board> DEVCREW_BOARD=<board> hermes kanban complete <task_id> [<task_id> ...]
```

with:

```
~/.hermes/profiles/devos/scripts/safe-complete <task_id> <board>   # one id at a time; refuses cards with live review markers
```

- [ ] **Step 4: Dedupe the doubled heading**

The file contains `## Related` on two consecutive lines (lines ~148-149). Delete one of them.

- [ ] **Step 5: Verify and commit**

```bash
cd "$DEVOS"
grep -m1 "^version:" agents/devos/skills/kanban-doctor/SKILL.md
grep -c "### 3b. Classify" agents/devos/skills/kanban-doctor/SKILL.md
grep -c "safe-complete" agents/devos/skills/kanban-doctor/SKILL.md
grep -c "^## Related$" agents/devos/skills/kanban-doctor/SKILL.md
git add agents/devos/skills/kanban-doctor/SKILL.md
git commit -m "feat(kanban-doctor): v1.1.0 — classify blocks before recovery; escalate genuine human concerns, never auto-complete them"
```
Expected greps: `version: 1.1.0`; `1`; `≥2`; `1`.

---

### Task 12: Verify `hermes profile install --force` semantics (throwaway HERMES_HOME)

Spec risk item: replace-vs-overlay is unverified. The fan-out runs after install either way, but record the actual behavior.

**Files:** none (recorded finding only)

- [ ] **Step 1: Run the sentinel test**

```bash
cd "$DEVOS"
export HERMES_HOME=$(mktemp -d /tmp/hermes-semantics.XXXX)
hermes profile install agents/devos --force --yes || echo "INSTALL-FAILED (see note below)"
mkdir -p "$HERMES_HOME/profiles/devos/skills/devops/kanban-worker"
echo sentinel > "$HERMES_HOME/profiles/devos/skills/devops/kanban-worker/SKILL.md"
hermes profile install agents/devos --force --yes || true
cat "$HERMES_HOME/profiles/devos/skills/devops/kanban-worker/SKILL.md" 2>/dev/null || echo "FILE-GONE"
unset HERMES_HOME
```

Interpretation (record the outcome as a comment in the Task 13 commit message):
- Output `sentinel` → `--force` OVERLAYS (extra files survive). Categorized duplicates persist across installs; sync-doctrine keeps them converged.
- Output `FILE-GONE` → `--force` REPLACES the skills tree. The fan-out + sync-doctrine running after install (by construction) restore the categorized copies; no plan change needed.
- `INSTALL-FAILED` (fresh HERMES_HOME may lack base config) → semantics remain unverified; rely on the after-install ordering, note it, and continue.

---

### Task 13: Apply locally + full verification battery

**Files:** none in git (live `~/.hermes` tree changes); fixes go back into earlier files if any check fails.

- [ ] **Step 1: Seeds identical across repos**

```bash
diff -q "$DEVCREW/skills/devops/kanban-worker/SKILL.md" "$DEVOS/skills/devops/kanban-worker/SKILL.md" && echo SEEDS-IDENTICAL
```
Expected: `SEEDS-IDENTICAL`

- [ ] **Step 2: Run the hermes-devcrew installer**

```bash
cd "$DEVCREW" && DEVCREW_SKIP_KEYS=1 bash install.sh 2>&1 | tail -25
```
Expected: per-profile `skills: devcrew-<role> += kanban-worker (seed)` lines for all 9 roles; drift warnings are expected on this FIRST run for previously-patched copies (e.g. devcrew-backend-dev) — that is the guard working.

- [ ] **Step 3: Run the dev-os installer + sync-doctrine**

```bash
cd "$DEVOS" && bash install.sh --yes --skip-oauth 2>&1 | tail -20
bash scripts/sync-doctrine.sh
```
Expected: `skills: devos += kanban-worker (seed)` (×3 profiles); sync output lists the global tree, 3 stray profiles, and the devos categorized duplicates.

- [ ] **Step 4: Every kanban-worker copy converged (expect 15 profiles + global = 16)**

```bash
COUNT=0
for f in "$HOME"/.hermes/profiles/*/skills/devops/kanban-worker/SKILL.md "$HOME"/.hermes/skills/devops/kanban-worker/SKILL.md; do
  [ -f "$f" ] || continue
  COUNT=$((COUNT+1))
  diff -q "$f" "$DEVOS/skills/devops/kanban-worker/SKILL.md" >/dev/null || echo "DRIFT: $f"
done
echo "copies: $COUNT"
grep -L "human-gated exactly once" "$HOME"/.hermes/profiles/*/skills/devops/kanban-worker/SKILL.md
```
Expected: no `DRIFT:` lines; `copies: 16` (9 devcrew + 3 devos-fleet + 3 strays + 1 global; devcrew-designer and devcrew-domain-expert gain the skill via fan-out); `grep -L` prints nothing.

- [ ] **Step 5: Orchestrator + doctor copies converged**

```bash
diff -q "$DEVOS/agents/devos/skills/kanban-orchestrator/SKILL.md" "$HOME/.hermes/profiles/devos/skills/kanban-orchestrator/SKILL.md" && echo FLAT-OK
diff -q "$DEVOS/agents/devos/skills/kanban-orchestrator/SKILL.md" "$HOME/.hermes/profiles/devos/skills/devops/kanban-orchestrator/SKILL.md" && echo CATEGORIZED-OK
diff -q "$DEVOS/agents/devos/skills/kanban-doctor/SKILL.md" "$HOME/.hermes/profiles/devos/skills/kanban-doctor/SKILL.md" && echo DOCTOR-OK
```
Expected: `FLAT-OK`, `CATEGORIZED-OK`, `DOCTOR-OK`. If FLAT-OK fails because `hermes profile install` did not refresh the flat copy, re-run `hermes profile install agents/devos --force --yes` from `$DEVOS` and re-check; if it still differs, copy explicitly (`cp` repo → flat path) and note that the flat path needs the same sync-doctrine treatment (add it to `sync_dir` section 3 and amend the Task 10 commit).

- [ ] **Step 6: Version + doctrine markers everywhere**

```bash
grep -m1 "^version:" "$DEVOS/agents/devos/skills/kanban-orchestrator/SKILL.md"            # 3.5.0
grep -m1 "^version:" "$DEVOS/agents/devos/skills/kanban-doctor/SKILL.md"                  # 1.1.0
grep -m1 "^version:" "$DEVOS/skills/devops/kanban-worker/SKILL.md"                        # 2.1.0
grep -m1 "^version:" "$DEVCREW/agents/architect/skills/decompose-goal/SKILL.md"           # 1.1.0
grep -c "most coding tasks" "$HOME/.hermes/hermes-agent/agent/prompt_builder.py"          # 0
grep -c "genuine human-only concerns" "$HOME/.hermes/hermes-agent/agent/prompt_builder.py" # 1
diff -q "$DEVCREW/agents/architect/skills/decompose-goal/SKILL.md" "$HOME/.hermes/profiles/devcrew-architect/skills/decompose-goal/SKILL.md" && echo ARCHITECT-OK
```
Expected: the four versions as annotated; `0`; `1`; `ARCHITECT-OK`.

- [ ] **Step 7: Idempotency — second run produces zero drift warnings**

```bash
cd "$DEVCREW" && DEVCREW_SKIP_KEYS=1 bash install.sh 2>&1 | grep -c "overwriting drifted"
cd "$DEVOS" && bash install.sh --yes --skip-oauth 2>&1 | grep -c "overwriting drifted"
bash scripts/sync-doctrine.sh | grep -c "overwriting drifted"
```
Expected: `0` `0` `0` — everything already converged, the guard stays silent.

---

### Task 14: Push (dev-os + hermes-devcrew only)

- [ ] **Step 1: Push both repos**

```bash
cd "$DEVOS" && git log origin/main..HEAD --oneline && git push origin main
cd "$DEVCREW" && git log origin/main..HEAD --oneline && git push origin main
```
Expected: dev-os pushes the spec/plan commits + Tasks 1,2,6,8,9,10,11; hermes-devcrew pushes Tasks 4,5,7.

- [ ] **Step 2: Confirm hermes-agent is NOT pushed**

```bash
cd "$HAGENT" && git log origin/main..HEAD --oneline | head -5 && echo "^ local-only commits, intentionally unpushed (upstream PR is a follow-up)"
```

- [ ] **Step 3: Durability — run the real upgrade pipeline end-to-end (post-push)**

```bash
DEV_OS_DIR="$DEVOS" bash "$DEVOS/scripts/upgrade.sh" 2>&1 | tail -15
cd "$DEVOS" && bash install.sh --yes --skip-oauth 2>&1 | grep -c "overwriting drifted"
grep -m1 "^version:" "$HOME/.hermes/profiles/devos/skills/devops/kanban-orchestrator/SKILL.md"
```
Expected: upgrade completes (`git pull` is a no-op post-push), prints `sync-doctrine: done`; drift-warning count `0`; profile orchestrator reads `version: 3.5.0`. The patches survived their own propagation pipeline.

---

## Post-implementation watch (behavioral verification, next real build)

On the next devcrew build (e.g. control-plane item7), confirm: self-blocks ≈ 0
outside the four genuine categories; reviewer and QA start together, only
after all impl cards; zero "code doesn't exist yet" findings; zero
force-completed gate cards; integrator runs only after gate fix cards land;
any genuine block surfaces as a Discord decision-brief instead of an
auto-complete. Regressions here mean a doctrine layer is still contradicting
the manifests — re-audit with the layer table in the spec.

## Explicitly out of scope (spec non-goals)

- Upstream PR to NousResearch/hermes-agent for the KANBAN_GUIDANCE change.
- VPS/devcrew-bridge worker-image rebuild (server fleet inherits L0+L3 on next image build; tighten_crew_caps precedent).
- Engine-level guards in `kanban_complete`/`kanban_block` (spec 2b follow-up).
- Drift-detection CI.
