# Ralph: Single Validation Subagent

For build and test operations, spawn exactly one subagent for validation — never fan out validation across multiple subagents, as this creates bad-form backpressure. Subagents are reserved for search and file operations. The validation subagent's result determines commit and next-iteration.
