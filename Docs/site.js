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

(() => {
  const canvas = document.querySelector(".hero-cursor");
  const context = canvas?.getContext("2d");
  if (!context) return;
  const hero = canvas.closest(".hero");
  const protectedAreas = document.querySelectorAll(".hero-copy, .hero-figure, .site-header");
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  const mouse = matchMedia("(hover: hover) and (pointer: fine)");
  const cells = new Map();
  const spacing = 20;
  const radius = 100;
  const lifetime = 750;
  let pointer = null;
  let frame = 0;
  let visible = true;

  function clear() {
    cancelAnimationFrame(frame);
    frame = 0;
    pointer = null;
    cells.clear();
    context.clearRect(0, 0, canvas.width, canvas.height);
  }

  function resize() {
    clear();
    const bounds = hero.getBoundingClientRect();
    const scale = Math.min(devicePixelRatio || 1, 2);
    canvas.width = Math.round(bounds.width * scale);
    canvas.height = Math.round(bounds.height * scale);
    context.setTransform(scale, 0, 0, scale, 0, 0);
  }

  function draw(now) {
    frame = 0;
    const bounds = hero.getBoundingClientRect();
    const excluded = Array.from(protectedAreas, element => element.getBoundingClientRect());
    const blocked = (x, y) => excluded.some(rect =>
      x + bounds.left >= rect.left - 16 && x + bounds.left <= rect.right + 16 &&
      y + bounds.top >= rect.top - 16 && y + bounds.top <= rect.bottom + 16);
    if (pointer) {
      const px = pointer.x - bounds.left;
      const py = pointer.y - bounds.top;
      for (let x = Math.max(0, Math.ceil((px - radius) / spacing) * spacing); x < Math.min(bounds.width, px + radius); x += spacing) {
        for (let y = Math.max(0, Math.ceil((py - radius) / spacing) * spacing); y < Math.min(bounds.height, py + radius); y += spacing) {
          const strength = 1 - Math.hypot(x - px, y - py) / radius;
          if (strength > 0 && !blocked(x, y)) cells.set(`${x},${y}`, { x, y, strength, time: now });
        }
      }
      pointer = null;
    }
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.font = "10px monospace";
    context.fillStyle = "#bcb5ff";
    for (const [key, cell] of cells) {
      const fade = 1 - (now - cell.time) / lifetime;
      if (fade <= 0) { cells.delete(key); continue; }
      if (blocked(cell.x, cell.y)) continue;
      context.globalAlpha = cell.strength * fade * 0.32;
      context.fillText((cell.x / spacing + cell.y / spacing) % 2 ? "1" : "0", cell.x, cell.y);
    }
    context.globalAlpha = 1;
    if (cells.size) frame = requestAnimationFrame(draw);
  }

  hero.addEventListener("pointermove", event => {
    if (event.pointerType !== "mouse" || motion.matches || !mouse.matches || !visible) return;
    pointer = { x: event.clientX, y: event.clientY };
    if (!frame) frame = requestAnimationFrame(draw);
  }, { passive: true });
  hero.addEventListener("pointerleave", () => { pointer = null; });
  addEventListener("resize", resize);
  addEventListener("scroll", () => { pointer = null; }, { passive: true });
  document.addEventListener("visibilitychange", () => { if (document.hidden) clear(); });
  motion.addEventListener("change", clear);
  mouse.addEventListener("change", clear);
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (!visible) clear();
  }).observe(hero);
  resize();
})();
