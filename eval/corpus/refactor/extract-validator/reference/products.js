"use strict";
const { isNonEmptyString, isEmail } = require("./validators");

const products = [];

function createProduct(title, supplierEmail) {
  if (!isNonEmptyString(title)) {
    throw new Error("invalid title");
  }
  if (!isEmail(supplierEmail)) {
    throw new Error("invalid email");
  }
  const product = { id: products.length + 1, title, supplierEmail };
  products.push(product);
  return product;
}

module.exports = { createProduct };
