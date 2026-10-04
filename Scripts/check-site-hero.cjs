// Run from the repository root: node Scripts/check-site-hero.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const frames = new Map();
const events = {};
const heroEvents = {};
const mediaEvents = {};
let nextFrame = 0;
let intersection;
const drawn = [];
const context = {
  clearRect() { drawn.length = 0; },
  setTransform() {},
  fillText(text, x, y) { drawn.push({ text, x, y, alpha: this.globalAlpha }); },
};
const bounds = { left: 0, top: 0, width: 600, height: 500 };
const hero = { getBoundingClientRect: () => bounds, addEventListener: (name, fn) => { heroEvents[name] = fn; } };
const canvas = { getContext: () => context, closest: () => hero };
const protectedRect = { left: 180, right: 300, top: 180, bottom: 300 };
const motion = { matches: false, addEventListener: (_, fn) => { mediaEvents.motion = fn; } };
const mouse = { matches: true, addEventListener: (_, fn) => { mediaEvents.mouse = fn; } };
const preview = {
  getBoundingClientRect: () => ({ top: 0 }),
  querySelector: selector => selector === '.chart-line'
    ? { getTotalLength: () => 820, getPointAtLength: x => ({ x, y: 80 }) }
    : { setAttribute() {} },
};
const document = {
  hidden: false,
  querySelector: selector => selector === '.device-frame' ? preview : canvas,
  querySelectorAll: () => [{ getBoundingClientRect: () => protectedRect }],
  addEventListener: (name, fn) => { events[name] = fn; },
};
vm.runInNewContext(fs.readFileSync('Docs/site.js', 'utf8'), {
  document, innerHeight: 1000, devicePixelRatio: 3,
  matchMedia: query => query.includes('reduced-motion') ? motion : mouse,
  addEventListener: (name, fn) => { events[name] = fn; },
  requestAnimationFrame: fn => { frames.set(++nextFrame, fn); return nextFrame; },
  cancelAnimationFrame: id => frames.delete(id),
  IntersectionObserver: class {
    constructor(fn) { intersection = fn; }
    observe(target) { assert.equal(target, hero); }
  },
});
const flush = now => { const pending = [...frames.values()]; frames.clear(); pending.forEach(fn => fn(now)); };
const move = (x, y, pointerType = 'mouse') => heroEvents.pointermove({ clientX: x, clientY: y, pointerType });
flush(0);
assert.equal(canvas.width, 1200, 'pixel density is capped at 2');
move(150, 200); move(160, 200);
assert.equal(frames.size, 1, 'pointer updates are coalesced');
flush(10);
assert.ok(drawn.length > 0, 'mouse movement reveals binary digits');
assert.ok(drawn.every(p => p.text === '0' || p.text === '1'));
assert.ok(drawn.every(p => !(p.x >= 164 && p.x <= 316 && p.y >= 164 && p.y <= 316)), 'content plus padding is excluded');
const initialAlpha = drawn.find(p => p.x === 160 && p.y === 160).alpha;
flush(300);
assert.ok(drawn.find(p => p.x === 160 && p.y === 160).alpha < initialAlpha, 'trail fades');
flush(800);
assert.equal(drawn.length, 0);
assert.equal(frames.size, 0, 'rendering stops after fade');
move(100, 100, 'touch'); assert.equal(frames.size, 0);
motion.matches = true; move(100, 100); assert.equal(frames.size, 0);
motion.matches = false; mouse.matches = false; move(100, 100); assert.equal(frames.size, 0);
mouse.matches = true; move(100, 100); flush(900);
intersection([{ isIntersecting: false }]);
assert.equal(frames.size, 0); assert.equal(drawn.length, 0);
move(100, 100); assert.equal(frames.size, 0, 'offscreen hero stays idle');
intersection([{ isIntersecting: true }]); move(100, 100); flush(1000);
motion.matches = true; mediaEvents.motion();
assert.equal(frames.size, 0); assert.equal(drawn.length, 0);
console.log('PASS: hero cursor trail, content exclusion, fading, idle shutdown, input and motion guards');
