# PRD Directory

This directory holds Product Requirements Documents for the Diary Transcriber project. Each file is a Markdown document named `NN-<kebab-case>.md`, where `NN` is a two-digit priority/order number.

The `ralph-prd-implementer` skill reads all files here, determines implementation order by dependency and priority, and spawns subagents to implement each PRD one at a time following Ralph Wiggum principles.

## File format

Each PRD is a JSON file named `NN-<kebab-case>.json`, where `NN` is a two-digit
priority/order number.

```json
{
  "title": "<Feature name>",
  "priority": 1,
  "depends": ["<other-prd-slug>", "<other-prd-slug>"],
  "status": "todo",
  "requirements": [
    "<functional requirement>",
    "<functional requirement>"
  ],
  "acceptance_criteria": [
    "<a specific, testable criterion>"
  ],
  "out_of_scope": [
    "<explicit non-goal>"
  ]
}
```

- `priority` is an integer; lower = higher priority. If absent, use the
  filename's `NN-` prefix.
- `depends` is an array of other PRD slugs (filename without leading `NN-` and
  `.json` suffix) used to topologically sort dependencies first. Omit or use an
  empty array if the PRD has no upstream dependencies.
- `status` is either `"todo"` or `"done"` — the sole tracking attribute for
  implementation progress.
- `acceptance_criteria` must be specific and testable — not "works correctly"
  but "recording starts within 1 second of tapping Start."

## How to use

1. Author each PRD as a separate Markdown file here.
2. Run the `ralph-prd-implementer` skill — it will inventory, order, and implement them.
3. Progress is tracked in `IMPLEMENTATION_PLAN.md` at the project root.
