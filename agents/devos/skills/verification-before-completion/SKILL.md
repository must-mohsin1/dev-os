---
name: verification-before-completion
description: "Never claim done without running the check and showing the evidence."
version: 1.0.0
author: hermes-devcrew
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [verification, quality, testing, discipline, evidence]
    related_skills: [test-driven-development, adversarial-review]
---

# Verification Before Completion

Use before marking ANY task complete or claiming a fix works. **Evidence before assertions —
always.**

## The rule
A task is "done" only when you have **run the verifying command and seen it pass** — not when the
code merely looks right.

## Procedure
1. **State the claim.** What are you about to assert? ("tests pass", "endpoint returns 200",
   "build is green").
2. **Pick the command that proves it.** Tests, build, linter, a `curl`, a script run — the thing
   that would FAIL if your claim were false.
3. **Run it.** Actually execute it in the workspace. Don't reason about what it "should" do.
4. **Read the output.** Exit code 0? All green? No new warnings? If anything is red, you're not done.
5. **Report with evidence.** In your `hermes kanban complete` summary, include the command and its
   key output (pass counts, exit status). No evidence → not complete.

## Red flags (you are rationalizing)
- "It's a trivial change, no need to run it" → run it.
- "The test should pass now" → "should" is not "did". Run it.
- "I'll mark it done and fix later if it breaks" → no. Verify first.

## Done when
You can show the exact command + output that proves the task's acceptance criteria are met.
