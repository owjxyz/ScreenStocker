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
