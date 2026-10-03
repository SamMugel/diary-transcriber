---
name: Auto-Commit
description: Commit changed files with a conventional-commit message that explains what and why, derived from the prompts that generated the changes. Invoke after each set of changes.
---

# Auto-Commit

Commit the current set of changes to Git using the conventions below. This skill is triggered by the `12-auto-commit-after-changes` rule after each set of changes OpenCode makes.

## Workflow

1. Run `git status --short` to identify changed, staged, and untracked files.
2. Stage all relevant changes: `git add -A` (or stage explicitly if some files should be excluded, e.g. build artifacts that the project's `.gitignore` does not catch).
3. Inspect the staged diff to write an accurate message: `git diff --cached --stat` and, if needed, `git diff --cached`.
4. Derive the commit message (see "Message format" below) from:
   - The **what**: file-level changes in the staged diff.
   - The **why**: the prompts exchanged in this session that caused the changes.
5. Commit with `git commit -m "<title>" -m "<body>"` (or a heredoc for multi-paragraph bodies).
6. Verify with `git log -1 --stat`.

## Message format

### Title (subject line)

```
<type>(<scope>): <subject>
```

- **`type`** — one of:
  - `feat` — new feature or capability
  - `fix` — bug fix
  - `docs` — documentation only
  - `style` — formatting, whitespace, no functional change
  - `refactor` — code change that neither adds a feature nor fixes a bug
  - `perf` — performance improvement
  - `test` — adding or fixing tests
  - `chore` — build tooling, dependencies, config
  - `build` — build system changes
  - `ci` — CI/CD pipeline changes
  - `revert` — reverts a previous commit
- **`scope`** — optional, the affected module/folder (e.g. `specs`, `recorder`, `opencode-config`). Omit the parentheses if there is no scope.
- **`subject`** — imperative, lowercase, ≤ 72 characters, no trailing period, no leading "Add"/"Fix" bloat — describe the change, not the action.

Examples:
- `feat(specs): add architecture and subsystem contracts`
- `fix(transcription): respect Whisper API timeout`
- `chore(opencode): bootstrap AGENTS.md and rule files`

### Body

Blank line after the title. The body has two parts, each as a bulleted list or short paragraph:

1. **What was changed** — one bullet per logical group of files. Group related files together rather than listing every file. Cite file or folder paths when it helps clarity.
2. **Why** — a final paragraph introduced by `Why:` explaining the prompts that generated the changes. Quote or paraphrase the key prompt ask; do not paste the full transcript.

Hard limits:
- Wrap body lines at ≤ 100 characters.
- If the title alone captures everything, a body is optional — but the `Why` paragraph is required for any change spanning more than one file.

### Example

```
feat(specs): add architecture and subsystem contracts

- specs/product-vision.md: target product, explicit non-goals, quality bars
- specs/decisions.md: decision log D-0001..D-0011 with rationale
- specs/architecture.md: folder layout, layering, reuse plan, known risks
- specs/build-plan.md: phased MVP-to-shareable rollout
- specs/subsystems/{recording,transcription,storage,ui,packaging}.md: per-module contracts

Why: The reviewed repository contained only a legacy CLI webcam recorder whose README contradicted the repo name. The prompt asked to export the clarified product vision to basic specs in a dedicated folder and fix contradictions in outdated files. This commit implements that prompt.
```

## Rules for deriving "why"

- Trace back through the prompts in the current session that led to each changed file or group of files.
- If multiple prompts contributed to one commit, summarize each prompt's contribution in one sentence.
- Do not invent a rationale that the prompts did not evidence. If the reason is unclear, state "Derived from prior session prompt" and describe the observable change.
- Keep the `Why:` paragraph ≤ 4 sentences.

## Exclusions

- Do not commit secrets, API keys, or credentials. The `.gitignore` should already exclude build artifacts; trust it and do not duplicate its rules here.
- Do not amend or force-push previous commits as part of this skill.
- Do not commit empty trees; skip the commit entirely if `git status --short` is empty.

## Failure mode

If `git commit` fails (pre-commit hook, signing error, etc.), surface the error output verbatim and stop — do not retry with `--no-verify` unless the user explicitly approves.
