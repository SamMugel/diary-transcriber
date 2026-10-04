# Rules Index

Auto-loaded by `opencode.json`. See `AGENTS.md` for naming conventions.

## Workflow rules (always-on `.md`)

| File | Rule | Purpose |
|---|---|---|
| 01-auto-commit-after-changes.md | Auto-Commit After Changes | Commit each set of changes via the auto-commit skill |
| 02-ralph-one-task-per-loop.md | Ralph: One Task Per Loop | Each loop iteration does exactly one task |
| 03-ralph-fresh-context-each-iteration.md | Ralph: Fresh Context Each Iteration | Persist progress to disk; re-read each session |
| 04-ralph-search-before-implementing.md | Ralph: Search Before Implementing | Verify functionality isn't already implemented |
| 05-ralph-backpressure-with-tests.md | Ralph: Backpressure With Tests | Pass validation before marking a task complete |
| 06-ralph-no-placeholders.md | Ralph: No Placeholders Or Minimal Implementations | No stubs, TODOs, or deferred work |
| 07-ralph-spawn-subagents-for-expensive-work.md | Ralph: Spawn Subagents For Expensive Work | Delegate non-trivial work to subagents |
| 08-ralph-single-validation-subagent.md | Ralph: Single Validation Subagent | One subagent for build/test validation |
| 09-ralph-let-ralph-decide.md | Ralph: Let Ralph Decide | Trust the agent; tune the environment |

## Swift language rules (glob-scoped `.mdc`, `**/*.swift`)

| File | Rule | Purpose |
|---|---|---|
| 10-swift-access-control.mdc | Swift Access Control | Encapsulate aggressively; expose only what's needed |
| 11-swift-ai-intent.mdc | Swift AI Intent Snippets | Structured inline notes for AI context |
| 12-swift-codable.mdc | Swift Codable | JSON serialization with minimal boilerplate |
| 13-swift-code-style.mdc | Swift Code Style | Clean, scannable Swift code conventions |
| 14-swift-concurrency.mdc | Swift Concurrency | Swift 6 strict concurrency patterns |
| 15-swift-error-handling.mdc | Swift Error Handling | Typed, descriptive errors throughout the stack |
| 16-swift-memory-management.mdc | Swift Memory Management | Prevent retain cycles in ARC-managed code |
| 17-swift-naming-conventions.mdc | Swift Naming Conventions | Descriptive identifiers following Swift conventions |
| 18-swift-optionals.mdc | Swift Optionals | Avoid force-unwrapping; prefer safe unwrapping |
| 19-swift-swiftui.mdc | Swift SwiftUI Patterns | Declarative UI with dumb views and view-models |
| 20-swift-testing.mdc | Swift Testing | Unit testing for all public types and logic |
| 21-swift-type-safety.mdc | Swift Type Safety | Push checks to compile time via the type system |
