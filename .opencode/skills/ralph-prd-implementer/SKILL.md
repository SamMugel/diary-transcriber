---
name: Ralph PRD Implementer
description: Inventory all PRDs in the PRD/ directory, auto-decide implementation order by dependency and priority, then spawn subagents to implement each PRD one at a time following Ralph Wiggum principles (search-before-implement, backpressure, commit per task).
---

# Ralph PRD Implementer

A Ralph Wiggum–style orchestrator that reads every Product Requirements Document in `PRD/`, determines the optimal sequence to implement them, then spawns a subagent per PRD to implement it.

## Preconditions

- The `PRD/` directory must exist at the project root (created on first run).
- Each file inside `PRD/` is a Markdown document named `NN-<kebab-case>.md`, where `NN` is a two-digit priority/order number.
- Each PRD contains, at minimum: a `# Title`, a `## Requirements` section, and a `## Acceptance Criteria` section. An optional top-level `Priority:` field and `Depends:` field are recognized.
- `AGENTS.md` documents the build, test, and lint commands that serve as backpressure.
- `specs/` and `build-plan.md` already exist as the higher-order project context.

## Workflow

1. **Inventory.** Glob `PRD/*.md`. If the directory is empty or has no `.md` files, notify the user that there are no PRDs to implement and stop.
2. **Parse.** For each PRD, extract:
   - `Priority:` field (default: the `NN-` numeric prefix of the filename).
   - `Depends:` field (comma separated list of other PRD slugs or filenames).
   - The full Markdown content.
3. **Order.** Topologically sort the PRDs by `Depends:` to satisfy dependencies first. Within a dependency group, sort by `Priority` ascending (lower number = higher priority). If a dependency cycle is detected, surface it and stop — cycles must be broken by the human editing the PRDs.
4. **Generate or update `IMPLEMENTATION_PLAN.md`.** Write the ordered list of PRDs as a checklist to `IMPLEMENTATION_PLAN.md` at the project root. Append a short justification for each ordering choice.
5. **Iterate.** For each PRD in order:
   a. Spawn a **research subagent** (general agent) to search the existing codebase and confirm the feature is not already implemented — see Ralph rule `04-ralph-search-before-implementing.md`.
   b. Spawn a **decision subagent** (general agent) with the PRD content, research findings, and `AGENTS.md` build/test commands. This subagent:
      - Implements the PRD completely (no placeholders — see `06-ralph-no-placeholders.md`.
      - Runs the build and tests for the unit of code it touched.
      - If tests fail, loops locally to fix them (max 3 iterations).
      - Commits with a conventional-commit message (see `auto-commit` skill).
      - Does NOT push — pushing is an explicit human or external-CI step.
   c. Wait for the implementation subagent to finish.
   d. Spawn a **validation subagent** (general agent, exactly one — see `08-ralph-single-validation-subagent.md`) that runs the full test suite and build, and reports pass/fail.
   e. If validation passes, mark the PRD as complete in `IMPLEMENTATION_PLAN.md`. If validation fails, mark it as blocked with the error, append the error to the plan, and move on to the next PRD — per eventual consistency, blocked PRDs can be retried in a later loop.
   f. If all 10 PRDs in `IMPLEMENTATION_PLAN.md` are either complete or blocked, stop, and report the summary.
6. **Update `AGENTS.md`.** If the implementation or validation subagents discovered build quirks, gotchas, or useful patterns, append them to `AGENTS.md` under a `## Learnings` section (if it doesn't already exist).
7. **Stop conditions.** The loop ends when either:
   - All PRDs are marked complete. Output `RALPH_COMPLETE`.
   - All remaining PRDs are marked blocked. Output `RALPH_BLOCKED: <count> PRDs blocked` and list them.
   - The user stops it manually.
8. **Commit.** After any change to `IMPLEMENTATION_PLAN.md`, commit it using the `auto-commit` skill conventions.

## PRD file format

```markdown
# <Feature name>

Priority: 1
Depends: <other-prd-slug>, <other-prd-slug>

## Requirements

- <numbered or bulleted list of functional requirements>

## Acceptance Criteria

- <a specific, testable criterion>
- <a specific, testable criterion>

## Out of Scope

- <optional: explicit non-goals for this PRD>
```

- `Priority` is an integer; lower = higher priority. If absent, use the filename's `NN-` prefix.
- `Depends` is optional; omit if the PRD has no upstream dependencies.
- `Acceptance Criteria` must be specific and testable — not "works correctly" but "recording starts within 1 second of tapping Start."

## Implementation order algorithm

```
1. Build dependency graph from each PRD's `Depends:` field.
2. Topological sort (Kahn's algorithm or equivalent).
3. If cycle: error out with the cycle listed.
4. For each level of the topological sort, sort by Priority ascending.
5. For items with same priority at same level, sort by filename.
6. Output the flattened ordered list.
```

## Agent spawning rules (Ralph Wiggum approach)

- **Research subagents:** spawn as many as needed in parallel (they are read-only
  and don't conflict). Each one studies a specific area of the codebase or a
  specific PRD.
- **Implementation subagent:** exactly one per PRD, run sequentially. It has
  write access to the codebase. It must not spawn its own implementation
  subagents (no recursive delegation) — keep the loop single-deep.
- **Validation subagent:** exactly one, after implementation. It runs the full
  build + test suite and reports a binary pass/fail.

## Example invocation

User: "run the Ralph PRD skill"

1. The skill reads `PRD/` and finds:
   - `01-d-0001-mac-desktop-baseline.md`
   - `02-d-0003-avfoundation-recording.md`
   - `03-d-0004-hybrid-transcription.md`
   - `04-d-0005-plain-folder-storage.md`
   - `05-d-0008-swiftui-timeline.md`

2. It builds the dependency graph:
   - `02` depends on `01`
   - `03` depends on `02`
   - `04` depends on `01`
   - `05` depends on `03` , `04`

3. Topological sort with priority ordering:
   Level 1: `01-d-0001-mac-desktop-baseline.md`
   Level 2: `02-d-0003-avfoundation-recording.md`, `04-d-0005-plain-folder-storage.md`
   Level 3: `03-d-0004-hybrid-transcription.md`

4. Implementation begins with `01`, then `02` and `04` (sequential), then `03`, then `05`.

5. For each, a research subagent confirms the feature isn't already implemented (Ralph rule `04`), then an implementation subagent implements and commits, then a validation subagent runs the full test suite.

6. `IMPLEMENTATION_PLAN.md` is updated after each PRD.

## Notes

- This skill follows the Ralph Wiggum formalism pioneered by Geoffrey Huntley. Each iteration gets fresh context, picks one task, implements it fully, validates with backpressure, commits, and loops.
- Faithfulness is the goal: the skill does not try to "optimize" by batching or parallelizing implementation — that breaks the isolation that makes Ralph work.
- If the per-PRD implementation subagent produces wrong code, do not patch the utility implementation here — instead, edit the PRD or `AGENTS.md` to steer toward correctness, per `10-ralph-let-ralph-decide.md`.
- `IMPLEMENTATION_PLAN.md` is the single shared state file on disk (see `09-ralph-shared-state-on-disk.md`); the loop never carries plan state in the conversation.
