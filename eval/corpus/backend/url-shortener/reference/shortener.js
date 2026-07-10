"use strict";

const ALPHABET =
  "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

function encodeBase62(n) {
  let s = "";
  do {
    s = ALPHABET[n % 62] + s;
    n = Math.floor(n / 62);
  } while (n > 0);
  return s;
}

function createStore() {
  const codeByUrl = new Map();
  const urlByCode = new Map();
  let next = 0;

  return {
    shorten(url) {
      if (typeof url !== "string" || url.length === 0) {
        throw new TypeError("url must be a non-empty string");
      }
      if (codeByUrl.has(url)) {
        return codeByUrl.get(url);
      }
      const code = encodeBase62(next++);
      codeByUrl.set(url, code);
      urlByCode.set(code, url);
      return code;
    },

    resolve(code) {
      return urlByCode.has(code) ? urlByCode.get(code) : null;
    },

    count() {
      return codeByUrl.size;
    },
  };
}

module.exports = { createStore };
