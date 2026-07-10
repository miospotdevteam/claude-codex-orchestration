# Rename a symbol and a field across files

You are given two CommonJS modules. Perform a **behavior-preserving
rename** across both files, as specified below.

## Runtime

Node.js (built-ins only). No npm dependencies.

## Starting code

`cart.js`:

```js
"use strict";
function cartSubtotal(items) {
  return items.reduce((sum, item) => sum + item.amount * item.qty, 0);
}
module.exports = { cartSubtotal };
```

`checkout.js`:

```js
"use strict";
const { cartSubtotal } = require("./cart");

function checkout(items, taxRate) {
  const subtotal = cartSubtotal(items);
  return { subtotal, total: subtotal * (1 + taxRate) };
}

module.exports = { checkout };
```

Each `item` is an object shaped `{ amount, qty }`.

## The rename

Apply **both** of these consistently across both files:

1. Rename the exported function `cartSubtotal` → `cartTotal`. The old
   name `cartSubtotal` must **no longer be exported** from `cart.js`.
2. Rename the item field `amount` → `price`. After the rename, both
   modules read `item.price` (each `item` is now `{ price, qty }`).

## Requirements

- `cart.js` exports `cartTotal(items)`, which returns
  `sum(item.price * item.qty)` over the items.
- `cart.js` no longer exports `cartSubtotal`.
- `checkout.js` imports and calls the renamed `cartTotal`, and its public
  behavior is unchanged: `checkout(items, taxRate)` returns
  `{ subtotal, total }` where `subtotal` is the cart total and `total` is
  `subtotal * (1 + taxRate)`. (The `checkout` function name and its
  returned `subtotal`/`total` keys stay as they are — only the item field
  and the cart function are renamed.)
- Print nothing on import.
