# GSAP SVG Plugins

Shape morphing, stroke animation, and SVG transform handling.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## 1. MorphSVG — Shape Morphing

Morph any SVG `<path>` into another, with intelligent point mapping.

```javascript
import { MorphSVGPlugin } from 'gsap/MorphSVGPlugin';
gsap.registerPlugin(MorphSVGPlugin);
```

### Basic Morph

```javascript
// Morph one path to another
gsap.to('#circle-path', {
  morphSVG: '#star-path',
  duration: 1.5,
  ease: 'power2.inOut',
});

// Using path data string directly
gsap.to('#shape', {
  morphSVG: 'M10,10 C20,20 40,20 50,10...',
  duration: 1,
});
```

### convertToPath() — Any Shape to Path

Convert non-path SVG elements so they can be morphed:

```javascript
// Convert individual elements
MorphSVGPlugin.convertToPath('circle');    // all <circle> elements
MorphSVGPlugin.convertToPath('#my-rect'); // specific element

// Supports: circle, rect, ellipse, polygon, polyline, line
// Does NOT convert: text, image, use

// Convert everything in an SVG
MorphSVGPlugin.convertToPath('circle, rect, ellipse, polygon, polyline, line');
```

### shapeIndex — Control Point Mapping

Controls which point on the start shape maps to which point on the end
shape. Affects how the morph looks mid-transition.

```javascript
gsap.to('#shape', {
  morphSVG: {
    shape: '#target',
    shapeIndex: 2,     // integer: rotates point mapping
    // shapeIndex: 'auto' // default: GSAP picks best match
  },
  duration: 1,
});
```

### findShapeIndex() — Visual Debugger

Opens a visual tool to find the best shapeIndex:

```javascript
// Opens interactive UI in the page
MorphSVGPlugin.findShapeIndex('#start', '#end');
// Try different values, see the result, pick the best one
```

### Morph Type

```javascript
gsap.to('#shape', {
  morphSVG: {
    shape: '#target',
    type: 'rotational', // default — smooth rotation-based morphing
    // type: 'linear',  // straight-line point interpolation
  },
});
```

### smooth — Extra Anchor Points (GSAP 3.14+)

Adds extra anchor points for smoother morph transitions, reducing mid-morph
kinks and sharp angles:

```javascript
gsap.to('#shape', {
  morphSVG: {
    shape: '#target',
    smooth: 80,        // number of extra points (higher = smoother)
    // smooth: 'auto', // let GSAP decide based on path complexity
  },
  duration: 1.5,
});
```

### curveMode — Prevent Mid-Animation Kinks (GSAP 3.14+)

Prevents angular artifacts during the morph transition:

```javascript
gsap.to('#shape', {
  morphSVG: {
    shape: '#target',
    curveMode: true,   // smoother interpolation, prevents kinks
  },
  duration: 1.5,
});
```

### RawPath Utilities (Canvas Rendering)

For rendering morphed paths to `<canvas>` instead of SVG:

```javascript
const { rawPathToString, stringToRawPath } = MorphSVGPlugin;

// Convert path data to RawPath array
const rawPath = stringToRawPath('M0,0 C10,20 30,20 40,0');

// Modify points programmatically
rawPath[0][0] += 10; // shift first x

// Convert back to string
const pathString = rawPathToString(rawPath);
```

### Examples

**Icon Morph (hamburger → X):**
```javascript
const tl = gsap.timeline({ paused: true });

tl.to('#top-line', { morphSVG: '#x-line-1', duration: 0.4 })
  .to('#middle-line', { opacity: 0, duration: 0.2 }, '<')
  .to('#bottom-line', { morphSVG: '#x-line-2', duration: 0.4 }, '<');

// Toggle on click
menuBtn.addEventListener('click', () => {
  tl.reversed() ? tl.play() : tl.reverse();
});
```

**Organic Blob Loop:**
```javascript
const shapes = ['#blob1', '#blob2', '#blob3', '#blob4'];
const tl = gsap.timeline({ repeat: -1 });

shapes.forEach((shape, i) => {
  const next = shapes[(i + 1) % shapes.length];
  tl.to('#blob', {
    morphSVG: next,
    duration: 2,
    ease: 'power1.inOut',
  });
});
```

**Scroll-Driven Shape Transform:**
```javascript
gsap.to('#shape', {
  morphSVG: '#target-shape',
  ease: 'none',
  scrollTrigger: {
    trigger: '.morph-section',
    start: 'top center',
    end: 'bottom center',
    scrub: 1,
  },
});
```

---

## 2. DrawSVG — Stroke Animation

Animate the `stroke-dashoffset` and `stroke-dasharray` of SVG strokes
to create drawing/erasing effects.

```javascript
import { DrawSVGPlugin } from 'gsap/DrawSVGPlugin';
gsap.registerPlugin(DrawSVGPlugin);
```

### Value Syntax

```javascript
drawSVG: '0%'          // fully hidden (stroke length 0)
drawSVG: '100%'        // fully drawn
drawSVG: '0% 100%'     // fully drawn (start to end)
drawSVG: '50% 50%'     // collapsed to midpoint (invisible)
drawSVG: '0% 30%'      // first 30% visible
drawSVG: '20% 80%'     // middle 60% visible
drawSVG: true           // alias for '0% 100%'
drawSVG: '200'          // first 200px visible (absolute length)
```

### Progressive Reveal (Line Drawing)

```javascript
// Draw from nothing to full stroke
gsap.fromTo('.line-art path', {
  drawSVG: '0%',
}, {
  drawSVG: '100%',
  duration: 2,
  ease: 'power2.inOut',
  stagger: 0.3,
});
```

### Center-Outward

```javascript
// Grow from center point outward
gsap.from('.path', {
  drawSVG: '50% 50%', // starts collapsed at center
  duration: 1.5,
  ease: 'power3.out',
});
```

### Sliding Dash

```javascript
// A dash that travels along the path
gsap.fromTo('.path', {
  drawSVG: '0% 10%',  // 10% segment at start
}, {
  drawSVG: '90% 100%', // 10% segment at end
  duration: 1.5,
  ease: 'none',
  repeat: -1,
});
```

### Scroll-Driven Line Drawing

```javascript
gsap.utils.toArray('.draw-path').forEach(path => {
  gsap.fromTo(path, {
    drawSVG: '0%',
  }, {
    drawSVG: '100%',
    ease: 'none',
    scrollTrigger: {
      trigger: path.closest('svg'),
      start: 'top 70%',
      end: 'bottom 30%',
      scrub: 1,
    },
  });
});
```

### SVG Signature Animation

```javascript
const paths = gsap.utils.toArray('#signature path');
const tl = gsap.timeline();

paths.forEach(path => {
  const length = path.getTotalLength();
  tl.fromTo(path, {
    drawSVG: '0%',
  }, {
    drawSVG: '100%',
    duration: length / 200, // proportional to path length
    ease: 'power1.inOut',
  });
});
```

### Important: SVG Requirements

```html
<!-- Strokes must be visible for DrawSVG to work -->
<path
  d="M10,10 L90,90"
  stroke="#00e5ff"
  stroke-width="2"
  fill="none"        <!-- usually no fill for line drawing -->
/>
```

---

## 3. SVG Transform Handling

GSAP normalizes SVG transforms across browsers, fixing common gotchas.

### transformOrigin

```javascript
// HTML elements: transformOrigin works as expected
gsap.to('.div', { rotation: 45, transformOrigin: '50% 50%' });

// SVG elements: percentage-based transformOrigin is normalized by GSAP
gsap.to('#svg-rect', {
  rotation: 45,
  transformOrigin: '50% 50%', // center of the element's bounding box
});
```

### svgOrigin — Transform Relative to SVG ViewBox

```javascript
// Origin relative to the SVG's coordinate system, not the element
gsap.to('#svg-element', {
  rotation: 360,
  svgOrigin: '200 150', // x y in SVG viewBox coordinates
  duration: 2,
  repeat: -1,
  ease: 'none',
});
```

Use `svgOrigin` when you need elements to orbit around a specific point
in the SVG canvas (e.g., planets around a sun, hands on a clock).

### smoothOrigin

```javascript
// Prevents the "jump" when changing transformOrigin mid-animation
gsap.set('#element', { smoothOrigin: true }); // enabled by default
```

### Animating SVG Attributes

```javascript
// Use attr:{} for SVG attributes (not CSS properties)
gsap.to('#circle', {
  attr: {
    cx: 200,
    cy: 150,
    r: 50,
  },
  duration: 1,
});

gsap.to('#rect', {
  attr: {
    width: 200,
    height: 100,
    rx: 20, // border radius
  },
  duration: 0.5,
});

// Animate path data
gsap.to('#path', {
  attr: { d: 'M10,80 Q95,10 180,80' },
  duration: 1,
});
```

---

## 4. Browser Gotchas

### SVG viewBox and Coordinates

```html
<!-- viewBox defines the coordinate system -->
<svg viewBox="0 0 400 300" width="100%" height="auto">
  <!-- Everything inside uses 0-400 x, 0-300 y -->
</svg>
```

- `svgOrigin` values are in viewBox coordinates
- `transformOrigin` percentages are relative to element bounding box
- GSAP handles the math — you just pick the right property

### Transform Quirks

```javascript
// GSAP normalizes these, but be aware:
// - SVG transforms are NOT CSS transforms (different spec)
// - Some browsers handle transform-origin differently on SVG
// - GSAP.to() handles all of this — don't use CSS transforms on SVG

// DO: Let GSAP handle all SVG transforms
gsap.to('#svg-el', { x: 100, y: 50, rotation: 45, scale: 1.5 });

// DON'T: Mix CSS transforms with GSAP on SVG
// element.style.transform = '...' // will conflict
```

### Stroke Animation Requirements

```javascript
// DrawSVG needs:
// 1. A visible stroke (stroke color + stroke-width set)
// 2. fill: none (usually — unless you want fill + stroke)
// 3. The path to have actual length (not zero-length paths)

// Check path length programmatically:
const length = path.getTotalLength();
console.log(`Path length: ${length}px`);
```

### Performance with Many SVG Elements

```javascript
// Batch SVG animations for performance
ScrollTrigger.batch('svg path', {
  onEnter: (paths) => {
    gsap.fromTo(paths, { drawSVG: '0%' }, {
      drawSVG: '100%',
      stagger: 0.05,
      duration: 1,
    });
  },
  start: 'top 85%',
});
```

---

## Quick Reference

| Plugin | Use Case |
|--------|----------|
| **MorphSVG** | Shape-to-shape morphing, icon transitions, organic blobs |
| **DrawSVG** | Line drawing, stroke animation, signature reveals |
| **attr:{}** | Animate any SVG attribute (cx, cy, r, width, d, etc.) |
| **svgOrigin** | Transform from a point in SVG coordinate space |
| **transformOrigin** | Transform from element's own center/corner |
