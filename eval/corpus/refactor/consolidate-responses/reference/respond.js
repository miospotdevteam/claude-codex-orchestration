"use strict";

function ok(body) {
  return { status: 200, body };
}

function notFound(message) {
  return { status: 404, body: { error: message } };
}

module.exports = { ok, notFound };
