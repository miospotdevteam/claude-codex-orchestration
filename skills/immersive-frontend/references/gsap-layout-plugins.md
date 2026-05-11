# GSAP Layout Plugins — Flip, Draggable, Observer

Comprehensive patterns for GSAP's layout-oriented plugins: Flip (FLIP-technique
layout animations), Draggable (drag & drop with physics), and Observer (unified
scroll/touch/pointer event handling).

GSAP is 100% free — all plugins included with `bun add gsap`.

---

## 1. Flip — Layout Animation (FLIP Technique)

The Flip plugin animates between DOM states using the "First, Last, Invert,
Play" technique. Record element positions, make DOM changes, then animate the
difference.

### Import & Register

```typescript
import gsap from 'gsap';
import { Flip } from 'gsap/Flip';

gsap.registerPlugin(Flip);
```

### Core Flow

Every Flip animation follows three steps:

```typescript
// 1. Capture current state
const state = Flip.getState('.targets');

// 2. Make DOM changes (reparent, reclass, reorder, show/hide)
element.classList.toggle('expanded');

// 3. Animate from old state to new layout
Flip.from(state, {
  duration: 0.8,
  ease: 'power2.inOut',
});
```

### Flip.getState()

Captures position, size, rotation, skew, and opacity of target elements.

```typescript
// Basic — capture all matching elements
const state = Flip.getState('.card');

// Capture additional CSS properties beyond defaults
const state = Flip.getState('.card', {
  props: 'backgroundColor,color,borderRadius',
});

// Simple mode — skip rotation/skew calculations for performance
const state = Flip.getState('.card', { simple: true });

// Nested — when animating both parent and child elements
const state = Flip.getState(['.container', '.container .item'], {
  nested: true,
});
```

**Options:**

| Option   | Type    | Description                                                |
| -------- | ------- | ---------------------------------------------------------- |
| `props`  | String  | Comma-delimited camelCased CSS properties to also capture  |
| `simple` | Boolean | Skip rotation/skew calculations (faster for simple layouts)|
| `nested` | Boolean | Prevent offset compounding for parent-child elements       |

### Flip.from()

Animates elements from their captured state to their current DOM position.
Returns a GSAP Timeline for chaining.

```typescript
Flip.from(state, {
  duration: 0.8,
  ease: 'power2.inOut',
  stagger: 0.05,
  absolute: true,     // position: absolute during animation (prevents layout shift)
  scale: true,         // use scaleX/scaleY instead of width/height (GPU-accelerated)
  nested: true,        // match getState nested option
  onEnter: (elements) => {
    // Animate newly added elements
    gsap.fromTo(elements, { opacity: 0, scale: 0 }, { opacity: 1, scale: 1, duration: 0.5 });
  },
  onLeave: (elements) => {
    // Animate removed elements
    gsap.to(elements, { opacity: 0, scale: 0, duration: 0.3 });
  },
});
```

**Full Options:**

| Option             | Type                       | Description                                                  |
| ------------------ | -------------------------- | ------------------------------------------------------------ |
| `duration`         | Number                     | Animation length in seconds                                  |
| `ease`             | String                     | Easing function (e.g., `"power2.inOut"`)                     |
| `stagger`          | Number/Object              | Delay between element animations                             |
| `absolute`         | Boolean/String/Element     | Apply `position: absolute` during animation                  |
| `absoluteOnLeave`  | Boolean                    | Set leaving elements to `position: absolute`                 |
| `scale`            | Boolean                    | Use scaleX/scaleY instead of width/height (GPU-optimized)    |
| `nested`           | Boolean                    | Prevent offset compounding for parent-child                  |
| `onEnter`          | Function                   | Callback for elements entering; receives element array       |
| `onLeave`          | Function                   | Callback for elements leaving; receives element array        |
| `toggleClass`      | String                     | CSS class applied during animation, removed after            |
| `zIndex`           | Number                     | Set z-index for animation duration                           |
| `fade`             | Boolean                    | Cross-fade when swapping elements with matching data-flip-id |
| `spin`             | Boolean/Number/Function    | Add rotation; `true` = 360deg, number = turns                |
| `targets`          | String/Element/Array       | Animate subset of captured state                             |
| `prune`            | Boolean                    | Remove non-animating targets (conserves resources)           |
| `props`            | String                     | Limit animation to specific captured properties              |
| `simple`           | Boolean                    | Skip rotation/scale/skew calculations                        |

### Flip.to()

Inverse of `Flip.from()` — animates FROM current state TO captured state.

```typescript
const state = Flip.getState('.card');
// ... DOM changes happen later ...
Flip.to(state, { duration: 0.6, ease: 'power1.inOut' });
```

### Flip.fit()

Repositions/resizes one element to match another element's dimensions and
position. Useful for fitting thumbnails to detail views.

```typescript
// Fit element A to match element B's position/size
Flip.fit(elementA, elementB);

// With options
Flip.fit(elementA, elementB, {
  scale: true,      // use scale transforms instead of width/height
  duration: 0.5,    // animate the fit
  ease: 'power2.out',
});

// Fit to a previously captured state
const state = Flip.getState(elementA);
// ... DOM changes ...
Flip.fit(elementA, state);
```

### data-flip-id — Tracking Elements Across Parents

When elements move between containers, Flip uses `data-flip-id` to correlate
elements between states. Without it, Flip auto-assigns IDs.

```html
<!-- Elements can be reparented and Flip tracks them by data-flip-id -->
<div class="grid">
  <div class="card" data-flip-id="project-1">Project 1</div>
  <div class="card" data-flip-id="project-2">Project 2</div>
</div>

<div class="detail-view">
  <!-- Card moves here when clicked -->
</div>
```

```typescript
const state = Flip.getState('[data-flip-id]');

// Reparent element
detailView.appendChild(card);

Flip.from(state, {
  duration: 0.6,
  ease: 'power2.inOut',
  absolute: true,
});
```

### Flip.batch()

Coordinates multiple Flip animations across components without
cross-contamination:

```typescript
const batch = Flip.batch('my-batch');
batch.state(() => Flip.getState('.items'));
batch.run(() => {
  // DOM changes
  container.classList.toggle('layout-b');
});
```

### Other Utility Methods

```typescript
// Check if an element is currently being flipped
Flip.isFlipping(target); // returns boolean

// Kill active Flip animation on targets
Flip.killFlipsOf(targets, complete); // complete: jump to end?

// Convert elements to position: absolute while preserving visual position
Flip.makeAbsolute(targets);
```

### Example: Filtering Grid (Show/Hide Categories)

```typescript
const buttons = document.querySelectorAll('.filter-btn');
const items = document.querySelectorAll('.grid-item');

buttons.forEach((btn) => {
  btn.addEventListener('click', () => {
    const filter = btn.dataset.filter;

    // 1. Capture state of ALL items (including those about to hide)
    const state = Flip.getState(items);

    // 2. Toggle visibility based on filter
    items.forEach((item) => {
      if (filter === 'all' || item.dataset.category === filter) {
        item.classList.remove('hidden');
      } else {
        item.classList.add('hidden');
      }
    });

    // 3. Animate the layout change
    Flip.from(state, {
      duration: 0.6,
      ease: 'power2.inOut',
      scale: true,
      absolute: true,
      stagger: 0.04,
      onEnter: (elements) => {
        gsap.fromTo(
          elements,
          { opacity: 0, scale: 0.8 },
          { opacity: 1, scale: 1, duration: 0.4 }
        );
      },
      onLeave: (elements) => {
        return gsap.to(elements, {
          opacity: 0,
          scale: 0.8,
          duration: 0.3,
        });
      },
    });
  });
});
```

CSS for hidden items:
```css
.grid {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
}

.grid-item.hidden {
  display: none;
}
```

### Example: Card Expand to Detail View

```typescript
function expandCard(card: HTMLElement) {
  const state = Flip.getState(card);

  // Move card to overlay container and add expanded class
  document.querySelector('.overlay')!.appendChild(card);
  card.classList.add('expanded');

  Flip.from(state, {
    duration: 0.6,
    ease: 'power2.inOut',
    scale: true,
    absolute: true,
    onComplete: () => {
      // Enable detail content after animation
      card.querySelector('.detail-content')!.classList.add('visible');
    },
  });
}

function collapseCard(card: HTMLElement, originalParent: HTMLElement) {
  const state = Flip.getState(card);

  card.classList.remove('expanded');
  card.querySelector('.detail-content')!.classList.remove('visible');
  originalParent.appendChild(card);

  Flip.from(state, {
    duration: 0.5,
    ease: 'power2.inOut',
    scale: true,
    absolute: true,
  });
}
```

### Example: Shared Layout Animation Between Routes

In a Next.js App Router context, use `data-flip-id` to animate elements across
page transitions:

```typescript
'use client';

import { useRef, useLayoutEffect } from 'react';
import gsap from 'gsap';
import { Flip } from 'gsap/Flip';
import { usePathname } from 'next/navigation';

gsap.registerPlugin(Flip);

export function SharedLayoutProvider({ children }: { children: React.ReactNode }) {
  const stateRef = useRef<Flip.FlipState | null>(null);
  const pathname = usePathname();

  useLayoutEffect(() => {
    if (stateRef.current) {
      // Animate from previous state to new layout
      const targets = document.querySelectorAll('[data-flip-id]');
      if (targets.length > 0) {
        Flip.from(stateRef.current, {
          duration: 0.5,
          ease: 'power2.inOut',
          scale: true,
          absolute: true,
          targets,
        });
      }
    }

    // Capture state before next route change
    return () => {
      stateRef.current = Flip.getState('[data-flip-id]');
    };
  }, [pathname]);

  return <>{children}</>;
}
```

### Important Caveats

- No 3D transform support (no rotationX, rotationY, z)
- Use `box-sizing: border-box` for accurate size calculations
- In React/Next.js, you may need `requestAnimationFrame()` before `Flip.from()`
  to ensure the DOM has updated
- Always specify `targets` in framework environments to reference new instances
- In-progress flips are not responsive to viewport changes

---

## 2. Draggable — Drag & Drop with Physics

Makes any DOM element draggable with support for bounds, snapping, inertia
(momentum), rotation, and collision detection. Works on desktop and touch.

### Import & Register

```typescript
import gsap from 'gsap';
import { Draggable } from 'gsap/Draggable';

gsap.registerPlugin(Draggable);
```

### Basic Usage

```typescript
// Simple horizontal drag
Draggable.create('#slider-handle', { type: 'x' });

// Free drag in both directions
Draggable.create('.draggable-card', { type: 'x,y' });

// Rotation drag (e.g., knob control)
Draggable.create('#dial', { type: 'rotation' });
```

### Type Parameter

Controls which CSS properties are affected by dragging:

| Type            | Description                              |
| --------------- | ---------------------------------------- |
| `'x,y'`        | Transform translateX/Y (default, GPU)    |
| `'x'`          | Horizontal only (transform)              |
| `'y'`          | Vertical only (transform)                |
| `'left,top'`   | CSS left/top positioning                 |
| `'left'`       | Horizontal only (CSS)                    |
| `'top'`        | Vertical only (CSS)                      |
| `'rotation'`   | Rotation transform                       |
| `'scroll'`     | ScrollTop of container                   |
| `'scrollTop'`  | ScrollTop only                           |
| `'scrollLeft'` | ScrollLeft only                          |

Prefer `'x,y'` over `'left,top'` for GPU-accelerated transforms.

### Bounds

Restrict draggable area with multiple constraint formats:

```typescript
// Constrain to a parent element
Draggable.create('.item', {
  type: 'x,y',
  bounds: '#container',
});

// Constrain to parent element
Draggable.create('.item', {
  type: 'x,y',
  bounds: document.querySelector('.item')!.parentElement!,
});

// Pixel-based bounds
Draggable.create('.item', {
  type: 'x,y',
  bounds: { minX: 0, maxX: 500, minY: 0, maxY: 300 },
});

// Rect-style bounds
Draggable.create('.item', {
  type: 'x,y',
  bounds: { top: 0, left: 0, width: 800, height: 600 },
});

// Update bounds dynamically
const [draggable] = Draggable.create('.item', { type: 'x,y', bounds: '#container' });
window.addEventListener('resize', () => draggable.applyBounds('#container'));
```

### Inertia (Momentum / Throw Physics)

Requires the InertiaPlugin (included free with GSAP). Elements continue moving
after release with natural deceleration.

```typescript
// Basic momentum
Draggable.create('.card', {
  type: 'x,y',
  inertia: true,
});

// Advanced inertia config
Draggable.create('.card', {
  type: 'x,y',
  inertia: true,
  throwResistance: 1500,       // higher = more friction (default ~1000)
  maxDuration: 5,               // max coast time in seconds
  minDuration: 0.2,             // min coast time
  overshootTolerance: 0.5,      // how far past snap points (0-1)
  snap: {
    x: (value) => Math.round(value / 100) * 100, // snap to 100px grid
    y: (value) => Math.round(value / 100) * 100,
  },
  onThrowUpdate: function () {
    console.log('coasting:', this.x, this.y);
  },
  onThrowComplete: function () {
    console.log('settled at:', this.x, this.y);
  },
});
```

### Snap — Grid, Points, and Functions

#### Live Snap (During Drag)

```typescript
// Snap to a grid while dragging
Draggable.create('.item', {
  type: 'x,y',
  liveSnap: {
    x: (value) => Math.round(value / 50) * 50,
    y: (value) => Math.round(value / 50) * 50,
  },
});

// Snap to specific values
Draggable.create('.item', {
  type: 'x',
  liveSnap: [0, 100, 200, 300, 400],
});

// Snap to nearest point
Draggable.create('.item', {
  type: 'x,y',
  liveSnap: {
    points: [
      { x: 0, y: 0 },
      { x: 200, y: 0 },
      { x: 400, y: 0 },
      { x: 0, y: 200 },
      { x: 200, y: 200 },
      { x: 400, y: 200 },
    ],
    radius: 30, // snap radius in pixels
  },
});
```

#### Release Snap (After Throwing)

```typescript
// Snap to grid after throw with inertia
Draggable.create('.item', {
  type: 'x,y',
  inertia: true,
  snap: {
    x: (value) => Math.round(value / 150) * 150,
    y: (value) => Math.round(value / 150) * 150,
  },
});

// Snap rotation to 90-degree increments
Draggable.create('#dial', {
  type: 'rotation',
  inertia: true,
  snap: (value) => Math.round(value / 90) * 90,
});
```

### Callbacks

All callbacks receive the pointer event. Inside callbacks, `this` refers to the
Draggable instance.

```typescript
Draggable.create('.item', {
  type: 'x,y',
  onPress: function (event) {
    // Mouse/touch down on element
    console.log('pressed', this.target);
  },
  onPressInit: function (event) {
    // Before starting values recorded (fires before onPress)
  },
  onDragStart: function (event) {
    // Movement exceeds minimumMovement threshold
    gsap.to(this.target, { scale: 1.1, duration: 0.2 });
  },
  onDrag: function (event) {
    // During drag (once per rAF)
    console.log('position:', this.x, this.y);
    console.log('delta:', this.deltaX, this.deltaY);
  },
  onDragEnd: function (event) {
    // Released after dragging
    gsap.to(this.target, { scale: 1, duration: 0.3, ease: 'back.out(1.7)' });
  },
  onRelease: function (event) {
    // Released (fires even if no drag occurred)
  },
  onClick: function (event) {
    // Released within minimumMovement — not a drag, a click
  },
  onLockAxis: function () {
    // Axis determined when lockAxis: true
    console.log('locked to:', this.lockedAxis); // "x" or "y"
  },
});
```

### hitTest() — Collision Detection

Detect overlap between draggable elements and targets:

```typescript
Draggable.create('.draggable', {
  type: 'x,y',
  onDrag: function () {
    const dropZones = document.querySelectorAll('.drop-zone');
    dropZones.forEach((zone) => {
      if (Draggable.hitTest(this.target, zone, '50%')) {
        zone.classList.add('active');
      } else {
        zone.classList.remove('active');
      }
    });
  },
  onDragEnd: function () {
    const dropZones = document.querySelectorAll('.drop-zone');
    dropZones.forEach((zone) => {
      if (Draggable.hitTest(this.target, zone, '50%')) {
        // Dropped on zone — handle it
        handleDrop(this.target, zone);
      }
      zone.classList.remove('active');
    });
  },
});
```

Threshold formats:
- `'50%'` — 50% overlap required
- `0.5` — same as 50%
- `20` — 20px overlap required

### Auto-Scroll Near Edges

Automatically scroll the container when dragging near its edges:

```typescript
Draggable.create('.item', {
  type: 'x,y',
  bounds: '#scroll-container',
  autoScroll: 1,    // normal speed (higher = faster)
  // autoScroll: 2  // double speed
});
```

### Instance Properties

```typescript
const [draggable] = Draggable.create('.item', { type: 'x,y' });

draggable.x;              // current x position
draggable.y;              // current y position
draggable.rotation;       // current rotation
draggable.startX;         // position when drag started
draggable.startY;
draggable.deltaX;         // change since last event
draggable.deltaY;
draggable.endX;           // predicted landing position (with inertia)
draggable.endY;
draggable.pointerX;       // current pointer position
draggable.pointerY;
draggable.isPressed;      // boolean
draggable.isDragging;     // boolean (alias for checking state)
draggable.isThrowing;     // boolean (coasting after release)
draggable.lockedAxis;     // "x" or "y" when lockAxis enabled
draggable.target;         // the DOM element
draggable.tween;          // InertiaPlugin tween instance
```

### Instance Methods

```typescript
draggable.enable();            // re-enable dragging
draggable.disable();           // disable (preserves position)
draggable.kill();              // destroy completely
draggable.startDrag(event);    // programmatically start drag
draggable.endDrag(event);      // programmatically end drag
draggable.applyBounds(bounds); // update bounds dynamically
draggable.update();            // refresh cached position values
draggable.getDirection('start'); // "left", "right", "up", "down"

// Retrieve instance for an element
const existing = Draggable.get(element);
```

### Configuration Options Reference

| Option                      | Type             | Default | Description                                    |
| --------------------------- | ---------------- | ------- | ---------------------------------------------- |
| `type`                      | String           | `"x,y"` | Properties to drag                             |
| `bounds`                    | String/Element/Object | —  | Constraint area                                |
| `inertia`                   | Boolean          | `false` | Enable momentum after release                  |
| `lockAxis`                  | Boolean          | `false` | Lock to first-detected axis                    |
| `minimumMovement`           | Number           | `3`     | Pixels before interpreting as drag             |
| `dragResistance`            | Number           | `0`     | Friction while dragging (0-1)                  |
| `edgeResistance`            | Number           | `0.5`   | Friction beyond bounds (0-1)                   |
| `cursor`                    | String           | `"move"`| CSS cursor                                     |
| `activeCursor`              | String           | —       | Cursor during drag                             |
| `zIndexBoost`               | Boolean          | `true`  | Auto-raise z-index on press                    |
| `trigger`                   | String/Element   | —       | Handle element that initiates drag             |
| `dragClickables`            | Boolean          | `true`  | Allow dragging on buttons/links                |
| `allowContextMenu`          | Boolean          | `false` | Allow right-click                              |
| `allowNativeTouchScrolling` | Boolean          | `true`  | Native scroll perpendicular to drag axis       |
| `autoScroll`                | Number           | `0`     | Auto-scroll speed near edges                   |
| `force3D`                   | Boolean          | `true`  | GPU acceleration                               |

### Example: Draggable Slider/Carousel

```typescript
function createDraggableSlider(containerSelector: string, slideWidth: number) {
  const container = document.querySelector(containerSelector) as HTMLElement;
  const track = container.querySelector('.slider-track') as HTMLElement;
  const slides = track.querySelectorAll('.slide');
  const totalSlides = slides.length;
  let currentIndex = 0;

  const [draggable] = Draggable.create(track, {
    type: 'x',
    bounds: {
      minX: -(totalSlides - 1) * slideWidth,
      maxX: 0,
    },
    inertia: true,
    snap: (value) => {
      // Snap to nearest slide
      const index = Math.round(-value / slideWidth);
      currentIndex = Math.max(0, Math.min(index, totalSlides - 1));
      return -currentIndex * slideWidth;
    },
    edgeResistance: 0.85,
    dragResistance: 0.1,
    onDragEnd: function () {
      updateIndicators(currentIndex);
    },
    onThrowComplete: function () {
      updateIndicators(currentIndex);
    },
  });

  function goToSlide(index: number) {
    currentIndex = Math.max(0, Math.min(index, totalSlides - 1));
    gsap.to(track, {
      x: -currentIndex * slideWidth,
      duration: 0.5,
      ease: 'power2.out',
      onComplete: () => draggable.update(),
    });
    updateIndicators(currentIndex);
  }

  function updateIndicators(index: number) {
    document.querySelectorAll('.indicator').forEach((dot, i) => {
      dot.classList.toggle('active', i === index);
    });
  }

  return { goToSlide, draggable };
}
```

### Example: Rotation Dial (Knob Control)

```typescript
function createRotationDial(selector: string, onChange: (value: number) => void) {
  const dial = document.querySelector(selector) as HTMLElement;
  const minRotation = 0;
  const maxRotation = 270;

  const [draggable] = Draggable.create(dial, {
    type: 'rotation',
    inertia: true,
    minRotation,
    maxRotation,
    snap: (value) => {
      // Snap to 10-degree increments
      return Math.round(value / 10) * 10;
    },
    onDrag: function () {
      const normalized = (this.rotation - minRotation) / (maxRotation - minRotation);
      onChange(normalized); // 0 to 1
    },
    onThrowUpdate: function () {
      const normalized = (this.rotation - minRotation) / (maxRotation - minRotation);
      onChange(normalized);
    },
  });

  return draggable;
}

// Usage with a volume control
createRotationDial('#volume-knob', (value) => {
  document.querySelector('#volume-display')!.textContent = `${Math.round(value * 100)}%`;
  // Apply value to audio, animation speed, etc.
});
```

### Example: Drag-to-Reorder List

```typescript
function createReorderableList(containerSelector: string) {
  const container = document.querySelector(containerSelector) as HTMLElement;
  const items = Array.from(container.querySelectorAll('.list-item'));
  const itemHeight = items[0].getBoundingClientRect().height;

  items.forEach((item, index) => {
    // Position items absolutely
    gsap.set(item, { y: index * itemHeight });

    Draggable.create(item, {
      type: 'y',
      bounds: container,
      cursor: 'grab',
      activeCursor: 'grabbing',
      zIndexBoost: true,
      onPress: function () {
        gsap.to(this.target, { scale: 1.03, boxShadow: '0 8px 25px rgba(0,0,0,0.3)', duration: 0.2 });
      },
      onDrag: function () {
        const dragIndex = Math.round(this.y / itemHeight);
        const currentIndex = items.indexOf(this.target as HTMLElement);

        if (dragIndex !== currentIndex && dragIndex >= 0 && dragIndex < items.length) {
          // Reorder the array
          items.splice(currentIndex, 1);
          items.splice(dragIndex, 0, this.target as HTMLElement);

          // Animate other items to their new positions
          items.forEach((el, i) => {
            if (el !== this.target) {
              gsap.to(el, { y: i * itemHeight, duration: 0.3, ease: 'power2.out' });
            }
          });
        }
      },
      onDragEnd: function () {
        const finalIndex = items.indexOf(this.target as HTMLElement);
        gsap.to(this.target, {
          y: finalIndex * itemHeight,
          scale: 1,
          boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
          duration: 0.3,
          ease: 'power2.out',
        });
      },
    });
  });
}
```

---

## 3. Observer — Scroll/Touch/Pointer Event Unification

Observer provides a unified API for detecting meaningful user interactions
across wheel, touch, pointer, and scroll events. It handles device detection,
debouncing, velocity tracking, and direction detection automatically.

### Import & Register

```typescript
import gsap from 'gsap';
import { Observer } from 'gsap/Observer';

gsap.registerPlugin(Observer);
```

Observer is also embedded within ScrollTrigger. If you already load
ScrollTrigger, you can use `ScrollTrigger.observe()` instead.

### Basic Usage

```typescript
Observer.create({
  target: window,
  type: 'wheel,touch,pointer',
  onUp: () => goToPreviousSection(),
  onDown: () => goToNextSection(),
});
```

### Event Types

The `type` property is a comma-delimited string specifying which event sources
to listen for:

| Type        | Description                          |
| ----------- | ------------------------------------ |
| `"wheel"`   | Mouse wheel events                   |
| `"touch"`   | Touch events (touchstart/move/end)   |
| `"pointer"` | Pointer events (pointerdown/move/up) |
| `"scroll"`  | Native scroll events                 |

```typescript
// Listen to everything
Observer.create({ type: 'wheel,touch,pointer,scroll', ... });

// Wheel and touch only (common for section navigation)
Observer.create({ type: 'wheel,touch', ... });
```

### Configuration Options

```typescript
Observer.create({
  // Target element (default: viewport)
  target: window,
  // or: target: '#my-section',

  // Event sources
  type: 'wheel,touch,pointer',

  // Minimum pixel distance before callbacks fire (then resets)
  tolerance: 10,

  // Minimum pixels for initial drag before drag callbacks trigger
  dragMinimum: 5,

  // Aggregate deltas per frame for performance (default: true)
  debounce: true,

  // Prevent default browser behavior
  preventDefault: true,

  // Speed multipliers
  wheelSpeed: 1,     // adjust wheel sensitivity (-1 inverts direction)
  scrollSpeed: 1,    // adjust scroll sensitivity

  // Lock to first-detected axis
  lockAxis: true,

  // Elements to ignore
  ignore: '.button, .input',

  // Capture phase listeners
  capture: false,

  // Unique ID for retrieval
  id: 'section-nav',
});
```

**Full Options Reference:**

| Option         | Type                      | Default                      | Description                                       |
| -------------- | ------------------------- | ---------------------------- | ------------------------------------------------- |
| `target`       | String/Element            | viewport                     | Element to monitor                                |
| `type`         | String                    | `"wheel,touch,pointer"`      | Comma-delimited event sources                     |
| `tolerance`    | Number                    | `0`                          | Min pixels before callbacks fire                  |
| `dragMinimum`  | Number                    | `0`                          | Min pixels before drag callbacks trigger          |
| `debounce`     | Boolean                   | `true`                       | Frame-rate delta aggregation                      |
| `preventDefault`| Boolean                  | `false`                      | Prevent default browser behavior                  |
| `wheelSpeed`   | Number                    | `1`                          | Wheel delta multiplier                            |
| `scrollSpeed`  | Number                    | `1`                          | Scroll delta multiplier                           |
| `lockAxis`     | Boolean                   | `false`                      | Lock to first axis of movement                    |
| `ignore`       | String/Element/Array      | —                            | Elements to exclude                               |
| `capture`      | Boolean                   | `false`                      | Use capture phase listeners                       |
| `id`           | String                    | —                            | ID for `Observer.getById()`                       |

### Callbacks

All movement callbacks receive the Observer instance as a parameter:

```typescript
Observer.create({
  type: 'wheel,touch,pointer',

  // Directional (most common)
  onUp: (self) => { /* scrolled/swiped up */ },
  onDown: (self) => { /* scrolled/swiped down */ },
  onLeft: (self) => { /* scrolled/swiped left */ },
  onRight: (self) => { /* scrolled/swiped right */ },

  // Axis change (fires on any movement in that axis)
  onChangeX: (self) => {
    console.log('deltaX:', self.deltaX, 'velocityX:', self.velocityX);
  },
  onChangeY: (self) => {
    console.log('deltaY:', self.deltaY, 'velocityY:', self.velocityY);
  },

  // Toggle (fires when direction changes)
  onToggleX: (self) => { /* horizontal direction changed */ },
  onToggleY: (self) => { /* vertical direction changed */ },

  // General change (either axis)
  onChange: (self) => { /* any movement */ },

  // Drag-specific (pointer/touch only)
  onDragStart: (self) => { /* drag began */ },
  onDrag: (self) => { /* during drag */ },
  onDragEnd: (self) => { /* drag ended */ },

  // Pointer events
  onPress: (self) => { /* pointer/touch down */ },
  onRelease: (self) => { /* pointer/touch up */ },
  onHover: (self) => { /* pointer entered target */ },
  onHoverEnd: (self) => { /* pointer left target */ },
  onMove: (self) => { /* pointer moved over target */ },

  // Special
  onWheel: (self) => { /* wheel event specifically */ },
  onClick: (self) => { /* clicked (no drag) */ },
  onStop: (self) => { /* movement stopped */ },
  onStopDelay: 0.25, // seconds of inactivity before onStop fires

  // Lifecycle
  onEnable: (self) => { /* observer enabled */ },
  onDisable: (self) => { /* observer disabled */ },
  onLockAxis: (self) => {
    console.log('locked to:', self.axis); // "x" or "y"
  },
});
```

### Observable Properties

Available on the Observer instance (the `self` parameter in callbacks):

```typescript
Observer.create({
  type: 'wheel,touch,pointer',
  onChange: (self) => {
    self.deltaX;      // pixel change since last callback (horizontal)
    self.deltaY;      // pixel change since last callback (vertical)
    self.velocityX;   // pixels per second (horizontal)
    self.velocityY;   // pixels per second (vertical)
    self.x;           // current clientX (touch/pointer only)
    self.y;           // current clientY (touch/pointer only)
    self.startX;      // clientX from most recent press
    self.startY;      // clientY from most recent press
    self.isDragging;  // boolean — active drag state
    self.isPressed;   // boolean — pointer/touch is down
    self.isEnabled;   // boolean — observer is active
    self.event;       // most recent event object
    self.axis;        // "x" or "y" when lockAxis is true
  },
});

// Static property — detect touch capability
Observer.isTouch; // 0 = pointer-only, 1 = touch-only, 2 = both
```

### Methods

```typescript
const observer = Observer.create({ ... });

// Temporarily disable (preserves config for re-enabling)
observer.disable();

// Re-enable
observer.enable();

// Destroy completely (removes from registry, enables GC)
observer.kill();

// Static: get all active observers
Observer.getAll();

// Static: retrieve by id
const nav = Observer.getById('section-nav');
```

### When to Use Observer vs ScrollTrigger

| Use Case                              | Tool            |
| ------------------------------------- | --------------- |
| Animate on scroll position            | ScrollTrigger   |
| Pin elements during scroll            | ScrollTrigger   |
| Scrub animation with scroll progress  | ScrollTrigger   |
| Detect swipe direction                | Observer        |
| Full-page section navigation          | Observer        |
| Velocity-based effects                | Observer        |
| Scroll hijacking (no native scroll)   | Observer        |
| Custom gesture handling               | Observer        |
| Parallax effects                      | ScrollTrigger   |
| Batch element reveals                 | ScrollTrigger   |

**Rule of thumb:** If you need scroll *position*, use ScrollTrigger. If you need
scroll *intent/direction/velocity*, use Observer.

### Example: Scroll Hijacking (Full-Page Sections)

```typescript
function createFullPageSections(sectionSelector: string) {
  const sections = document.querySelectorAll(sectionSelector);
  let currentIndex = 0;
  let isAnimating = false;

  // Set initial positions
  gsap.set(sections, { yPercent: (i) => (i === 0 ? 0 : 100) });

  function goToSection(index: number, direction: number) {
    if (isAnimating || index < 0 || index >= sections.length) return;
    isAnimating = true;

    const tl = gsap.timeline({
      defaults: { duration: 1, ease: 'power2.inOut' },
      onComplete: () => {
        isAnimating = false;
        currentIndex = index;
      },
    });

    // Slide out current section
    tl.to(sections[currentIndex], { yPercent: direction < 0 ? 100 : -100 });

    // Slide in new section
    tl.fromTo(
      sections[index],
      { yPercent: direction < 0 ? -100 : 100 },
      { yPercent: 0 },
      '<' // same time
    );
  }

  Observer.create({
    type: 'wheel,touch,pointer',
    wheelSpeed: -1, // invert for natural direction
    tolerance: 10,
    preventDefault: true,
    onUp: () => goToSection(currentIndex - 1, -1),
    onDown: () => goToSection(currentIndex + 1, 1),
  });

  // Keyboard navigation
  document.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowUp') goToSection(currentIndex - 1, -1);
    if (e.key === 'ArrowDown') goToSection(currentIndex + 1, 1);
  });

  return { goToSection, getCurrentIndex: () => currentIndex };
}
```

### Example: Swipe Detection for Mobile Navigation

```typescript
function createSwipeNavigation(
  onSwipeLeft: () => void,
  onSwipeRight: () => void,
  onSwipeUp: () => void,
  onSwipeDown: () => void,
) {
  const observer = Observer.create({
    target: document.body,
    type: 'touch,pointer',
    dragMinimum: 30,       // 30px minimum before triggering
    tolerance: 20,         // 20px tolerance for direction
    lockAxis: true,        // lock to first-detected axis
    preventDefault: true,
    onLeft: () => onSwipeLeft(),
    onRight: () => onSwipeRight(),
    onUp: () => onSwipeUp(),
    onDown: () => onSwipeDown(),
  });

  return observer;
}

// Usage
createSwipeNavigation(
  () => navigateToNextSlide(),
  () => navigateToPrevSlide(),
  () => openDrawer(),
  () => closeDrawer(),
);
```

### Example: Velocity-Based Carousel

```typescript
function createVelocityCarousel(containerSelector: string) {
  const container = document.querySelector(containerSelector) as HTMLElement;
  const track = container.querySelector('.carousel-track') as HTMLElement;
  const items = track.querySelectorAll('.carousel-item');
  const itemWidth = (items[0] as HTMLElement).offsetWidth;
  const totalWidth = items.length * itemWidth;
  let currentX = 0;

  Observer.create({
    target: container,
    type: 'wheel,touch,pointer',
    dragMinimum: 5,
    onChangeX: (self) => {
      // Apply delta directly for responsive feel
      currentX += self.deltaX;

      // Clamp to bounds
      currentX = Math.max(-(totalWidth - container.offsetWidth), Math.min(0, currentX));

      gsap.to(track, {
        x: currentX,
        duration: 0.3,
        ease: 'power2.out',
        overwrite: true,
      });
    },
    onDragEnd: (self) => {
      // Use velocity for momentum snap
      const velocity = self.velocityX;
      const snapWidth = itemWidth;
      const momentumX = currentX + velocity * 0.3; // project position

      // Snap to nearest item
      const snappedX = Math.round(momentumX / snapWidth) * snapWidth;
      currentX = Math.max(
        -(totalWidth - container.offsetWidth),
        Math.min(0, snappedX)
      );

      gsap.to(track, {
        x: currentX,
        duration: 0.6,
        ease: 'power2.out',
      });
    },
    onWheel: (self) => {
      // Convert vertical wheel to horizontal scroll
      if (Math.abs(self.deltaY) > Math.abs(self.deltaX)) {
        currentX -= self.deltaY;
        currentX = Math.max(-(totalWidth - container.offsetWidth), Math.min(0, currentX));

        gsap.to(track, {
          x: currentX,
          duration: 0.5,
          ease: 'power2.out',
          overwrite: true,
        });
      }
    },
  });
}
```

---

## 4. Combining Plugins

### Flip + Draggable: Drag-to-Reparent

```typescript
const containers = document.querySelectorAll('.column');

containers.forEach((container) => {
  const items = container.querySelectorAll('.card');

  items.forEach((item) => {
    Draggable.create(item, {
      type: 'x,y',
      onDragEnd: function () {
        // Find which container was dropped on
        containers.forEach((target) => {
          if (Draggable.hitTest(this.target, target, '50%') && target !== this.target.parentElement) {
            const state = Flip.getState('.card');

            // Reparent element
            target.appendChild(this.target);

            // Reset drag position
            gsap.set(this.target, { x: 0, y: 0 });

            // Animate layout change
            Flip.from(state, {
              duration: 0.4,
              ease: 'power2.out',
              absolute: true,
            });
          } else {
            // Snap back to original position
            gsap.to(this.target, { x: 0, y: 0, duration: 0.3, ease: 'back.out(1.7)' });
          }
        });
      },
    });
  });
});
```

### Observer + Flip: Gesture-Triggered Layout Changes

```typescript
let isExpanded = false;

Observer.create({
  target: '.card-container',
  type: 'touch,pointer',
  onUp: () => {
    if (!isExpanded) {
      const state = Flip.getState('.card');
      document.querySelector('.card-container')!.classList.add('expanded-layout');
      isExpanded = true;
      Flip.from(state, { duration: 0.6, ease: 'power2.inOut', scale: true });
    }
  },
  onDown: () => {
    if (isExpanded) {
      const state = Flip.getState('.card');
      document.querySelector('.card-container')!.classList.remove('expanded-layout');
      isExpanded = false;
      Flip.from(state, { duration: 0.6, ease: 'power2.inOut', scale: true });
    }
  },
});
```

---

## 5. React/Next.js Integration

### gsap.context() for Cleanup

Always use `gsap.context()` in React to ensure proper cleanup on unmount:

```typescript
'use client';

import { useRef, useLayoutEffect } from 'react';
import gsap from 'gsap';
import { Flip } from 'gsap/Flip';
import { Draggable } from 'gsap/Draggable';
import { Observer } from 'gsap/Observer';

gsap.registerPlugin(Flip, Draggable, Observer);

export function InteractiveGrid() {
  const containerRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const ctx = gsap.context(() => {
      // All GSAP animations, Draggable instances, and Observers
      // created inside this context are automatically cleaned up

      Draggable.create('.grid-item', { type: 'x,y', bounds: containerRef.current });

      Observer.create({
        target: containerRef.current,
        type: 'wheel',
        onDown: () => { /* ... */ },
      });
    }, containerRef); // scope to this component

    return () => ctx.revert(); // clean up everything
  }, []);

  return <div ref={containerRef}>{/* ... */}</div>;
}
```

### Framework Flip Caveat

In React/Next.js, DOM updates happen asynchronously. Wrap `Flip.from()` in
`requestAnimationFrame` to ensure the DOM has settled:

```typescript
function handleLayoutChange() {
  const state = Flip.getState('.items');

  // Trigger React state update that changes layout
  setLayout('grid');

  // Wait for React to flush DOM updates
  requestAnimationFrame(() => {
    Flip.from(state, {
      duration: 0.5,
      ease: 'power2.inOut',
      targets: document.querySelectorAll('.items'), // re-query for new instances
    });
  });
}
```

---

## 6. Best Practices

1. **`scale: true` in Flip** — GPU-accelerated size transitions instead of
   width/height reflow
2. **`absolute: true` in Flip** — prevents layout shift during animation
3. **`box-sizing: border-box`** — required for accurate Flip calculations
4. **`gsap.context()`** — always use in React for automatic cleanup
5. **`lockAxis` in Draggable/Observer** — prevents diagonal confusion
6. **`tolerance` in Observer** — filter out micro-movements (10-20px)
7. **`inertia: true` in Draggable** — natural-feeling momentum
8. **`snap` functions** — always clamp within valid ranges
9. **`data-flip-id`** — explicit IDs when reparenting elements
10. **`requestAnimationFrame`** — wrap Flip.from() after React state changes
