"use strict";
function isWithin(date, start, end) {
  const d = new Date(date).getTime();
  return d >= new Date(start).getTime() && d <= new Date(end).getTime();
}
module.exports = { isWithin };
