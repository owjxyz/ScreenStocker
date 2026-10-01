// Run from the repository root: node Scripts/check-site-chart.cjs
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const events = {};
const frames = [];
const attributes = {};
let top = 900;
const reducedMotion = { matches: false, addEventListener: (_, handler) => { events.motion = handler; } };
const line = {
  getTotalLength: () => 1000,
  getPointAtLength: (distance) => ({ x: distance * 0.82, y: 257 - distance * 0.177 }),
};
const preview = {
  getBoundingClientRect: () => ({ top }),
  querySelector: (selector) => selector === ".chart-line" ? line : {
    setAttribute: (name, value) => { attributes[name] = value; },
  },
};
vm.runInNewContext(fs.readFileSync("Docs/site.js", "utf8"), {
  document: { querySelector: () => preview },
  matchMedia: () => reducedMotion,
  innerHeight: 1000,
  addEventListener: (name, handler) => { events[name] = handler; },
  requestAnimationFrame: (handler) => { frames.push(handler); return frames.length; },
});
const flush = () => { frames.splice(0).forEach((handler) => handler()); };
const scrollTo = (position) => { top = position; events.scroll(); flush(); };
flush();
assert.equal(attributes.width, 0);
scrollTo(550);
assert.equal(attributes.width, 410);
assert.equal(attributes.cx, attributes.width);
assert.equal(attributes.cy, 168.5);
scrollTo(0);
assert.equal(attributes.width, 820);
scrollTo(1200);
assert.equal(attributes.width, 0);
events.scroll(); events.scroll(); events.resize();
assert.equal(frames.length, 1, "updates should share one animation frame");
flush();
reducedMotion.matches = true;
events.motion(); flush();
assert.equal(attributes.width, 820, "reduced motion should show the entire chart");
assert.equal(attributes.cx, 820);
console.log("PASS: chart reveals and reverses with scroll, tracks its tip, coalesces updates, and respects reduced motion");
