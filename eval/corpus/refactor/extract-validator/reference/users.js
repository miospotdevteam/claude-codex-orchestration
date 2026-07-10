"use strict";
const { isNonEmptyString, isEmail } = require("./validators");

const users = [];

function createUser(name, email) {
  if (!isNonEmptyString(name)) {
    throw new Error("invalid name");
  }
  if (!isEmail(email)) {
    throw new Error("invalid email");
  }
  const user = { id: users.length + 1, name, email };
  users.push(user);
  return user;
}

module.exports = { createUser };
