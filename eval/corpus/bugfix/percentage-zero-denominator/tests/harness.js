"use strict";
const path = require("path");
const assert = require("assert");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);

test("repro: zero whole yields 0, not NaN", (M) => {
  assert.strictEqual(M.percentage(0, 0), 0);
  assert.strictEqual(M.percentage(5, 0), 0);
});

test("simple exact percentage", (M) => {
  assert.strictEqual(M.percentage(1, 4), 25);
});

test("one-decimal rounding preserved", (M) => {
  assert.strictEqual(M.percentage(1, 3), 33.3);
  assert.strictEqual(M.percentage(2, 3), 66.7);
});

test("zero part over nonzero whole is 0", (M) => {
  assert.strictEqual(M.percentage(0, 10), 0);
});

test("full and over-100 cases", (M) => {
  assert.strictEqual(M.percentage(10, 10), 100);
  assert.strictEqual(M.percentage(3, 2), 150);
});

function main() {
  let M;
  try {
    M = require(path.join(CAND, "percent.js"));
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
