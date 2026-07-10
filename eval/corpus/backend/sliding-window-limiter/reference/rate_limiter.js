"use strict";

function createLimiter(limit, windowMs) {
  const hits = new Map(); // clientId -> ascending array of timestamps

  return {
    allow(clientId, now) {
      const cutoff = now - windowMs;
      let times = hits.get(clientId);
      if (times === undefined) {
        times = [];
        hits.set(clientId, times);
      }
      while (times.length > 0 && times[0] <= cutoff) {
        times.shift();
      }
      if (times.length < limit) {
        times.push(now);
        return true;
      }
      return false;
    },
  };
}

module.exports = { createLimiter };
