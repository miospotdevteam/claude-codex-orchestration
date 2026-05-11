# GSAP ScrollToPlugin

Animated scrolling to positions, elements, or maximum scroll. Use for nav
links, scroll-to-section, back-to-top buttons, and programmatic scroll
within containers.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## Import & Register

```javascript
import { ScrollToPlugin } from 'gsap/ScrollToPlugin';
gsap.registerPlugin(ScrollToPlugin);
```

---

## 1. Basic Usage

### Scroll Window to Pixel Position

```javascript
// Scroll to 400px from top
gsap.to(window, { duration: 2, scrollTo: 400 });
```

### Scroll Window to Element

```javascript
// Scroll to bring element into view
gsap.to(window, { duration: 2, scrollTo: '#section-3' });

// With easing
gsap.to(window, { duration: 1.5, scrollTo: '#contact', ease: 'power2.inOut' });
```

### Scroll to Maximum

```javascript
// Scroll to bottom of page
gsap.to(window, { duration: 2, scrollTo: 'max' });
```

### Scroll Within a Container

For scrollable containers (`overflow: scroll` or `overflow: auto`):

```javascript
// Scroll a div to a position
gsap.to('#scroll-container', { duration: 1, scrollTo: 250 });

// Scroll a div to an element inside it
gsap.to('#scroll-container', { duration: 1, scrollTo: '#item-5' });
```

---

## 2. Configuration Object

For more control, pass an object instead of a simple value:

```javascript
gsap.to(window, {
  duration: 2,
  scrollTo: {
    y: '#target-section',    // vertical target (px, element, or 'max')
    x: 0,                    // horizontal target
    offsetY: 80,             // offset from target (e.g., for fixed header)
    offsetX: 0,              // horizontal offset
    autoKill: true,          // cancel if user scrolls manually
    onAutoKill: () => {
      console.log('Scroll animation cancelled by user');
    },
  },
  ease: 'power2.inOut',
});
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `y` | Number/String | — | Vertical scroll target (px, selector, or `'max'`) |
| `x` | Number/String | — | Horizontal scroll target |
| `offsetY` | Number | `0` | Pixel offset from vertical target (positive = gap above) |
| `offsetX` | Number | `0` | Pixel offset from horizontal target |
| `autoKill` | Boolean | `false` | Cancel tween if scroll position changes externally |
| `onAutoKill` | Function | — | Callback when autoKill triggers |

---

## 3. Common Patterns

### Nav Links (Smooth Scroll to Sections)

```javascript
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', (e) => {
    e.preventDefault();
    const target = link.getAttribute('href');

    gsap.to(window, {
      duration: 1,
      scrollTo: {
        y: target,
        offsetY: 80,        // account for fixed header
        autoKill: true,      // respect manual scroll
      },
      ease: 'power2.inOut',
    });
  });
});
```

### Back-to-Top Button

```javascript
document.querySelector('#back-to-top').addEventListener('click', () => {
  gsap.to(window, {
    duration: 1.5,
    scrollTo: { y: 0 },
    ease: 'power3.inOut',
  });
});
```

### Horizontal + Vertical Simultaneous Scroll

```javascript
gsap.to('#scroll-container', {
  duration: 2,
  scrollTo: { x: 400, y: 200 },
  ease: 'power2.out',
});
```

### Scroll on Page Load (After Hash)

```javascript
// If URL has a hash, smooth scroll to it after page loads
window.addEventListener('load', () => {
  if (window.location.hash) {
    gsap.to(window, {
      duration: 1,
      scrollTo: {
        y: window.location.hash,
        offsetY: 80,
      },
      ease: 'power2.inOut',
      delay: 0.3, // wait for layout
    });
  }
});
```

### Timeline Integration

```javascript
const tl = gsap.timeline();

tl.to(window, { scrollTo: '#section-1', duration: 1 })
  .to(window, { scrollTo: '#section-2', duration: 1 }, '+=1')
  .to(window, { scrollTo: '#section-3', duration: 1 }, '+=1');
```

---

## 4. Global Configuration

```javascript
// Set autoKill globally for all ScrollTo tweens
ScrollToPlugin.config({ autoKill: true });
```

---

## 5. Gotchas

### CSS scroll-behavior Conflicts

```css
/* REMOVE this if using ScrollToPlugin — it fights for control */
html {
  scroll-behavior: smooth; /* conflicts with GSAP! */
}
```

### Lenis / ScrollSmoother Interaction

If using Lenis or ScrollSmoother for smooth scrolling, prefer their native
`.scrollTo()` methods instead of ScrollToPlugin — they understand the
smooth scroll offset:

```javascript
// With Lenis — use Lenis API, not ScrollToPlugin
lenis.scrollTo('#section-3', { offset: -80, duration: 1.5 });

// With ScrollSmoother
smoother.scrollTo('#section-3', true, 'top 80px');
```

ScrollToPlugin works with native scroll position, which can desync from
smooth scroll libraries. Use it for:
- Projects without Lenis/ScrollSmoother
- Scrolling within containers (not the main page)
- Simple anchor link scrolling

### Don't Confuse with ScrollTrigger

| Plugin | Purpose |
|--------|---------|
| **ScrollToPlugin** | Animate *to* a scroll position (user navigation) |
| **ScrollTrigger** | Trigger animations *based on* scroll position (scroll-driven effects) |

They complement each other but serve different purposes.

---

## Quick Reference

| Usage | Code |
|-------|------|
| Scroll to px | `gsap.to(window, { scrollTo: 400 })` |
| Scroll to element | `gsap.to(window, { scrollTo: '#id' })` |
| Scroll to bottom | `gsap.to(window, { scrollTo: 'max' })` |
| With offset | `gsap.to(window, { scrollTo: { y: '#id', offsetY: 80 } })` |
| Auto-cancel | `gsap.to(window, { scrollTo: { y: '#id', autoKill: true } })` |
| Container scroll | `gsap.to('#div', { scrollTo: { y: 300, x: 200 } })` |
| Global config | `ScrollToPlugin.config({ autoKill: true })` |
