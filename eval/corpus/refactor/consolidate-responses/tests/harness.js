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
    respond: require(path.join(CAND, "respond.js")),
    handlers: require(path.join(CAND, "handlers.js")),
  };
}

function readCandidateFile(name) {
  return fs.readFileSync(path.join(CAND, name), "utf8");
}

function loadHandlersWithRespond(spies) {
  const handlersPath = fs.realpathSync(path.join(CAND, "handlers.js"));
  const respondPath = fs.realpathSync(path.join(CAND, "respond.js"));
  delete require.cache[require.resolve(handlersPath)];
  delete require.cache[require.resolve(respondPath)];
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (parent && parent.filename === handlersPath && request === "./respond") {
      return spies;
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require(handlersPath);
  } finally {
    Module._load = originalLoad;
    delete require.cache[require.resolve(handlersPath)];
  }
}

// --- behavior preserved ---
test("getUser found returns 200 with entity", (M) => {
  assert.deepStrictEqual(M.handlers.getUser("1"), {
    status: 200,
    body: { id: "1", name: "Ada" },
  });
});

test("getUser missing returns 404 with wording", (M) => {
  assert.deepStrictEqual(M.handlers.getUser("nope"), {
    status: 404,
    body: { error: "user not found" },
  });
});

test("getProduct found and missing", (M) => {
  assert.deepStrictEqual(M.handlers.getProduct("10"), {
    status: 200,
    body: { id: "10", title: "Widget" },
  });
  assert.deepStrictEqual(M.handlers.getProduct("x"), {
    status: 404,
    body: { error: "product not found" },
  });
});

test("getOrder found and missing", (M) => {
  assert.deepStrictEqual(M.handlers.getOrder("100"), {
    status: 200,
    body: { id: "100", total: 42 },
  });
  assert.deepStrictEqual(M.handlers.getOrder("x"), {
    status: 404,
    body: { error: "order not found" },
  });
});

// --- target shape present and correct ---
test("respond.ok builds a 200 envelope", (M) => {
  assert.strictEqual(typeof M.respond.ok, "function");
  assert.deepStrictEqual(M.respond.ok({ a: 1 }), { status: 200, body: { a: 1 } });
});

test("respond.notFound builds a 404 envelope", (M) => {
  assert.strictEqual(typeof M.respond.notFound, "function");
  assert.deepStrictEqual(M.respond.notFound("x not found"), {
    status: 404,
    body: { error: "x not found" },
  });
});

test("handlers call the shared response helpers", () => {
  const calls = [];
  const handlers = loadHandlersWithRespond({
    ok(body) {
      calls.push(["ok", body]);
      return { status: 200, body };
    },
    notFound(message) {
      calls.push(["notFound", message]);
      return { status: 404, body: { error: message } };
    },
  });
  handlers.getUser("1");
  handlers.getUser("nope");
  handlers.getProduct("10");
  handlers.getProduct("x");
  handlers.getOrder("100");
  handlers.getOrder("x");
  assert.deepStrictEqual(
    calls.map(([name]) => name),
    ["ok", "notFound", "ok", "notFound", "ok", "notFound"]
  );
});

test("response envelope literals are not duplicated in handlers", () => {
  const src = readCandidateFile("handlers.js");
  assert.doesNotMatch(src, /status\s*:\s*200/, "200 response shape belongs in respond.js");
  assert.doesNotMatch(src, /status\s*:\s*404/, "404 response shape belongs in respond.js");
  assert.doesNotMatch(src, /body\s*:\s*\{\s*error\b/, "error envelope belongs in respond.js");
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
