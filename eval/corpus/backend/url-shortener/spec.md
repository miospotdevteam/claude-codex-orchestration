# URL shortener store

Implement an in-memory URL shortener store.

## Deliverable

Create a single file `shortener.js` (CommonJS) that exports a factory:

```js
module.exports = { createStore };
```

## Runtime

Node.js (built-ins only). No npm dependencies, no network, no disk.

## Interface

`createStore()` returns a store object with three methods:

```js
store.shorten(url)   // -> code (string)
store.resolve(code)  // -> original url (string), or null if unknown
store.count()        // -> number of distinct urls stored
```

## Behavior

- `shorten(url)` returns a short **code** for `url`:
  - The code is a non-empty string containing only the characters
    `[A-Za-z0-9]` and is at most 16 characters long.
  - **Idempotent**: calling `shorten` again with the same `url` returns
    the *same* code and does not create a new entry.
  - **Distinct**: two different urls always receive two different codes.
  - If `url` is not a non-empty string, throw a `TypeError`.
- `resolve(code)` returns the url a code maps to, or `null` if no such
  code exists. `resolve(store.shorten(u))` must equal `u` for any valid
  `u`.
- `count()` returns the number of distinct urls stored so far.
- Each `createStore()` call yields an independent store; two stores share
  no state.

## Constraints

- Pure in-memory; no I/O, no globals shared across stores.
- Deterministic within a single store instance.
- Print nothing on import.
