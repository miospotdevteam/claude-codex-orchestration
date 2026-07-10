"use strict";
const path = require("path");
const assert = require("assert");
const fs = require("fs");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);

function loadAll() {
  return {
    cart: require(path.join(CAND, "cart.js")),
    checkout: require(path.join(CAND, "checkout.js")),
  };
}

function candidateJsSources() {
  return fs
    .readdirSync(CAND)
    .filter((name) => name.endsWith(".js"))
    .map((name) => [name, fs.readFileSync(path.join(CAND, name), "utf8")]);
}

test("cartTotal computes sum(price*qty)", (M) => {
  assert.strictEqual(typeof M.cart.cartTotal, "function");
  const items = [
    { price: 10, qty: 2 },
    { price: 5, qty: 1 },
  ];
  assert.strictEqual(M.cart.cartTotal(items), 25);
});

test("cartTotal on empty cart is 0", (M) => {
  assert.strictEqual(M.cart.cartTotal([]), 0);
});

test("old export cartSubtotal is gone", (M) => {
  assert.strictEqual(M.cart.cartSubtotal, undefined);
});

test("checkout preserves shape and math", (M) => {
  const items = [
    { price: 10, qty: 2 },
    { price: 5, qty: 1 },
  ];
  const r = M.checkout.checkout(items, 0.1);
  assert.strictEqual(r.subtotal, 25);
  assert.ok(Math.abs(r.total - 27.5) < 1e-9);
});

test("checkout empty cart", (M) => {
  const r = M.checkout.checkout([], 0.2);
  assert.strictEqual(r.subtotal, 0);
  assert.strictEqual(r.total, 0);
});

test("old symbol and field names are gone from candidate source", () => {
  for (const [name, src] of candidateJsSources()) {
    assert.doesNotMatch(src, /\bcartSubtotal\b/, `${name} still references cartSubtotal`);
    assert.doesNotMatch(src, /\bamount\b/, `${name} still references amount`);
  }
});

function main() {
  let M;
  try {
    M = loadAll();
  } catch (e) {
    console.error(e);
    console.log(`RESULT 0 ${TESTS.length}`);
    process.exit(1);
  }
  let passed = 0;
  for (const [name, fn] of TESTS) {
    try {
      fn(M);
      passed++;
    } catch (e) {
      console.error(`FAIL ${name}: ${e && e.message}`);
    }
  }
  console.log(`RESULT ${passed} ${TESTS.length}`);
  process.exit(passed === TESTS.length ? 0 : 1);
}

main();
