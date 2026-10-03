---
name: Auto-Commit
description: Commit changed files with a conventional-commit message explaining what and why, derived from the prompts that generated the changes. Invoke after each set of changes.
---

# Auto-Commit

## Workflow

1. Run `git status --short` to identify changed files.
2. Stage relevant changes: `git add -A` (exclude only if `.gitignore` misses something).
3. Inspect staged diff: `git diff --cached --stat` (and `git diff --cached` if needed).
4. Derive the commit message per "Message format" below.
5. Commit with `git commit -m "<title>" -m "<body>"`.
6. Verify with `git log -1 --stat`.

## Message format

Title: `<type>(<scope>): <subject>`

- `type` — conventional commits type (`feat`, `fix`, `docs`, `refactor`, `chore`, `build`, `style`, `perf`, `test`, `ci`, `revert`).
- `scope` — optional, the affected module/folder. Omit parentheses if none.
- `subject` — imperative, lowercase, ≤ 72 chars, no trailing period.

Body (blank line after title):

1. **What** — one bullet per logical group of changed files, citing paths.
2. **Why** — a final paragraph starting with `Why:` — paraphrase the prompts that generated the changes (≤ 4 sentences, no full transcript). Do not invent rationale.

Example:

```
feat(specs): add architecture and subsystem contracts

- specs/architecture.md, specs/build-plan.md: layout and phased rollout
- specs/subsystems/*.md: per-module contracts

Why: The prompt asked to export the product vision to specs in a dedicated folder.
```

## Exclusions

- Do not commit secrets or credentials.
- Do not amend or force-push previous commits.
- Skip if the working tree is clean.

## Failure mode

If `git commit` fails (hook, signing, etc.), surface the error verbatim and stop. Do not retry with `--no-verify` unless the user explicitly approves.
