# Corpus Review Notes

- A cross-family review of `eval/corpus/` gold tasks ran with Codex and Grok.
- Codex reported six findings: one implementation-bias issue in `backend/lru-cache/rubric.md`, plus five refactor hidden-test gaps where behavior-only checks did not enforce the requested structure.
- Grok returned PASS.
- Folded-in fixes: neutralized the LRU rubric language, added structural assertions for the five refactor tasks, and kept the task specs unchanged.
