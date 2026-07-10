"use strict";
const { ok, notFound } = require("./respond");

const users = { "1": { id: "1", name: "Ada" } };
const products = { "10": { id: "10", title: "Widget" } };
const orders = { "100": { id: "100", total: 42 } };

function getUser(id) {
  const user = users[id];
  return user ? ok(user) : notFound("user not found");
}

function getProduct(id) {
  const product = products[id];
  return product ? ok(product) : notFound("product not found");
}

function getOrder(id) {
  const order = orders[id];
  return order ? ok(order) : notFound("order not found");
}

module.exports = { getUser, getProduct, getOrder };
