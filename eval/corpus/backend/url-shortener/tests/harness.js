"use strict";
const path = require("path");
const assert = require("assert");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);
const CODE_RE = /^[A-Za-z0-9]{1,16}$/;

test("shorten returns valid code and round-trips", (M) => {
  const s = M.createStore();
  const c = s.shorten("https://example.com/a");
  assert.match(c, CODE_RE);
  assert.strictEqual(s.resolve(c), "https://example.com/a");
});

test("idempotent: same url -> same code, no new entry", (M) => {
  const s = M.createStore();
  const c1 = s.shorten("https://x.test/1");
  const c2 = s.shorten("https://x.test/1");
  assert.strictEqual(c1, c2);
  assert.strictEqual(s.count(), 1);
});

test("distinct urls -> distinct codes", (M) => {
  const s = M.createStore();
  const seen = new Set();
  for (let i = 0; i < 100; i++) {
    const c = s.shorten("https://x.test/" + i);
    assert.match(c, CODE_RE);
    assert.ok(!seen.has(c), "duplicate code for distinct url");
    seen.add(c);
  }
  assert.strictEqual(s.count(), 100);
});

test("resolve unknown code -> null", (M) => {
  const s = M.createStore();
  s.shorten("https://x.test/only");
  assert.strictEqual(s.resolve("definitely-not-a-code"), null);
});

test("invalid input throws TypeError", (M) => {
  const s = M.createStore();
  assert.throws(() => s.shorten(""), TypeError);
  assert.throws(() => s.shorten(42), TypeError);
  assert.throws(() => s.shorten(null), TypeError);
});

test("stores are independent", (M) => {
  const a = M.createStore();
  const b = M.createStore();
  a.shorten("https://x.test/shared");
  assert.strictEqual(b.count(), 0);
});

test("count reflects distinct inserts only", (M) => {
  const s = M.createStore();
  s.shorten("u1");
  s.shorten("u2");
  s.shorten("u1");
  assert.strictEqual(s.count(), 2);
});

function main() {
  let M;
  try {
    M = require(path.join(CAND, "shortener.js"));
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
