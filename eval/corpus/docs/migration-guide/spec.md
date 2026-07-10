# Task: Write a migration guide for a breaking library change

Write a **migration guide** for users upgrading a popular open-source
HTTP-client library, **fetchkit**, from **v2** to **v3**. The audience is
existing users on v2 who need to update their code. Your guide ships as
`MIGRATING.md` in the v3 release.

Below is the source of truth: the concrete set of breaking and notable
changes between v2 and v3.

## Source of truth — what changed in v3

1. **`createClient` options renamed.**
   - v2: `createClient({ baseUrl, timeout, retry })` where `retry` was a
     number (retry count).
   - v3: `createClient({ baseURL, timeoutMs, retries })`. `baseUrl` →
     `baseURL`, `timeout` → `timeoutMs` (same meaning, milliseconds),
     `retry` (number) → `retries: { count, backoffMs }` (an object).
     Passing the old keys throws `TypeError` at construction.

2. **Response body access is now explicit.**
   - v2: `const res = await client.get(url)` returned an object whose
     `res.data` was the already-parsed JSON.
   - v3: `client.get(url)` returns a `Response`; you call `await
     res.json()` (or `res.text()`) yourself. `res.data` no longer exists.

3. **Errors are typed.**
   - v2: any non-2xx **rejected** the promise with a generic `Error`.
   - v3: non-2xx responses **do not reject** by default; you inspect
     `res.ok` / `res.status`. To restore v2 behavior, pass
     `throwOnError: true` to `createClient`, which rejects with a
     `HttpError` (has `.status` and `.response`).

4. **`client.stream()` removed.** Use `client.get(url)` and read
   `res.body` (a `ReadableStream`) instead.

5. **Node 16 dropped.** v3 requires Node 18+ (uses the global `fetch`).

6. **Non-breaking addition:** `client.use(middleware)` for request/response
   interceptors is new in v3 (nice to mention, not required to migrate).

## Requirements

Produce a single Markdown document, `MIGRATING.md`, that covers:

- A short intro: who needs to read this and the headline of what changed.
- **Requirements/prerequisites** (the Node version bump).
- Each breaking change as its own section, each with a **before (v2) /
  after (v3) code diff or side-by-side** so a reader can pattern-match
  their own code.
- Clear guidance for the **error-handling behavior change** (the most
  subtle one), including how to restore the old throwing behavior.
- A brief mention of the new non-breaking `use()` capability.
- Order the changes so the most impactful / most common appear first.

## Constraints

- Cover exactly the changes in the source of truth — do not invent
  changes and do not omit breaking ones.
- Code snippets must be **valid and consistent** with the described v2 and
  v3 APIs.

## Deliverable

A single `MIGRATING.md`.
