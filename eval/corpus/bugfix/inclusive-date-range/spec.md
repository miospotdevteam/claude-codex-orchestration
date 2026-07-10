# Bug: the end date of a range is treated as outside it

## Runtime

Node.js (built-ins only). No npm dependencies.

## The code

`range.js`:

```js
"use strict";
function isWithin(date, start, end) {
  const d = new Date(date).getTime();
  return d >= new Date(start).getTime() && d < new Date(end).getTime();
}
module.exports = { isWithin };
```

`isWithin(date, start, end)` should report whether `date` falls inside
the **inclusive** range `[start, end]` — both endpoints count as inside.
All three arguments are ISO date strings like `"2026-01-01"`.

## Symptom

A date equal to the `end` of the range is wrongly reported as outside it:

```js
isWithin("2026-01-31", "2026-01-01", "2026-01-31"); // -> false (WRONG: expected true)
```

The `start` endpoint is handled correctly; only the `end` endpoint is
excluded.

## Task

Fix `range.js` so the range is inclusive on **both** ends:

- A date equal to `start` is inside (already true).
- A date equal to `end` is inside.
- A date strictly between them is inside.
- A date before `start` or after `end` is outside.

Change nothing beyond the boundary bug. Print nothing on import.
