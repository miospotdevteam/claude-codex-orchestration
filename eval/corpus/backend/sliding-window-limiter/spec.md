# Sliding-window rate limiter

Implement a per-client sliding-window rate limiter.

## Deliverable

Create a single file `rate_limiter.js` (CommonJS) exporting a factory:

```js
module.exports = { createLimiter };
```

## Runtime

Node.js (built-ins only). No npm dependencies, no timers, no wall clock.

## Interface

```js
createLimiter(limit, windowMs)   // -> limiter
limiter.allow(clientId, now)     // -> boolean
```

- `limit` — the maximum number of allowed requests permitted to a single
  client within any trailing window of `windowMs` milliseconds.
- `now` — the current time in milliseconds, passed explicitly. Callers
  use a **non-decreasing** clock. The limiter must never read a wall
  clock itself.

## Behavior

- `allow(clientId, now)` decides whether a request from `clientId` at
  time `now` is permitted, using a **sliding window** over the trailing
  `windowMs`:
  - A previously-allowed request at time `t` still counts against the
    window while `t > now - windowMs`. Once `t <= now - windowMs` it has
    aged out and no longer counts.
  - If the number of still-counting allowed requests for that client is
    **less than** `limit`, record this request at `now` and return
    `true`.
  - Otherwise return `false` and record **nothing** (a rejected request
    does not consume capacity or extend the window).
- Different `clientId`s are rate-limited independently.

## Constraints

- Deterministic; no I/O, no logging, no timers, no shared globals across
  limiter instances. Print nothing on import.
