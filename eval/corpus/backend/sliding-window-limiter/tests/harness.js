"use strict";
const path = require("path");
const assert = require("assert");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);

test("allows up to limit then blocks", (M) => {
  const l = M.createLimiter(3, 1000);
  assert.strictEqual(l.allow("c", 0), true);
  assert.strictEqual(l.allow("c", 0), true);
  assert.strictEqual(l.allow("c", 0), true);
  assert.strictEqual(l.allow("c", 0), false);
});

test("window slides: capacity returns after windowMs", (M) => {
  const l = M.createLimiter(3, 1000);
  l.allow("c", 0);
  l.allow("c", 0);
  l.allow("c", 0);
  assert.strictEqual(l.allow("c", 999), false); // t=0 still counts (0 > -1)
  assert.strictEqual(l.allow("c", 1000), true); // t=0 aged out (0 <= 0)
});

test("rejected request records nothing", (M) => {
  const l = M.createLimiter(1, 1000);
  assert.strictEqual(l.allow("c", 0), true);
  assert.strictEqual(l.allow("c", 100), false); // rejected
  assert.strictEqual(l.allow("c", 100), false); // still blocked by the t=0 hit
  assert.strictEqual(l.allow("c", 1000), true); // t=0 aged out
});

test("clients are independent", (M) => {
  const l = M.createLimiter(1, 1000);
  assert.strictEqual(l.allow("a", 0), true);
  assert.strictEqual(l.allow("b", 0), true);
  assert.strictEqual(l.allow("a", 0), false);
});

test("partial slide frees exactly the aged-out slots", (M) => {
  const l = M.createLimiter(2, 100);
  assert.strictEqual(l.allow("c", 0), true);
  assert.strictEqual(l.allow("c", 50), true);
  assert.strictEqual(l.allow("c", 60), false); // both still in window
  assert.strictEqual(l.allow("c", 100), true); // t=0 aged out (0 <= 0)
  assert.strictEqual(l.allow("c", 100), false); // t=50 and t=100 fill it
});

test("limit zero blocks everything", (M) => {
  const l = M.createLimiter(0, 1000);
  assert.strictEqual(l.allow("c", 0), false);
});

function main() {
  let M;
  try {
    M = require(path.join(CAND, "rate_limiter.js"));
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
