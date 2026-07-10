"use strict";
const { cartTotal } = require("./cart");

function checkout(items, taxRate) {
  const subtotal = cartTotal(items);
  return { subtotal, total: subtotal * (1 + taxRate) };
}

module.exports = { checkout };
