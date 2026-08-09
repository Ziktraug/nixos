# Pattern: Large Output Normalization

When tool output is large:

- extract only required fields
- remove repetition
- summarize early
- keep ≤10 representative lines as evidence

Never stream large logs into main context unless explicitly requested.
