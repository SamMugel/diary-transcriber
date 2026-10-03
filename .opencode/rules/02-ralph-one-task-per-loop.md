# Ralph: One Task Per Loop

Follow Geoffrey Huntley's Ralph Wiggum formalism: each loop iteration does exactly one task — no batching. Pick the highest-priority incomplete item from the active plan, implement it fully, validate, commit, then stop. Relaxed batching is permitted only after the project stabilizes; revert to single-task if quality degrades.
