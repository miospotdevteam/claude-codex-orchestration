"use strict";
function percentage(part, whole) {
  if (whole === 0) {
    return 0;
  }
  return Math.round((part / whole) * 1000) / 10;
}
module.exports = { percentage };
