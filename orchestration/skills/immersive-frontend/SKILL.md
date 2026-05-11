---
name: immersive-frontend
description: "Build award-winning immersive web experiences with WebGL, Three.js, R3F, GSAP ScrollTrigger, custom GLSL shaders, and scroll-driven 3D choreography. Make sure to use this skill whenever the user asks for: immersive websites, WebGL experiences, 3D web, creative dev, scroll-driven animations, cinematic scroll, Three.js scenes, GSAP + Three.js, motion-driven sites, award-winning website design, Awwwards-quality sites, full-canvas experiences, particle systems, shader effects, smooth scroll with WebGL, preloader animations, image distortion effects, parallax depth, magnetic cursors, text reveal animations, infinite marquees, camera flythrough, noise displacement, fresnel glow, chromatic aberration, post-processing bloom, film grain, or any request that goes beyond standard UI into experiential, motion-first, canvas-driven territory. Also trigger when the user references studios like Active Theory, Lusion, Immersive Garden, or sites from Awwwards/Codrops, or uses words like 'cinematic', 'theatrical', or 'dark theme with neon'. Do NOT use for: standard UI components, form-heavy pages, admin dashboards, simple CSS hover states, or basic Framer Motion page transitions — use frontend-design instead."
---

# Immersive Frontend

Build full-canvas WebGL experiences with custom shaders, scroll-choreographed
3D scenes, smooth-scrolled cinematics, and theatrical loading sequences. This
skill sits at the intersection of creative coding and web development.

**Announce at start:** "I'm using the immersive-frontend skill to build this
experience."

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Assessment) runs during Step 1 (Explore).
- **Phase 2** (Architecture) feeds into the masterPlan via `writing-plans`.
- **Phase 3** (Implementation) runs during Step 3 (Execute).
- **Phase 4** (Verification) runs after implementation.

If `brainstorming` ran first and produced visual direction: use those
decisions. If `frontend-design` Phase 2 ran first: use its design direction
(axes, creative seed, typography, color). In both cases, skip to Phase 2.

---

## Phase 1: Assessment — What Are We Building?

### Design Direction

An immersive site still needs intentional design — typography, color, spacing,
and creative direction. Before diving into technical architecture:

**If `frontend-design` Phase 2 ran first** (it produced a Design Handoff
document with axis scores, creative seed, typography, color system, motion
tier, and scope): read that document from `discovery.md` or `design.md`.
Those decisions inform background colors, text overlays, particle palettes,
UI chrome, and overall mood. If the handoff specifies a hybrid scope,
follow the Hybrid Projects pattern above. Skip to the Decision Tree below.

**If `brainstorming` ran first** and produced visual direction in `design.md`:
use those decisions. Skip to the Decision Tree below. If the design
includes a **Creative Brief**, its Intent and Visual Direction directly
inform scene mood, color choices, and motion personality — replacing
the need to invoke `frontend-design` Phase 2 for aesthetic direction.
The Copy Voice section guides any DOM text overlays or UI chrome copy.

**If neither ran**: invoke `frontend-design` Phase 2 (Greenfield — Decision
Matrix) to establish the aesthetic direction. The 6-axis scores, creative
seed, typography pairing, and color system apply to immersive sites just as
much as standard ones. Once the user approves the direction, return here
for the technical architecture.

Do NOT skip design direction because the work is "technical." An immersive
experience with default colors and Inter is a tech demo, not a designed
experience.

### Creative Palette Libraries

For scene colors (particles, mesh materials, canvas backgrounds), use
curated creative palette libraries instead of picking colors by hand:

| Library | Best for | Install |
|---|---|---|
| **chromotome** | Artistic scenes — 200+ palettes with designated background + stroke colors | `npm i chromotome` |
| **nice-color-palettes** | Random harmonious palettes (1000 × 5 colors) for generative work | `npm i nice-color-palettes` |
| **riso-colors** | Retro/print aesthetic with flat, textured tones | `npm i riso-colors` |

```javascript
// Example: chromotome palette → Three.js materials
import { getRandom } from 'chromotome';
const palette = getRandom();
const bgColor = new THREE.Color(palette.background);
const meshColors = palette.colors.map(c => new THREE.Color(c));
scene.background = bgColor;
```

UI chrome (nav, text overlays, buttons) should still use the design tokens
from `frontend-design` — creative palettes are for the visual/artistic
layer only.

See `PACKAGES.md` in the plugin root for the full list.

### Decision Tree

Answer these questions to determine scope and which references to read:

```
Does it need 3D objects / WebGL?
├── YES → Read: references/three-js-patterns.md
│   ├── Custom shaders needed? → Also read: references/shader-recipes.md
│   ├── Scroll drives the 3D scene? → Also read: references/gsap-scroll-patterns.md
│   │   └── ScrollSmoother or Observer? → Also read: references/gsap-scroll-advanced.md
│   ├── Heavy assets (models, textures)? → Also read: references/architecture.md (preloader)
│   └── Physics, motion paths, particles? → Also read: references/gsap-motion-physics.md
│
├── SVG morphing, drawing, or stroke animation?
│   └── Read: references/gsap-svg-plugins.md
│
├── Layout animations (Flip, Draggable, Observer)?
│   └── Read: references/gsap-layout-plugins.md
│
├── Text effects (SplitText, ScrambleText, decode)?
│   └── Read: references/gsap-text-plugins.md
│
├── Custom easing (bounce, wiggle, rough, slow-mo)?
│   └── Read: references/gsap-easing-advanced.md
│
├── Animated scroll-to navigation (anchor links, back-to-top)?
│   └── Read: references/gsap-scroll-to-plugin.md
│
├── Momentum/throw physics, infinite loops, value snapping?
│   └── Read: references/gsap-value-plugins.md
│
└── NO (2D motion only: text reveals, parallax, marquees)
    └── Read: references/gsap-scroll-patterns.md + references/effects-cookbook.md
```

**Always read:** `references/architecture.md` for the canvas+DOM layering
pattern and smooth scroll setup — these apply to every immersive site.

**Always read:** `references/gsap-core-patterns.md` for gsap.context()
(cleanup), gsap.matchMedia() (responsive), and gsap.utils (utilities) —
these apply to every GSAP project.

**When debugging:** Read `references/gsap-common-mistakes.md` for common
pitfalls. Keep `references/gsap-helpers-cheatsheet.md` handy as a quick
lookup for imports, methods, and configuration.

### Complexity Tiers

| Tier | Description | Stack | Reference Files |
|------|-------------|-------|-----------------|
| **Motion-Enhanced** | Smooth scroll, text reveals, parallax, marquees. No WebGL. | GSAP + Lenis | gsap-scroll-patterns, effects-cookbook |
| **WebGL-Lite** | Canvas background (particles, blobs), DOM content on top. | Three.js + GSAP + Lenis | All except shader-recipes |
| **Full Immersive** | Scroll-driven 3D scenes, custom shaders, preloader, page transitions. | Three.js + GSAP + Lenis + GLSL | All reference files |

### Hybrid Projects (Immersive Sections in Standard UI)

When adding immersive sections to an existing UI site (not a full-canvas
experience):

1. **Scope partition:** Identify which sections are immersive (this skill)
   vs standard UI (`frontend-design`). Document the boundary explicitly.
2. **Canvas containment:** Use a scoped `<canvas>` inside a section, not
   `position: fixed` full-page. The canvas lives inside the immersive
   section's DOM element and resizes with it.
3. **Lazy loading:** Don't block the rest of the site. Load Three.js and
   scene assets only when the immersive section enters the viewport (use
   `IntersectionObserver` or dynamic `import()`).
4. **Scroll handoff:** The page uses native or standard smooth scrolling.
   The immersive section pins and scrubs its content within its scroll
   range. After the section ends, normal scrolling resumes.
5. **Design continuity:** The immersive section's typography, colors, and
   spacing should match the rest of the site (consume the same design
   tokens). The transition into and out of the immersive section should
   feel seamless.

```javascript
// Lazy-load the 3D section
const observer = new IntersectionObserver((entries) => {
  if (entries[0].isIntersecting) {
    import('./ImmersiveSection.js').then(m => m.init(sectionEl));
    observer.disconnect();
  }
}, { rootMargin: '200px' }); // Start loading 200px before visible
observer.observe(document.querySelector('#immersive-section'));
```

See `references/architecture.md` § Hybrid Integration Pattern for the
scoped canvas setup.

---

## Phase 2: Architecture

### Quick-Start Structure (Every Immersive Site)

```
┌─────────────────────────────────────────┐
│  PRELOADER (fixed, z-index: 9999)       │  ← Loads all assets before reveal
│  - Progress counter / bar               │
│  - Theatrical exit animation            │
├─────────────────────────────────────────┤
│  CANVAS LAYER (fixed, z-index: 0)       │  ← Three.js WebGLRenderer
│  - Full viewport, position: fixed       │
│  - Transparent or scene background      │
│  - Renders on GSAP ticker (not own rAF) │
├─────────────────────────────────────────┤
│  DOM CONTENT (relative, z-index: 1)     │  ← Scrollable HTML content
│  - Lenis smooth scroll                  │
│  - ScrollTrigger-driven animations      │
│  - pointer-events: none on overlay text │
├─────────────────────────────────────────┤
│  RENDER LOOP (single GSAP ticker)       │  ← One heartbeat for everything
│  - gsap.ticker.add() drives:            │
│    → Lenis.raf() (smooth scroll)        │
│    → ScrollTrigger.update (animations)  │
│    → renderer.render() (Three.js)       │
│  - gsap.ticker.lagSmoothing(0)          │
└─────────────────────────────────────────┘
```

### The Critical Integration Pattern

```javascript
// ONE render loop to rule them all
const lenis = new Lenis({ duration: 1.2, smoothWheel: true });
lenis.on('scroll', ScrollTrigger.update);

gsap.ticker.add((time) => {
  lenis.raf(time * 1000);        // 1. Smooth scroll
  // ScrollTrigger auto-updates  // 2. Animations
  renderer.render(scene, camera); // 3. WebGL
});

gsap.ticker.lagSmoothing(0); // Prevent desync after lag spikes
```

### Technology Selection Guide

| Need | Use | Why |
|------|-----|-----|
| 3D objects, models, particles | **Three.js** (vanilla) | Full control, smaller bundle |
| 3D in React app | **React Three Fiber + Drei** | Declarative, auto-disposal, hooks |
| Scroll-linked animations | **GSAP ScrollTrigger** | Scrub, pin, snap, batch, timeline |
| Smooth scrolling | **Lenis** | Syncs with rAF, works with ScrollTrigger |
| Text split/reveal | **GSAP SplitText** (free, included with gsap) | Industry standard for char/word/line animation |
| Page transitions (MPA) | **Barba.js** | Preserves canvas across navigations |
| Spring physics (React) | **Motion (Framer Motion)** | AnimatePresence, layout animations |
| Custom visual effects | **GLSL shaders** | GPU-accelerated, per-pixel control |
| 2D parallax only | **GSAP ScrollTrigger alone** | No WebGL overhead needed |

### CDN Links (for single-file HTML)

Pin specific versions for production. **Before using the versions below,
check npm for the latest stable release** — these are reference versions
that may be outdated:

| Library | npm page | Reference version |
|---|---|---|
| Three.js | `npmjs.com/package/three` | 0.170.0 |
| GSAP | `npmjs.com/package/gsap` | 3.12.7 |
| Lenis | `npmjs.com/package/lenis` | 1.2.3 |

See `references/architecture.md` § CDN Reference for copy-paste `<script>`
tags with the latest known versions.

---

## Phase 3: Implementation Rules

### Critical Performance Rules

1. **One render loop.** Drive Lenis, ScrollTrigger, and Three.js from
   `gsap.ticker.add()`. Never use a separate `requestAnimationFrame`.

2. **Cap pixel ratio at 2.** `Math.min(window.devicePixelRatio, 2)`.
   3x DPR triples GPU work for imperceptible gain.

3. **Animate only transform and opacity** in DOM. These are GPU-composited.
   Never animate `width`, `height`, `top`, `left`, `margin`, `padding`.

4. **Dispose everything.** GPU memory is NOT garbage collected. Call
   `.dispose()` on geometries, materials, and textures when removing objects.

5. **Preload before reveal.** Gate the experience behind a loading screen.
   Use `THREE.LoadingManager` for 3D assets, `Promise.all` for others.

6. **scrub: 0.5 to 1.5** for scroll-driven animations. Raw `scrub: true`
   feels jerky. The smoothing value adds polish.

7. **Draw calls < 50 mobile, < 100 desktop.** Monitor with
   `renderer.info.render.calls`. Use InstancedMesh for repeated geometry.

8. **Use autoAlpha over opacity** in GSAP. It sets `visibility: hidden`
   at 0, removing the element from the render tree.

9. **Texture sizes:** Max 2048x2048 for hero, 1024x1024 for gallery,
   512x512 for UI. Power-of-two dimensions for GPU efficiency.

10. **Mobile fallback.** Detect via `matchMedia` and serve reduced
    particle counts, no shadows, simpler shaders, lower DPR.

### Accessibility for Immersive Experiences

Immersive sites must be usable by everyone. These aren't optional — they're
requirements.

**Vestibular / motion sensitivity:**
- Detect `prefers-reduced-motion: reduce` and provide a meaningful static
  fallback — not a blank page, but a simplified version with no parallax,
  no scroll-driven camera movement, and no auto-playing animation
- Offer a visible "Reduce motion" toggle in the UI (don't rely solely on
  OS setting)
- Avoid large-area motion (full-viewport transforms) that triggers
  vestibular responses

**Seizure / photosensitivity (WCAG 2.3.1):**
- No content flashes more than 3 times per second
- No sudden high-contrast transitions (dark↔light full-screen)
- Avoid strobing particle effects or rapid color cycling

**Cognitive overload:**
- Don't fire all effects simultaneously — stagger reveals so the user
  processes one thing at a time
- Provide visual anchors (stable text, fixed nav) alongside moving elements
- Keep the scroll-to-effect ratio predictable — erratic speeds disorient

**Implementation pattern:**
```javascript
const prefersReduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

if (prefersReduced) {
  // Static scene: set final camera position, skip scroll animation
  camera.position.set(0, 0, 5);
  // Show content immediately, no preloader animation
  gsap.set('#preloader', { autoAlpha: 0 });
  // Disable Lenis smooth scroll — use native
  // Don't start the render loop ticker for scroll-driven updates
} else {
  // Full immersive experience
  initLenis();
  initScrollTriggers();
  startRenderLoop();
}
```

See `references/architecture.md` § Accessibility Implementation Patterns
for complete patterns.

### Anti-Patterns — What NOT to Do

Also read `references/anti-slop.md` for the shared cross-skill banlist
covering typography, color, layout, animation, illustration, and copy.

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Separate rAF for Lenis and Three.js | Frame desync, tearing between DOM and canvas | Single gsap.ticker drives everything |
| `scrub: true` (no smoothing) | Jerky, mechanical camera/animation movement | `scrub: 0.5` to `scrub: 2` |
| Skipping the preloader | White flash, pop-in, broken first impression | Always gate behind a loading screen |
| Animating `top`/`left`/`width` | Triggers layout reflow every frame, kills FPS | Use `transform` (x, y, scale, rotation) |
| `devicePixelRatio` uncapped | GPU meltdown on 3x Retina, >4x fill rate | `Math.min(window.devicePixelRatio, 2)` |
| Forgetting `.dispose()` | GPU memory leak, crashes after page transitions | Dispose geometry, material, textures on cleanup |
| `any` type on Three.js objects | Loses intellisense, hides bugs | Proper typing or let inference work |
| Huge textures (4K+) | GPU memory explosion, slow load | 2048 max, use KTX2 compression |
| Raw `window.scrollY` in render loop | Desyncs with Lenis smooth scroll | Read `lenis.scroll` or `lenis.progress` |
| No resize handler | Broken aspect ratio, stretched canvas | Update camera.aspect, renderer.setSize, ScrollTrigger.refresh() |
| Inline shaders as template literals without `/* glsl */` | No syntax highlighting, hard to debug | Tag with `/* glsl */` or use `<script type="x-shader">` |
| Post-processing > 6 passes | Each pass is a full-screen draw, kills mobile | Combine effects, keep to 3-5 passes |

### Shader Integration Pattern

When using custom shaders, always provide uniforms for time, scroll, and mouse:

```javascript
const material = new THREE.ShaderMaterial({
  uniforms: {
    uTime:           { value: 0 },
    uScrollProgress: { value: 0 },      // 0-1, full page
    uScrollVelocity: { value: 0 },      // Lenis velocity
    uMouse:          { value: new THREE.Vector2(0.5, 0.5) },
    uResolution:     { value: new THREE.Vector2(width, height) },
  },
  vertexShader: vertexShaderCode,
  fragmentShader: fragmentShaderCode,
});

// Update in the single ticker
gsap.ticker.add((time) => {
  material.uniforms.uTime.value = time;
  material.uniforms.uScrollProgress.value = lenis.progress;
  material.uniforms.uScrollVelocity.value = lenis.velocity;
});
```

### Responsive WebGL Pattern

```javascript
function onResize() {
  const w = window.innerWidth;
  const h = window.innerHeight;

  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  // Update resolution uniform if using shaders
  material.uniforms.uResolution.value.set(
    w * renderer.getPixelRatio(),
    h * renderer.getPixelRatio()
  );

  // Recalculate ScrollTrigger positions
  ScrollTrigger.refresh();
}
window.addEventListener('resize', onResize);
```

---

## Phase 4: Verification

### Immersive-Specific Checklist

- [ ] **60fps**: No frame drops during scroll (check DevTools Performance)
- [ ] **Preloader**: All assets load before experience reveals
- [ ] **Smooth scroll**: Lenis + ScrollTrigger synced via GSAP ticker
- [ ] **Responsive**: Canvas resizes, camera updates, ScrollTrigger refreshes
- [ ] **Disposal**: All geometries/materials/textures disposed on cleanup
- [ ] **DPR capped**: `Math.min(devicePixelRatio, 2)` applied
- [ ] **Mobile**: Reduced quality tier applied (fewer particles, no shadows)
- [ ] **No layout animation**: Only transform/opacity animated in DOM
- [ ] **Draw calls**: Within budget (check `renderer.info.render.calls`)
- [ ] **Scroll feels right**: `scrub` has smoothing value, not raw `true`

### Performance Profiling Workflow

When verifying performance, follow this sequence (see
`references/architecture.md` § Performance Profiling Workflow for detailed
steps):

1. **Chrome DevTools Performance tab** — record a scroll through the full
   experience, look for long frames (>16ms) and jank
2. **Rendering panel** — enable "Paint flashing" and "Layout shift regions"
   to catch DOM-triggered repaints
3. **`renderer.info`** — log draw calls, triangles, texture/geometry counts
   against the performance budgets
4. **GPU bottleneck test** — reduce canvas size by 50%; if FPS improves
   significantly, you're fill-rate bound (reduce shader complexity, lower
   DPR)
5. **CPU bottleneck test** — simplify JS logic; if FPS improves, optimize
   the ticker callback or reduce object count

### Standard Checks (from engineering-discipline)

- [ ] Type checker passes
- [ ] Linter passes
- [ ] No `any` / `as any` in TypeScript
- [ ] prefers-reduced-motion respected (disable WebGL motion, simplify DOM animation)

---

## Reference Files

> **Note:** GSAP is now 100% free — all plugins included with `bun add gsap`.

### Core References (read for every project)

| File | Contents | When to Read |
|------|----------|--------------|
| `references/architecture.md` | Preloader, canvas+DOM layering, DOM-to-WebGL sync, page transitions, performance budgets | Site architecture decisions |
| `references/gsap-scroll-patterns.md` | GSAP core, ScrollTrigger, Lenis, SplitText basics, Motion, timelines | Any scroll-driven animation |
| `references/gsap-core-patterns.md` | gsap.context() cleanup, gsap.matchMedia() responsive, quickTo/quickSetter, registerEffect, gsap.utils, CSS variable animation, delayedCall, exportRoot | Every GSAP project |
| `references/gsap-helpers-cheatsheet.md` | Full import table, methods, timeline control, position parameter, stagger, easing, ScrollTrigger config, ticker | Quick lookup / cheatsheet |

### WebGL & Shaders

| File | Contents | When to Read |
|------|----------|--------------|
| `references/three-js-patterns.md` | Scene setup, cameras, materials, R3F, particles, post-processing, disposal | Any WebGL work |
| `references/shader-recipes.md` | Complete GLSL: noise displacement, chromatic aberration, distortion, grain, ripple, vignette, fresnel | Custom shader effects |

### GSAP Plugin References

| File | Contents | When to Read |
|------|----------|--------------|
| `references/gsap-text-plugins.md` | SplitText (new free API: mask, autoSplit, onSplit, aria), ScrambleText, TextPlugin | Text reveal, decode, typewriter effects |
| `references/gsap-svg-plugins.md` | MorphSVG (morphing, convertToPath, shapeIndex), DrawSVG (stroke animation), SVG transforms | SVG morphing, line drawing, stroke animation |
| `references/gsap-layout-plugins.md` | Flip (FLIP layout animation), Draggable (drag with physics), Observer (event unification) | Layout transitions, drag-to-reorder, scroll hijacking |
| `references/gsap-motion-physics.md` | MotionPath (SVG path animation), Physics2D (velocity/gravity), PhysicsProps (per-property physics) | Path animation, particle explosions, physics simulation |
| `references/gsap-scroll-advanced.md` | ScrollSmoother (vs Lenis comparison), advanced Observer patterns, velocity carousel | Choosing smooth scroll approach, full-page snapping |
| `references/gsap-easing-advanced.md` | CustomEase (SVG paths), CustomBounce (squash), CustomWiggle (oscillation), EasePack (RoughEase, SlowMo, ExpoScaleEase) | Custom/branded motion curves, glitch effects, dramatic reveals |
| `references/gsap-scroll-to-plugin.md` | ScrollToPlugin — animated scroll to positions/elements, offsetY, autoKill, container scrolling | Nav links, scroll-to-section, back-to-top, programmatic scrolling |
| `references/gsap-value-plugins.md` | InertiaPlugin (momentum/throw), Modifiers (per-frame value interception, infinite loops), Snap (live grid/array snapping), roundProps (integer rounding) | Momentum physics, infinite carousels, value snapping, pixel-perfect counters |

### Debugging & Patterns

| File | Contents | When to Read |
|------|----------|--------------|
| `references/gsap-common-mistakes.md` | 8 ScrollTrigger mistakes, 8 GSAP core mistakes, FOUC prevention, SVG gotchas, debugging checklist | Debugging, code review, avoiding pitfalls |
| `references/effects-cookbook.md` | 8 complete implementations: preloader, smooth scroll, text reveal, marquee, magnetic cursor, image distortion, parallax, camera path | Building specific effects |

### Routing to Other Skills

| Need | Skill |
|------|-------|
| Design direction (typography, color, axes, creative seed) | `frontend-design` Phase 2 |
| Standard DOM-based UI (no WebGL/canvas) | `frontend-design` Phase 3 |
| Creative direction brainstorming | `brainstorming` |
| Implementation planning | `writing-plans` |
| Testing strategy | `test-driven-development` |

---

## Output Contract

This skill produces:

1. **Architecture decisions** in `discovery.md` — tier selection, tech stack,
   performance budget, mobile strategy
2. **Working code** — HTML/CSS/JS with WebGL, shaders, scroll animations
3. **Verification results** in masterPlan step Results — fps, draw calls,
   disposal confirmed, responsive confirmed
