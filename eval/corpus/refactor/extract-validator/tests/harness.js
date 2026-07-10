"use strict";
const path = require("path");
const assert = require("assert");
const fs = require("fs");
const Module = require("module");

const CAND = path.resolve(process.argv[2]);
const TESTS = [];
const test = (name, fn) => TESTS.push([name, fn]);

function loadAll() {
  return {
    validators: require(path.join(CAND, "validators.js")),
    users: require(path.join(CAND, "users.js")),
    products: require(path.join(CAND, "products.js")),
  };
}

function readCandidateFile(name) {
  return fs.readFileSync(path.join(CAND, name), "utf8");
}

function loadWithValidators(moduleName, validators) {
  const modulePath = fs.realpathSync(path.join(CAND, moduleName));
  const validatorsPath = fs.realpathSync(path.join(CAND, "validators.js"));
  delete require.cache[require.resolve(modulePath)];
  delete require.cache[require.resolve(validatorsPath)];
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (parent && parent.filename === modulePath && request === "./validators") {
      return validators;
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require(modulePath);
  } finally {
    Module._load = originalLoad;
    delete require.cache[require.resolve(modulePath)];
  }
}

// --- behavior preserved ---
test("createUser accepts valid input and shapes result", (M) => {
  const u = M.users.createUser("Ada", "ada@example.com");
  assert.strictEqual(typeof u.id, "number");
  assert.ok(u.id >= 1);
  assert.strictEqual(u.name, "Ada");
  assert.strictEqual(u.email, "ada@example.com");
});

test("createUser rejects blank name and bad email", (M) => {
  assert.throws(() => M.users.createUser("   ", "ada@example.com"), /invalid name/);
  assert.throws(() => M.users.createUser("Ada", "nope"), /invalid email/);
  assert.throws(() => M.users.createUser("Ada", "a@@b.com"), /invalid email/);
});

test("createProduct accepts valid input and shapes result", (M) => {
  const p = M.products.createProduct("Widget", "sales@acme.io");
  assert.strictEqual(typeof p.id, "number");
  assert.strictEqual(p.title, "Widget");
  assert.strictEqual(p.supplierEmail, "sales@acme.io");
});

test("createProduct rejects blank title and bad email", (M) => {
  assert.throws(() => M.products.createProduct("", "sales@acme.io"), /invalid title/);
  assert.throws(() => M.products.createProduct("Widget", "acme.io"), /invalid email/);
});

// --- target shape present and correct ---
test("validators.js exports isNonEmptyString with correct behavior", (M) => {
  const { isNonEmptyString } = M.validators;
  assert.strictEqual(typeof isNonEmptyString, "function");
  assert.strictEqual(isNonEmptyString("x"), true);
  assert.strictEqual(isNonEmptyString("   "), false);
  assert.strictEqual(isNonEmptyString(""), false);
  assert.strictEqual(isNonEmptyString(5), false);
});

test("validators.js exports isEmail with correct behavior", (M) => {
  const { isEmail } = M.validators;
  assert.strictEqual(typeof isEmail, "function");
  assert.strictEqual(isEmail("a@b.co"), true);
  assert.strictEqual(isEmail("a@b"), false);
  assert.strictEqual(isEmail("@b.co"), false);
  assert.strictEqual(isEmail(42), false);
});

test("users.js and products.js call the shared validators", () => {
  const calls = [];
  const validators = {
    isNonEmptyString(value) {
      calls.push(["isNonEmptyString", value]);
      return true;
    },
    isEmail(value) {
      calls.push(["isEmail", value]);
      return true;
    },
  };
  const users = loadWithValidators("users.js", validators);
  const products = loadWithValidators("products.js", validators);
  users.createUser("Ada", "ada@example.com");
  products.createProduct("Widget", "sales@acme.io");
  assert.deepStrictEqual(
    calls.map(([name]) => name),
    ["isNonEmptyString", "isEmail", "isNonEmptyString", "isEmail"]
  );
});

test("inline duplicated validation logic is removed from callers", () => {
  for (const name of ["users.js", "products.js"]) {
    const src = readCandidateFile(name);
    assert.doesNotMatch(src, /\.trim\s*\(/, `${name} should not contain the non-empty-string implementation`);
    assert.doesNotMatch(src, /\[\^@\\s\]\+@/, `${name} should not contain the email regex implementation`);
    assert.doesNotMatch(src, /typeof\s+\w+\s*!==\s*["']string["']/, `${name} should not reimplement type checks inline`);
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
