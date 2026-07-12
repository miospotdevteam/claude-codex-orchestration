# GSAP Core Patterns

Essential patterns for every GSAP project: cleanup, responsive animations,
high-performance updates, reusable effects, and utility functions.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## 1. gsap.context() — Scoped Cleanup

Create a context to automatically track and revert all GSAP animations
within a scope. Essential for React/Next.js components.

```javascript
import gsap from 'gsap';

// Create context scoped to a DOM element
const ctx = gsap.context((self) => {
  // All GSAP calls inside here are tracked
  gsap.to('.box', { x: 200 });
  gsap.from('.title', { opacity: 0 });

  // self.add() lets you add animations later
  self.add('animate', () => {
    gsap.to('.box', { rotation: 360 });
  });
}, containerRef); // scope selector queries to this element

// Later: revert ALL animations in context
ctx.revert(); // kills tweens, restores original values
```

### React Integration with useGSAP

```javascript
import { useGSAP } from '@gsap/react';
import gsap from 'gsap';

function MyComponent() {
  const containerRef = useRef(null);

  useGSAP((self) => {
    // Selectors scoped to containerRef
    gsap.to('.box', { x: 200 });
    gsap.from('.title', { opacity: 0, y: 50 });

    // ScrollTrigger instances are also tracked
    gsap.to('.parallax', {
      y: -100,
      scrollTrigger: { trigger: '.section', scrub: 1 },
    });
  }, { scope: containerRef }); // auto-cleanup on unmount

  return <div ref={containerRef}>...</div>;
}
```

### Adding to Context Later

```javascript
const ctx = gsap.context(() => {}, container);

// Add named functions
ctx.add('hover', () => {
  gsap.to('.card', { scale: 1.05, duration: 0.3 });
});

// Call them
ctx.hover();

// Or add anonymous (just tracked for cleanup)
ctx.add(() => {
  gsap.from('.new-element', { opacity: 0 });
});
```

**When to use:** Every React/Next.js component with GSAP animations.
Always. No exceptions. Without context, animations leak on unmount.

---

## 2. gsap.matchMedia() — Responsive Animations

Create responsive animations that automatically set up and tear down
based on media queries.

```javascript
import gsap from 'gsap';

const mm = gsap.matchMedia();

mm.add({
  // Named conditions
  isDesktop: '(min-width: 1024px)',
  isTablet: '(min-width: 768px) and (max-width: 1023px)',
  isMobile: '(max-width: 767px)',
  reduceMotion: '(prefers-reduced-motion: reduce)',
}, (context) => {
  const { isDesktop, isTablet, isMobile, reduceMotion } = context.conditions;

  if (reduceMotion) {
    // Show content without animation
    gsap.set('.hero-text', { autoAlpha: 1 });
    return; // skip all motion
  }

  if (isDesktop) {
    gsap.from('.hero-text', {
      x: -200, opacity: 0, duration: 1.5,
      scrollTrigger: { trigger: '.hero', scrub: 1.5 },
    });
  }

  if (isMobile) {
    gsap.from('.hero-text', {
      y: 50, opacity: 0, duration: 0.8,
      scrollTrigger: { trigger: '.hero', start: 'top 80%' },
    });
  }

  // Cleanup is automatic when conditions change
});

// Cleanup all
mm.revert();
```

### Single Condition (simpler syntax)

```javascript
mm.add('(min-width: 768px)', () => {
  // Only runs on tablet+
  gsap.to('.sidebar', { x: 0, scrollTrigger: { ... } });
  // Auto-reverts when viewport shrinks below 768px
});
```

### Reduced Motion Guard

```javascript
mm.add('(prefers-reduced-motion: no-preference)', () => {
  // ALL motion code goes here
  initLenis();
  initScrollTriggers();
  startRenderLoop();
});

// Outside matchMedia: static content is always visible
gsap.set('.content', { autoAlpha: 1 });
```

**When to use:** Responsive animations, prefers-reduced-motion handling,
any animation that should differ by viewport size.

---

## 3. gsap.quickTo() / gsap.quickSetter() — High-Performance Updates

### quickTo — Optimized Repeated Animations

Creates a reusable function that efficiently animates to new values.
Much faster than calling `gsap.to()` repeatedly (e.g., on mousemove).

```javascript
// Create quickTo functions (once)
const xTo = gsap.quickTo('.cursor', 'x', { duration: 0.6, ease: 'power3.out' });
const yTo = gsap.quickTo('.cursor', 'y', { duration: 0.6, ease: 'power3.out' });

// Call on every mousemove (fast!)
document.addEventListener('mousemove', (e) => {
  xTo(e.clientX);
  yTo(e.clientY);
});
```

### Magnetic Cursor Effect

```javascript
const buttons = gsap.utils.toArray('.magnetic-btn');

buttons.forEach(btn => {
  const xTo = gsap.quickTo(btn, 'x', { duration: 0.4, ease: 'power3.out' });
  const yTo = gsap.quickTo(btn, 'y', { duration: 0.4, ease: 'power3.out' });

  btn.addEventListener('mousemove', (e) => {
    const { left, top, width, height } = btn.getBoundingClientRect();
    const x = (e.clientX - left - width / 2) * 0.3;
    const y = (e.clientY - top - height / 2) * 0.3;
    xTo(x);
    yTo(y);
  });

  btn.addEventListener('mouseleave', () => {
    xTo(0);
    yTo(0);
  });
});
```

### quickSetter — Zero-Duration Batch Updates

For render loops where you need maximum performance (no tweening, just
raw property setting).

```javascript
// Create setter (once)
const setX = gsap.quickSetter('.particle', 'x', 'px');
const setY = gsap.quickSetter('.particle', 'y', 'px');
const setRotation = gsap.quickSetter('.particle', 'rotation', 'deg');

// Use in render loop (fastest possible)
gsap.ticker.add(() => {
  setX(Math.sin(Date.now() * 0.001) * 100);
  setY(Math.cos(Date.now() * 0.001) * 100);
  setRotation(Date.now() * 0.1);
});
```

### Updating Three.js Uniforms via quickSetter

```javascript
// For batch uniform updates in the GSAP ticker
const setProgress = gsap.quickSetter(material.uniforms.uScrollProgress, 'value');
const setVelocity = gsap.quickSetter(material.uniforms.uScrollVelocity, 'value');

gsap.ticker.add(() => {
  setProgress(lenis.progress);
  setVelocity(lenis.velocity);
});
```

**When to use:** quickTo for mouse followers, magnetic effects, any
frequently-updated animation target. quickSetter for render loops where
you need raw speed with no interpolation.

---

## 4. gsap.registerEffect() — Reusable Animation Effects

Define named, configurable animation effects that can be applied to any
element.

```javascript
// Register effects (once, at app init)
gsap.registerEffect({
  name: 'fadeUp',
  effect: (targets, config) => {
    return gsap.from(targets, {
      y: config.y,
      opacity: 0,
      duration: config.duration,
      ease: config.ease,
      stagger: config.stagger,
    });
  },
  defaults: { y: 60, duration: 0.8, ease: 'power3.out', stagger: 0.1 },
  extendTimeline: true, // allows tl.fadeUp('.el')
});

gsap.registerEffect({
  name: 'slideIn',
  effect: (targets, config) => {
    return gsap.from(targets, {
      x: config.direction === 'left' ? -200 : 200,
      opacity: 0,
      duration: config.duration,
      ease: config.ease,
    });
  },
  defaults: { direction: 'left', duration: 1, ease: 'power2.out' },
  extendTimeline: true,
});

gsap.registerEffect({
  name: 'staggerReveal',
  effect: (targets, config) => {
    return gsap.from(targets, {
      y: 40, opacity: 0, scale: 0.95,
      duration: config.duration,
      ease: config.ease,
      stagger: { each: config.stagger, from: config.from },
    });
  },
  defaults: { duration: 0.6, ease: 'power3.out', stagger: 0.08, from: 'start' },
  extendTimeline: true,
});
```

### Using Effects

```javascript
// Standalone
gsap.effects.fadeUp('.hero-title');
gsap.effects.fadeUp('.cards', { y: 80, stagger: 0.2 });
gsap.effects.slideIn('.sidebar', { direction: 'right' });

// In timelines (with extendTimeline: true)
const tl = gsap.timeline();
tl.fadeUp('.hero-title')
  .slideIn('.hero-image', { direction: 'right' }, '-=0.5')
  .staggerReveal('.feature-card', { from: 'center' }, '-=0.3');
```

**When to use:** Consistent animation language across a site. Define once,
use everywhere. Prevents drift where each component invents its own enter
animation.

---

## 5. gsap.utils — Utility Belt

### Value Transformation

```javascript
// clamp — restrict value to range
const clamped = gsap.utils.clamp(0, 100, value); // 0-100

// mapRange — map from one range to another
const mapped = gsap.utils.mapRange(0, 1, -200, 200, scrollProgress);
// scrollProgress 0.5 → 0

// normalize — convert value to 0-1 range
const normalized = gsap.utils.normalize(100, 500, 300); // 0.5

// interpolate — blend between values
gsap.utils.interpolate(0, 100, 0.5);           // 50
gsap.utils.interpolate('#ff0000', '#0000ff', 0.5); // purple
gsap.utils.interpolate('20px', '100px', 0.5);   // '60px'
// Also works with objects:
gsap.utils.interpolate(
  { x: 0, y: 0 },
  { x: 100, y: 200 },
  0.5
); // { x: 50, y: 100 }
```

### Wrapping & Snapping

```javascript
// wrap — cycle through values
const colors = ['#ff0000', '#00ff00', '#0000ff'];
gsap.utils.wrap(colors, 0);  // '#ff0000'
gsap.utils.wrap(colors, 3);  // '#ff0000' (wraps)
gsap.utils.wrap(colors, 5);  // '#0000ff'

// wrap with range
gsap.utils.wrap(0, 360, 400); // 40 (wraps around)

// snap — snap to nearest value
gsap.utils.snap(10, 23);      // 20 (nearest multiple of 10)
gsap.utils.snap([0, 25, 50, 75, 100], 32); // 25 (nearest in array)

// snap with radius (only snap if within radius)
gsap.utils.snap({ values: [0, 50, 100], radius: 15 }, 42); // 50
gsap.utils.snap({ values: [0, 50, 100], radius: 15 }, 30); // 30 (not close enough)
```

### Distribution & Random

```javascript
// distribute — create evenly distributed values (great for staggers)
const positions = gsap.utils.distribute({
  base: 0,
  amount: 500,
  from: 'center',
  ease: 'power2',
});
// Returns a function: positions(index, target, targets)

// random — generate random values
gsap.utils.random(0, 100);           // random float 0-100
gsap.utils.random(0, 100, 5);        // random, snapped to nearest 5
gsap.utils.random([1, 5, 10, 20]);   // random from array

// random as reusable function
const randomX = gsap.utils.random(-200, 200, 1, true); // returns function
randomX(); // new random int each call
```

### Array & Selector

```javascript
// toArray — convert anything to array (NodeList, selector, single el)
const boxes = gsap.utils.toArray('.box');         // NodeList → Array
const items = gsap.utils.toArray(['.a', '.b']);    // multiple selectors
const els = gsap.utils.toArray(nodeList);          // NodeList → Array

// selector — scoped selector function
const q = gsap.utils.selector(containerRef.current);
gsap.to(q('.box'), { x: 100 });  // only .box inside container

// splitColor — parse any color format
gsap.utils.splitColor('#ff5500');        // [255, 85, 0]
gsap.utils.splitColor('rgb(255,85,0)');  // [255, 85, 0]
gsap.utils.splitColor('hsl(20,100%,50%)', true); // [20, 100, 50] (HSL)

// getUnit — extract CSS unit from string
gsap.utils.getUnit('200px');  // 'px'
gsap.utils.getUnit('50%');    // '%'
gsap.utils.getUnit('10rem');  // 'rem'
```

### pipe — Compose Utility Functions

```javascript
// Chain utilities together
const transform = gsap.utils.pipe(
  gsap.utils.clamp(0, 1),           // 1. Clamp to 0-1
  gsap.utils.mapRange(0, 1, -100, 100), // 2. Map to -100..100
  gsap.utils.snap(10),              // 3. Snap to nearest 10
);

transform(0.73); // 50 (clamped → mapped to 46 → snapped to 50)

// Great for scroll-driven values
const scrollToRotation = gsap.utils.pipe(
  gsap.utils.normalize(0, document.body.scrollHeight),
  gsap.utils.mapRange(0, 1, 0, 360),
);
```

### unitize — Add Units to Functions

```javascript
// Wrap a function to append a CSS unit
const clampPx = gsap.utils.unitize(gsap.utils.clamp(0, 500), 'px');
clampPx(300); // '300px'
clampPx(600); // '500px'
```

---

## 6. CSS Variable Animation (GSAP 3.13+)

Animate CSS custom properties directly — works with design tokens,
theme switching, and CSS-driven layouts.

```javascript
// Animate any CSS variable
gsap.to('.progress-bar', {
  '--progress': 1,
  duration: 1.5,
  ease: 'power2.out',
});
// CSS: .progress-bar { width: calc(var(--progress) * 100%); }

// Theme transition
gsap.to(':root', {
  '--primary-hue': 200,
  '--bg-lightness': '15%',
  duration: 0.8,
  ease: 'power2.inOut',
});

// Color variables
gsap.to('.card', {
  '--accent-color': '#ff6600',
  '--shadow-opacity': 0.3,
  duration: 0.5,
});
```

**When to use:** Design token animations, theme transitions, any case
where CSS variables drive visual properties (gradients, shadows, layout
calculations via `calc()`).

---

## 7. gsap.delayedCall() and gsap.exportRoot()

### delayedCall — GSAP-Aware setTimeout

Unlike `setTimeout`, respects `globalTimeline.timeScale()` and pause.

```javascript
// Simple delayed callback
gsap.delayedCall(2, () => showNotification('Ready!'));

// With params
gsap.delayedCall(1, (msg) => console.log(msg), ['Hello']);

// Cancel
const delayed = gsap.delayedCall(5, cleanup);
delayed.kill(); // cancel before it fires
```

### exportRoot — Global Animation Control

Wraps all currently active animations into a new Timeline. New animations
created after `exportRoot()` are NOT captured — useful for game pause.

```javascript
// Pause all current animations (e.g., game pause)
const snapshot = gsap.exportRoot();
snapshot.pause();

// User presses resume
snapshot.resume();

// Animations created after exportRoot are independent
gsap.to('.ui-element', { opacity: 1 }); // this still plays during pause
```

---

## Quick Reference

| Utility | Use Case |
|---------|----------|
| `gsap.context()` | Framework cleanup, scoped animations |
| `gsap.matchMedia()` | Responsive + reduced motion |
| `gsap.quickTo()` | Smooth mouse followers |
| `gsap.quickSetter()` | Raw speed in render loops |
| `gsap.registerEffect()` | Reusable named animations |
| `gsap.utils.clamp()` | Restrict to range |
| `gsap.utils.mapRange()` | Convert between ranges |
| `gsap.utils.interpolate()` | Blend values (numbers, colors, objects) |
| `gsap.utils.wrap()` | Cycle through values |
| `gsap.utils.snap()` | Snap to grid/values |
| `gsap.utils.distribute()` | Stagger distribution |
| `gsap.utils.random()` | Random values |
| `gsap.utils.toArray()` | Selector → array |
| `gsap.utils.selector()` | Scoped queries |
| `gsap.utils.pipe()` | Compose functions |
| `gsap.utils.normalize()` | Value → 0-1 |
| `gsap.utils.splitColor()` | Parse colors |
| `gsap.utils.getUnit()` | Extract CSS units |
| `gsap.utils.unitize()` | Append units to functions |
| CSS `--variable` animation | Design token / theme transitions |
| `gsap.delayedCall()` | GSAP-aware setTimeout |
| `gsap.exportRoot()` | Snapshot all animations for global pause |
