# Extract a shared validation module

You are given two small CommonJS modules that duplicate the same
validation logic. Refactor them to remove the duplication by extracting a
shared module, **without changing any observable behavior**.

## Runtime

Node.js (built-ins only). No npm dependencies.

## Starting code

`users.js`:

```js
"use strict";
const users = [];

function createUser(name, email) {
  if (typeof name !== "string" || name.trim().length === 0) {
    throw new Error("invalid name");
  }
  if (typeof email !== "string" || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new Error("invalid email");
  }
  const user = { id: users.length + 1, name, email };
  users.push(user);
  return user;
}

module.exports = { createUser };
```

`products.js`:

```js
"use strict";
const products = [];

function createProduct(title, supplierEmail) {
  if (typeof title !== "string" || title.trim().length === 0) {
    throw new Error("invalid title");
  }
  if (
    typeof supplierEmail !== "string" ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(supplierEmail)
  ) {
    throw new Error("invalid email");
  }
  const product = { id: products.length + 1, title, supplierEmail };
  products.push(product);
  return product;
}

module.exports = { createProduct };
```

The non-empty-string check and the email check are byte-for-byte
duplicated between the two files.

## Target shape

Produce **three** files:

1. `validators.js` — a new CommonJS module that exports exactly two
   predicate functions:
   - `isNonEmptyString(value)` → `true` iff `value` is a string with at
     least one non-whitespace character.
   - `isEmail(value)` → `true` iff `value` is a string matching the same
     email rule used above (`/^[^@\s]+@[^@\s]+\.[^@\s]+$/`).
2. `users.js` — unchanged public behavior, but its validation now calls
   the shared predicates from `validators.js`.
3. `products.js` — likewise.

## Requirements

- `createUser` and `createProduct` keep the **exact** behavior above:
  same accepted inputs, same thrown errors, same returned shape
  (`{ id, name, email }` / `{ id, title, supplierEmail }`, ids starting
  at 1 and incrementing).
- No duplicated validation logic remains between `users.js` and
  `products.js`.
- Print nothing on import.
