# Project conventions

This project follows the conventions below. Preserve them unless explicitly
instructed otherwise.

## Structure

- `AGENTS.md` holds high-level, always-on project instructions.
- `opencode.json` loads `.opencode/rules/*.md`.
- `.opencode/rules/` contains one rule per file.
- `.opencode/skills/` contains one directory per skill, each containing a
  `SKILL.md`.

## Rule files

- Map each input rule, row, or item to exactly one rule file.
- Name rules `NN-<concise-kebab-case-name>.md`, preserving input order.
- A rule file contains only `# <Rule Name>` followed by a concise, imperative
  rule.
- Reuse or update existing rules and skills; do not duplicate.
- Do not create alternative rule or skill locations.
- Preserve these conventions unless explicitly instructed otherwise.
