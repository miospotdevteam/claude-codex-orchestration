# GSAP + Scroll Patterns

Complete patterns for GSAP animations, ScrollTrigger, Lenis smooth scroll,
SplitText, timelines, and the critical integration with Three.js.

---

## 1. GSAP Core

### Basic Tweens

```javascript
import gsap from 'gsap';

// Animate TO target values
gsap.to('.box', { x: 200, rotation: 360, scale: 1.5, opacity: 0.5, duration: 1, ease: 'power2.out' });

// Animate FROM values to current state
gsap.from('.hero-title', { y: 80, opacity: 0, duration: 1.2, ease: 'power3.out' });

// Define both start and end
gsap.fromTo('.el', { opacity: 0, y: 50 }, { opacity: 1, y: 0, duration: 1, ease: 'power2.out' });

// Instant set (zero duration)
gsap.set('.hidden', { autoAlpha: 0, y: 30 });
// autoAlpha = opacity + visibility (sets visibility:hidden at 0)
```

### Easing Quick Reference

```javascript
ease: 'power2.out'     // Moderate deceleration (most common for entrances)
ease: 'power3.out'     // Strong deceleration
ease: 'power4.out'     // Very strong deceleration
ease: 'power2.inOut'   // Smooth both ends (transitions)
ease: 'back.out(1.7)'  // Slight overshoot
ease: 'elastic.out(1, 0.3)' // Springy bounce
ease: 'expo.out'       // Exponential deceleration
ease: 'none'           // Linear (constant speed — use for scroll-driven)
```

### Stagger

```javascript
gsap.from('.card', {
  y: 60, opacity: 0, duration: 0.8, ease: 'power3.out',
  stagger: 0.15, // Simple: 0.15s between each
});

// Advanced stagger
gsap.from('.grid-item', {
  scale: 0, opacity: 0, duration: 0.6, ease: 'back.out(1.7)',
  stagger: {
    each: 0.1,
    from: 'center', // 'start', 'end', 'center', 'edges', 'random'
    grid: [4, 8],
    axis: 'y',
  },
});
```

---

## 2. Timelines

```javascript
const tl = gsap.timeline({
  defaults: { duration: 0.8, ease: 'power3.out' }
});

tl.from('.hero-bg', { scale: 1.2, duration: 1.5, ease: 'power2.out' })
  .from('.hero-title', { y: 80, opacity: 0 }, '-=0.8')   // 0.8s before prev ends
  .from('.hero-subtitle', { y: 40, opacity: 0 }, '-=0.5')
  .from('.hero-cta', { y: 30, opacity: 0 }, '-=0.3');
```

### Position Parameter (critical for choreography)

```javascript
tl.to('.a', { x: 100 }, 0)       // absolute: starts at 0s
  .to('.b', { x: 100 }, '+=0.5') // 0.5s AFTER previous ends
  .to('.c', { x: 100 }, '-=0.3') // 0.3s BEFORE previous ends (overlap)
  .to('.d', { x: 100 }, '<')     // same time as previous START
  .to('.e', { x: 100 }, '<0.2'); // 0.2s after previous START
```

### Nested Timelines

```javascript
function heroAnim() {
  return gsap.timeline()
    .from('.hero-bg', { scale: 1.3, duration: 2 })
    .from('.hero-text', { y: 80, opacity: 0 }, '-=1.5');
}

function cardsAnim() {
  return gsap.timeline()
    .from('.card', { y: 60, opacity: 0, stagger: 0.15 });
}

const master = gsap.timeline();
master.add(heroAnim()).add(cardsAnim(), '-=0.5');
```

---

## 3. ScrollTrigger

```javascript
import { ScrollTrigger } from 'gsap/ScrollTrigger';
gsap.registerPlugin(ScrollTrigger);
```

### Basic Usage

```javascript
gsap.to('.parallax-image', {
  y: -200, ease: 'none',
  scrollTrigger: {
    trigger: '.parallax-section',
    start: 'top bottom',  // trigger's top hits viewport bottom
    end: 'bottom top',    // trigger's bottom hits viewport top
    scrub: true,          // link to scroll position
  },
});
```

### Start/End Syntax

```javascript
start: 'top center'      // trigger's top at viewport center
start: 'top 80%'         // trigger's top at 80% down viewport
start: 'top bottom'      // trigger's top at viewport bottom (enters view)
start: 'top top'         // trigger's top at viewport top (pinned)
start: 'top center+=100' // 100px below center
```

### Scrub (scroll-linked)

```javascript
scrub: true    // Instant follow (jerky)
scrub: 0.5     // 0.5s smooth lag (recommended minimum)
scrub: 1       // 1s smooth lag (polished feel)
scrub: 2       // 2s lag (cinematic, for camera paths)
```

### Pin

```javascript
gsap.to(sections, {
  xPercent: -100 * (sections.length - 1), ease: 'none',
  scrollTrigger: {
    trigger: '.horizontal-container',
    pin: true,
    scrub: 1,
    snap: 1 / (sections.length - 1),
    end: () => `+=${container.scrollWidth - window.innerWidth}`,
    invalidateOnRefresh: true,
  },
});
```

### toggleActions (play/reverse without scrub)

```javascript
gsap.from('.fade-section', {
  opacity: 0, y: 50, duration: 1,
  scrollTrigger: {
    trigger: '.fade-section',
    start: 'top 80%',
    toggleActions: 'play none none reverse',
    // Format: "onEnter onLeave onEnterBack onLeaveBack"
  },
});
```

### Batch (stagger elements as they enter viewport)

```javascript
ScrollTrigger.batch('.grid-item', {
  onEnter: (elements) => {
    gsap.from(elements, { opacity: 0, y: 60, stagger: 0.1, duration: 0.8 });
  },
  start: 'top 85%',
});
```

### Scroll-Driven Timeline

```javascript
const tl = gsap.timeline({
  scrollTrigger: {
    trigger: '.panels-container',
    pin: true,
    scrub: 1,
    snap: 1 / (sections.length - 1),
    start: 'top top',
    end: () => `+=${sections.length * 100}vh`,
  },
});

tl.from('.panel-1 .title', { opacity: 0, y: 50, duration: 0.3 })
  .from('.panel-1 .image', { scale: 0.8, opacity: 0 }, '<0.1')
  .to('.panel-1', { opacity: 0, duration: 0.2 }, '+=0.5')
  .from('.panel-2 .title', { opacity: 0, y: 50 });
```

### Responsive GSAP

Prefer `gsap.matchMedia()` for responsive animation branches and cleanup.

```javascript
const mm = gsap.matchMedia();

mm.add('(min-width: 768px)', () => {
  gsap.to('.hero', { x: 200, scrollTrigger: { ... } });
});

mm.add('(max-width: 767px)', () => {
  gsap.to('.hero', { y: 100, scrollTrigger: { ... } });
});
```

---

## 4. Lenis Smooth Scroll

### Setup

```javascript
import Lenis from 'lenis';
import 'lenis/dist/lenis.css';

const lenis = new Lenis({
  autoRaf: false,        // disable internal RAF when using GSAP ticker
  duration: 1.2,
  easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
  smoothWheel: true,
  syncTouch: false,
  touchMultiplier: 2,
});
```

### Lenis + GSAP Integration (THE critical pattern)

```javascript
lenis.on('scroll', ScrollTrigger.update);

gsap.ticker.add((time) => {
  lenis.raf(time * 1000);
});

gsap.ticker.lagSmoothing(0);
```

### Lenis CSS (required)

```css
html.lenis, html.lenis body { height: auto; }
.lenis.lenis-smooth { scroll-behavior: auto !important; }
.lenis.lenis-smooth [data-lenis-prevent] { overscroll-behavior: contain; }
.lenis.lenis-stopped { overflow: hidden; }
```

### Lenis API

```javascript
lenis.scrollTo('#section-3');
lenis.scrollTo(500);
lenis.scrollTo('#el', { offset: -100, duration: 2 });
lenis.stop();    // Pause (for modals)
lenis.start();   // Resume
lenis.destroy(); // Cleanup

lenis.scroll    // Current position (smoothed)
lenis.progress  // 0-1
lenis.velocity  // Current velocity
lenis.direction // 1 (down) or -1 (up)
```

---

## 5. SplitText (now free — included with `bun add gsap`)

> SplitText is now 100% free with GSAP. Use it instead of manual splitting —
> it handles emoji, ligatures, RTL, nested elements, and screen readers.
> For full API reference, see `gsap-text-plugins.md`.

### Character Cascade

```javascript
import { SplitText } from 'gsap/SplitText';
gsap.registerPlugin(SplitText);

const split = new SplitText('.hero-title', { type: 'chars,words' });

gsap.fromTo(split.chars, {
  y: 80, rotationX: -90, opacity: 0,
}, {
  y: 0, rotationX: 0, opacity: 1,
  duration: 0.8, ease: 'power3.out',
  stagger: { amount: 0.6, from: 'start' },
  scrollTrigger: { trigger: '.hero-title', start: 'top 80%', toggleActions: 'play none none reverse' }
});
```

### Line-by-Line Masked Reveal (using built-in mask)

```javascript
// NEW: mask property adds overflow:hidden wrappers automatically
const split = new SplitText('.paragraph', {
  type: 'lines',
  mask: 'lines',        // built-in masking — no manual wrappers needed
  autoSplit: true,       // auto re-split on resize
  onSplit: (self) => {   // fires on split and every re-split
    gsap.from(self.lines, {
      yPercent: 100, duration: 0.8, ease: 'power4.out', stagger: 0.12,
      scrollTrigger: { trigger: '.paragraph', start: 'top 85%' },
    });
  },
});
```

### Cleanup

```javascript
split.revert(); // Always revert before re-splitting (unless using autoSplit)
```

---

## 6. Infinite Marquee

```javascript
function createMarquee(selector, speed = 40) {
  const track = document.querySelector(`${selector} .marquee-track`);
  const items = Array.from(track.children);

  // Clone items for seamless loop
  items.forEach(item => {
    const clone = item.cloneNode(true);
    clone.setAttribute('aria-hidden', 'true');
    track.appendChild(clone);
  });

  const tween = gsap.to(track, {
    xPercent: -50,
    ease: 'none',
    duration: speed,
    repeat: -1,
  });

  // Pause on hover with smooth deceleration
  track.closest(selector).addEventListener('mouseenter', () => {
    gsap.to(tween, { timeScale: 0, duration: 0.5 });
  });
  track.closest(selector).addEventListener('mouseleave', () => {
    gsap.to(tween, { timeScale: 1, duration: 0.5 });
  });

  return tween;
}
```

CSS:
```css
.marquee { overflow: hidden; white-space: nowrap; }
.marquee-track { display: inline-flex; }
.marquee-item { flex-shrink: 0; padding: 0 2rem; }
```

### Scroll-Velocity-Reactive Marquee

```javascript
ScrollTrigger.create({
  trigger: '.marquee',
  start: 'top bottom',
  end: 'bottom top',
  onUpdate: (self) => {
    const velocity = Math.abs(self.getVelocity());
    gsap.to(tween, { timeScale: 1 + velocity / 1000, duration: 0.3, overwrite: true });
  },
});
```

---

## 7. Motion (`motion/react`)

### React Components

```jsx
import { motion, AnimatePresence } from 'motion/react';

<AnimatePresence>
  {isVisible && (
    <motion.div
      initial={{ opacity: 0, y: 50 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ type: 'spring', stiffness: 200, damping: 20 }}
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      layout
    >
      Content
    </motion.div>
  )}
</AnimatePresence>
```

### Vanilla JS

```javascript
import { animate, scroll, inView } from 'motion';

scroll(animate('.progress-bar', { scaleX: [0, 1] }));

inView('.section', (info) => {
  animate(info.target, { opacity: 1, y: 0 }, { duration: 0.8 });
  return () => animate(info.target, { opacity: 0, y: 50 });
}, { amount: 0.3 });
```

---

## 8. Lenis + GSAP + Three.js (Full Stack)

```javascript
import * as THREE from 'three';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

// 1. Lenis
const lenis = new Lenis({ autoRaf: false, duration: 1.2, smoothWheel: true });
lenis.on('scroll', ScrollTrigger.update);

// 2. Three.js scene
const { scene, camera, renderer, material } = createScene();

// 3. Single ticker drives everything
gsap.ticker.add((time) => {
  lenis.raf(time * 1000);
  material.uniforms.uTime.value = time;
  material.uniforms.uScrollProgress.value = lenis.progress;
  material.uniforms.uScrollVelocity.value = lenis.velocity;
  renderer.render(scene, camera);
});
gsap.ticker.lagSmoothing(0);

// 4. Scroll-driven 3D via GSAP
gsap.to(mesh.rotation, { y: Math.PI * 2, ease: 'none',
  scrollTrigger: { trigger: '.section-2', start: 'top bottom', end: 'bottom top', scrub: 1 }
});

// 5. Cleanup
function destroy() {
  lenis.destroy();
  ScrollTrigger.killAll();
  renderer.dispose();
  scene.traverse(child => {
    if (child.isMesh) { child.geometry.dispose(); child.material.dispose(); }
  });
}
```

---

## 9. Best Practices

1. **`scrub: 0.5` to `scrub: 1`** — raw `true` feels jerky
2. **`gsap.ticker.lagSmoothing(0)`** when using Lenis
3. **One GSAP ticker** drives Lenis, ScrollTrigger, AND Three.js
4. **`invalidateOnRefresh: true`** on ScrollTriggers with dynamic values
5. **`autoAlpha` over `opacity`** — sets `visibility:hidden` at 0
6. **`ScrollTrigger.batch()`** for grid reveals
7. **`gsap.context()`** in React for cleanup on unmount
8. **`split.revert()`** before re-splitting on resize
9. **Remove `markers: true`** before production
10. **`fastScrollEnd: true`** when multiple triggers compete
