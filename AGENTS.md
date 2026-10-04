# Project conventions

- `AGENTS.md` holds high-level, always-on project instructions.
- `opencode.json` loads `.opencode/rules/*.md`.
- `.opencode/rules/` contains one rule per file, named `NN-<kebab-case>.md`.
- `.mdc` files are glob-scoped, frontmatter-bearing Cursor-style rules that also follow the `NN-<kebab-case>` prefix (continuing from `10-` after the `.md` workflow rules occupy `01-`–`09-`) and keep the `.mdc` extension to distinguish them from always-on `.md` workflow rules.
- `.opencode/skills/` contains one directory per skill, each with a `SKILL.md`.
- A rule file contains only `# <Rule Name>` followed by a concise, imperative rule.
- Reuse or update existing rules and skills; do not duplicate.
- Do not create alternative rule or skill locations.
- Preserve these conventions unless explicitly instructed otherwise.
