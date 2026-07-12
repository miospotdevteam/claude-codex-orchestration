# GSAP Common Mistakes

Pitfalls, gotchas, and debugging patterns for GSAP and ScrollTrigger.
Read this when debugging, reviewing code, or starting a new project.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## ScrollTrigger Mistakes

### 1. Creating ScrollTriggers Before DOM is Ready

**Problem:** Elements don't exist yet, ScrollTrigger measures zero-height
elements, animations fire immediately or not at all.

```javascript
// WRONG — runs before DOM is painted
gsap.from('.hero', {
  opacity: 0,
  scrollTrigger: { trigger: '.hero', start: 'top 80%' },
});
```

**Fix:**
```javascript
// Vanilla JS — wait for DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => { ... });

// React — use useGSAP hook (or useLayoutEffect)
import { useGSAP } from '@gsap/react';
useGSAP(() => {
  gsap.from('.hero', {
    opacity: 0,
    scrollTrigger: { trigger: '.hero', start: 'top 80%' },
  });
}, { scope: containerRef });

// Next.js — useGSAP with dependency array
useGSAP(() => { ... }, { scope: ref, dependencies: [data] });
```

### 2. Not Calling ScrollTrigger.refresh() After Layout Changes

**Problem:** Start/end positions are cached. Dynamic content, lazy-loaded
images, or font loading changes element heights but ScrollTrigger doesn't
know.

**Fix:**
```javascript
// After images load
window.addEventListener('load', () => ScrollTrigger.refresh());

// After dynamic content
async function loadContent() {
  await fetchData();
  renderContent();
  ScrollTrigger.refresh(); // recalculate all trigger positions
}

// After fonts load
document.fonts.ready.then(() => ScrollTrigger.refresh());
```

### 3. Conflicting ScrollTriggers on Same Element

**Problem:** Multiple tweens with ScrollTrigger targeting the same
property fight for control — flicker, jumps, unpredictable behavior.

```javascript
// WRONG — two triggers control opacity
gsap.to('.box', { opacity: 0.5, scrollTrigger: { trigger: '.a', scrub: 1 } });
gsap.to('.box', { opacity: 1, scrollTrigger: { trigger: '.b', scrub: 1 } });
```

**Fix:**
```javascript
// Use a single timeline with one ScrollTrigger
const tl = gsap.timeline({
  scrollTrigger: { trigger: '.container', scrub: 1 },
});
tl.to('.box', { opacity: 0.5 })
  .to('.box', { opacity: 1 });

// Or use preventOverlaps / fastScrollEnd
gsap.to('.box', {
  opacity: 0.5,
  scrollTrigger: {
    trigger: '.a',
    preventOverlaps: 'group1',
    fastScrollEnd: true,
  },
});
```

### 4. Pin Spacing Issues

**Problem:** Pinned elements add padding to push content below. Sometimes
you handle spacing manually and the extra padding doubles the gap.

```javascript
// WRONG — double spacing if you already account for it
gsap.to('.panel', { scrollTrigger: { pin: true } });
```

**Fix:**
```javascript
// Disable auto-added spacing when you handle it yourself
gsap.to('.panel', {
  scrollTrigger: {
    pin: true,
    pinSpacing: false, // disable automatic spacing
  },
});
```

### 5. Resize/Orientation Doesn't Update

**Problem:** Positions calculated at load time become wrong after resize.

**Fix:**
```javascript
// Add invalidateOnRefresh for dynamic values
gsap.to('.box', {
  x: () => window.innerWidth * 0.5, // function-based value
  scrollTrigger: {
    trigger: '.section',
    scrub: 1,
    invalidateOnRefresh: true, // re-evaluates function values on resize
  },
});

// Manual resize handling
window.addEventListener('resize', () => {
  ScrollTrigger.refresh();
});
```

### 6. FOUC (Flash of Unstyled Content)

**Problem:** Elements are visible at their final position, then jump to
the `from` values when GSAP initializes.

```css
/* Fix: set initial state in CSS */
.animate-in {
  visibility: hidden;
}
```

```javascript
// GSAP's autoAlpha manages visibility automatically
gsap.from('.animate-in', {
  autoAlpha: 0, // sets visibility:visible when animation starts
  y: 50,
  scrollTrigger: { trigger: '.animate-in', start: 'top 85%' },
});
```

### 7. Scroll Position Jumps After SPA Navigation

**Problem:** Browser restores scroll position on navigation, causing
ScrollTrigger positions to be wrong.

**Fix:**
```javascript
// Disable browser scroll restoration
if ('scrollRestoration' in history) {
  history.scrollRestoration = 'manual';
}

// Scroll to top on route change (Next.js)
// In app/layout.tsx or a navigation hook
window.scrollTo(0, 0);
ScrollTrigger.refresh();
```

### 8. Markers Don't Match Actual Trigger Points

**Problem:** Markers show wrong positions due to smooth scroll offset or
dynamic content loaded after markers were placed.

**Fix:**
```javascript
// Initialize smooth scroll BEFORE creating ScrollTriggers
const lenis = new Lenis({ ... });
lenis.on('scroll', ScrollTrigger.update);
// THEN create your animations with markers
gsap.from('.el', {
  scrollTrigger: { trigger: '.el', markers: true },
});

// For dynamic content: refresh after content loads
ScrollTrigger.refresh();
```

---

## GSAP Core Mistakes

### 1. Not Registering Plugins

**Problem:** Plugin silently fails — no error, animation just doesn't work.

```javascript
// WRONG — forgot to register
import { ScrollTrigger } from 'gsap/ScrollTrigger';
gsap.to('.box', { scrollTrigger: { ... } }); // doesn't work
```

**Fix:**
```javascript
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
gsap.registerPlugin(ScrollTrigger); // MUST register before use
```

### 2. Animating Layout Properties

**Problem:** Animating `width`, `height`, `top`, `left`, `padding`,
`margin` triggers layout reflow every frame — kills performance.

```javascript
// WRONG — triggers layout reflow
gsap.to('.box', { width: 200, left: 100, top: 50 });
```

**Fix:**
```javascript
// Use transform properties (GPU-composited)
gsap.to('.box', { scaleX: 2, x: 100, y: 50 });
// And opacity (also GPU-composited)
gsap.to('.box', { autoAlpha: 0.5 });
```

### 3. Not Cleaning Up in React/SPA

**Problem:** Animations continue after component unmounts — memory leaks,
errors accessing removed DOM elements.

```javascript
// WRONG — no cleanup
useEffect(() => {
  gsap.to('.box', { x: 200 });
  ScrollTrigger.create({ ... });
}, []);
```

**Fix:**
```javascript
import { useGSAP } from '@gsap/react';

// useGSAP handles cleanup automatically
useGSAP(() => {
  gsap.to('.box', { x: 200 });
  ScrollTrigger.create({ ... });
}, { scope: containerRef });

// Or manual context
useEffect(() => {
  const ctx = gsap.context(() => {
    gsap.to('.box', { x: 200 });
  }, containerRef.current);

  return () => ctx.revert(); // cleanup everything
}, []);
```

### 4. Overwriting Active Animations

**Problem:** Creating a new tween on a property that's already being
animated causes flickering.

```javascript
// WRONG — rapid hover creates conflicting tweens
el.addEventListener('mouseenter', () => gsap.to(el, { scale: 1.2 }));
el.addEventListener('mouseleave', () => gsap.to(el, { scale: 1 }));
// If mouse enters/leaves quickly, tweens stack up
```

**Fix:**
```javascript
// Option 1: overwrite (recommended)
el.addEventListener('mouseenter', () => {
  gsap.to(el, { scale: 1.2, overwrite: true });
});
el.addEventListener('mouseleave', () => {
  gsap.to(el, { scale: 1, overwrite: true });
});

// Option 2: quickTo (most performant)
const scaleTo = gsap.quickTo(el, 'scale', { duration: 0.3 });
el.addEventListener('mouseenter', () => scaleTo(1.2));
el.addEventListener('mouseleave', () => scaleTo(1));
```

### 5. CSS Transitions Conflicting with GSAP

**Problem:** CSS `transition` property fights with GSAP for control of
the same properties. Causes sluggish, doubled animations.

```css
/* WRONG — CSS transition competes with GSAP */
.box {
  transition: transform 0.3s ease;
}
```

**Fix:**
```css
/* Remove CSS transitions on GSAP-animated elements */
.box {
  /* no transition property */
}
```

```javascript
// Or clear it programmatically
gsap.set('.box', { clearProps: 'transition' });
```

### 6. immediateRender on .from() with ScrollTrigger

**Problem:** `.from()` renders the "from" values immediately by default.
With ScrollTrigger, this means the element starts in the "from" state even
before scrolling to it — then jumps back on scroll back.

```javascript
// WRONG — element starts invisible even before scroll reaches it
gsap.from('.box', {
  opacity: 0, y: 50,
  scrollTrigger: { trigger: '.box', start: 'top 80%' },
});
```

**Fix:**
```javascript
// Disable immediate render
gsap.from('.box', {
  opacity: 0, y: 50,
  immediateRender: false,
  scrollTrigger: { trigger: '.box', start: 'top 80%' },
});

// Or use fromTo (more predictable)
gsap.fromTo('.box', {
  opacity: 0, y: 50,
}, {
  opacity: 1, y: 0,
  scrollTrigger: { trigger: '.box', start: 'top 80%' },
});
```

### 7. Stacking .from() Animations

**Problem:** Multiple `.from()` tweens on the same element all try to set
initial values — unpredictable results.

**Fix:** Use `.fromTo()` for explicit start and end states, or use a
timeline to sequence them properly.

### 8. Will-Change Overuse

**Problem:** Adding `will-change: transform` to many elements consumes
GPU memory and can actually hurt performance.

**Fix:**
```javascript
// Only add will-change during active animation
gsap.to('.box', {
  x: 200,
  onStart: () => el.style.willChange = 'transform',
  onComplete: () => el.style.willChange = 'auto',
});

// Or let GSAP handle it (force3D adds translateZ(0))
gsap.to('.box', { x: 200, force3D: true }); // default for transforms
```

---

## FOUC Prevention Checklist

```css
/* 1. Hide elements that will animate in */
.will-animate {
  visibility: hidden;
}
```

```javascript
// 2. Use autoAlpha (handles visibility for you)
gsap.from('.will-animate', {
  autoAlpha: 0,  // starts at opacity:0 + visibility:hidden
  y: 50,         // slides up
  // When animation plays: sets visibility:visible, animates opacity to 1
});
```

```javascript
// 3. For scroll-triggered elements
gsap.from('.scroll-reveal', {
  autoAlpha: 0,
  y: 60,
  scrollTrigger: {
    trigger: '.scroll-reveal',
    start: 'top 85%',
    toggleActions: 'play none none reverse',
  },
});
```

---

## SVG Animation Gotchas

1. **transformOrigin** — percentages work on SVG elements in GSAP, but
   measure differently than HTML. Test with `markers` or visual inspection.

2. **viewBox coordinate system** — `svgOrigin` uses viewBox coordinates,
   `transformOrigin` uses element bounding box percentages.

3. **Stroke animations need explicit stroke** — `DrawSVG` requires
   `stroke`, `stroke-width`, and usually `fill: none` set on the element.

4. **Browser rendering differences** — GSAP normalizes most quirks, but
   complex nested SVG transforms may still vary. Test Chrome + Safari.

5. **SVG inside `<img>` tags can't be animated** — use inline `<svg>` or
   `<object>` tags for animated SVGs.

---

## Debugging Checklist

1. **Add `markers: true`** to ScrollTrigger — visual start/end markers
2. **Check `gsap.version`** in console — ensure correct version loaded
3. **Verify plugin registration** — `gsap.registerPlugin()` called?
4. **Check element existence** — `gsap.utils.toArray('.target')` returns
   elements? Or empty array?
5. **Disable `lagSmoothing`** — `gsap.ticker.lagSmoothing(0)` to rule
   out lag compensation issues
6. **Use GSDevTools** — timeline scrubbing, speed control, visual inspection
   ```javascript
   import { GSDevTools } from 'gsap/GSDevTools';
   gsap.registerPlugin(GSDevTools);
   GSDevTools.create();
   ```
7. **Check z-index and overflow** — elements may be animating but hidden
   behind other elements or clipped by `overflow: hidden`
8. **Check for CSS transitions** — competing with GSAP animations
9. **Console log in onUpdate** — verify values are changing as expected
   ```javascript
   gsap.to('.box', {
     x: 200,
     onUpdate: function() { console.log(this.progress()); },
   });
   ```
10. **Performance tab** — record and check for long frames during scroll
