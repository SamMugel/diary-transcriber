---
name: Ralph PRD Implementer
description: Inventory all PRDs in the PRD/ directory, auto-decide implementation order by dependency and priority, then spawn subagents to implement each PRD one at a time following Ralph Wiggum principles (search-before-implement, backpressure, commit per task).
---

# Ralph PRD Implementer

A Ralph Wiggum–style orchestrator that reads every PRD in `PRD/`, determines the optimal sequence to implement them, then spawns a subagent per PRD to implement it.

## Preconditions

- `PRD/*.md` contains at least one document named `NN-<kebab-case>.md`.
- Each PRD has: a `# Title`, `## Requirements`, and `## Acceptance Criteria`. Optional top-level `Priority:` and `Depends:` fields are recognized.
- `AGENTS.md` documents the build, test, and lint commands that serve as backpressure.

## Workflow

1. **Inventory.** Glob `PRD/*.md`. If empty, notify the user and stop.
2. **Parse.** Extract `Priority:` (default: filename's `NN-` prefix) and `Depends:` (comma-separated list of other PRD slugs).
3. **Order.** Topologically sort by `Depends:` to satisfy dependencies first. Within each level, sort by `Priority` ascending; ties break by filename. If a dependency cycle is detected, surface it and stop.
4. **Generate or update `IMPLEMENTATION_PLAN.md`** at the project root as a checklist in the determined order.
5. **Iterate.** For each PRD in order:
   a. Spawn a **research subagent** to search the codebase and confirm the feature is not already implemented (Ralph rule 04).
   b. Spawn an **implementation subagent** with the PRD content, research findings, and `AGENTS.md`. This subagent implements the PRD completely (no placeholders — rule 06), runs the tests for the unit of code it touched, loops locally to fix failures (max 3 iterations), and commits using the `auto-commit` skill. It does NOT push.
   c. Spawn a **validation subagent** (exactly one — rule 08) that runs the full test suite and build, reports pass/fail.
   d. If validation passes, mark the PRD complete in `IMPLEMENTATION_PLAN.md`. If it fails, mark it blocked with the error, append the error to the plan, and move on — blocked PRDs can be retried in a later loop per eventual consistency.
6. **Update `AGENTS.md`.** If subagents discovered build quirks or useful patterns, append them under a `## Learnings` section.
7. **Stop.** Output `RALPH_COMPLETE` when all PRDs are complete, or `RALPH_BLOCKED: <count> blocked` listing them.

## Agent spawning rules

- **Research subagents:** spawn as many in parallel as needed (read-only, no conflicts).
- **Implementation subagent:** exactly one per PRD, sequential. Write access. No recursive delegation.
- **Validation subagent:** exactly one, after implementation. Runs full build + test suite, reports binary pass/fail.

## PRD file format

See `PRD/README.md` for the canonical format guide.
