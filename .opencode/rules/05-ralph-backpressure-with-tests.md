# Ralph: Backpressure With Tests

Validation is the only acceptable exit signal for a loop iteration. Backpressure (tests, type checks, builds, linters) must pass before a task is marked complete and committed. After making a change, run the test for the unit of code that was implemented and explain what it covers and why it matters.
