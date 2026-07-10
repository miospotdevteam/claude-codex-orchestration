# Bug: mismatched brackets pass the balance check

## Runtime

Node.js (built-ins only). No npm dependencies.

## The code

`brackets.js`:

```js
"use strict";
function isBalanced(str) {
  const closeToOpen = { ")": "(", "]": "[", "}": "{" };
  const stack = [];
  for (const ch of str) {
    if (ch === "(" || ch === "[" || ch === "{") {
      stack.push(ch);
    } else if (ch === ")" || ch === "]" || ch === "}") {
      if (stack.length === 0) {
        return false;
      }
      stack.pop();
    }
  }
  return stack.length === 0;
}
module.exports = { isBalanced };
```

`isBalanced(str)` should return `true` iff every `(`, `[`, `{` is closed
by the matching `)`, `]`, `}` in the correct nested order. Characters
that are not brackets are ignored.

## Symptom

Strings whose brackets are balanced *in count* but **crossed** in nesting
are wrongly accepted:

```js
isBalanced("([)]");  // -> true (WRONG: expected false)
isBalanced("(]");    // -> true (WRONG: expected false)
```

The check pops a bracket off the stack without confirming it matches the
opener it is closing.

## Task

Fix `brackets.js` so that a closer only balances the matching opener:

- Correctly nested strings like `"()"`, `"([])"`, `"a(b[c]d)e"` return
  `true`.
- Crossed or mismatched strings like `"([)]"`, `"(]"`, `")("` return
  `false`.
- Unclosed openers (`"((("`) and stray closers (`")"`) return `false`.
- The empty string returns `true`.
- Non-bracket characters are ignored.

Change nothing beyond fixing the match check. Print nothing on import.
