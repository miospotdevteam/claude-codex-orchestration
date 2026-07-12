# GSAP Advanced Scroll Patterns

ScrollSmoother (alternative to Lenis), advanced Observer patterns,
and hybrid scroll architectures.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## 1. ScrollSmoother — Native-Feel Smooth Scrolling

GSAP's built-in smooth scroll solution. Uses native scrollbar but smooths
the movement. Previously paid — now free.

```javascript
import { ScrollSmoother } from 'gsap/ScrollSmoother';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
gsap.registerPlugin(ScrollSmoother, ScrollTrigger);
```

### Required HTML Structure

```html
<body>
  <div id="smooth-wrapper">
    <div id="smooth-content">
      <!-- ALL your page content goes here -->
      <section class="hero">...</section>
      <section class="about">...</section>
    </div>
  </div>
</body>
```

### Setup

```javascript
const smoother = ScrollSmoother.create({
  wrapper: '#smooth-wrapper',
  content: '#smooth-content',
  smooth: 1.5,              // smoothing duration (seconds)
  effects: true,             // enable data-speed / data-lag
  smoothTouch: 0.1,          // touch smoothing (0 = off, recommended)
  normalizeScroll: true,     // prevents address bar resize issues (mobile)
  ignoreMobileResize: true,  // ignore height changes from mobile toolbar
});
```

### Parallax with Data Attributes

No JavaScript needed — just HTML attributes:

```html
<!-- Slower than scroll (background parallax) -->
<img data-speed="0.5" src="bg.jpg" />

<!-- Faster than scroll -->
<div data-speed="1.5">Zooms past</div>

<!-- Cinematic lag (follows scroll with delay) -->
<h1 data-lag="0.5">Smooth title</h1>

<!-- Prevent element from going past natural edges -->
<img data-speed="clamp(0.5)" src="hero.jpg" />
```

### Methods

```javascript
// Scroll to element
smoother.scrollTo('.section-3', true); // true = smooth
smoother.scrollTo('.section-3', true, 'center center'); // with position

// Pause/resume
smoother.paused(true);   // pause smooth scrolling
smoother.paused(false);  // resume

// Get/set scroll position
smoother.scrollTop();        // current smooth scroll position
smoother.scrollTop(500);     // jump to position

// Get effects
smoother.effects();          // array of all data-speed/data-lag effects

// Kill
smoother.kill();             // destroy and restore native scroll
```

### With ScrollTrigger

ScrollSmoother works seamlessly with ScrollTrigger — no extra setup:

```javascript
ScrollSmoother.create({ ... });

// ScrollTrigger works normally
gsap.to('.box', {
  x: 200,
  scrollTrigger: {
    trigger: '.section',
    start: 'top center',
    end: 'bottom center',
    scrub: 1,
  },
});
```

### Reduced Motion

```javascript
const prefersReduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

if (!prefersReduced) {
  ScrollSmoother.create({
    smooth: 1.5,
    effects: true,
  });
}
// ScrollTrigger animations still work without ScrollSmoother
```

---

## ScrollSmoother vs Lenis

| Feature | ScrollSmoother | Lenis |
|---------|---------------|-------|
| **Integration** | Native GSAP — zero config with ScrollTrigger | Needs `lenis.on('scroll', ScrollTrigger.update)` + ticker |
| **Parallax** | Built-in: `data-speed`, `data-lag` | Manual: must create ScrollTrigger per element |
| **Mobile normalize** | `normalizeScroll: true` handles address bar | Not available |
| **Wrapper markup** | Requires `#smooth-wrapper` > `#smooth-content` | No wrapper needed |
| **Bundle** | Included with `bun add gsap` | Separate: `bun add lenis` |
| **Render loop** | Automatic via ScrollTrigger | Must wire into `gsap.ticker.add()` |
| **Three.js render** | Still need ticker for `renderer.render()` | Already in ticker — add render call |
| **API** | `.scrollTo()`, `.paused()`, `.effects()` | `.scrollTo()`, `.stop()`, `.start()`, `.progress` |
| **Velocity access** | `ScrollTrigger.getVelocity()` | `lenis.velocity` |
| **Framework** | Any | Any |

### When to Choose ScrollSmoother

- All-GSAP stack (no extra dependencies)
- Heavy parallax with `data-speed`/`data-lag`
- Mobile normalize needed
- Don't want to wire up a custom render loop for scroll

### When to Choose Lenis

- Already using Lenis in the project
- Need access to `lenis.progress` and `lenis.velocity` in render loop
- Prefer no wrapper markup
- Want the explicit `gsap.ticker.add()` pattern (more control)
- Using vanilla Three.js with the single-ticker pattern (Lenis fits
  naturally into the existing ticker)

### For Immersive WebGL Sites

**Recommended: Lenis** — because you already need `gsap.ticker.add()` for
`renderer.render()`, adding `lenis.raf()` to the same ticker is natural.
ScrollSmoother handles its own render timing, so coordinating it with a
Three.js render loop adds complexity.

---

## 2. Advanced Observer Patterns

Observer unifies scroll, touch, and pointer events into directional
callbacks. Use it when you need to hijack or intercept scroll behavior.

```javascript
import { Observer } from 'gsap/Observer';
gsap.registerPlugin(Observer);
```

### Full-Page Section Snapping

```javascript
const sections = gsap.utils.toArray('.fullpage-section');
let currentIndex = 0;
let isAnimating = false;

function goToSection(index) {
  index = gsap.utils.clamp(0, sections.length - 1, index);
  if (index === currentIndex || isAnimating) return;

  isAnimating = true;
  const direction = index > currentIndex ? 1 : -1;

  // Animate out current
  gsap.to(sections[currentIndex], {
    yPercent: -100 * direction,
    duration: 0.8,
    ease: 'power2.inOut',
  });

  // Animate in next
  gsap.fromTo(sections[index], {
    yPercent: 100 * direction,
  }, {
    yPercent: 0,
    duration: 0.8,
    ease: 'power2.inOut',
    onComplete: () => { isAnimating = false; },
  });

  currentIndex = index;
}

Observer.create({
  type: 'wheel,touch,pointer',
  wheelSpeed: -1,
  tolerance: 10,
  preventDefault: true,
  onUp: () => goToSection(currentIndex + 1),
  onDown: () => goToSection(currentIndex - 1),
});
```

### Horizontal Scroll Convert

Convert vertical wheel events to horizontal scroll:

```javascript
const container = document.querySelector('.horizontal-container');
const sections = gsap.utils.toArray('.horizontal-section');

const scrollTween = gsap.to(sections, {
  xPercent: -100 * (sections.length - 1),
  ease: 'none',
  scrollTrigger: {
    trigger: container,
    pin: true,
    scrub: 1,
    end: () => `+=${container.scrollWidth}`,
  },
});

// Alternative: Observer-based horizontal scroll
Observer.create({
  target: container,
  type: 'wheel',
  onChangeY: (self) => {
    // Convert vertical wheel to horizontal movement
    gsap.to(container, {
      scrollLeft: `+=${self.deltaY}`,
      duration: 0.3,
      overwrite: true,
    });
  },
});
```

### Velocity-Based Carousel

```javascript
const track = document.querySelector('.carousel-track');
let velocity = 0;

Observer.create({
  target: track,
  type: 'touch,pointer',
  dragMinimum: 5,
  onDrag: (self) => {
    gsap.to(track, {
      x: `+=${self.deltaX}`,
      duration: 0,
      overwrite: true,
    });
  },
  onDragEnd: (self) => {
    // Momentum based on release velocity
    gsap.to(track, {
      x: `+=${self.velocityX * 0.5}`,
      duration: Math.abs(self.velocityX) / 1000,
      ease: 'power3.out',
    });
  },
});
```

### Swipe Detection for Mobile

```javascript
Observer.create({
  type: 'touch',
  tolerance: 50,        // minimum distance for swipe
  dragMinimum: 10,
  onLeft: () => {
    // Swipe left → next slide
    goToSlide(currentSlide + 1);
  },
  onRight: () => {
    // Swipe right → prev slide
    goToSlide(currentSlide - 1);
  },
  onUp: () => {
    // Swipe up → scroll to next section
    goToSection(currentSection + 1);
  },
  preventDefault: true,
});
```

### Observer vs ScrollTrigger

| Use Case | Observer | ScrollTrigger |
|----------|----------|---------------|
| Scroll-linked animation (scrub) | No | Yes |
| Direction detection | Yes | Via onUpdate |
| Scroll hijacking | Yes | Via pin |
| Touch/pointer events | Yes | No |
| Velocity access | Yes (callbacks) | Yes (getVelocity) |
| Section snapping | Yes (manual) | Yes (snap) |

**Rule of thumb:** Use ScrollTrigger when animation should scrub with
scroll position. Use Observer when you need to intercept events and
implement custom behavior.

### Combining Observer + ScrollTrigger

```javascript
// Free scroll sections use ScrollTrigger
gsap.to('.parallax-bg', {
  y: -200,
  scrollTrigger: { trigger: '.section-1', scrub: 1 },
});

// Hijacked section uses Observer
const hijackSection = document.querySelector('.hijack-section');
let hijackActive = false;

ScrollTrigger.create({
  trigger: hijackSection,
  start: 'top top',
  end: 'bottom bottom',
  onEnter: () => { hijackActive = true; },
  onLeave: () => { hijackActive = false; },
  onEnterBack: () => { hijackActive = true; },
  onLeaveBack: () => { hijackActive = false; },
});

Observer.create({
  type: 'wheel,touch',
  onChange: (self) => {
    if (!hijackActive) return;
    // Custom behavior only in the hijacked section
    handleCustomScroll(self.deltaY);
  },
});
```

---

## Quick Reference

| Pattern | Best Tool | Key Config |
|---------|-----------|-----------|
| Smooth scroll | ScrollSmoother or Lenis | smooth, effects |
| Parallax layers | ScrollSmoother (`data-speed`) or ScrollTrigger (scrub) | data-speed, scrub |
| Full-page snapping | Observer | type, tolerance, onUp/onDown |
| Horizontal scroll | ScrollTrigger (pin + xPercent) | pin, scrub |
| Swipe detection | Observer | type: 'touch', tolerance |
| Velocity carousel | Observer (onDrag + onDragEnd) | dragMinimum |
| Scroll hijack zones | Observer + ScrollTrigger | Combined |
