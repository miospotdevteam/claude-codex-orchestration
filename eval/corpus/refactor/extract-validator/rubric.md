# Quality rubric — extract shared validator

Scored 0–5 per dimension, layered on top of objective correctness
(behavior preserved + `validators.js` present and correct).

## Dimensions

1. **Duplication removed (0–5)** — The email and non-empty-string checks
   live in exactly one place and both callers use them. Penalize any
   residual copy of either check in `users.js` or `products.js`.

2. **Idiomatic (0–5)** — Clean CommonJS: a small predicates module,
   destructured imports. Penalize re-exporting through indirection or
   leaving the regex inline "just in case".

3. **Minimal & behavior-preserving (0–5)** — Only the validation is
   extracted; the returned shapes, error messages, and id sequencing are
   untouched. Penalize incidental changes (renamed fields, reordered
   checks that change which error fires first).

4. **Readable (0–5)** — A reader sees at a glance that both factories
   validate via the shared predicates. Penalize predicate names that
   don't state what they assert.

5. **Naming (0–5)** — `isNonEmptyString` / `isEmail` (or equally clear).
   Penalize vague names like `check` or `valid`.
