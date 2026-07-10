# Bug: percentage of a zero whole returns NaN

## Runtime

Node.js (built-ins only). No npm dependencies.

## The code

`percent.js`:

```js
"use strict";
function percentage(part, whole) {
  return Math.round((part / whole) * 1000) / 10;
}
module.exports = { percentage };
```

`percentage(part, whole)` returns what percent `part` is of `whole`,
rounded to **one decimal place**. For example `percentage(1, 4)` is `25`
and `percentage(1, 3)` is `33.3`.

## Symptom

When `whole` is `0`, the function returns `NaN` instead of a number:

```js
percentage(0, 0);  // -> NaN (WRONG: expected 0)
percentage(5, 0);  // -> NaN (WRONG: expected 0)
```

A zero whole should yield `0` percent, not `NaN`.

## Task

Fix `percent.js` so that:

- When `whole` is `0`, the result is `0` (for any `part`).
- Otherwise the result is `part / whole * 100`, rounded to one decimal
  place, exactly as before (`percentage(1, 3)` stays `33.3`,
  `percentage(2, 3)` stays `66.7`).

Change nothing beyond guarding the zero-denominator case. Print nothing
on import.
