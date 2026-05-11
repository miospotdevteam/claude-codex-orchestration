# GSAP Value Plugins — InertiaPlugin, Modifiers, Snap, roundProps

Plugins that control how property values behave during tweens: momentum
deceleration, per-frame interception, live snapping, and integer rounding.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.
> Modifiers, Snap, and roundProps are **core plugins** — no import or
> registration needed. InertiaPlugin requires import + registration.

---

## 1. InertiaPlugin — Momentum Deceleration

Smoothly glide any property to a stop, honoring initial velocity. Perfect
for flick-scrolling, throw effects, and custom drag interactions outside
of Draggable.

```javascript
import { InertiaPlugin } from 'gsap/InertiaPlugin';
gsap.registerPlugin(InertiaPlugin);
```

### Basic Usage

```javascript
// Glide with initial velocity
gsap.to(obj, {
  inertia: {
    x: 500,     // 500 px/sec initial velocity
    y: -300,    // -300 px/sec (upward)
  },
});
// Duration is auto-calculated based on velocity + resistance
```

### With Boundaries and Snapping

```javascript
gsap.to(obj, {
  inertia: {
    x: {
      velocity: 500,
      min: 0,              // can't end below 0
      max: 1024,           // can't end above 1024
      end: [0, 256, 512, 768, 1024], // snap to nearest value
    },
    y: {
      velocity: -300,
      min: 0,
      max: 720,
      end: (value) => Math.round(value / 100) * 100, // snap to 100s
    },
  },
});
```

### Configuration Properties

| Property | Type | Description |
|----------|------|-------------|
| `velocity` | Number / `'auto'` | Initial speed in units/sec. `'auto'` uses tracked velocity |
| `min` | Number | Minimum boundary for final resting position |
| `max` | Number | Maximum boundary for final resting position |
| `end` | Number / Array / Function | Landing spot: exact value, snap-to array, or custom function |
| `resistance` | Number | Friction per second (higher = faster stop, default ~1000) |
| `linkedProps` | String | Comma-delimited props passed together to function-based `end` |

### Duration Control

```javascript
gsap.to(obj, {
  inertia: { x: 500 },
  duration: { min: 0.5, max: 3 }, // constrain auto-calculated duration
});

// Or fixed duration (overrides auto-calculation)
gsap.to(obj, {
  inertia: { x: 500 },
  duration: 1.5,
});
```

### Velocity Tracking (Standalone)

Track property velocity over time, then use it in a tween. This is how
InertiaPlugin works independently of Draggable.

```javascript
// 1. Start tracking (do this early — needs ~100ms of data)
InertiaPlugin.track(myObject, 'x,y');

// 2. Update the properties however you want (mousemove, etc.)
document.addEventListener('mousemove', (e) => {
  myObject.x = e.clientX;
  myObject.y = e.clientY;
});

// 3. Later: tween using tracked velocity
document.addEventListener('mouseup', () => {
  gsap.to(myObject, {
    inertia: {
      x: 'auto',   // uses tracked velocity automatically
      y: 'auto',
    },
  });
});

// 4. Check velocity at any time
const vx = InertiaPlugin.getVelocity(myObject, 'x'); // px/sec

// 5. Stop tracking when done
InertiaPlugin.untrack(myObject);
```

### Static Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `InertiaPlugin.track(target, props)` | Array | Start velocity tracking for comma-delimited props |
| `InertiaPlugin.untrack(target, props?)` | void | Stop tracking (all props if none specified) |
| `InertiaPlugin.getVelocity(target, prop)` | Number | Current velocity in units/sec |
| `InertiaPlugin.isTracking(target, prop?)` | Boolean | Whether tracking is active |

### linkedProps — Coupled Snapping

When x and y need to snap together (e.g., to grid intersections):

```javascript
gsap.to(obj, {
  inertia: {
    x: { velocity: 300, end: snapToGrid },
    y: { velocity: -200, end: snapToGrid },
    linkedProps: 'x,y', // both passed to end function as object
  },
});

function snapToGrid(endValues) {
  // endValues = { x: naturalLandingX, y: naturalLandingY }
  return {
    x: Math.round(endValues.x / 100) * 100,
    y: Math.round(endValues.y / 100) * 100,
  };
}
```

### Custom Flick-to-Dismiss

```javascript
const card = document.querySelector('.card');

// Track card position
InertiaPlugin.track(card, 'x,y');

// On drag end, flick with momentum
function onDragEnd() {
  const vx = InertiaPlugin.getVelocity(card, 'x');

  if (Math.abs(vx) > 500) {
    // Fast flick — dismiss
    gsap.to(card, {
      inertia: { x: 'auto' },
      opacity: 0,
      onComplete: () => card.remove(),
    });
  } else {
    // Slow — snap back
    gsap.to(card, { x: 0, duration: 0.5, ease: 'back.out(1.7)' });
  }
}
```

---

## 2. Modifiers — Per-Frame Value Interception

Intercept the value GSAP would apply on each tick and transform it with
custom logic. Built into GSAP core — no import needed.

### How It Works

```javascript
gsap.to('.box', {
  x: 500,
  duration: 2,
  modifiers: {
    x: (value, target) => {
      // value: what GSAP calculated for this frame (number)
      // target: the animated element
      // Return: the value GSAP should actually apply
      return Math.round(value / 50) * 50; // snap to 50px grid
    },
  },
});
```

### Infinite Carousel (The Killer Use Case)

Wrap values so elements seamlessly loop without resetting:

```javascript
const items = gsap.utils.toArray('.carousel-item');
const totalWidth = items.length * itemWidth;

gsap.to(items, {
  x: `-=${totalWidth}`,
  duration: 20,
  ease: 'none',
  repeat: -1,
  modifiers: {
    x: gsap.utils.unitize(
      gsap.utils.wrap(-itemWidth, totalWidth - itemWidth)
    ),
  },
});
```

Each item's x is wrapped so when it goes off-screen left, it appears on
the right. One tween, infinite seamless loop.

### Clamping Values

```javascript
gsap.to('.slider', {
  x: 1000,
  modifiers: {
    x: (value) => gsap.utils.clamp(0, 500, parseFloat(value)),
  },
});
```

### Snap Rotation to 45-Degree Increments

```javascript
gsap.to('.dial', {
  rotation: 360,
  duration: 2,
  modifiers: {
    rotation: (value) => Math.round(value / 45) * 45,
  },
});
```

### Cross-Property Logic

```javascript
gsap.to('.ball', {
  x: 500,
  duration: 2,
  modifiers: {
    // Make y follow a sine wave based on x position
    y: (value, target) => {
      const x = gsap.getProperty(target, 'x');
      return Math.sin(x * 0.02) * 100;
    },
  },
});
```

### Caveats

- Use `scaleX` / `scaleY`, not `scale` (scale is a shortcut)
- Use `rotation`, not `rotationZ`
- Cannot combine `roundProps` or `snap` with `modifiers` on the same
  property — they share the same mechanism internally. Put the rounding
  or snapping logic inside the modifier function instead.

---

## 3. Snap (Core Plugin) — Live Value Snapping

Snap property values to increments, arrays, or radius-constrained values
during the tween. Built into GSAP core — no import needed.

Different from `gsap.utils.snap()` (a standalone utility function). This
is a tween-level property that applies snapping to every frame.

### Snap to Whole Numbers

```javascript
gsap.to('.counter', {
  x: 1000,
  y: 250,
  snap: 'x,y', // snap both to nearest integer
});
```

### Snap to Increment

```javascript
gsap.to('.grid-item', {
  x: 1000,
  snap: {
    x: 20, // snap to nearest multiple of 20 (0, 20, 40, 60...)
  },
});
```

### Snap to Array Values

```javascript
gsap.to('.slider', {
  x: 1000,
  snap: {
    x: [0, 100, 250, 500, 750, 1000], // snap to nearest value
  },
});
```

### Snap with Radius (Magnetic Snap)

Only snap when within a certain distance of a snap value:

```javascript
gsap.to('.element', {
  x: 1000,
  snap: {
    x: {
      values: [0, 250, 500, 750, 1000],
      radius: 30, // only snap within 30px of a value
    },
  },
});
```

### Multiple Properties

```javascript
gsap.to('.box', {
  x: 500,
  y: 300,
  rotation: 360,
  snap: {
    x: 50,                          // snap x to 50px grid
    y: [0, 100, 200, 300],          // snap y to specific values
    rotation: 90,                    // snap rotation to 90-degree increments
  },
});
```

### Snap vs gsap.utils.snap()

| | `snap` (tween property) | `gsap.utils.snap()` |
|---|---|---|
| When | Every frame during tween | Standalone utility function |
| Where | Inside a tween config | Anywhere in code |
| How | Automatic, per-property | Manual, returns a function |
| Use for | Snappy tween behavior | Snapping in callbacks, events, render loops |

---

## 4. roundProps — Integer Rounding

Round specific properties to the nearest integer on every frame. Built
into GSAP core — no import needed.

### Basic Usage

```javascript
// Round x and y to integers (pixel-perfect positioning)
gsap.to('.element', {
  x: 300.7,
  y: 150.3,
  opacity: 0.5,
  roundProps: 'x,y', // only x and y get rounded, opacity stays fractional
});
```

### Counter Animation (Whole Numbers)

```javascript
const counter = { value: 0 };
gsap.to(counter, {
  value: 1000,
  duration: 2,
  roundProps: 'value',
  onUpdate: () => {
    document.querySelector('.counter').textContent = counter.value;
  },
});
```

### When to Use roundProps vs Snap vs Modifiers

| Need | Use |
|------|-----|
| Round to integer | `roundProps: 'x,y'` |
| Snap to specific increment (10, 25, etc.) | `snap: { x: 10 }` |
| Snap to specific values (array) | `snap: { x: [0, 50, 100] }` |
| Custom per-frame logic (wrap, clamp, cross-property) | `modifiers: { x: fn }` |
| Combine rounding + custom logic | Use `modifiers` with `Math.round()` inside |

**Cannot combine:** `roundProps`, `snap`, and `modifiers` on the same
property — they share the same internal mechanism. If you need rounding
plus custom logic, put `Math.round()` inside your modifier function.

---

## Quick Reference

| Plugin | Core? | Registration | Use Case |
|--------|-------|-------------|----------|
| **InertiaPlugin** | No | `gsap.registerPlugin(InertiaPlugin)` | Momentum, throw, flick-to-stop |
| **Modifiers** | Yes | None needed | Per-frame value transform, infinite loops, wrapping |
| **Snap** | Yes | None needed | Live snapping to grids, arrays, or radius |
| **roundProps** | Yes | None needed | Integer rounding for pixel-perfect or counters |

### Import Reference

```javascript
// InertiaPlugin (only one that needs import)
import { InertiaPlugin } from 'gsap/InertiaPlugin';
gsap.registerPlugin(InertiaPlugin);

// Modifiers, Snap, roundProps — just use them, they're built in
gsap.to('.el', {
  x: 500,
  modifiers: { x: (v) => gsap.utils.wrap(0, 500, parseFloat(v)) },
  snap: { y: 50 },
  roundProps: 'rotation',
});
```
