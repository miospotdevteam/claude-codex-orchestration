# GSAP Helpers Cheatsheet

Dense, scannable reference for all GSAP core methods, properties, plugins,
and helper patterns. Everything in one file.

---

## Quick Import Reference

```javascript
// ALL plugins are now free — one install
// bun add gsap

import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { ScrollSmoother } from 'gsap/ScrollSmoother';
import { Flip } from 'gsap/Flip';
import { Draggable } from 'gsap/Draggable';
import { Observer } from 'gsap/Observer';
import { SplitText } from 'gsap/SplitText';
import { MorphSVGPlugin } from 'gsap/MorphSVGPlugin';
import { DrawSVGPlugin } from 'gsap/DrawSVGPlugin';
import { MotionPathPlugin } from 'gsap/MotionPathPlugin';
import { Physics2DPlugin } from 'gsap/Physics2DPlugin';
import { PhysicsPropsPlugin } from 'gsap/PhysicsPropsPlugin';
import { ScrambleTextPlugin } from 'gsap/ScrambleTextPlugin';
import { TextPlugin } from 'gsap/TextPlugin';
import { CustomEase } from 'gsap/CustomEase';
import { CustomBounce } from 'gsap/CustomBounce';
import { CustomWiggle } from 'gsap/CustomWiggle';
import { EasePack } from 'gsap/EasePack';
import { ScrollToPlugin } from 'gsap/ScrollToPlugin';
import { InertiaPlugin } from 'gsap/InertiaPlugin';
import { MotionPathHelper } from 'gsap/MotionPathHelper';
import { EaselPlugin } from 'gsap/EaselPlugin';   // EaselJS/CreateJS integration
import { PixiPlugin } from 'gsap/PixiPlugin';     // PixiJS integration
import { GSDevTools } from 'gsap/GSDevTools';

// For SSR/Next.js (no window):
import gsap from 'gsap/dist/gsap';
import { ScrollTrigger } from 'gsap/dist/ScrollTrigger';
```

### Plugin Registration

```javascript
// Register once at app root — before any animation code runs
gsap.registerPlugin(ScrollTrigger, Flip, SplitText, Observer);

// In Next.js App Router, register in a "use client" layout or top-level component
// Do NOT register in server components
```

---

## Core Methods Cheatsheet

| Method | Use |
|---|---|
| `gsap.to()` | Animate to values |
| `gsap.from()` | Animate from values |
| `gsap.fromTo()` | Animate from→to |
| `gsap.set()` | Instant set (0 duration) |
| `gsap.timeline()` | Sequence animations |
| `gsap.killTweensOf()` | Stop animations on target |
| `gsap.isTweening()` | Check if target is animating |
| `gsap.getProperty()` | Read current property |
| `gsap.quickTo()` | Optimized repeated-to |
| `gsap.quickSetter()` | Optimized repeated-set |
| `gsap.registerEffect()` | Define reusable effects |
| `gsap.effects.name()` | Use registered effect |
| `gsap.context()` | Scope for cleanup |
| `gsap.matchMedia()` | Responsive conditions |
| `gsap.ticker` | The render loop |
| `gsap.globalTimeline` | Root of all timelines |
| `gsap.exportRoot()` | Wrap active animations for global control |
| `gsap.delayedCall()` | setTimeout replacement on GSAP timing |
| `gsap.getById()` | Find animation by id |
| `gsap.defaults()` | Set global defaults |
| `gsap.config()` | Global configuration |

### Core Method Signatures

```javascript
// gsap.to(targets, vars)
gsap.to('.box', { x: 200, duration: 1, ease: 'power2.out' });

// gsap.from(targets, vars)
gsap.from('.box', { opacity: 0, y: 50, duration: 0.8 });

// gsap.fromTo(targets, fromVars, toVars)
gsap.fromTo('.box', { opacity: 0 }, { opacity: 1, duration: 1 });

// gsap.set(targets, vars) — instant, no duration
gsap.set('.box', { autoAlpha: 0, y: 30 });

// gsap.killTweensOf(targets, properties?)
gsap.killTweensOf('.box');           // kill all
gsap.killTweensOf('.box', 'x,y');   // kill only x and y

// gsap.getProperty(target, property, unit?)
const x = gsap.getProperty('.box', 'x');         // number
const w = gsap.getProperty('.box', 'width', 'px'); // with unit

// gsap.isTweening(target)
if (gsap.isTweening('.box')) { /* still animating */ }
```

### quickTo and quickSetter

```javascript
// quickTo — optimized for frequent updates (mouse tracking, etc.)
const xTo = gsap.quickTo('.cursor', 'x', { duration: 0.3, ease: 'power3.out' });
const yTo = gsap.quickTo('.cursor', 'y', { duration: 0.3, ease: 'power3.out' });
window.addEventListener('mousemove', (e) => {
  xTo(e.clientX);
  yTo(e.clientY);
});

// quickSetter — even faster, no tweening, immediate set
const xSet = gsap.quickSetter('.el', 'x', 'px');
const ySet = gsap.quickSetter('.el', 'y', 'px');
gsap.ticker.add(() => {
  xSet(someValue);
  ySet(someOtherValue);
});
```

### Registered Effects

```javascript
// Define once
gsap.registerEffect({
  name: 'fadeIn',
  effect: (targets, config) => {
    return gsap.from(targets, {
      opacity: 0,
      y: config.y,
      duration: config.duration,
      ease: 'power2.out',
    });
  },
  defaults: { y: 30, duration: 0.8 },
  extendTimeline: true, // allows tl.fadeIn('.el')
});

// Use anywhere
gsap.effects.fadeIn('.card');
gsap.effects.fadeIn('.card', { y: 60, duration: 1.2 });

// On timeline (if extendTimeline: true)
const tl = gsap.timeline();
tl.fadeIn('.title')
  .fadeIn('.subtitle', '<0.2');
```

---

## Timeline Control

| Method | Description |
|---|---|
| `.play()` | Play forward |
| `.pause()` | Pause |
| `.reverse()` | Play backward |
| `.restart()` | Restart from beginning |
| `.seek(time)` | Jump to time |
| `.progress(0.5)` | Jump to 50% |
| `.timeScale(2)` | Double speed |
| `.kill()` | Destroy |
| `.isActive()` | Currently animating? |
| `.totalDuration()` | Total including repeats |
| `.endTime()` | When it ends |
| `.then()` | Promise-based completion |
| `.revert()` | Undo all changes |
| `.invalidate()` | Clear recorded values |
| `.totalProgress()` | Progress including repeats |
| `.time()` | Current playhead time |
| `.iteration()` | Current repeat iteration |

### Timeline Creation Options

```javascript
const tl = gsap.timeline({
  paused: true,
  repeat: -1,               // -1 = infinite
  yoyo: true,
  repeatDelay: 0.5,
  defaults: {                // inherited by children
    duration: 0.8,
    ease: 'power2.out',
  },
  onComplete: () => {},
  onUpdate: () => {},
  onStart: () => {},
  onRepeat: () => {},
  onReverseComplete: () => {},
  smoothChildTiming: true,   // auto-adjust child timing
  autoRemoveChildren: false,
});
```

### Adding to Timelines

```javascript
const tl = gsap.timeline();

tl.to('.a', { x: 100 })
  .to('.b', { y: 50 })         // after .a ends
  .from('.c', { opacity: 0 })  // after .b ends
  .fromTo('.d', { scale: 0 }, { scale: 1 })
  .set('.e', { visibility: 'visible' })
  .call(() => doSomething())   // insert function call
  .add(otherTimeline)          // nest another timeline
  .addLabel('midpoint')
  .addPause()                  // pause playback here
  ;
```

---

## Position Parameter Quick Reference

```
tl.to(a, {}, 0)          // at absolute 0 seconds
tl.to(a, {}, '+=0.5')    // 0.5s after previous ends
tl.to(a, {}, '-=0.3')    // 0.3s before previous ends (overlap)
tl.to(a, {}, '<')         // at previous animation's START
tl.to(a, {}, '<0.2')     // 0.2s after previous START
tl.to(a, {}, '<-0.1')    // 0.1s before previous START
tl.to(a, {}, '>')         // at previous animation's END (same as default)
tl.to(a, {}, '>-0.1')    // 0.1s before previous END
tl.to(a, {}, '>0.2')     // 0.2s after previous END
tl.to(a, {}, 'label')    // at named label
tl.to(a, {}, 'label+=1') // 1s after label
tl.to(a, {}, 'label-=0.5') // 0.5s before label
```

### Common Overlap Patterns

```javascript
// Waterfall with overlap
tl.to('.a', { x: 100, duration: 1 })
  .to('.b', { x: 100, duration: 1 }, '-=0.3')
  .to('.c', { x: 100, duration: 1 }, '-=0.3');

// All start together
tl.to('.a', { x: 100 }, 0)
  .to('.b', { y: 100 }, 0)
  .to('.c', { rotation: 360 }, 0);

// Staggered from same point
tl.to('.a', { x: 100 }, 'start')
  .to('.b', { x: 100 }, 'start+=0.1')
  .to('.c', { x: 100 }, 'start+=0.2');
```

---

## Special Properties

| Property | Description |
|---|---|
| `duration` | Animation length (seconds) |
| `ease` | Easing function |
| `delay` | Start delay |
| `repeat` | Number of repeats (-1=infinite) |
| `yoyo` | Reverse on repeat |
| `repeatDelay` | Delay between repeats |
| `stagger` | Delay between targets |
| `overwrite` | Handle conflicts (`'auto'`, `true`, `false`) |
| `onComplete` | Callback when done |
| `onUpdate` | Callback every frame |
| `onStart` | Callback when starts |
| `onRepeat` | Callback on each repeat |
| `onReverseComplete` | Callback when reverse completes |
| `callbackScope` | `this` for callbacks |
| `paused` | Start paused |
| `immediateRender` | Render on creation |
| `autoAlpha` | opacity + visibility |
| `clearProps` | Reset CSS after animation |
| `keyframes` | Array of states |
| `id` | ID for GSDevTools |
| `data` | Arbitrary data attached to tween |
| `lazy` | Delay rendering 1 tick (default: true for .to/.from) |
| `inherit` | Inherit parent timeline defaults |

### autoAlpha vs opacity

```javascript
// autoAlpha: sets visibility:hidden when opacity reaches 0
// This removes the element from tab order and click events
gsap.set('.modal', { autoAlpha: 0 }); // opacity:0 + visibility:hidden
gsap.to('.modal', { autoAlpha: 1 });  // opacity:1 + visibility:visible
```

### clearProps

```javascript
// After animation, reset inline styles so CSS takes over
gsap.to('.el', {
  x: 100,
  duration: 1,
  clearProps: 'all',          // clear ALL inline styles on complete
  // clearProps: 'transform', // clear only transform
  // clearProps: 'x,y',       // clear specific properties
});
```

### Keyframes

```javascript
gsap.to('.box', {
  keyframes: [
    { x: 100, duration: 0.5 },
    { y: 50, duration: 0.3 },
    { rotation: 360, duration: 0.8 },
  ],
  ease: 'power2.inOut',
});

// Percentage-based keyframes
gsap.to('.box', {
  keyframes: {
    '0%':   { x: 0, y: 0 },
    '25%':  { x: 100, y: 0 },
    '50%':  { x: 100, y: 100 },
    '75%':  { x: 0, y: 100 },
    '100%': { x: 0, y: 0 },
  },
  duration: 2,
  ease: 'none',
});
```

### Overwrite Modes

```javascript
// 'auto' (default) — kills only conflicting properties on same target
gsap.to('.box', { x: 100, overwrite: 'auto' });

// true — kills ALL tweens on same target immediately
gsap.to('.box', { x: 100, overwrite: true });

// false — no overwriting, tweens fight
gsap.to('.box', { x: 100, overwrite: false });
```

---

## Stagger Object

```javascript
stagger: {
  each: 0.1,           // time between each
  amount: 0.8,         // total time distributed across all targets
  from: 'start',       // 'start', 'end', 'center', 'edges', 'random', index
  grid: [rows, cols],  // for grid layouts
  axis: 'x',           // 'x' or 'y' for grid direction
  ease: 'power2.in',   // stagger distribution ease (NOT the animation ease)
}
```

### Stagger Examples

```javascript
// Simple stagger
gsap.from('.card', { y: 40, opacity: 0, stagger: 0.1 });

// From center outward
gsap.from('.grid-item', {
  scale: 0,
  stagger: { each: 0.05, from: 'center' },
});

// Grid stagger (ripple from top-left)
gsap.from('.grid-item', {
  scale: 0,
  opacity: 0,
  stagger: {
    each: 0.04,
    grid: [4, 8],
    from: 0,     // index 0 = top-left
    axis: null,  // both axes (diagonal ripple)
  },
});

// Function stagger (custom per-element delay)
gsap.from('.el', {
  y: 50,
  opacity: 0,
  stagger: (index, target, list) => {
    return index * 0.1 + Math.random() * 0.05;
  },
});
```

---

## ScrollTrigger Config

```javascript
scrollTrigger: {
  trigger: '.el',               // element that triggers
  start: 'top center',          // trigger-position viewport-position
  end: 'bottom center',         // when to stop
  scrub: 1,                     // smooth scrubbing (seconds of catch-up)
  pin: true,                    // pin trigger element
  pinSpacing: true,             // add spacing for pinned element
  snap: 0.5,                    // snap to 50% increments
  markers: true,                // debug markers (dev only!)
  toggleActions: 'play none none reverse',
  toggleClass: 'active',
  invalidateOnRefresh: true,    // recalculate on resize
  fastScrollEnd: true,          // force finish on fast scroll
  preventOverlaps: true,        // prevent overlapping animations
  anticipatePin: 1,             // pre-pin to prevent flash
  endTrigger: '.other-el',      // different end trigger element
  scroller: '.scroll-container', // custom scroll container (default: window)

  // Callbacks
  onEnter:      (self) => {},
  onLeave:      (self) => {},
  onEnterBack:  (self) => {},
  onLeaveBack:  (self) => {},
  onUpdate:     (self) => {
    // self.progress  — 0 to 1
    // self.direction — 1 (forward) or -1 (backward)
    // self.velocity  — scroll speed
    // self.isActive  — currently in range?
  },
  onToggle:     (self) => { /* self.isActive */ },
  onRefresh:    (self) => {},
  onScrubComplete: () => {},
}
```

### start/end String Format

```
// Format: "triggerPosition viewportPosition"
// triggerPosition: top of trigger element relative to...
// viewportPosition: ...this position in the viewport

'top center'      // trigger's top hits viewport center
'top top'         // trigger's top hits viewport top
'top 80%'         // trigger's top hits 80% down viewport
'center center'   // trigger's center hits viewport center
'bottom bottom'   // trigger's bottom hits viewport bottom
'top+=100 center' // 100px below trigger's top hits center
'bottom-=50 80%'  // 50px above trigger's bottom hits 80%

// Numeric / function
start: 0,                     // absolute scroll position
start: () => someCalculation, // dynamic (recalculated on refresh)
```

### toggleActions

```
// Format: "onEnter onLeave onEnterBack onLeaveBack"
// Values: play, pause, resume, reverse, restart, reset, complete, none

'play none none none'      // play once, never reverse
'play none none reverse'   // play on enter, reverse on scroll back (most common)
'play pause resume reverse' // full control
'restart none none reverse' // restart every time
'play complete none none'  // play and immediately complete on leave
```

### ScrollTrigger Static Methods

```javascript
// Batch multiple elements
ScrollTrigger.batch('.card', {
  onEnter: (batch) => gsap.from(batch, {
    y: 40, opacity: 0, stagger: 0.1,
  }),
  start: 'top 85%',
});

// Create standalone (no tween)
ScrollTrigger.create({
  trigger: '.section',
  start: 'top top',
  end: '+=300%',
  pin: true,
  onUpdate: (self) => updateScene(self.progress),
});

// Refresh all ScrollTriggers (after DOM changes)
ScrollTrigger.refresh();

// Sort ScrollTriggers (after dynamic reordering)
ScrollTrigger.sort();

// Get all ScrollTriggers
ScrollTrigger.getAll();

// Get by ID
ScrollTrigger.getById('hero');

// Kill all
ScrollTrigger.killAll();

// Save/restore scroll position
ScrollTrigger.saveStyles('.el');

// Match media via gsap
gsap.matchMedia().add({
  '(min-width: 768px)': () => { /* desktop animations */ },
  '(max-width: 767px)': () => { /* mobile animations */ },
  'all': () => { /* all sizes */ },
});

// Scroll position helpers
ScrollTrigger.isScrolling();     // boolean
ScrollTrigger.positionInViewport('.el', 'center'); // 0-1
```

### Scrub Values

```javascript
scrub: true,   // instant link (no smoothing — can feel jerky)
scrub: 0.5,    // 0.5s catch-up (snappy)
scrub: 1,      // 1s catch-up (smooth)
scrub: 1.5,    // 1.5s catch-up (cinematic, great for camera movement)
scrub: 3,      // 3s catch-up (very laggy — intentional dreamy feel)
```

### Snap

```javascript
snap: 1 / 5,                    // snap to 20% increments (5 sections)
snap: { snapTo: 1/5, duration: 0.5, ease: 'power2.inOut' },
snap: {
  snapTo: 'labels',             // snap to timeline labels
  duration: { min: 0.2, max: 0.6 },
  delay: 0.1,
  ease: 'power1.inOut',
},
snap: {
  snapTo: (value) => {          // custom snap function
    return Math.round(value * 4) / 4; // snap to quarters
  },
},
```

---

## GSAP Context (Cleanup)

```javascript
// gsap.context() — scopes all animations for easy cleanup
const ctx = gsap.context(() => {
  gsap.to('.box', { x: 100 });
  gsap.from('.title', { opacity: 0 });
  ScrollTrigger.create({ /* ... */ });
  // ALL animations/ScrollTriggers created here are tracked
}, containerRef); // optional scope element for selector scoping

// Cleanup everything at once
ctx.revert(); // kills all animations + ScrollTriggers in this context

// Add to existing context
ctx.add(() => {
  gsap.to('.new-el', { y: 50 });
});

// Conditions (for matchMedia-like behavior)
ctx.add('desktop', () => { /* desktop only */ });
ctx.add('mobile', () => { /* mobile only */ });
ctx.conditions({ desktop: true }); // activate desktop
```

---

## GSAP matchMedia

```javascript
const mm = gsap.matchMedia();

mm.add('(min-width: 768px)', () => {
  // Desktop animations — automatically reverted when condition no longer matches
  gsap.to('.hero', { x: 200 });
  ScrollTrigger.create({ /* ... */ });

  return () => {
    // Optional additional cleanup
  };
});

mm.add('(max-width: 767px)', () => {
  // Mobile animations
  gsap.to('.hero', { x: 50 });
});

mm.add('(prefers-reduced-motion: no-preference)', () => {
  // Only animate when motion is OK
  gsap.from('.title', { y: 50, opacity: 0 });
});

// Cleanup all
mm.revert();
```

---

## GSAP Ticker

```javascript
// Add to render loop
gsap.ticker.add((time, deltaTime, frame) => {
  // time: total elapsed (seconds)
  // deltaTime: since last tick (seconds)
  // frame: frame count
});

gsap.ticker.fps(60);           // cap framerate
gsap.ticker.lagSmoothing(0);   // disable lag compensation (recommended for scroll-driven)
gsap.ticker.remove(fn);        // remove listener
gsap.ticker.sleep();           // pause ticker
gsap.ticker.wake();            // resume ticker
gsap.ticker.deltaRatio(60);    // multiplier for 60fps-independent updates
// Returns 1 at 60fps, 2 at 30fps — use for consistent physics in ticker
```

### Single Render Loop Pattern (Three.js + Lenis + ScrollTrigger)

```javascript
import Lenis from 'lenis';

const lenis = new Lenis({ autoRaf: false });

// Lenis listens to ScrollTrigger
lenis.on('scroll', ScrollTrigger.update);

// One ticker drives everything
gsap.ticker.add((time) => {
  lenis.raf(time * 1000); // Lenis expects milliseconds
});
gsap.ticker.lagSmoothing(0);

// In useWebGL or your render hook:
gsap.ticker.add((time, deltaTime) => {
  updateScene(time, deltaTime);
  renderer.render(scene, camera);
});
```

---

## exportRoot / delayedCall / getById

```javascript
// gsap.exportRoot() — wrap all active animations into a Timeline for global control
// Useful for game pause: new animations after export are NOT affected
const allAnimations = gsap.exportRoot();
allAnimations.pause();   // pause everything currently running
allAnimations.resume();  // resume

// gsap.delayedCall(delay, callback, params) — GSAP-aware setTimeout
// Respects globalTimeline.timeScale() and pause, unlike setTimeout
const delayed = gsap.delayedCall(2, () => {
  showNotification('Hello!');
});
delayed.kill(); // cancel

// gsap.getById(id) — find animation by its id property
gsap.to('.box', { x: 200, id: 'boxMove' });
const tween = gsap.getById('boxMove');
tween.pause();
```

### CSS Variable Animation (GSAP 3.13+)

```javascript
// Animate CSS custom properties directly
gsap.to('.element', {
  '--progress': 1,           // animate a CSS variable
  '--color': '#ff0000',      // color variables work too
  duration: 1,
});

// Use with design tokens
gsap.to(':root', {
  '--primary-hue': 200,
  duration: 2,
  ease: 'power2.inOut',
});

// Drive CSS from a variable animated by GSAP
// CSS: .bar { width: calc(var(--progress) * 100%); }
gsap.to('.bar', { '--progress': 1, duration: 1.5 });
```

---

## Easing Quick Reference

```
// Standard (most common for UI)
'none'              // linear (constant speed — use for scroll-driven scrub)
'power1.out'        // subtle decel
'power2.out'        // moderate decel (default feel, most versatile)
'power3.out'        // strong decel (entrances, reveals)
'power4.out'        // very strong decel (dramatic entrances)
'expo.out'          // exponential decel (snappy, modern feel)

// Directions
'.in'               // accelerate (exits, things leaving)
'.out'              // decelerate (entrances, things arriving)
'.inOut'            // both (transitions, state changes)

// Special
'back.out(1.7)'         // overshoot then settle (playful)
'back.in(1.7)'          // pull back before exiting
'elastic.out(1, 0.3)'   // springy bounce (attention-grabbing)
'bounce.out'             // bouncing ball effect
'circ.out'               // circular deceleration
'sine.out'               // gentle sine wave (subtle, natural)

// Stepped
'steps(12)'         // 12 discrete steps (sprite animation, clock ticks)

// Slow-motion middle
'slow(0.7, 0.7, false)' // EasePack — slow in the middle portion

// Custom (requires CustomEase plugin)
CustomEase.create('myEase', 'M0,0 C0.2,1 0.4,1 1,1');
```

### Ease Selection Guide

| Situation | Recommended Ease |
|---|---|
| Element entering viewport | `power2.out` or `power3.out` |
| Element leaving viewport | `power2.in` |
| Modal open/close | `power2.inOut` |
| Scroll-driven (scrub) | `none` (linear) |
| Playful UI interaction | `back.out(1.7)` |
| Attention-grabbing | `elastic.out(1, 0.3)` |
| Loading spinner | `none` or `power1.inOut` |
| Page transition | `expo.inOut` or `power4.inOut` |
| Hover effect | `power1.out` (subtle) |
| Parallax | `none` |

---

## gsap.config() and gsap.defaults()

```javascript
// Global configuration
gsap.config({
  autoSleep: 60,          // seconds of inactivity before ticker sleeps
  force3D: 'auto',        // force GPU acceleration (true, false, 'auto')
  nullTargetWarn: false,   // suppress warnings for null targets
  units: { x: 'px', y: 'px', rotation: 'deg' }, // default units
});

// Global defaults (inherited by all tweens)
gsap.defaults({
  duration: 0.8,
  ease: 'power2.out',
  overwrite: 'auto',
});
```

---

## Helper Functions Collection

### 1. React Cleanup Pattern

```typescript
import { useEffect, useRef } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

function AnimatedSection() {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const ctx = gsap.context(() => {
      gsap.from('.title', {
        y: 50, opacity: 0, duration: 1,
        scrollTrigger: { trigger: '.title', start: 'top 80%' },
      });

      const tl = gsap.timeline({
        scrollTrigger: { trigger: '.cards', start: 'top 70%' },
      });
      tl.from('.card', { y: 30, opacity: 0, stagger: 0.15 });
    }, containerRef); // scope selectors to this container

    return () => ctx.revert(); // cleanup everything
  }, []);

  return <div ref={containerRef}>{/* ... */}</div>;
}
```

### 2. Scroll-Speed Reactive Animation

```javascript
// Scale particles or effects based on scroll velocity
ScrollTrigger.create({
  trigger: '.scene',
  start: 'top top',
  end: 'bottom bottom',
  onUpdate: (self) => {
    const velocity = Math.abs(self.getVelocity());
    const normalized = gsap.utils.clamp(0, 1, velocity / 3000);

    // Spread particles when scrolling fast
    particleMaterial.uniforms.uSpread.value = gsap.utils.interpolate(
      particleMaterial.uniforms.uSpread.value,
      normalized,
      0.1 // lerp factor
    );
  },
});
```

### 3. Parallax with Clamp

```javascript
// Clamped parallax — element moves slower than scroll but never overshoots
gsap.to('.bg-layer', {
  y: () => -window.innerHeight * 0.3, // 30% of viewport
  ease: 'none',
  scrollTrigger: {
    trigger: '.section',
    start: 'top bottom',
    end: 'bottom top',
    scrub: true,
    invalidateOnRefresh: true, // recalculate on resize
  },
});

// Multiple parallax layers with different speeds
['.layer-1', '.layer-2', '.layer-3'].forEach((selector, i) => {
  gsap.to(selector, {
    y: () => -(i + 1) * 50,
    ease: 'none',
    scrollTrigger: {
      trigger: '.parallax-container',
      start: 'top bottom',
      end: 'bottom top',
      scrub: true,
      invalidateOnRefresh: true,
    },
  });
});
```

### 4. Responsive Animation Values

```javascript
// Use gsap.matchMedia for responsive animation values
const mm = gsap.matchMedia();

mm.add({
  isDesktop: '(min-width: 1024px)',
  isTablet: '(min-width: 768px) and (max-width: 1023px)',
  isMobile: '(max-width: 767px)',
}, (context) => {
  const { isDesktop, isTablet, isMobile } = context.conditions!;

  gsap.from('.hero-title', {
    y: isDesktop ? 100 : isTablet ? 60 : 30,
    duration: isDesktop ? 1.2 : 0.8,
    ease: 'power3.out',
  });

  gsap.from('.card', {
    y: isMobile ? 20 : 40,
    opacity: 0,
    stagger: isMobile ? 0.05 : 0.1,
  });
});
```

### 5. Debounced Resize Handler for ScrollTrigger

```javascript
// ScrollTrigger already debounces resize, but for custom logic:
let resizeTimer: ReturnType<typeof setTimeout>;

function onResize() {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    ScrollTrigger.refresh();
  }, 250);
}

window.addEventListener('resize', onResize);

// Better: use ScrollTrigger's built-in resize refresh
ScrollTrigger.config({
  autoRefreshEvents: 'visibilitychange,DOMContentLoaded,load,resize',
  // ignoreMobileResize: true, // skip refresh on mobile address bar changes
});

// For Three.js canvas resize:
const ro = new ResizeObserver(() => {
  const { clientWidth: w, clientHeight: h } = canvas.parentElement!;
  renderer.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  ScrollTrigger.refresh();
});
ro.observe(canvas.parentElement!);
```

### 6. Batch Scroll Reveal

```javascript
// Efficient batch reveal for many elements (cards, list items, etc.)
ScrollTrigger.batch('.reveal-item', {
  onEnter: (batch) => {
    gsap.from(batch, {
      y: 40,
      opacity: 0,
      duration: 0.6,
      ease: 'power2.out',
      stagger: 0.08,
      overwrite: true,
    });
  },
  onLeave: (batch) => {
    gsap.to(batch, { opacity: 0, overwrite: true });
  },
  onEnterBack: (batch) => {
    gsap.to(batch, { opacity: 1, y: 0, overwrite: true });
  },
  start: 'top 85%',
  end: 'bottom 15%',
  batchMax: 6, // max elements per batch
});
```

### 7. Smooth Counter Animation

```javascript
// Animate a number display (preloaders, stats, etc.)
const counter = { value: 0 };
gsap.to(counter, {
  value: 100,
  duration: 2,
  ease: 'power2.out',
  onUpdate: () => {
    document.querySelector('.counter')!.textContent =
      Math.round(counter.value).toString();
  },
});
```

### 8. Wrap and Clamp Utilities

```javascript
// gsap.utils — pure utility functions, no animation
const clamp = gsap.utils.clamp(0, 100);
clamp(150);  // 100
clamp(-10);  // 0

const wrap = gsap.utils.wrap(0, 360);
wrap(400);   // 40
wrap(-10);   // 350

const mapRange = gsap.utils.mapRange(0, 1, 0, 100);
mapRange(0.5); // 50

const interpolate = gsap.utils.interpolate(0, 100, 0.5); // 50
// Also works with colors:
gsap.utils.interpolate('#ff0000', '#0000ff', 0.5); // purple

const normalize = gsap.utils.normalize(0, 100, 50); // 0.5

const snap = gsap.utils.snap(10);
snap(23); // 20
snap(27); // 30

const pipe = gsap.utils.pipe(
  gsap.utils.clamp(0, 1),
  gsap.utils.mapRange(0, 1, -100, 100),
  gsap.utils.snap(25)
);
pipe(0.73); // 50

// Distribute values evenly
const values = gsap.utils.distribute({
  base: 0,
  amount: 100,
  from: 'center',
  ease: 'power2',
});

// Convert to array
gsap.utils.toArray('.card'); // NodeList → Array
gsap.utils.toArray(nodeList);
```

### 9. Scroll-Driven Three.js Uniforms

```javascript
// Drive shader uniforms directly from scroll progress
ScrollTrigger.create({
  trigger: '.underwater-section',
  start: 'top top',
  end: 'bottom bottom',
  scrub: 1.5,
  onUpdate: (self) => {
    // Depth-based fog density
    fogMaterial.uniforms.uDensity.value = gsap.utils.interpolate(
      0.02, 0.08, self.progress
    );
    // Particle opacity fade-out during transition
    particleMaterial.uniforms.uOpacity.value = gsap.utils.interpolate(
      1.0, 0.0, gsap.utils.clamp(0, 1, (self.progress - 0.7) / 0.3)
    );
  },
});
```

### 10. prefers-reduced-motion Guard

```javascript
// Pattern: wrap all motion in a reduced-motion check
const prefersReducedMotion = window.matchMedia(
  '(prefers-reduced-motion: reduce)'
).matches;

if (prefersReducedMotion) {
  // Show everything immediately, no animation
  gsap.set('.reveal', { opacity: 1, y: 0, clearProps: 'all' });
} else {
  // Full animation experience
  gsap.from('.reveal', {
    y: 50, opacity: 0, duration: 1,
    stagger: 0.1, ease: 'power3.out',
    scrollTrigger: { trigger: '.section', start: 'top 80%' },
  });
}

// Or use matchMedia (cleaner, auto-reverts):
const mm = gsap.matchMedia();
mm.add('(prefers-reduced-motion: no-preference)', () => {
  gsap.from('.reveal', {
    y: 50, opacity: 0, stagger: 0.1,
    scrollTrigger: { trigger: '.section', start: 'top 80%' },
  });
});
```

---

## Plugin Quick References

### Flip

```javascript
import { Flip } from 'gsap/Flip';
gsap.registerPlugin(Flip);

// 1. Record state
const state = Flip.getState('.items');
// 2. Make DOM changes
container.classList.toggle('grid-view');
// 3. Animate from old → new
Flip.from(state, {
  duration: 0.6,
  ease: 'power2.inOut',
  stagger: 0.05,
  absolute: true,  // use position:absolute during animation
  onEnter: (els) => gsap.from(els, { opacity: 0, scale: 0 }),
  onLeave: (els) => gsap.to(els, { opacity: 0, scale: 0 }),
});
```

### Observer

```javascript
import { Observer } from 'gsap/Observer';
gsap.registerPlugin(Observer);

Observer.create({
  target: window,
  type: 'wheel,touch,pointer',
  onUp: () => goToSection(currentIndex - 1),
  onDown: () => goToSection(currentIndex + 1),
  tolerance: 10,
  preventDefault: true,
  wheelSpeed: -1,     // natural scrolling
  onStopDelay: 0.25,  // delay before onStop fires
  onStop: () => {},
});
```

### SplitText

```javascript
import { SplitText } from 'gsap/SplitText';
gsap.registerPlugin(SplitText);

const split = new SplitText('.text', {
  type: 'chars,words,lines',
  charsClass: 'char',
  wordsClass: 'word',
  linesClass: 'line',
});

// Animate characters
gsap.from(split.chars, {
  y: 50, opacity: 0, rotateX: -90,
  stagger: 0.02, duration: 0.6, ease: 'back.out(1.7)',
});

// Cleanup (restore original HTML)
split.revert();
```

### MotionPathPlugin

```javascript
import { MotionPathPlugin } from 'gsap/MotionPathPlugin';
gsap.registerPlugin(MotionPathPlugin);

gsap.to('.rocket', {
  motionPath: {
    path: '#flight-path',       // SVG path or array of points
    align: '#flight-path',
    autoRotate: true,           // rotate to match path direction
    alignOrigin: [0.5, 0.5],
    start: 0,
    end: 1,
  },
  duration: 3,
  ease: 'power1.inOut',
});

// Convert coordinates to path
MotionPathPlugin.convertToPath('.line');
```

### DrawSVGPlugin

```javascript
import { DrawSVGPlugin } from 'gsap/DrawSVGPlugin';
gsap.registerPlugin(DrawSVGPlugin);

// Animate stroke drawing
gsap.from('.svg-path', { drawSVG: 0, duration: 2, ease: 'none' });

// Partial draw
gsap.to('.svg-path', { drawSVG: '20% 80%', duration: 1 });
```

### MorphSVGPlugin

```javascript
import { MorphSVGPlugin } from 'gsap/MorphSVGPlugin';
gsap.registerPlugin(MorphSVGPlugin);

gsap.to('#circle', { morphSVG: '#star', duration: 1.5, ease: 'power2.inOut' });

// With fine control
gsap.to('#shape1', {
  morphSVG: { shape: '#shape2', shapeIndex: 'auto', map: 'complexity' },
});
```

### ScrambleTextPlugin

```javascript
import { ScrambleTextPlugin } from 'gsap/ScrambleTextPlugin';
gsap.registerPlugin(ScrambleTextPlugin);

gsap.to('.el', {
  scrambleText: {
    text: 'HELLO WORLD',
    chars: 'upperCase',     // 'upperCase', 'lowerCase', 'custom chars'
    speed: 0.5,
    revealDelay: 0.3,
    tweenLength: false,
  },
  duration: 2,
});
```

### TextPlugin

```javascript
import { TextPlugin } from 'gsap/TextPlugin';
gsap.registerPlugin(TextPlugin);

// Typewriter effect
gsap.to('.el', {
  text: { value: 'New text content', delimiter: '' },
  duration: 2,
  ease: 'none',
});
```

### ScrollSmoother

```javascript
import { ScrollSmoother } from 'gsap/ScrollSmoother';
gsap.registerPlugin(ScrollTrigger, ScrollSmoother);

// Requires specific HTML structure:
// <div id="smooth-wrapper">
//   <div id="smooth-content">...page...</div>
// </div>

const smoother = ScrollSmoother.create({
  smooth: 1.5,              // seconds of smoothing
  effects: true,            // enable data-speed and data-lag
  smoothTouch: 0.1,         // touch device smoothing (0 = native)
  normalizeScroll: true,    // prevent address bar issues on mobile
});

// In HTML: <div data-speed="0.5">slow parallax</div>
// In HTML: <div data-lag="0.8">follows with delay</div>

smoother.scrollTo('.section', true); // smooth scroll to element
smoother.paused(true);               // pause smooth scrolling
```

### CustomEase

```javascript
import { CustomEase } from 'gsap/CustomEase';
gsap.registerPlugin(CustomEase);

// Create from SVG-like path
CustomEase.create('smoothSnap', 'M0,0 C0.14,0 0.27,0.55 0.32,0.75 0.41,1.08 0.5,1 1,1');

// Use it
gsap.to('.el', { x: 100, ease: 'smoothSnap' });

// Get ease from existing tween
const ease = CustomEase.getSVGData('power2.out');
```

### CustomBounce and CustomWiggle

```javascript
import { CustomBounce } from 'gsap/CustomBounce';
import { CustomWiggle } from 'gsap/CustomWiggle';
gsap.registerPlugin(CustomBounce, CustomWiggle);

CustomBounce.create('gentleBounce', {
  strength: 0.4,
  squash: 2,    // squash on impact
  endAtStart: false,
});

CustomWiggle.create('shakeX', {
  wiggles: 8,
  type: 'uniform',  // 'uniform', 'random', 'easeOut'
});

gsap.to('.el', { y: 300, ease: 'gentleBounce' });
gsap.to('.el', { x: 20, ease: 'shakeX' });
```

### GSDevTools

```javascript
import { GSDevTools } from 'gsap/GSDevTools';
gsap.registerPlugin(GSDevTools);

// Visual timeline debugger (dev only!)
GSDevTools.create({
  animation: myTimeline,   // specific timeline, or omit for global
  paused: false,
  loop: true,
  minimal: false,
});
```

### ScrollToPlugin

```javascript
import { ScrollToPlugin } from 'gsap/ScrollToPlugin';
gsap.registerPlugin(ScrollToPlugin);

// Scroll to pixel position
gsap.to(window, { scrollTo: 400, duration: 1 });

// Scroll to element
gsap.to(window, { scrollTo: '#section-3', duration: 1.5, ease: 'power2.inOut' });

// With offset (for fixed header)
gsap.to(window, { scrollTo: { y: '#section', offsetY: 80 }, duration: 1 });

// Scroll to bottom
gsap.to(window, { scrollTo: 'max', duration: 2 });

// Container scroll
gsap.to('#scrollable-div', { scrollTo: { y: 300, x: 200 }, duration: 1 });

// Auto-cancel on manual scroll
gsap.to(window, { scrollTo: { y: '#target', autoKill: true }, duration: 1 });

// Global config
ScrollToPlugin.config({ autoKill: true });
```

### InertiaPlugin

```javascript
import { InertiaPlugin } from 'gsap/InertiaPlugin';
gsap.registerPlugin(InertiaPlugin);

// Basic momentum
gsap.to(obj, { inertia: { x: 500, y: -300 } }); // velocity in px/sec

// With boundaries and snap
gsap.to(obj, {
  inertia: {
    x: { velocity: 500, min: 0, max: 1024, end: [0, 256, 512, 768, 1024] },
  },
});

// Velocity tracking (standalone, without Draggable)
InertiaPlugin.track(target, 'x,y');        // start tracking
InertiaPlugin.getVelocity(target, 'x');    // read velocity
InertiaPlugin.isTracking(target, 'x');     // check status
InertiaPlugin.untrack(target);             // stop tracking

// Auto velocity from tracking
gsap.to(obj, { inertia: { x: 'auto', y: 'auto' } });
```

### Modifiers (Core — No Import)

```javascript
// Per-frame value interception
gsap.to('.el', {
  x: 500,
  modifiers: {
    x: (value, target) => {
      // intercept, transform, return
      return Math.round(parseFloat(value) / 50) * 50;
    },
  },
});

// Infinite carousel via wrap
gsap.to(items, {
  x: `-=${totalWidth}`,
  repeat: -1,
  ease: 'none',
  modifiers: {
    x: gsap.utils.unitize(gsap.utils.wrap(-itemWidth, totalWidth - itemWidth)),
  },
});
```

### Snap (Core — No Import)

```javascript
// Snap to integers
gsap.to('.el', { x: 1000, snap: 'x,y' });

// Snap to increment
gsap.to('.el', { x: 1000, snap: { x: 20 } }); // nearest multiple of 20

// Snap to array
gsap.to('.el', { x: 1000, snap: { x: [0, 100, 250, 500] } });

// Snap with radius (magnetic)
gsap.to('.el', { x: 1000, snap: { x: { values: [0, 250, 500], radius: 30 } } });
```

### roundProps (Core — No Import)

```javascript
// Round specific properties to integers every frame
gsap.to('.el', { x: 300.7, y: 150.3, roundProps: 'x,y' });

// Counter with whole numbers
const c = { value: 0 };
gsap.to(c, { value: 1000, roundProps: 'value', onUpdate: () => display(c.value) });

// NOTE: roundProps, snap, and modifiers share the same mechanism —
// cannot combine them on the same property
```

---

## Common Patterns

### Kill and Restart on Route Change

```javascript
// In a Next.js App Router layout or page component
useEffect(() => {
  const ctx = gsap.context(() => {
    // ... animations
  });
  return () => {
    ctx.revert();
    ScrollTrigger.getAll().forEach((st) => st.kill());
  };
}, [pathname]);
```

### Horizontal Scroll Section

```javascript
const sections = gsap.utils.toArray<HTMLElement>('.panel');

gsap.to(sections, {
  xPercent: -100 * (sections.length - 1),
  ease: 'none',
  scrollTrigger: {
    trigger: '.horizontal-container',
    pin: true,
    scrub: 1,
    snap: 1 / (sections.length - 1),
    end: () => '+=' + document.querySelector('.horizontal-container')!.scrollWidth,
  },
});
```

### Pinned Section with Internal Timeline

```javascript
const tl = gsap.timeline({
  scrollTrigger: {
    trigger: '.pinned-section',
    start: 'top top',
    end: '+=300%',     // 3x viewport height of scroll distance
    pin: true,
    scrub: 1,
  },
});

tl.addLabel('phase1')
  .from('.step-1', { opacity: 0, y: 30 })
  .to('.step-1', { opacity: 0 }, '+=0.5')
  .addLabel('phase2')
  .from('.step-2', { opacity: 0, y: 30 })
  .to('.step-2', { opacity: 0 }, '+=0.5')
  .addLabel('phase3')
  .from('.step-3', { opacity: 0, y: 30 });
```

### Text Reveal without SplitText (Manual)

```javascript
// When you don't want the SplitText plugin dependency
// Wrap each character in a span manually
function splitChars(el: HTMLElement): HTMLSpanElement[] {
  const text = el.textContent || '';
  el.textContent = '';
  return [...text].map((char) => {
    const span = document.createElement('span');
    span.textContent = char === ' ' ? '\u00A0' : char;
    span.style.display = 'inline-block';
    el.appendChild(span);
    return span;
  });
}

const chars = splitChars(document.querySelector('.title')!);
gsap.from(chars, {
  y: '100%', opacity: 0,
  duration: 0.6, ease: 'power3.out',
  stagger: 0.03,
});
```

### Infinite Marquee

```javascript
function createMarquee(selector: string, speed = 50) {
  const el = document.querySelector(selector) as HTMLElement;
  const clone = el.cloneNode(true) as HTMLElement;
  el.parentElement!.appendChild(clone);

  const width = el.offsetWidth;
  const duration = width / speed;

  gsap.set([el, clone], { xPercent: (i) => i * 100 });

  const tl = gsap.timeline({ repeat: -1 });
  tl.to([el, clone], {
    xPercent: (i) => (i - 1) * 100,
    duration,
    ease: 'none',
  });

  return tl;
}
```

---

## Debugging Tips

```javascript
// 1. Add markers to see ScrollTrigger positions
scrollTrigger: { markers: true }

// 2. Log progress
onUpdate: (self) => console.log(self.progress.toFixed(2))

// 3. Use GSDevTools for visual timeline debugging
GSDevTools.create({ animation: tl });

// 4. Check what's animating a target
console.log(gsap.getTweensOf('.box'));

// 5. List all ScrollTriggers
console.log(ScrollTrigger.getAll());

// 6. Slow down globally
gsap.globalTimeline.timeScale(0.2);

// 7. Check if GSAP is loaded and version
console.log(gsap.version);
```
