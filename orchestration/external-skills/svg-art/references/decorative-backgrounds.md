# Decorative Backgrounds

Ready-to-use SVG patterns and backgrounds for sections, heroes, and
full-page backdrops. Each recipe is self-contained — copy the SVG
markup or CSS directly.

## Table of Contents

1. [Tile Patterns](#tile-patterns) — dots, lines, crosses, chevrons, hex
2. [Organic Backgrounds](#organic-backgrounds) — blobs, waves, topographic, aurora
3. [Gradient Techniques](#gradient-techniques) — mesh, radial, conic, animated

---

## Tile Patterns

All tile patterns use `<pattern>` with `patternUnits="userSpaceOnUse"`
for consistent behavior. Apply them with `fill="url(#pattern-id)"` on
a full-size `<rect>`.

### Dot Grid

```svg
<svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <pattern id="dots" width="20" height="20" patternUnits="userSpaceOnUse">
      <circle cx="10" cy="10" r="1.5" fill="var(--text-muted)" opacity="0.3" />
    </pattern>
  </defs>
  <rect width="100%" height="100%" fill="url(#dots)" />
</svg>
```

**Variations:**
- Alternating sizes: add a second circle at (0,0) with r="1"
- Offset rows: shift every other row by half the width
- Gradient opacity: use `<linearGradient>` on the fill rect, not
  the dots, to fade the pattern out

### Diagonal Lines (Hatching)

```svg
<pattern id="hatch" width="10" height="10" patternUnits="userSpaceOnUse"
  patternTransform="rotate(45)">
  <line x1="0" y1="0" x2="0" y2="10"
    stroke="var(--border)" stroke-width="0.5" />
</pattern>
```

`patternTransform="rotate(45)"` rotates the entire pattern tile.
Change the angle for different hatching directions. Use `rotate(30)`
or `rotate(60)` for variety.

### Cross / Plus Pattern

```svg
<pattern id="crosses" width="24" height="24" patternUnits="userSpaceOnUse">
  <path d="M 12 8 L 12 16 M 8 12 L 16 12"
    stroke="var(--text-muted)" stroke-width="1" opacity="0.2"
    stroke-linecap="round" />
</pattern>
```

### Chevron / Herringbone

```svg
<pattern id="chevron" width="28" height="20" patternUnits="userSpaceOnUse">
  <path d="M 0 15 L 14 5 L 28 15"
    fill="none" stroke="var(--border)" stroke-width="1" opacity="0.3" />
</pattern>
```

### Hexagonal Grid

```svg
<pattern id="hex" width="56" height="100" patternUnits="userSpaceOnUse">
  <path d="M 28 0 L 56 17 L 56 50 L 28 67 L 0 50 L 0 17 Z"
    fill="none" stroke="var(--border)" stroke-width="0.5" opacity="0.15" />
  <path d="M 28 67 L 56 84 M 28 67 L 0 84"
    fill="none" stroke="var(--border)" stroke-width="0.5" opacity="0.15" />
</pattern>
```

### Grid Lines

```svg
<pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
  <path d="M 40 0 L 0 0 L 0 40"
    fill="none" stroke="var(--border)" stroke-width="0.5" opacity="0.1" />
</pattern>
```

### CSS Background Approach

For performance, encode small pattern tiles as data URIs:

```css
.dotted-bg {
  background-image: url("data:image/svg+xml,%3Csvg width='20' height='20' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='10' cy='10' r='1.5' fill='%23888' opacity='0.2'/%3E%3C/svg%3E");
  background-size: 20px 20px;
}
```

**URL encoding cheat sheet** for data URIs:
- `<` → `%3C`
- `>` → `%3E`
- `#` → `%23`
- `"` → `%22` (or use single quotes inside SVG)
- space → `%20`

### Fading Pattern Edge

Overlay a gradient to fade the pattern out at edges:

```css
.pattern-section {
  position: relative;
}
.pattern-section::before {
  content: '';
  position: absolute;
  inset: 0;
  background-image: url("data:image/svg+xml,...");
  mask-image: radial-gradient(ellipse at center, black 40%, transparent 70%);
  -webkit-mask-image: radial-gradient(ellipse at center, black 40%, transparent 70%);
  pointer-events: none;
}
```

---

## Organic Backgrounds

### Blob Background

Large, overlapping soft blobs behind content. Use low opacity and
the page's color palette:

```svg
<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"
  style="position: absolute; inset: 0; width: 100%; height: 100%; z-index: -1;">

  <!-- Blob 1: large, background -->
  <circle cx="200" cy="300" r="250" fill="var(--primary)" opacity="0.06" />

  <!-- Blob 2: offset, different color -->
  <ellipse cx="600" cy="200" rx="200" ry="280" fill="var(--accent)" opacity="0.05"
    transform="rotate(-15 600 200)" />

  <!-- Blob 3: organic shape -->
  <path d="M 400 100 C 500 50, 650 150, 600 300
           S 450 500, 350 400 C 250 350, 300 150, 400 100 Z"
    fill="var(--primary)" opacity="0.04" />

  <!-- Optional: blur for softness -->
  <defs>
    <filter id="blob-blur">
      <feGaussianBlur stdDeviation="40" />
    </filter>
  </defs>
</svg>
```

For truly organic blobs, use the `blobPath()` function from
`generative-patterns.md` § Organic Shapes.

### Wave Section Divider

A wave-shaped divider between two sections:

```svg
<svg viewBox="0 0 1440 120" xmlns="http://www.w3.org/2000/svg"
  aria-hidden="true" preserveAspectRatio="none"
  style="width: 100%; height: 80px; display: block;">
  <path d="M 0 60
    C 240 0, 480 120, 720 60
    S 1200 0, 1440 60
    L 1440 120 L 0 120 Z"
    fill="var(--surface-1)" />
</svg>
```

`preserveAspectRatio="none"` stretches to fill the width. The
`display: block` removes the inline gap below the SVG.

**Layered waves** — stack 2-3 wave paths with different amplitudes
and opacities for depth:

```svg
<svg viewBox="0 0 1440 200" preserveAspectRatio="none" aria-hidden="true"
  style="width: 100%; height: 120px; display: block;">
  <!-- Back wave (subtle) -->
  <path d="M 0 100 C 360 50, 720 150, 1080 80 S 1440 120, 1440 100
    L 1440 200 L 0 200 Z"
    fill="var(--surface-1)" opacity="0.5" />
  <!-- Front wave (solid) -->
  <path d="M 0 120 C 300 80, 600 160, 900 100 S 1200 140, 1440 110
    L 1440 200 L 0 200 Z"
    fill="var(--surface-1)" />
</svg>
```

### Topographic Background

Contour lines created with SVG filter:

```svg
<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"
  style="position: absolute; inset: 0; width: 100%; height: 100%; z-index: -1; opacity: 0.08;">
  <defs>
    <filter id="topo">
      <feTurbulence type="fractalNoise" baseFrequency="0.012"
        numOctaves="4" seed="42" />
      <feComponentTransfer>
        <feFuncR type="discrete"
          tableValues="0 0 0.3 0.3 0.6 0.6 0.9 0.9 1 1" />
        <feFuncG type="discrete"
          tableValues="0 0 0.3 0.3 0.6 0.6 0.9 0.9 1 1" />
        <feFuncB type="discrete"
          tableValues="0 0 0.3 0.3 0.6 0.6 0.9 0.9 1 1" />
      </feComponentTransfer>
    </filter>
  </defs>
  <rect width="100%" height="100%" filter="url(#topo)" />
</svg>
```

The `seed` attribute on `feTurbulence` controls which random pattern
is generated. Change it to get different topographic shapes.

### Aurora / Northern Lights

Layered gradient blobs with blur and blend:

```svg
<svg viewBox="0 0 800 400" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <filter id="aurora-blur">
      <feGaussianBlur stdDeviation="30" />
    </filter>
  </defs>

  <!-- Dark sky background -->
  <rect width="100%" height="100%" fill="#0a0a1a" />

  <!-- Aurora bands -->
  <g filter="url(#aurora-blur)" opacity="0.6">
    <ellipse cx="300" cy="200" rx="350" ry="60" fill="#00ff88"
      transform="rotate(-5 300 200)" opacity="0.4" />
    <ellipse cx="500" cy="180" rx="300" ry="40" fill="#00ddff"
      transform="rotate(3 500 180)" opacity="0.3" />
    <ellipse cx="400" cy="220" rx="250" ry="50" fill="#8800ff"
      transform="rotate(-8 400 220)" opacity="0.2" />
  </g>

  <!-- Star speckle overlay -->
  <rect width="100%" height="100%" filter="url(#stars)" opacity="0.3" />
</svg>
```

---

## Gradient Techniques

### Multi-Stop Linear Gradient

```svg
<defs>
  <linearGradient id="sunset" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" stop-color="#1a0533" />
    <stop offset="30%" stop-color="#4a1942" />
    <stop offset="60%" stop-color="#c94b4b" />
    <stop offset="80%" stop-color="#f0a500" />
    <stop offset="100%" stop-color="#f8d568" />
  </linearGradient>
</defs>
```

### Radial Spotlight

Off-center radial gradient creates a spotlight effect:

```svg
<defs>
  <radialGradient id="spotlight" cx="30%" cy="30%" r="70%">
    <stop offset="0%" stop-color="var(--primary)" stop-opacity="0.15" />
    <stop offset="100%" stop-color="transparent" />
  </radialGradient>
</defs>
<rect width="100%" height="100%" fill="url(#spotlight)" />
```

### Mesh-Like Gradient (Multiple Radials)

True mesh gradients aren't widely supported in SVG, but layering
multiple radial gradients approximates the effect:

```svg
<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <radialGradient id="mesh1" cx="20%" cy="30%" r="50%">
      <stop offset="0%" stop-color="#6366f1" stop-opacity="0.4" />
      <stop offset="100%" stop-color="transparent" />
    </radialGradient>
    <radialGradient id="mesh2" cx="70%" cy="60%" r="45%">
      <stop offset="0%" stop-color="#ec4899" stop-opacity="0.3" />
      <stop offset="100%" stop-color="transparent" />
    </radialGradient>
    <radialGradient id="mesh3" cx="50%" cy="80%" r="40%">
      <stop offset="0%" stop-color="#06b6d4" stop-opacity="0.25" />
      <stop offset="100%" stop-color="transparent" />
    </radialGradient>
  </defs>

  <rect width="100%" height="100%" fill="var(--surface-0)" />
  <rect width="100%" height="100%" fill="url(#mesh1)" />
  <rect width="100%" height="100%" fill="url(#mesh2)" />
  <rect width="100%" height="100%" fill="url(#mesh3)" />
</svg>
```

### CSS Conic Gradient Background

Not SVG but pairs well with SVG overlays:

```css
.conic-bg {
  background: conic-gradient(
    from 45deg at 50% 50%,
    var(--primary) 0deg,
    var(--accent) 120deg,
    var(--primary-light) 240deg,
    var(--primary) 360deg
  );
  filter: blur(80px);
  opacity: 0.15;
}
```

### Animated Gradient (CSS on SVG)

```css
@keyframes gradient-shift {
  0%, 100% { stop-color: var(--primary); }
  50% { stop-color: var(--accent); }
}

#animated-grad stop:first-child {
  animation: gradient-shift 6s ease-in-out infinite;
}
```

### Gradient Along Path

Use `gradientUnits="userSpaceOnUse"` to align a gradient to the
world coordinate space (useful for paths that aren't axis-aligned):

```svg
<defs>
  <linearGradient id="path-grad" gradientUnits="userSpaceOnUse"
    x1="0" y1="0" x2="800" y2="0">
    <stop offset="0%" stop-color="var(--primary)" />
    <stop offset="100%" stop-color="var(--accent)" />
  </linearGradient>
</defs>
<path d="M 50 300 C 200 100, 400 500, 600 200 S 750 400, 800 300"
  stroke="url(#path-grad)" stroke-width="3" fill="none" />
```
