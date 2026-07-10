"use strict";
function isBalanced(str) {
  const closeToOpen = { ")": "(", "]": "[", "}": "{" };
  const stack = [];
  for (const ch of str) {
    if (ch === "(" || ch === "[" || ch === "{") {
      stack.push(ch);
    } else if (ch === ")" || ch === "]" || ch === "}") {
      if (stack.pop() !== closeToOpen[ch]) {
        return false;
      }
    }
  }
  return stack.length === 0;
}
module.exports = { isBalanced };
