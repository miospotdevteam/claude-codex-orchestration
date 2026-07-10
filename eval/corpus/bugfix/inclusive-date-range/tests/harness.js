"use strict";
const path = require("path");
const assert = require("assert");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);

const S = "2026-01-01";
const E = "2026-01-31";

test("repro: end endpoint is inside", (M) => {
  assert.strictEqual(M.isWithin(E, S, E), true);
});

test("start endpoint is inside", (M) => {
  assert.strictEqual(M.isWithin(S, S, E), true);
});

test("interior date is inside", (M) => {
  assert.strictEqual(M.isWithin("2026-01-15", S, E), true);
});

test("before start is outside", (M) => {
  assert.strictEqual(M.isWithin("2025-12-31", S, E), false);
});

test("after end is outside", (M) => {
  assert.strictEqual(M.isWithin("2026-02-01", S, E), false);
});

test("single-day range includes that day", (M) => {
  assert.strictEqual(M.isWithin(S, S, S), true);
});

function main() {
  let M;
  try {
    M = require(path.join(CAND, "range.js"));
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
