# Ralph: Spawn Subagents For Expensive Work

The primary context window acts as a scheduler — it spawns subagents for expensive work (search, file reads, gap analysis, implementation, summarizing test results). Do not allocate the primary context to work that a subagent can do. Use subagents for all non-trivial operations; reserve the primary context for orchestration and decision-making.
