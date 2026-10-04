(() => {
  const preview = document.querySelector(".device-frame");
  const line = preview.querySelector(".chart-line");
  const point = preview.querySelector(".chart-point");
  const reveal = preview.querySelector("#chart-reveal rect");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const length = line.getTotalLength();
  let pendingFrame = 0;

  function updateChart() {
    pendingFrame = 0;
    // Reveal while the preview travels from the bottom toward the top of the viewport.
    const progress = reducedMotion.matches ? 1 : Math.min(1, Math.max(0,
      (innerHeight * 0.9 - preview.getBoundingClientRect().top) / (innerHeight * 0.7)
    ));
    const position = line.getPointAtLength(length * progress);
    reveal.setAttribute("width", position.x);
    point.setAttribute("cx", position.x);
    point.setAttribute("cy", position.y);
  }

  function scheduleUpdate() {
    if (!pendingFrame) pendingFrame = requestAnimationFrame(updateChart);
  }

  addEventListener("scroll", scheduleUpdate, { passive: true });
  addEventListener("resize", scheduleUpdate);
  reducedMotion.addEventListener("change", scheduleUpdate);
  scheduleUpdate();
})();

// Cursor-field geometry and timing verified against Toss Open API's published
// d8a22ffa-b8b8873d2584e253.js on 2026-10-05; rendered only inside our hero.
(() => {
  const canvas = document.querySelector(".hero-cursor");
  const context = canvas?.getContext("2d");
  if (!context) return;
  const hero = canvas.closest(".hero");
  const protectedAreas = hero.querySelectorAll(".hero-copy, .hero-figure");
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  const mouse = matchMedia("(hover: hover) and (pointer: fine)");
  const spacing = 1450 / 150;
  const palette = [[255, 255, 255], [180, 120, 255], [180, 255, 180], [100, 180, 255]];
  const chars = Array.from({ length: 12000 }, () => Math.random() > 0.5 ? "1" : "0");
  const timers = chars.map(() => Math.floor(120 * Math.random()));
  const trail = [], clicks = [];
  let width = 0, height = 0, frame = 0, idleTimer = 0;
  let visible = true, pointer = null, idle = null, scrollHover = null;
  let effectStarted = null, lastClick = -Infinity, clickCount = 0;
  let trailColor = palette[0], clickColor = palette[0];
  const enabled = () => visible && !document.hidden && !motion.matches && mouse.matches;
  const clamp = value => Math.min(1, Math.max(0, value));
  const smooth = value => { const t = clamp(value); return t * t * (3 - 2 * t); };
  const color = () => palette[Math.floor(Math.random() * palette.length)];
  const rgba = (rgb, alpha) => `rgba(${rgb.join(",")},${alpha.toFixed(2)})`;

  function stop() {
    cancelAnimationFrame(frame); clearTimeout(idleTimer);
    frame = idleTimer = 0;
    trail.length = clicks.length = 0;
    idle = scrollHover = pointer = effectStarted = null;
    context.clearRect(0, 0, width, height);
  }
  function kick() { if (enabled() && !frame) frame = requestAnimationFrame(draw); }
  function resize() {
    stop();
    const bounds = hero.getBoundingClientRect();
    width = bounds.width; height = bounds.height;
    const scale = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.max(1, Math.floor(width * scale));
    canvas.height = Math.max(1, Math.floor(height * scale));
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.textAlign = "center";
    context.textBaseline = "middle";
  }
  function locate(clientX, clientY) {
    const bounds = hero.getBoundingClientRect();
    const x = clientX - bounds.left, y = clientY - bounds.top;
    return x >= 0 && y >= 0 && x <= width && y <= height ? { x, y } : null;
  }
  function addPoint(event) {
    pointer = { clientX: event.clientX, clientY: event.clientY };
    const point = locate(event.clientX, event.clientY);
    if (!point) return false;
    const last = trail[trail.length - 1];
    if (last && Math.hypot(point.x - last.x, point.y - last.y) < 6) return true;
    if (!trail.length) trailColor = color();
    trail.push({ ...point, at: performance.now() });
    if (trail.length > 35) trail.splice(0, trail.length - 35);
    return true;
  }
  function rippleFactor(x, y, ripple, now, life, speed) {
    const elapsed = now - ripple.at;
    const fade = 0.5 * (1 + Math.cos(Math.PI * clamp(elapsed / life))) * ripple.fade;
    const distance = Math.hypot(x - ripple.x, y - ripple.y);
    return {
      char: fade * Math.max(0, 1 - distance / 61.8666666667),
      cursor: fade * Math.max(0, 1 - Math.abs(distance - elapsed / 1000 * speed) / 38.6666666667),
      distance,
    };
  }
  function draw(now) {
    frame = 0;
    if (!enabled()) { stop(); return; }
    while (trail.length && now - trail[0].at > 400) trail.shift();
    for (let i = clicks.length - 1; i >= 0; i--) {
      if (now - clicks[i].at >= 1200 * clicks[i].scale) clicks.splice(i, 1);
    }
    if (idle && now - idle.at >= 800) idle = null;
    if (scrollHover && now >= scrollHover.expiresAt) scrollHover = null;
    context.clearRect(0, 0, width, height);
    if (!trail.length && !clicks.length && !idle && !scrollHover) { effectStarted = null; return; }
    if (effectStarted === null) effectStarted = now;
    const effectAlpha = 1 - (1 - clamp((now - effectStarted) / 500)) ** 3;
    const bounds = hero.getBoundingClientRect();
    const excluded = Array.from(protectedAreas, element => element.getBoundingClientRect());
    const offsetX = (width - 1450) / 2, offsetY = (height - 773.3333333333) / 2;
    const firstColumn = Math.floor(-offsetX / spacing - 0.5);
    const lastColumn = Math.ceil((width - offsetX) / spacing - 0.5);
    const firstRow = Math.floor((Math.max(0, -bounds.top) - offsetY) / spacing - 0.5);
    const lastRow = Math.ceil((Math.min(height, innerHeight - bounds.top) - offsetY) / spacing - 0.5);
    const activeColor = clicks.length ? clickColor : trailColor;
    const ripples = idle ? [idle, ...clicks] : clicks;
    for (let row = firstRow; row <= lastRow; row++) {
      for (let column = firstColumn; column <= lastColumn; column++) {
        const x = offsetX + (column + 0.5) * spacing, y = offsetY + (row + 0.5) * spacing;
        if (x < 0 || x > width || y < 0 || y > height) continue;
        let charFactor = 0, cursorFactor = 0, nearest = Infinity;
        for (const point of trail) {
          const distance = Math.hypot(x - point.x, y - point.y);
          if (distance > 232) continue;
          const fade = smooth(1 - (now - point.at) / 400);
          if (fade <= 0) continue;
          nearest = Math.min(nearest, distance);
          cursorFactor = Math.max(cursorFactor, Math.max(0, 1 - distance / (100.5333333333 * fade)) * fade);
          charFactor = Math.max(charFactor, Math.max(0, 1 - distance / (232 * fade)) * fade);
        }
        if (scrollHover) {
          const fade = smooth((scrollHover.expiresAt - now) / 500);
          const distance = Math.hypot(x - scrollHover.x, y - scrollHover.y);
          nearest = Math.min(nearest, distance);
          cursorFactor = Math.max(cursorFactor, Math.max(0, 1 - distance / 100.5333333333) * fade);
          charFactor = Math.max(charFactor, Math.max(0, 1 - distance / 232) * fade);
        }
        for (const ripple of ripples) {
          const isIdle = ripple === idle;
          const factor = rippleFactor(x, y, ripple, now, isIdle ? 800 : 1200 * ripple.scale, isIdle ? 100.5333333333 : 154.6666666667);
          charFactor = Math.max(charFactor, factor.char);
          cursorFactor = Math.max(cursorFactor, factor.cursor);
          nearest = Math.min(nearest, factor.distance);
        }
        if (cursorFactor * effectAlpha <= 0.018) continue;
        const edge = Math.min(smooth(Math.min(x, width - x) / 120.8333333333), smooth(Math.min(y, height - y) / 64.4444444444));
        const region = Math.min(smooth(y / 200), smooth((height - y) / 200));
        let occlusion = 0;
        for (const rect of excluded) {
          const dx = Math.max(rect.left - 10 - bounds.left - x, bounds.left + x - rect.right - 10, 0);
          const dy = Math.max(rect.top - 10 - bounds.top - y, bounds.top + y - rect.bottom - 10, 0);
          occlusion = Math.max(occlusion, (1 - smooth(Math.hypot(dx, dy) / 200)) * 0.85);
        }
        const visibility = edge * region * (1 - occlusion) * effectAlpha;
        const alpha = Math.min(0.95, 0.67 * cursorFactor) * visibility;
        const wave = 1 + 0.9 * cursorFactor * Math.sin(0.05172413793103449 * nearest - now * 0.003);
        const dotAlpha = Math.min(0.9, 0.18 * cursorFactor * visibility);
        if (dotAlpha > 0.01) {
          context.beginPath(); context.arc(x, y, 0.435, 0, Math.PI * 2);
          context.fillStyle = rgba(activeColor, dotAlpha); context.fill();
        }
        if (charFactor > 0.05) {
          const index = ((row % 80 + 80) % 80) * 150 + ((column % 150 + 150) % 150);
          if (--timers[index] <= 0) {
            chars[index] = Math.random() > 0.5 ? "1" : "0";
            timers[index] = Math.floor(30 + 90 * Math.random());
          }
          context.font = `${(10.6333333333 * (0.08 + 0.9 * cursorFactor)).toFixed(1)}px "SF Mono", ui-monospace, SFMono-Regular, Menlo, monospace`;
          context.fillStyle = rgba(activeColor, Math.min(0.95, alpha * Math.max(0.1, wave)));
          context.fillText(chars[index], x, y);
        } else {
          context.beginPath(); context.arc(x, y, Math.max(0.3, 2.4166666667 * (0.2 + 0.48 * cursorFactor) * Math.max(0.1, wave)), 0, Math.PI * 2);
          context.fillStyle = rgba(activeColor, alpha); context.fill();
        }
      }
    }
    kick();
  }
  hero.addEventListener("pointermove", event => {
    if (event.pointerType !== "mouse" || !enabled()) return;
    if (idle) idle.at -= 800;
    if (!addPoint(event)) return;
    kick(); clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      if (!enabled() || !pointer || performance.now() - lastClick < 600) return;
      const point = locate(pointer.clientX, pointer.clientY);
      if (point) { idle = { ...point, at: performance.now(), fade: 1 }; kick(); }
    }, 50);
  }, { passive: true });
  hero.addEventListener("pointerleave", () => { pointer = null; clearTimeout(idleTimer); });
  hero.addEventListener("pointerdown", event => {
    if (event.pointerType !== "mouse" || !enabled() || !addPoint(event)) return;
    const now = performance.now();
    clickCount = now - lastClick <= 500 ? clickCount + 1 : 1; lastClick = now;
    const scale = Math.min(1 + (clickCount - 1) * 0.5, 3);
    const point = locate(event.clientX, event.clientY);
    clickColor = color();
    clicks.push({ ...point, scale, fade: 0.85, at: now });
    if (clickCount >= 2) clicks.push({ ...point, scale: scale * 1.5, fade: 0.55, at: now });
    if (clicks.length > 6) clicks.splice(0, clicks.length - 6);
    if (effectStarted === null) effectStarted = now - 500;
    kick();
  }, { passive: true });
  addEventListener("resize", resize);
  addEventListener("scroll", () => {
    if (!enabled() || !pointer) return;
    const point = locate(pointer.clientX, pointer.clientY);
    if (point) { scrollHover = { ...point, expiresAt: performance.now() + 500 }; kick(); }
  }, { passive: true });
  document.addEventListener("visibilitychange", () => { if (!enabled()) stop(); });
  motion.addEventListener("change", () => { if (!enabled()) stop(); });
  mouse.addEventListener("change", () => { if (!enabled()) stop(); });
  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; if (!visible) stop(); }).observe(hero);
  resize();
})();
