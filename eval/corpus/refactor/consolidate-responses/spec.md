# Consolidate duplicated response building

You are given a module of HTTP-style handlers that each build their
success and not-found responses with copy-pasted logic. Consolidate the
duplication into a shared helper **without changing any observable
behavior**.

## Runtime

Node.js (built-ins only). No npm dependencies.

## Starting code

`handlers.js`:

```js
"use strict";
const users = { "1": { id: "1", name: "Ada" } };
const products = { "10": { id: "10", title: "Widget" } };
const orders = { "100": { id: "100", total: 42 } };

function getUser(id) {
  const user = users[id];
  if (!user) {
    return { status: 404, body: { error: "user not found" } };
  }
  return { status: 200, body: user };
}

function getProduct(id) {
  const product = products[id];
  if (!product) {
    return { status: 404, body: { error: "product not found" } };
  }
  return { status: 200, body: product };
}

function getOrder(id) {
  const order = orders[id];
  if (!order) {
    return { status: 404, body: { error: "order not found" } };
  }
  return { status: 200, body: order };
}

module.exports = { getUser, getProduct, getOrder };
```

The `{ status: 200, body: ... }` and `{ status: 404, body: { error } }`
shapes are duplicated across all three handlers.

## Target shape

Produce **two** files:

1. `respond.js` — a new CommonJS module exporting exactly two helpers:
   - `ok(body)` → `{ status: 200, body }`.
   - `notFound(message)` → `{ status: 404, body: { error: message } }`.
2. `handlers.js` — same three handlers, same public behavior, but each
   now builds its responses by calling `ok` / `notFound` from
   `respond.js`.

## Requirements

- Public behavior is identical: a found entity yields
  `{ status: 200, body: <entity> }`; a miss yields
  `{ status: 404, body: { error: "<thing> not found" } }` with the same
  wording (`"user not found"`, `"product not found"`,
  `"order not found"`).
- The response-shape literals appear in exactly one place (`respond.js`).
- Print nothing on import.
