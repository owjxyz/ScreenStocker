// Run from the repository root: node Scripts/check-site-hero.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const frames = new Map(), timeouts = new Map();
const events = {}, heroEvents = {}, mediaEvents = {};
let nextId = 0, clock = 0, intersection;
const drawn = [], dots = [], protectedRects = [];
const context = {
  clearRect() { drawn.length = dots.length = 0; },
  setTransform() {}, beginPath() {},
  arc(x, y, radius) { dots.push({ x, y, radius }); },
  fill() { dots[dots.length - 1].style = this.fillStyle; },
  fillText(text, x, y) { drawn.push({ text, x, y, style: this.fillStyle, font: this.font }); },
};
const bounds = { left: 0, top: 0, width: 600, height: 500 };
const hero = {
  getBoundingClientRect: () => bounds,
  addEventListener: (name, fn) => { heroEvents[name] = fn; },
  querySelectorAll: () => protectedRects,
};
const canvas = { getContext: () => context, closest: () => hero };
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
  addEventListener: (name, fn) => { events[name] = fn; },
};
vm.runInNewContext(fs.readFileSync('Docs/site.js', 'utf8'), {
  document, innerHeight: 1000, devicePixelRatio: 3, performance: { now: () => clock },
  matchMedia: query => query.includes('reduced-motion') ? motion : mouse,
  addEventListener: (name, fn) => { events[name] = fn; },
  requestAnimationFrame: fn => { frames.set(++nextId, fn); return nextId; },
  cancelAnimationFrame: id => frames.delete(id),
  setTimeout: (fn, delay) => { timeouts.set(++nextId, { fn, at: clock + delay }); return nextId; },
  clearTimeout: id => timeouts.delete(id),
  IntersectionObserver: class {
    constructor(fn) { intersection = fn; }
    observe(target) { assert.equal(target, hero); }
  },
});
const flush = now => {
  clock = now;
  for (const [id, timeout] of timeouts) {
    if (timeout.at <= now) { timeouts.delete(id); timeout.fn(); }
  }
  const pending = [...frames.values()]; frames.clear(); pending.forEach(fn => fn(now));
};
const event = (x, y, pointerType = 'mouse') => ({ clientX: x, clientY: y, pointerType });
const move = (x, y, pointerType = 'mouse') => heroEvents.pointermove(event(x, y, pointerType));
const alpha = p => Number(p.style.match(/,([^,]+)\)$/)[1]);
const furthest = () => Math.max(...dots.map(p => Math.hypot(p.x - 300, p.y - 250)));
flush(0);
assert.equal(canvas.width, 1200, 'DPR is capped at 2 as in Toss');
assert.equal(frames.size, 0, 'effect is idle before interaction');
move(280, 250); move(300, 250); flush(10); flush(40);
assert.ok(drawn.length > 0, 'movement reveals digits');
assert.ok(drawn.every(p => p.text === '0' || p.text === '1'));
assert.ok(drawn.every(p => Number.parseFloat(p.font) < 10.5), 'character size follows cursor strength');
assert.ok(dots.length > 0, 'dots and digits are rendered together');
assert.equal(frames.size, 1, 'movement shares one rendering loop');
heroEvents.pointerleave(); flush(150);
const earlyCount = drawn.length;
flush(350);
assert.ok(drawn.length < earlyCount, 'trail shrinks and fades over 400 ms');
flush(400); // The exact expiry boundary must not produce NaN colors.
assert.ok([...drawn, ...dots].every(p => !p.style.includes('NaN')));
flush(450);
assert.equal(frames.size, 0); assert.equal(drawn.length, 0);
move(300, 250); flush(500); flush(550); flush(650);
const earlyRadius = furthest();
flush(1000);
assert.ok(furthest() > earlyRadius, 'stopped cursor wave expands through the grid');
flush(1400);
assert.equal(frames.size, 0, 'idle wave expires after 800 ms');
heroEvents.pointerdown(event(300, 250)); flush(1500); flush(1800);
assert.ok(dots.length > 0, 'click produces a field ripple');
flush(2700); assert.equal(frames.size, 0, 'single click expires after 1200 ms');
heroEvents.pointerdown(event(300, 250));
clock = 2800; heroEvents.pointerdown(event(300, 250));
flush(4300); assert.ok(dots.length > 0, 'repeated click creates longer scaled waves');
flush(5600); assert.equal(frames.size, 0);
move(300, 250, 'touch'); assert.equal(frames.size, 0);
motion.matches = true; move(300, 250); assert.equal(frames.size, 0);
motion.matches = false; mouse.matches = false; move(300, 250); assert.equal(frames.size, 0);
mouse.matches = true; move(300, 250); intersection([{ isIntersecting: false }]);
assert.equal(frames.size, 0); assert.equal(timeouts.size, 0);
move(300, 250); assert.equal(frames.size, 0);
intersection([{ isIntersecting: true }]); move(300, 250); flush(5700);
heroEvents.pointerdown(event(300, 250)); flush(5800);
const normalAlpha = Math.max(...drawn.map(alpha));
protectedRects.push({ getBoundingClientRect: () => ({ left: 0, right: 600, top: 0, bottom: 500 }) });
flush(5800);
const occludedAlpha = Math.max(...drawn.map(alpha));
assert.ok(Math.abs(occludedAlpha / normalAlpha - 0.15) < 0.02, 'content occlusion suppresses opacity by 85 percent');
document.hidden = true; events.visibilitychange(); assert.equal(frames.size, 0);
console.log('PASS: Toss-style dots/digits, shrinking trail, stopped-cursor wave, scaled clicks, idle shutdown and input guards');
