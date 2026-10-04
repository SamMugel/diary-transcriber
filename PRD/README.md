# PRD Directory

This directory holds Product Requirements Documents for the Diary Transcriber project. Each file is a Markdown document named `NN-<kebab-case>.md`, where `NN` is a two-digit priority/order number.

The `ralph-prd-implementer` skill reads all files here, determines implementation order by dependency and priority, and spawns subagents to implement each PRD one at a time following Ralph Wiggum principles.

## File format

```markdown
# <Feature name>

Priority: 1
Depends: <other-prd-slug>, <other-prd-slug>

## Requirements

- <numbered or bulleted list of functional requirements>

## Acceptance Criteria

- <a specific, testable criterion>

## Out of Scope

- <optional: explicit non-goals for this PRD>
```

- `Priority` is an integer; lower = higher priority. If absent, use the filename's `NN-` prefix.
- `Depends` is a comma-separated list of other PRD slugs used to topologically sort dependencies first. Omit if the PRD has no upstream dependencies.
- `Acceptance Criteria` must be specific and testable — not "works correctly" but "recording starts within 1 second of tapping Start."

## How to use

1. Author each PRD as a separate Markdown file here.
2. Run the `ralph-prd-implementer` skill — it will inventory, order, and implement them.
3. Progress is tracked in `IMPLEMENTATION_PLAN.md` at the project root.
