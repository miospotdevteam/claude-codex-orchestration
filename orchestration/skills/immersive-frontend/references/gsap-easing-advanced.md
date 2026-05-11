# GSAP Advanced Easing

Custom easing curves, bounce physics, wiggle oscillation, and specialty
eases for cinematic motion.

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## 1. CustomEase — SVG Path-Based Easing

Define easing curves with SVG path data for precise, branded motion.

```javascript
import { CustomEase } from 'gsap/CustomEase';
gsap.registerPlugin(CustomEase);
```

### Creating Custom Eases

```javascript
// SVG path data defines the curve
// M0,0 = start (0% time, 0% progress)
// ...control points...
// 1,1 = end (100% time, 100% progress)

CustomEase.create('smoothOut', 'M0,0 C0.25,0.1 0.25,1 1,1');
CustomEase.create('snapBack', 'M0,0 C0.5,0 0.2,1.6 0.5,1 0.7,0.8 1,1');
CustomEase.create('dramaticPause', 'M0,0 C0.2,0.8 0.2,0.8 0.5,0.8 0.8,0.8 0.8,1 1,1');

// Use like any ease
gsap.to('.box', { x: 200, ease: 'smoothOut', duration: 1 });
gsap.to('.box', { x: 200, ease: 'snapBack', duration: 1 });
```

### getSVGData() — Visualize Any Ease

```javascript
// Get SVG path data for any ease (for visualization/debugging)
const svgData = CustomEase.getSVGData('power2.out', {
  width: 200,
  height: 100,
});
// Returns SVG path string you can render

// Visualize a custom ease
const pathEl = document.querySelector('#ease-preview path');
pathEl.setAttribute('d', CustomEase.getSVGData('snapBack', {
  width: 300,
  height: 150,
}));
```

### Multi-Stage Ease

```javascript
// Fast start → pause in middle → fast end
CustomEase.create('suspense',
  'M0,0 C0.3,0.6 0.3,0.6 0.5,0.6 0.7,0.6 0.7,1 1,1'
);

// Overshoot then settle
CustomEase.create('overshoot',
  'M0,0 C0.2,0 0.3,1.4 0.5,1 0.65,0.9 0.8,1.02 1,1'
);
```

**When to use:** Branded motion (company-specific easing), matching
easing from After Effects/Figma curves, any motion that standard eases
can't achieve.

---

## 2. CustomBounce — Realistic Bounce

Creates bounce easing with configurable squash-and-stretch.

```javascript
import { CustomBounce } from 'gsap/CustomBounce';
gsap.registerPlugin(CustomBounce);
```

### Creating Bounce Eases

```javascript
// Basic bounce
CustomBounce.create('myBounce', {
  strength: 0.7,    // 0-1: how high bounces go (0.7 = 70% of original height)
  squash: 3,         // amount of squash on impact (0 = none)
  squashID: 'myBounce-squash', // paired ease for squash animation
  endAtStart: false, // if true, ends at starting position
});

// Use the bounce
gsap.to('.ball', {
  y: 300,
  duration: 2,
  ease: 'myBounce',
});

// Use the paired squash ease for width/scaleX
gsap.to('.ball', {
  scaleX: 1.4,
  scaleY: 0.6,
  duration: 2,
  ease: 'myBounce-squash', // squashes on each bounce impact
  transformOrigin: 'center bottom',
});
```

### Ball Drop with Squash

```javascript
CustomBounce.create('drop', {
  strength: 0.6,
  squash: 2,
  squashID: 'drop-squash',
});

const tl = gsap.timeline();
tl.to('.ball', {
  y: 400,
  duration: 2,
  ease: 'drop',
})
.to('.ball', {
  scaleX: 1.3,
  scaleY: 0.7,
  duration: 2,
  ease: 'drop-squash',
  transformOrigin: 'center bottom',
}, 0); // simultaneous
```

### Notification Badge Bounce

```javascript
CustomBounce.create('badge', { strength: 0.5, squash: 0 });

gsap.from('.notification-badge', {
  scale: 0,
  duration: 0.8,
  ease: 'badge',
});
```

**When to use:** Bouncing balls, notification badges, playful UI elements,
any physics-inspired bounce.

---

## 3. CustomWiggle — Oscillating Motion

Creates easing that oscillates back and forth a specified number of times.

```javascript
import { CustomWiggle } from 'gsap/CustomWiggle';
gsap.registerPlugin(CustomWiggle);
```

### Creating Wiggle Eases

```javascript
CustomWiggle.create('myWiggle', {
  wiggles: 8,        // number of oscillations
  type: 'easeOut',   // 'uniform', 'random', 'easeOut' (default), 'easeInOut'
});

gsap.to('.element', {
  x: 20,             // wiggle ±20px
  duration: 1,
  ease: 'myWiggle',
});
```

### Wiggle Types

```javascript
// easeOut (default) — strong at start, fading out (earthquake aftershock)
CustomWiggle.create('quake', { wiggles: 10, type: 'easeOut' });

// uniform — consistent amplitude throughout
CustomWiggle.create('vibrate', { wiggles: 20, type: 'uniform' });

// random — varied amplitude (organic feel)
CustomWiggle.create('jitter', { wiggles: 12, type: 'random' });

// easeInOut — builds up, then fades
CustomWiggle.create('tremor', { wiggles: 8, type: 'easeInOut' });
```

### Shake/Vibration Effect

```javascript
CustomWiggle.create('shake', { wiggles: 6, type: 'easeOut' });

function shakeElement(el) {
  gsap.to(el, {
    x: 15,
    duration: 0.6,
    ease: 'shake',
  });
}

// Error shake on form
form.addEventListener('invalid', () => shakeElement(form));
```

### Jello Wobble

```javascript
CustomWiggle.create('jello', { wiggles: 5, type: 'easeOut' });

gsap.to('.card', {
  rotation: 5,
  duration: 0.8,
  ease: 'jello',
});
```

### Attention-Seeking Wiggle

```javascript
CustomWiggle.create('attention', { wiggles: 4, type: 'easeInOut' });

function wiggleAttention(el) {
  gsap.to(el, {
    rotation: 10,
    duration: 0.5,
    ease: 'attention',
  });
}
```

**When to use:** Error states, attention indicators, vibration, jello
effects, organic micro-interactions.

---

## 4. EasePack — Specialty Eases

Three unique eases for specific motion needs.

```javascript
import { EasePack } from 'gsap/EasePack';
gsap.registerPlugin(EasePack);
```

### RoughEase — Randomized Jagged Motion

Adds randomized "noise" to an ease curve. Great for glitch effects.

```javascript
// Glitch/distortion effect
gsap.to('.glitch-text', {
  x: 5,
  duration: 0.5,
  ease: 'rough({strength: 2, points: 20, taper: "none", randomize: true, clamp: true})',
});

// Configuration
ease: 'rough({
  strength: 2,        // amplitude of roughness (default: 1)
  points: 20,         // number of random points (default: 20)
  taper: "none",      // "none", "in", "out", "both" (default: "out")
  randomize: true,     // randomize point placement
  clamp: false,        // restrict to 0-1 range
  template: "power2.out" // base ease to roughen
})'
```

**Example — Glitch Effect:**
```javascript
gsap.to('.glitch', {
  skewX: 10,
  duration: 0.3,
  ease: 'rough({strength: 3, points: 50, taper: "none", clamp: true})',
  repeat: 3,
  yoyo: true,
});
```

**Example — Hand-Drawn Feel:**
```javascript
gsap.to('.hand-drawn path', {
  drawSVG: '100%',
  duration: 2,
  ease: 'rough({strength: 0.5, points: 30, taper: "out", template: "power1.out"})',
});
```

### SlowMo — Slow Middle Section

Motion that starts fast, slows dramatically in the middle, then speeds
up again. Cinematic emphasis.

```javascript
// SlowMo.ease.config(linearRatio, power, yoyoMode)
gsap.to('.spotlight', {
  x: 500,
  duration: 3,
  ease: 'slow(0.5, 0.8, false)',
  // 0.5 = 50% of duration is slow
  // 0.8 = how slow (0=linear, 1=nearly stopped)
  // false = no yoyo
});
```

**Example — Dramatic Reveal:**
```javascript
gsap.to('.reveal-curtain', {
  xPercent: -100,
  duration: 2,
  ease: 'slow(0.7, 0.7, false)',
  // Starts fast, slows when content is revealed, finishes fast
});
```

### ExpoScaleEase — Exponential Scaling

Maps an exponential curve between two values. Useful for frequency
sweeps, zoom transitions, and logarithmic scales.

```javascript
// ExpoScaleEase.config(startScale, endScale, ease)
gsap.to('.element', {
  scale: 10,
  duration: 2,
  ease: 'expoScale(1, 10)',
  // Exponential growth from 1 to 10
});

// With a base ease
gsap.to('.element', {
  scale: 10,
  duration: 2,
  ease: 'expoScale(1, 10, power2.inOut)',
});
```

**Example — Zoom from Overview:**
```javascript
const camera = { fov: 75 };
gsap.to(camera, {
  fov: 15,
  duration: 2,
  ease: 'expoScale(75, 15, power2.inOut)',
  onUpdate: () => {
    threeCamera.fov = camera.fov;
    threeCamera.updateProjectionMatrix();
  },
});
```

---

## Quick Reference

| Ease | Best For | Key Config |
|------|----------|------------|
| **CustomEase** | Precise branded curves | SVG path data |
| **CustomBounce** | Physical bounce with squash | strength, squash |
| **CustomWiggle** | Shake, vibrate, attention | wiggles, type |
| **RoughEase** | Glitch, distortion, hand-drawn | strength, points, taper |
| **SlowMo** | Dramatic reveal, emphasis | linearRatio, power |
| **ExpoScaleEase** | Zoom, frequency sweep | startScale, endScale |

### Standard Eases vs Advanced

| Need | Standard | Advanced |
|------|----------|----------|
| Smooth entrance | `power3.out` | — |
| Playful overshoot | `back.out(1.7)` | — |
| Springy | `elastic.out(1, 0.3)` | — |
| Branded motion | — | `CustomEase` |
| Realistic bounce | `bounce.out` | `CustomBounce` (better: squash) |
| Shake/vibrate | — | `CustomWiggle` |
| Glitch | — | `RoughEase` |
| Slow-mo emphasis | — | `SlowMo` |
| Exponential zoom | — | `ExpoScaleEase` |
