# SVG Micro-Animations

Patterns for making SVG elements feel alive without being distracting.
Every animation here uses CSS `@keyframes` or SMIL — no JavaScript required.

## Table of Contents

1. [Core Principles](#core-principles) — how much motion, how fast, when to stop
2. [Pulsing & Breathing](#pulsing--breathing) — status indicators, glows, rings
3. [Floating & Bobbing](#floating--bobbing) — weightless drift for decorative elements
4. [Drawing-On](#drawing-on) — stroke reveal for line art and charts
5. [Orbital Motion](#orbital-motion) — dots or elements circling a center
6. [Particle Drift](#particle-drift) — scattered dots that fade and move
7. [Hover Interactions](#hover-interactions) — mouse-triggered transitions
8. [Performance & Accessibility](#performance--accessibility) — the non-negotiable rules

---

## Core Principles

### The alive-vs-gimmicky threshold

Human peripheral vision detects ALL motion. Every animation competes for
attention. The threshold:

- **2-3 simultaneous animations per viewport** — maximum. More than that
  fragments attention and creates visual noise.
- **3-6 seconds per loop** for ambient animations (breathing, floating).
  Faster than 2s feels anxious. Slower than 8s becomes imperceptible.
- **200-500ms for transitions** (hover, state changes). Under 100ms is
  invisible. Over 400ms feels sluggish.

### The invisibility test

The best ambient animations are ones users don't consciously notice. They
create a "living" feel without drawing attention. If a visitor points at
an animation and says "look at that" — it's probably too much.

### Custom easing is mandatory

Never use bare `ease`, `ease-in`, `ease-out`, or `linear` for organic
motion. These are generic defaults. Custom `cubic-bezier` values give
animations a distinctive, premium feel:

| Curve | Values | Use for |
|---|---|---|
| Organic breathing | `cubic-bezier(0.4, 0, 0.6, 1)` | Pulsing, breathing, floating |
| Natural deceleration | `cubic-bezier(0.4, 0, 0.2, 1)` | Drawing-on, entry animations |
| Bounce overshoot | `cubic-bezier(0.2, 0.7, 0.4, 1.65)` | Hover effects, playful entrances |
| Gentle float | `cubic-bezier(0.3, 0, 0.7, 1)` | Floating X-axis movement |

### SMIL for self-contained SVG animations

For inline SVG elements that should animate on their own (hero art,
decorative elements, badge icons), prefer SMIL over CSS @keyframes. SMIL
animations live inside the SVG element — copy it and the animation travels
with it. SMIL also offers capabilities CSS can't match:

- **Per-segment easing** via `calcMode="spline"` with `keySplines` — a
  different curve for each value transition, not one timing function for
  the whole animation
- **Motion along a path** via `<animateMotion>` — elements follow arbitrary
  SVG paths (trailing dots, orbiting particles)
- **Any SVG attribute** — animate `r`, `cx`, `cy`, `d`, `stroke-dashoffset`,
  not just transform and opacity

```svg
<!-- keySplines: one entry per transition (3 values = 2 entries) -->
<animate attributeName="r" values="20;23;20" dur="4s"
  calcMode="spline"
  keySplines="0.4 0 0.6 1; 0.6 0 0.4 1"
  repeatCount="indefinite"/>
```

**Use CSS @keyframes when** animating HTML elements around the SVG (card
hover, container transitions) or when the page's stylesheet already
controls timing.

---

## Pulsing & Breathing

Creates a "heartbeat" or "alive" feel for rings, dots, status indicators.

### Status indicator (pulsing dot)

```css
@keyframes pulse-ring {
  0% { transform: scale(1); opacity: 0.6; }
  100% { transform: scale(2.5); opacity: 0; }
}

.pulse-dot {
  position: relative;
}

.pulse-dot::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 50%;
  background: inherit;
  animation: pulse-ring 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
```

### Breathing glow (SVG)

```svg
<circle cx="50" cy="50" r="20" fill="var(--primary)">
  <animate attributeName="r" values="20;22;20" dur="4s"
    keySplines="0.4 0 0.6 1; 0.4 0 0.6 1" calcMode="spline"
    repeatCount="indefinite" />
  <animate attributeName="opacity" values="0.7;1;0.7" dur="4s"
    keySplines="0.4 0 0.6 1; 0.4 0 0.6 1" calcMode="spline"
    repeatCount="indefinite" />
</circle>
```

### Breathing dot with glow filter (premium pattern)

A SMIL-animated dot combined with an SVG glow filter creates a luminous,
living accent — richer than plain radius animation:

```svg
<defs>
  <filter id="dot-glow" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur"/>
    <feMerge>
      <feMergeNode in="blur"/>
      <feMergeNode in="SourceGraphic"/>
    </feMerge>
  </filter>
</defs>

<circle cx="50" cy="50" r="5" fill="var(--primary)"
  filter="url(#dot-glow)">
  <animate attributeName="r" values="5;7;5" dur="3s"
    calcMode="spline" keySplines="0.4 0 0.6 1; 0.4 0 0.6 1"
    repeatCount="indefinite"/>
  <animate attributeName="opacity" values="0.7;1;0.7" dur="3s"
    calcMode="spline" keySplines="0.4 0 0.6 1; 0.4 0 0.6 1"
    repeatCount="indefinite"/>
</circle>
```

The glow bleeds outward as the dot pulses, creating a warm "breathing"
effect. Use 3-5 of these scattered across a hero with staggered `begin`
offsets (`begin="0s"`, `begin="1s"`, `begin="2.2s"`).

### Rules

- Scale range: 0.95–1.05 (5% variation) for subtle. Never exceed ±15%.
- Duration: 3–6 seconds per cycle.
- **Stagger multiple pulsing elements** with `animation-delay` so they
  don't synchronize. Synchronized pulsing looks mechanical.
- Never pulse CTAs or buttons continuously — users will think they're
  loading indicators.

---

## Floating & Bobbing

Creates a weightless, drifting feel for decorative hero elements.

### Basic float

```css
@keyframes float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-12px); }
}
.floating { animation: float 4s cubic-bezier(0.4, 0, 0.6, 1) infinite; }
```

### Premium float (combined Y + rotation on different durations)

This breaks the loop's predictability — the combination of two animations
at different speeds means the element never quite repeats exactly:

```css
@keyframes float-y {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-12px); }
}
@keyframes sway {
  0%, 100% { transform: rotate(-1.5deg); }
  50% { transform: rotate(1.5deg); }
}
.floating-premium {
  animation:
    float-y 4s cubic-bezier(0.4, 0, 0.6, 1) infinite,
    sway 5.5s cubic-bezier(0.3, 0, 0.7, 1) infinite;
}
```

### Companion shadow

A floating element feels more grounded with a shadow that compresses
as the element rises:

```svg
<!-- Shadow ellipse under the floating element -->
<ellipse cx="50" cy="90" rx="20" ry="4" fill="rgba(0,0,0,0.08)">
  <animate attributeName="rx" values="20;16;20" dur="4s"
    keySplines="0.4 0 0.6 1; 0.4 0 0.6 1" calcMode="spline"
    repeatCount="indefinite" />
  <animate attributeName="opacity" values="0.08;0.04;0.08" dur="4s"
    keySplines="0.4 0 0.6 1; 0.4 0 0.6 1" calcMode="spline"
    repeatCount="indefinite" />
</ellipse>
```

### Rules

- Movement range: `translateY(-10px)` to `translateY(10px)` for small
  elements. Larger elements should move less (2-5% of their height).
- Never use `linear` timing — it makes objects look like they're on a
  conveyor belt.
- Never float text or anything users need to read.

---

## Drawing-On

Creates a "pen drawing" effect using `stroke-dashoffset` animation.

### Basic drawing-on

```css
.draw-on path {
  stroke-dasharray: 500;  /* >= total path length */
  stroke-dashoffset: 500;
  animation: draw 2.5s cubic-bezier(0.4, 0, 0.2, 1) forwards;
}
@keyframes draw {
  to { stroke-dashoffset: 0; }
}
```

### Staggered multi-path (sequential drawing)

```css
.draw-on path:nth-child(1) { animation-delay: 0s; }
.draw-on path:nth-child(2) { animation-delay: 0.3s; }
.draw-on path:nth-child(3) { animation-delay: 0.6s; }
```

### Rules

- Duration: 1.5–3s for a single icon, 3–5s for complex illustrations.
- Always use `animation-fill-mode: forwards` — without it, the drawing
  vanishes when the animation ends.
- Trigger below-fold drawings on scroll intersection, not page load.
  CSS: `animation-play-state: paused` until an `IntersectionObserver`
  adds a `.visible` class.
- Getting path length: set `stroke-dasharray` to a value larger than the
  path (e.g., 1000) — it works, even if it's not perfectly measured.

### Drawing-on with trailing dot (SMIL)

A dot following the drawn path creates a pen-tip effect. Uses
`<animateMotion>` to move a circle along the same path being revealed:

```svg
<g>
  <!-- The line being drawn -->
  <path id="draw-line" d="M20,50 C80,20 160,80 280,40"
    fill="none" stroke="var(--primary)" stroke-width="2"
    stroke-dasharray="300" stroke-dashoffset="300">
    <animate attributeName="stroke-dashoffset" from="300" to="0"
      dur="3s" calcMode="spline" keySplines="0.4 0 0.2 1"
      fill="freeze"/>
  </path>

  <!-- Trailing dot following the same path -->
  <circle r="4" fill="var(--primary)">
    <animateMotion dur="3s" calcMode="spline"
      keySplines="0.4 0 0.2 1" fill="freeze">
      <mpath href="#draw-line"/>
    </animateMotion>
    <animate attributeName="opacity" values="1;1;0"
      keyTimes="0;0.9;1" dur="3s" fill="freeze"/>
  </circle>
</g>
```

The trailing dot fades out in the last 10% of the animation. This is
much richer than a plain dashoffset reveal — the moving dot gives the
drawing a sense of agency and intention.

---

## Orbital Motion

Elements circling a center. Good for tech diagrams and abstract compositions.

### Circular orbit (stable orientation)

The double-rotate trick keeps the orbiting element upright while it follows
a circular path:

```css
@keyframes orbit {
  from { transform: rotate(0deg) translateX(80px) rotate(0deg); }
  to { transform: rotate(360deg) translateX(80px) rotate(-360deg); }
}
.orbiting-dot {
  animation: orbit 12s linear infinite;
  transform-box: fill-box;  /* critical for SVG elements */
  transform-origin: center;
}
```

### Multiple dots (staggered with negative delay)

Negative `animation-delay` pre-positions elements along the orbit so they
start at different points:

```css
.dot-1 { animation: orbit 12s linear infinite; animation-delay: 0s; }
.dot-2 { animation: orbit 12s linear infinite; animation-delay: -4s; }
.dot-3 { animation: orbit 12s linear infinite; animation-delay: -8s; }
```

### Rules

- Duration: 8–20 seconds. Faster than 5s looks like a loading spinner.
- Maximum 4-5 orbiting elements — more becomes chaotic.
- `linear` timing is correct here (constant-speed orbits feel natural).
- **`transform-box: fill-box`** is required on SVG elements — without it,
  `transform-origin` defaults to the SVG viewport origin (0,0), causing
  unexpected rotation centers.

---

## Particle Drift

Scattered dots that fade and drift for atmospheric depth.

### CSS-only particles (no JS needed for small counts)

```css
@keyframes drift {
  0% { transform: translateY(0) translateX(0); opacity: 0.5; }
  100% { transform: translateY(-40px) translateX(15px); opacity: 0; }
}

.particle {
  position: absolute;
  width: 4px; height: 4px;
  border-radius: 50%;
  background: var(--primary);
  animation: drift 5s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
.particle:nth-child(2) { animation-delay: -1.2s; animation-duration: 6s; }
.particle:nth-child(3) { animation-delay: -2.8s; animation-duration: 4.5s; }
```

### SVG particles with SMIL

```svg
<circle cx="100" cy="200" r="2" fill="var(--primary)" opacity="0">
  <animate attributeName="cy" values="200;160" dur="5s"
    repeatCount="indefinite" />
  <animate attributeName="opacity" values="0;0.5;0" dur="5s"
    repeatCount="indefinite" />
</circle>
```

### Rules

- 10–20 particles for a subtle effect. Over 30 impacts performance.
- Each particle should use only `transform` and `opacity` for GPU
  compositing.
- Vary duration (4–7s) and delay across particles so they don't sync.
- Never let particles obscure readable content.

---

## Hover Interactions

Mouse-triggered transitions for cards, icons, and badges.

### Card lift

```css
.card {
  transition: transform 200ms cubic-bezier(0.2, 0.7, 0.4, 1.65),
              box-shadow 200ms ease-out;
}
.card:hover {
  transform: translateY(-4px) scale(1.01);
  box-shadow: 0 12px 24px rgba(0, 0, 0, 0.08);
}
```

### SVG icon color shift

```css
.icon-wrap svg {
  transition: color 150ms ease-out;
  color: var(--text-secondary);
}
.icon-wrap:hover svg {
  color: var(--primary);
}
```

### Rules

- Duration: 150–300ms for hover transitions. Over 400ms feels sluggish.
- Use a bounce overshoot (`cubic-bezier(0.2, 0.7, 0.4, 1.65)`) for
  hover-in but simpler `ease-out` for hover-out.
- Keep hover movement under 8px translation.
- Hover effects don't exist on touch devices — never rely on them for
  critical interactions.

---

## Performance & Accessibility

### Animate only compositor-safe properties

These run on the GPU and never trigger layout recalculation:
- `transform` (translate, scale, rotate)
- `opacity`

**Never animate**: `width`, `height`, `top`, `left`, `margin`, `padding`,
`border`, `box-shadow`, `filter`, `border-radius`. These trigger expensive
repaint cycles.

### SVG-specific: transform-box

Always set `transform-box: fill-box` on SVG elements animated with CSS.
Without it, `transform-origin` defaults to the SVG viewport origin (0,0)
rather than the element's own bounding box:

```css
svg .animated-element {
  transform-box: fill-box;
  transform-origin: center;
}
```

### will-change: use sparingly

Do NOT apply `will-change` as a blanket optimization. Each declaration
creates a new compositor layer, consuming GPU memory. Apply it only to
elements with measured jank, and only if the animation is continuous.

### prefers-reduced-motion (non-negotiable)

70+ million people have vestibular disorders. This is mandatory:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

**Nuanced approach**: instead of killing all animation, reduce to
opacity-only transitions (fade without movement). This preserves visual
feedback while removing the motion that causes sickness.

### Simultaneous animation budget

Keep to **2-3 actively animating elements** in any viewport. Stagger
`animation-delay` so animations don't all start together. On mobile,
reduce to 1-2 animations — mobile GPUs are weaker.
