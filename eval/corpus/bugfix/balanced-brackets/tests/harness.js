"use strict";
const path = require("path");
const assert = require("assert");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);

test("repro: crossed pairs are unbalanced", (M) => {
  assert.strictEqual(M.isBalanced("([)]"), false);
  assert.strictEqual(M.isBalanced("(]"), false);
});

test("correctly nested strings pass", (M) => {
  assert.strictEqual(M.isBalanced("()"), true);
  assert.strictEqual(M.isBalanced("([])"), true);
  assert.strictEqual(M.isBalanced("{[()]}"), true);
});

test("non-bracket characters are ignored", (M) => {
  assert.strictEqual(M.isBalanced("a(b[c]d)e"), true);
});

test("stray closer and reversed order fail", (M) => {
  assert.strictEqual(M.isBalanced(")"), false);
  assert.strictEqual(M.isBalanced(")("), false);
});

test("unclosed openers fail", (M) => {
  assert.strictEqual(M.isBalanced("((("), false);
  assert.strictEqual(M.isBalanced("([]"), false);
});

test("empty string is balanced", (M) => {
  assert.strictEqual(M.isBalanced(""), true);
});

function main() {
  let M;
  try {
    M = require(path.join(CAND, "brackets.js"));
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
