# GSAP Motion & Physics Plugins

Animate along paths, apply 2D physics (velocity, gravity, friction),
and drive per-property physics simulations.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## 1. MotionPath — Animate Along Paths

Move elements along SVG paths or coordinate arrays with autoRotate.

```javascript
import { MotionPathPlugin } from 'gsap/MotionPathPlugin';
gsap.registerPlugin(MotionPathPlugin);
```

### Follow an SVG Path

```javascript
gsap.to('.rocket', {
  motionPath: {
    path: '#flight-path',     // SVG <path> element or selector
    align: '#flight-path',    // align element position to path
    alignOrigin: [0.5, 0.5],  // center of element on path
    autoRotate: true,          // face direction of travel
  },
  duration: 5,
  ease: 'power1.inOut',
});
```

### Coordinate Array

```javascript
gsap.to('.dot', {
  motionPath: {
    path: [
      { x: 0, y: 0 },
      { x: 100, y: -50 },
      { x: 200, y: 20 },
      { x: 300, y: -30 },
      { x: 400, y: 0 },
    ],
    curviness: 1.5,  // how curved the path is (0=straight, 2=very curved)
  },
  duration: 3,
  ease: 'none',
});
```

### Configuration

```javascript
motionPath: {
  path: '#path',              // SVG path, selector, or coordinate array
  align: '#path',             // element to align position to
  alignOrigin: [0.5, 0.5],   // [x, y] origin on element (0-1)
  autoRotate: true,           // face direction of travel
  // autoRotate: 90,           // face direction + 90° offset
  start: 0,                   // start position on path (0-1)
  end: 1,                     // end position on path (0-1)
  curviness: 1.25,            // for coordinate arrays (0-2+)
  offsetX: 0,                 // pixel offset from path
  offsetY: 0,
  relative: false,            // treat coords as relative to current pos
  type: 'cubic',              // 'cubic' or 'thru' (Catmull-Rom)
  resolution: 12,             // points per segment for length calculation
  useRadians: false,          // rotation in radians (for Canvas)
}
```

### Scroll-Driven Path Animation

```javascript
gsap.to('.explorer', {
  motionPath: {
    path: '#winding-path',
    align: '#winding-path',
    alignOrigin: [0.5, 0.5],
    autoRotate: true,
  },
  ease: 'none',
  scrollTrigger: {
    trigger: '.path-section',
    start: 'top top',
    end: 'bottom bottom',
    scrub: 1.5,
  },
});
```

### Partial Path Traversal

```javascript
// Only traverse middle 50% of the path
gsap.to('.element', {
  motionPath: {
    path: '#path',
    start: 0.25,
    end: 0.75,
  },
  duration: 2,
});
```

### Static Methods

```javascript
// Convert coordinates to SVG path data
const pathData = MotionPathPlugin.convertToPath([
  { x: 0, y: 0 },
  { x: 100, y: -50 },
  { x: 200, y: 0 },
]);

// Get position at point on path
const point = MotionPathPlugin.getRelativePosition(
  startElement,
  endElement
);

// Convert array to RawPath
const rawPath = MotionPathPlugin.arrayToRawPath(coordArray);

// Slice a portion of a RawPath
const sliced = MotionPathPlugin.sliceRawPath(rawPath, 0.2, 0.8);

// Convert RawPath to SVG path string
const svgString = MotionPathPlugin.rawPathToString(rawPath);
```

### MotionPathHelper — Visual Path Editor (Dev Tool)

Interactive in-browser tool for editing motion paths. Drag anchors and
control points, add points with ALT-click, copy the resulting path data.

```javascript
import { MotionPathHelper } from 'gsap/MotionPathHelper';
gsap.registerPlugin(MotionPathHelper);

// Attach to an existing MotionPath tween for visual editing
MotionPathHelper.create('.rocket', {
  path: '#flight-path',
  // Opens an interactive editor overlay in the browser
});
```

Use during development to visually design paths, then copy the path data
into your code. Remove before production.

### Flying Particles Along Curved Paths

```javascript
function createParticleTrail(count, pathSelector) {
  for (let i = 0; i < count; i++) {
    const particle = document.createElement('div');
    particle.className = 'trail-particle';
    container.appendChild(particle);

    gsap.to(particle, {
      motionPath: {
        path: pathSelector,
        align: pathSelector,
        alignOrigin: [0.5, 0.5],
      },
      duration: gsap.utils.random(2, 4),
      delay: gsap.utils.random(0, 2),
      repeat: -1,
      ease: 'none',
      opacity: 0,
      modifiers: {
        opacity: () => `${gsap.utils.random(0.3, 1)}`,
      },
    });
  }
}
```

---

## 2. Physics2D — 2D Physics Simulation

Apply velocity, angle, gravity, and friction to elements. Great for
explosions, confetti, floating particles.

```javascript
import { Physics2DPlugin } from 'gsap/Physics2DPlugin';
gsap.registerPlugin(Physics2DPlugin);
```

### Basic Usage

```javascript
gsap.to('.ball', {
  duration: 3,
  physics2D: {
    velocity: 300,      // initial speed (px/sec)
    angle: -60,         // direction in degrees (0=right, -90=up, 90=down)
    gravity: 500,       // downward acceleration (px/sec²)
    friction: 0.05,     // resistance (0=none, 1=max)
  },
});
```

### Angle Reference

```
        -90 (up)
         |
  -180 --+-- 0 (right)
 (left)  |
        90 (down)
```

### Particle Explosion

```javascript
function explode(x, y, count = 30) {
  for (let i = 0; i < count; i++) {
    const particle = document.createElement('div');
    particle.className = 'explosion-particle';
    particle.style.left = `${x}px`;
    particle.style.top = `${y}px`;
    document.body.appendChild(particle);

    gsap.to(particle, {
      duration: gsap.utils.random(1, 3),
      physics2D: {
        velocity: gsap.utils.random(100, 500),
        angle: gsap.utils.random(0, 360),
        gravity: 400,
        friction: gsap.utils.random(0.01, 0.1),
      },
      opacity: 0,
      scale: gsap.utils.random(0.3, 1),
      onComplete: () => particle.remove(),
    });
  }
}

document.addEventListener('click', (e) => explode(e.clientX, e.clientY));
```

### Confetti Burst

```javascript
function confetti(originX, originY) {
  const colors = ['#ff0000', '#00ff00', '#0000ff', '#ffff00', '#ff00ff'];

  for (let i = 0; i < 50; i++) {
    const piece = document.createElement('div');
    piece.className = 'confetti-piece';
    piece.style.cssText = `
      position: fixed;
      left: ${originX}px;
      top: ${originY}px;
      width: ${gsap.utils.random(5, 12)}px;
      height: ${gsap.utils.random(5, 12)}px;
      background: ${gsap.utils.random(colors)};
    `;
    document.body.appendChild(piece);

    gsap.to(piece, {
      duration: gsap.utils.random(2, 4),
      physics2D: {
        velocity: gsap.utils.random(200, 600),
        angle: gsap.utils.random(-120, -60), // upward cone
        gravity: 300,
        friction: 0.02,
      },
      rotation: gsap.utils.random(-720, 720),
      opacity: 0,
      onComplete: () => piece.remove(),
    });
  }
}
```

### Floating Bubbles

```javascript
function createBubble() {
  const bubble = document.createElement('div');
  bubble.className = 'bubble';
  bubble.style.left = `${gsap.utils.random(0, window.innerWidth)}px`;
  bubble.style.bottom = '0px';
  container.appendChild(bubble);

  gsap.to(bubble, {
    duration: gsap.utils.random(4, 8),
    physics2D: {
      velocity: gsap.utils.random(50, 150),
      angle: gsap.utils.random(-100, -80), // mostly upward
      gravity: -20,                         // negative = floats up
      friction: 0.02,
    },
    opacity: 0,
    scale: gsap.utils.random(0.5, 2),
    onComplete: () => bubble.remove(),
  });
}

// Spawn bubbles continuously
gsap.ticker.add(() => {
  if (Math.random() < 0.05) createBubble();
});
```

### Projectile with Gravity

```javascript
gsap.to('.projectile', {
  duration: 5,
  physics2D: {
    velocity: 400,
    angle: -45,       // 45° upward
    gravity: 300,     // pulls down
    friction: 0,      // no air resistance
  },
});
```

### Acceleration

```javascript
gsap.to('.car', {
  duration: 3,
  physics2D: {
    velocity: 0,               // starts still
    angle: 0,                  // moves right
    acceleration: 200,         // accelerates
    accelerationAngle: 0,      // acceleration direction
    friction: 0,
  },
});
```

---

## 3. PhysicsProps — Per-Property Physics

Apply independent physics to individual CSS/JS properties.

```javascript
import { PhysicsPropsPlugin } from 'gsap/PhysicsPropsPlugin';
gsap.registerPlugin(PhysicsPropsPlugin);
```

### Basic Usage

```javascript
gsap.to('.element', {
  duration: 5,
  physicsProps: {
    x: {
      velocity: 200,
      acceleration: -50,
      friction: 0.02,
      min: 0,
      max: 500,        // bounces off boundaries
    },
    y: {
      velocity: -100,
      gravity: 300,     // per-property gravity (same as acceleration)
      friction: 0.01,
    },
  },
});
```

### Independent X/Y Physics

```javascript
// Ball with different physics per axis
gsap.to('.ball', {
  duration: 4,
  physicsProps: {
    x: {
      velocity: gsap.utils.random(-300, 300),
      friction: 0.05,
      min: 0,
      max: window.innerWidth - 20,
    },
    y: {
      velocity: -200,
      gravity: 500,     // gravity only on Y
      friction: 0.02,
      min: 0,
      max: window.innerHeight - 20,
    },
  },
});
```

### Spinning to Stop (Rotation with Friction)

```javascript
gsap.to('.wheel', {
  duration: 8,
  physicsProps: {
    rotation: {
      velocity: 720,    // degrees per second
      friction: 0.08,   // gradually slows
    },
  },
});
```

### Scale Bouncing

```javascript
gsap.to('.element', {
  duration: 3,
  physicsProps: {
    scale: {
      velocity: 2,
      friction: 0.15,
      min: 0.5,
      max: 2,
    },
  },
});
```

---

## Quick Reference

| Plugin | Properties | Best For |
|--------|-----------|----------|
| **MotionPath** | path, align, autoRotate, curviness, start/end | Following curves, guided motion |
| **Physics2D** | velocity, angle, gravity, friction, acceleration | Explosions, confetti, projectiles, floating |
| **PhysicsProps** | velocity, acceleration, friction, min/max per prop | Spinning, bouncing, independent axis physics |

### Physics2D vs PhysicsProps

| Feature | Physics2D | PhysicsProps |
|---------|-----------|-------------|
| Controls | x + y together via angle | Each property independently |
| Gravity | Global direction | Per-property |
| Boundaries (min/max) | No | Yes |
| Best for | Projectiles, explosions | Constrained physics, bouncing |
