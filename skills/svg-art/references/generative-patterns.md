# Generative Patterns

Mathematical and algorithmic techniques for creating SVG art
programmatically. All examples produce SVG path data that can be
embedded as inline `<path d="...">` elements.

## Table of Contents

1. [Utility Functions](#utility-functions) — random, map, lerp, polar
2. [Mathematical Curves](#mathematical-curves) — sine, Lissajous, spirograph, spiral
3. [Organic Shapes](#organic-shapes) — blobs, fluid forms, natural curves
4. [Grid Art](#grid-art) — generative grid compositions
5. [Distributions](#distributions) — particle fields, dot patterns, scatter
6. [Data-Driven Art](#data-driven-art) — sparklines, abstract data representation
7. [Smoothing Techniques](#smoothing-techniques) — converting points to smooth curves

---

## Utility Functions

These appear in `<script>` blocks or in build-time generation scripts.
All generative SVG techniques build on these primitives:

```javascript
function random(min, max) {
  return Math.random() * (max - min) + min;
}

function randomInt(min, max) {
  return Math.floor(random(min, max + 1));
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function map(value, inMin, inMax, outMin, outMax) {
  return ((value - inMin) / (inMax - inMin)) * (outMax - outMin) + outMin;
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function polar(cx, cy, radius, angle) {
  return {
    x: cx + radius * Math.cos(angle),
    y: cy + radius * Math.sin(angle)
  };
}

function dist(x1, y1, x2, y2) {
  return Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2);
}

// Simple seeded pseudo-random for reproducible results
function seededRandom(seed) {
  let s = seed;
  return function() {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
}
```

---

## Mathematical Curves

### Sine Wave Path

```javascript
function sinePath(width, amplitude, frequency, yOffset, steps = 200) {
  const points = [];
  for (let i = 0; i <= steps; i++) {
    const x = (i / steps) * width;
    const y = yOffset + amplitude * Math.sin((i / steps) * frequency * Math.PI * 2);
    points.push({ x, y });
  }
  return pointsToSmoothPath(points); // See Smoothing Techniques
}
```

**Layered waves** — multiple sine waves at different frequencies create
ocean, terrain, or audio waveform effects:

```javascript
function layeredWaves(width, height, layers = 5) {
  const paths = [];
  for (let i = 0; i < layers; i++) {
    const amp = random(10, 30);
    const freq = random(2, 6);
    const yBase = map(i, 0, layers - 1, height * 0.3, height * 0.8);
    const opacity = map(i, 0, layers - 1, 0.1, 0.4);
    const d = sinePath(width, amp, freq, yBase);
    // Close the path at the bottom to create filled wave shapes
    paths.push({
      d: d + ` L ${width} ${height} L 0 ${height} Z`,
      opacity
    });
  }
  return paths;
}
```

### Lissajous Curves

Parametric curves that create intricate looping patterns:

```javascript
function lissajousPath(cx, cy, A, B, freqX, freqY, phase, steps = 500) {
  const points = [];
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * Math.PI * 2;
    points.push({
      x: cx + A * Math.sin(freqX * t + phase),
      y: cy + B * Math.cos(freqY * t)
    });
  }
  return pointsToSmoothPath(points) + ' Z';
}
```

**Frequency ratios determine the shape:**
- 1:2 → figure-eight
- 2:3 → trefoil knot
- 3:4 → complex loops
- Irrational ratios → never-closing curves (most interesting visually)

**Phase shift** (`phase` parameter) rotates/morphs the shape. Animating
phase from 0 to 2π creates smooth morphing.

### Spirograph (Hypotrochoid)

```javascript
function spirographPath(cx, cy, R, r, d, steps = 1000) {
  const points = [];
  const turns = r / gcd(R, r); // Number of full rotations needed
  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * Math.PI * 2 * turns;
    points.push({
      x: cx + (R - r) * Math.cos(t) + d * Math.cos(((R - r) / r) * t),
      y: cy + (R - r) * Math.sin(t) - d * Math.sin(((R - r) / r) * t)
    });
  }
  return pointsToSmoothPath(points) + ' Z';
}

function gcd(a, b) {
  return b === 0 ? a : gcd(b, a % b);
}
```

**Parameter guide:**
- `R` — outer circle radius (e.g., 200)
- `r` — inner circle radius (e.g., 75)
- `d` — pen offset from inner center (e.g., 50)
- When `d < r` → loops stay inside outer circle
- When `d > r` → loops extend outside
- When `R/r` is an integer → simpler patterns
- When `R/r` is irrational → endlessly complex

### Spiral

```javascript
function spiralPath(cx, cy, startRadius, endRadius, turns, steps = 300) {
  const points = [];
  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const angle = t * turns * Math.PI * 2;
    const radius = lerp(startRadius, endRadius, t);
    points.push(polar(cx, cy, radius, angle));
  }
  return pointsToSmoothPath(points);
}
```

---

## Organic Shapes

### Blob Generator

Creates smooth, organic blob shapes using polar coordinates with
sinusoidal radius variation:

```javascript
function blobPath(cx, cy, baseRadius, variance, complexity, points = 64) {
  const angleStep = (Math.PI * 2) / points;
  const coords = [];

  for (let i = 0; i < points; i++) {
    const angle = i * angleStep;
    // Layer multiple sine waves for organic feel
    let r = baseRadius;
    for (let j = 1; j <= complexity; j++) {
      r += (variance / j) * Math.sin(angle * j + random(0, Math.PI * 2));
    }
    coords.push(polar(cx, cy, r, angle));
  }

  return pointsToSmoothPath(coords, true); // closed = true
}
```

**Parameter guide:**
- `baseRadius` — average blob size
- `variance` — how much the radius wobbles (10-30% of baseRadius)
- `complexity` — number of frequency layers (2 = simple, 5 = complex)
- Higher complexity = more tentacle-like protrusions

### Fluid / Metaball Forms

Layer multiple overlapping blobs with the same fill color to create
fluid, merged shapes:

```javascript
function fluidComposition(width, height, count = 5) {
  const blobs = [];
  for (let i = 0; i < count; i++) {
    blobs.push(blobPath(
      random(width * 0.2, width * 0.8),
      random(height * 0.2, height * 0.8),
      random(40, 120),   // baseRadius
      random(10, 30),    // variance
      randomInt(2, 4)    // complexity
    ));
  }
  return blobs;
}
```

### Terrain / Mountain Silhouette

Midpoint displacement algorithm for natural-looking terrain:

```javascript
function terrainPath(width, height, roughness, depth = 8) {
  // Start with two endpoints
  let points = [
    { x: 0, y: height * 0.6 },
    { x: width, y: height * 0.6 }
  ];

  // Midpoint displacement
  for (let d = 0; d < depth; d++) {
    const newPoints = [points[0]];
    for (let i = 0; i < points.length - 1; i++) {
      const mid = {
        x: (points[i].x + points[i + 1].x) / 2,
        y: (points[i].y + points[i + 1].y) / 2 +
           random(-roughness, roughness) * (width / Math.pow(2, d + 1))
      };
      newPoints.push(mid, points[i + 1]);
    }
    points = newPoints;
  }

  // Close the path at the bottom
  const d = pointsToPath(points);
  return d + ` L ${width} ${height} L 0 ${height} Z`;
}
```

Layer 3-4 terrain paths with different roughness and opacity for
a mountain range with atmospheric depth.

---

## Grid Art

### Generative Grid Composition

Fill grid cells with random geometric elements from a curated set:

```javascript
function gridArt(width, height, cols, rows, palette) {
  const cellW = width / cols;
  const cellH = height / rows;
  const elements = [];

  const cellTypes = [
    drawCircle, drawDiagonal, drawQuarterCircle,
    drawCross, drawHalfCircle, drawTriangle, drawEmpty
  ];

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = c * cellW;
      const y = r * cellH;
      const draw = pick(cellTypes);
      const fg = pick(palette);
      const bg = pick(palette);
      elements.push(draw(x, y, cellW, cellH, fg, bg));
    }
  }
  return elements;
}

// Example cell type: quarter circle in corner
function drawQuarterCircle(x, y, w, h, fg, bg) {
  const corner = randomInt(0, 3); // which corner
  const cx = corner % 2 === 0 ? x : x + w;
  const cy = corner < 2 ? y : y + h;
  return `
    <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${bg}" />
    <circle cx="${cx}" cy="${cy}" r="${Math.min(w, h)}" fill="${fg}" />
  `;
}
```

**Design principles for grid art:**
- Use a limited palette (3-5 colors) — the grid structure provides
  enough visual complexity
- Include an "empty" cell type (just background color) to create
  breathing room
- Clip each cell so shapes don't overflow: wrap in a `<clipPath>`
- Vary the rotation of elements within cells for asymmetry

### Bento Grid

Non-uniform grid where some cells span 2+ rows or columns:

```javascript
function bentoGrid(width, height, palette) {
  const unit = width / 6; // 6-column base grid
  const cells = [
    { x: 0, y: 0, w: 2, h: 2 },     // large square
    { x: 2, y: 0, w: 4, h: 1 },     // wide bar
    { x: 2, y: 1, w: 2, h: 1 },     // medium
    { x: 4, y: 1, w: 2, h: 2 },     // tall
    { x: 0, y: 2, w: 3, h: 1 },     // wide
    { x: 3, y: 2, w: 1, h: 1 },     // small
  ];

  return cells.map(cell => {
    const x = cell.x * unit;
    const y = cell.y * unit;
    const w = cell.w * unit;
    const h = cell.h * unit;
    return drawGridCell(x, y, w, h, pick(palette));
  });
}
```

---

## Distributions

### Poisson Disk Sampling

Distribute points with minimum spacing (more natural than random):

```javascript
function poissonDisk(width, height, minDist, maxAttempts = 30) {
  const points = [];
  const cellSize = minDist / Math.SQRT2;
  const cols = Math.ceil(width / cellSize);
  const rows = Math.ceil(height / cellSize);
  const grid = new Array(cols * rows).fill(null);
  const active = [];

  function gridIndex(x, y) {
    return Math.floor(x / cellSize) + Math.floor(y / cellSize) * cols;
  }

  // Seed point
  const seed = { x: width / 2, y: height / 2 };
  points.push(seed);
  active.push(seed);
  grid[gridIndex(seed.x, seed.y)] = seed;

  while (active.length > 0) {
    const idx = randomInt(0, active.length - 1);
    const point = active[idx];
    let found = false;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const angle = random(0, Math.PI * 2);
      const radius = random(minDist, minDist * 2);
      const candidate = {
        x: point.x + radius * Math.cos(angle),
        y: point.y + radius * Math.sin(angle)
      };

      if (candidate.x < 0 || candidate.x >= width ||
          candidate.y < 0 || candidate.y >= height) continue;

      let tooClose = false;
      const gi = gridIndex(candidate.x, candidate.y);
      // Check neighboring cells
      for (let dx = -2; dx <= 2 && !tooClose; dx++) {
        for (let dy = -2; dy <= 2 && !tooClose; dy++) {
          const ni = gi + dx + dy * cols;
          if (ni >= 0 && ni < grid.length && grid[ni]) {
            if (dist(candidate.x, candidate.y, grid[ni].x, grid[ni].y) < minDist) {
              tooClose = true;
            }
          }
        }
      }

      if (!tooClose) {
        points.push(candidate);
        active.push(candidate);
        grid[gridIndex(candidate.x, candidate.y)] = candidate;
        found = true;
        break;
      }
    }

    if (!found) active.splice(idx, 1);
  }

  return points;
}
```

### Concentric Distribution

Points arranged in rings with slight randomization:

```javascript
function concentricDots(cx, cy, rings, dotsPerRing, maxRadius) {
  const points = [];
  for (let r = 1; r <= rings; r++) {
    const radius = (r / rings) * maxRadius;
    const count = Math.floor(dotsPerRing * (r / rings));
    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2 + random(-0.1, 0.1);
      const jitter = random(-3, 3);
      points.push(polar(cx, cy, radius + jitter, angle));
    }
  }
  return points;
}
```

### Size-Varying Dot Field

Map dot size to distance from a focal point:

```javascript
function focalDotField(points, focalX, focalY, maxDist, minSize, maxSize) {
  return points.map(p => {
    const d = dist(p.x, p.y, focalX, focalY);
    const size = map(Math.min(d, maxDist), 0, maxDist, maxSize, minSize);
    return `<circle cx="${p.x}" cy="${p.y}" r="${size}" />`;
  }).join('\n');
}
```

---

## Data-Driven Art

### Sparkline

Minimal inline line chart:

```javascript
function sparkline(data, width, height, strokeColor = 'currentColor') {
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;

  const points = data.map((v, i) => ({
    x: (i / (data.length - 1)) * width,
    y: height - ((v - min) / range) * height
  }));

  const d = pointsToSmoothPath(points);

  return `<svg viewBox="0 0 ${width} ${height}" aria-hidden="true"
    style="width: ${width}px; height: ${height}px;">
    <path d="${d}" fill="none" stroke="${strokeColor}"
      stroke-width="1.5" stroke-linecap="round" />
  </svg>`;
}
```

### Bar Chart (Minimal)

```javascript
function miniBarChart(data, width, height, color) {
  const max = Math.max(...data);
  const barW = width / data.length * 0.8;
  const gap = width / data.length * 0.2;

  const bars = data.map((v, i) => {
    const barH = (v / max) * height;
    const x = i * (barW + gap);
    const y = height - barH;
    return `<rect x="${x}" y="${y}" width="${barW}" height="${barH}"
      rx="2" fill="${color}" opacity="${map(v, 0, max, 0.4, 1)}" />`;
  }).join('\n');

  return `<svg viewBox="0 0 ${width} ${height}" aria-hidden="true">${bars}</svg>`;
}
```

### Data-as-Art

Use real data values to drive generative parameters:

```javascript
// Map data to ring radii for abstract visualization
function dataRings(data, cx, cy, maxRadius, strokeColor) {
  return data.map((v, i) => {
    const radius = map(v, 0, Math.max(...data), 10, maxRadius);
    const opacity = map(i, 0, data.length - 1, 0.8, 0.2);
    return `<circle cx="${cx}" cy="${cy}" r="${radius}"
      fill="none" stroke="${strokeColor}" stroke-width="1"
      opacity="${opacity}" />`;
  }).join('\n');
}
```

---

## Smoothing Techniques

Raw computed points produce jagged paths. These functions convert
point arrays to smooth SVG curves.

### Points to Smooth Path (Catmull-Rom → Cubic Bezier)

The most useful smoothing function. Converts any array of points into
a smooth SVG path using Catmull-Rom to cubic bezier conversion:

```javascript
function pointsToSmoothPath(points, closed = false) {
  if (points.length < 2) return '';
  if (points.length === 2) {
    return `M ${points[0].x} ${points[0].y} L ${points[1].x} ${points[1].y}`;
  }

  const tension = 0.3; // 0 = angular, 0.5 = very smooth
  let d = `M ${points[0].x} ${points[0].y}`;

  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[i === 0 ? (closed ? points.length - 1 : 0) : i - 1];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[i + 2 >= points.length ? (closed ? (i + 2) % points.length : points.length - 1) : i + 2];

    const cp1x = p1.x + (p2.x - p0.x) * tension;
    const cp1y = p1.y + (p2.y - p0.y) * tension;
    const cp2x = p2.x - (p3.x - p1.x) * tension;
    const cp2y = p2.y - (p3.y - p1.y) * tension;

    d += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2.x} ${p2.y}`;
  }

  if (closed) d += ' Z';
  return d;
}
```

### Points to Polyline (No Smoothing)

For when you want sharp edges (geometric patterns, data viz):

```javascript
function pointsToPath(points, closed = false) {
  if (points.length === 0) return '';
  let d = `M ${points[0].x} ${points[0].y}`;
  for (let i = 1; i < points.length; i++) {
    d += ` L ${points[i].x} ${points[i].y}`;
  }
  if (closed) d += ' Z';
  return d;
}
```

### Simplify Path (Ramer-Douglas-Peucker)

Reduce point count while preserving shape. Essential for performance
when generating paths with hundreds of points:

```javascript
function simplifyPath(points, epsilon) {
  if (points.length <= 2) return points;

  let maxDist = 0;
  let maxIdx = 0;

  const start = points[0];
  const end = points[points.length - 1];

  for (let i = 1; i < points.length - 1; i++) {
    const d = pointToLineDist(points[i], start, end);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }

  if (maxDist > epsilon) {
    const left = simplifyPath(points.slice(0, maxIdx + 1), epsilon);
    const right = simplifyPath(points.slice(maxIdx), epsilon);
    return left.slice(0, -1).concat(right);
  }

  return [start, end];
}

function pointToLineDist(point, lineStart, lineEnd) {
  const dx = lineEnd.x - lineStart.x;
  const dy = lineEnd.y - lineStart.y;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len === 0) return dist(point.x, point.y, lineStart.x, lineStart.y);
  const t = Math.max(0, Math.min(1,
    ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (len * len)));
  return dist(point.x, point.y,
    lineStart.x + t * dx, lineStart.y + t * dy);
}
```
