---
name: svg-art
description: "Generate distinctive, production-quality SVG artwork inline in code — decorative backgrounds, abstract illustrations, generative patterns, filter effects, section dividers, brand marks, data visualizations, and animated elements. Pure hand-coded SVG with no external image assets or libraries. Use this skill whenever the user asks for: SVG illustrations, decorative SVG backgrounds, SVG patterns, SVG textures, grain/noise effects, generative art, abstract shapes, blob shapes, topographic patterns, mesh gradients, hero illustrations, SVG icons, section dividers, SVG filters, duotone effects, glow effects, SVG data visualization, sparklines, inline charts, or any request where visual art should be created as SVG code rather than imported as an image. Also trigger when frontend-design produces a design that calls for decorative artwork, custom illustrations, or textured backgrounds. Do NOT use for: GSAP-driven SVG animation (use immersive-frontend), raster image editing, CSS-only effects that don't need SVG, or simple geometric shapes that don't require artistic direction."
---

# SVG Art

Generate SVG artwork directly in code — no external assets, no image
editors, no libraries. Everything from grain textures to abstract
illustrations to generative compositions, written as inline `<svg>`
elements or embedded in CSS.

**Announce at start:** "I'm using the svg-art skill to create this
artwork."

---

## Prerequisites

This skill operates within the conductor's execution phases:

- **Phase 1** (Direction) runs during Step 1 (Explore) — determine what
  kind of SVG art is needed and what aesthetic it should serve.
- **Phase 2** (Composition) produces the design approach — palette, style,
  complexity level.
- **Phase 3** (Implementation) runs during Step 3 (Execute) — write the
  SVG code.

If `frontend-design` ran first: inherit its design direction (color
palette, temperature, creative seed). The SVG art should reinforce
the page's aesthetic, not compete with it.

If `brainstorming` ran first: use its visual direction from `design.md`.
If the design includes a **Creative Brief**, read its Intent and Visual
Direction sections before the decision tree below. Let the brief's mood,
conceptual thread, and craftsmanship standard guide which techniques you
choose — don't pick techniques first and retrofit intent afterward.

---

## Phase 1: What Are We Making?

### Decision Tree

Answer these questions to determine which references to read:

```
What kind of SVG art is needed?
│
├── Background texture or pattern?
│   ├── Grain / noise / paper texture → Read: references/filter-recipes.md (§ Texture Filters)
│   ├── Geometric tile pattern (dots, lines, crosses, chevrons) → Read: references/decorative-backgrounds.md (§ Tile Patterns)
│   ├── Organic background (blobs, waves, topographic) → Read: references/decorative-backgrounds.md (§ Organic Backgrounds)
│   └── Mesh gradient or color field → Read: references/decorative-backgrounds.md (§ Gradient Techniques)
│
├── Illustration or decorative element?
│   ├── Hero section artwork → Read: references/illustration-techniques.md (§ Hero Art)
│   ├── Section dividers / separators → Read: references/illustration-techniques.md (§ Section Dividers)
│   ├── Abstract composition → Read: references/illustration-techniques.md (§ Abstract Compositions)
│   ├── Brand mark / logo shape → Read: references/illustration-techniques.md (§ Brand Marks)
│   ├── Icon system → Read: references/illustration-techniques.md (§ Icon Systems)
│   ├── Trust badges / security seals → Read: references/illustration-techniques.md (§ Trust Badges)
│   └── Micro-animations (pulsing, floating, drawing-on) → Read: references/micro-animations.md
│
├── Generative / algorithmic art?
│   ├── Mathematical curves (Lissajous, spirograph, sine composites) → Read: references/generative-patterns.md (§ Curves)
│   ├── Grid-based generative composition → Read: references/generative-patterns.md (§ Grid Art)
│   ├── Organic blobs / fluid shapes → Read: references/generative-patterns.md (§ Organic Shapes)
│   └── Particle fields / dot distributions → Read: references/generative-patterns.md (§ Distributions)
│
├── Filter effect or color treatment?
│   ├── Glow / neon → Read: references/filter-recipes.md (§ Glow)
│   ├── Emboss / metallic / 3D lighting → Read: references/filter-recipes.md (§ Lighting)
│   ├── Duotone / color matrix → Read: references/filter-recipes.md (§ Color)
│   ├── Displacement / distortion → Read: references/filter-recipes.md (§ Displacement)
│   └── Composite effect (layered filters) → Read: references/filter-recipes.md (§ Composites)
│
└── Data visualization?
    ├── Sparkline / inline chart → Read: references/illustration-techniques.md (§ Data Viz)
    └── Decorative data (abstract representation) → Read: references/generative-patterns.md (§ Data-Driven)
```

**Always read:** `references/svg-gotchas.md` before writing any SVG —
it covers viewBox, performance, accessibility, and browser quirks that
cause the most bugs.

---

## Phase 2: Composition Principles

These principles apply to ALL SVG art regardless of category. They're
what separates professional artwork from random shapes on a canvas.

### 1. Intentional negative space

Not every pixel needs to be filled. The empty areas are as important as
the drawn areas — they direct the eye, create breathing room, and
establish visual hierarchy. A composition with 40% negative space usually
reads better than one with 10%.

### 2. Limited palette

Constrain colors deliberately:
- **Decorative backgrounds**: 1-2 colors + transparency
- **Illustrations**: 2-4 colors from the page's design tokens
- **Generative art**: pick from a curated palette, not random RGB

If `frontend-design` set the page palette, pull SVG colors from those
CSS custom properties. The SVG should feel like part of the page, not
pasted on top of it:

```svg
<circle fill="var(--primary)" opacity="0.15"/>
<path stroke="var(--accent)" stroke-width="1.5"/>
```

### 3. Consistent stroke weight

Pick 1-2 stroke widths for the entire composition and stick to them.
Mixing 4 different stroke widths without reason looks sloppy. If you
need hierarchy, use opacity or color — not stroke width variation.

**Exception:** intentional weight contrast (a thick border with thin
interior detail) is a valid compositional choice, but it should be a
conscious design decision.

### 4. Smooth curves over jagged lines

When generating paths programmatically, use cubic beziers (`C`) or
quadratic beziers (`Q`) instead of sequences of `L` (line-to) commands.
The difference between a smooth organic blob and a jagged polygon is
curve interpolation.

For computed points, convert to smooth curves:
```
BAD:  M 0,50 L 10,45 L 20,52 L 30,48 L 40,55 ...
GOOD: M 0,50 C 5,47 15,43 20,52 S 35,46 40,55 ...
```

### 5. Depth through layering

A single flat shape is rarely interesting. Build depth by layering:
- Multiple translucent shapes that overlap
- Background → midground → foreground elements
- Subtle filter effects (blur on background layers, crisp foreground)

### 6. Scale awareness

Design for the container, not for a fixed size. Use `viewBox` to define
the coordinate space, and let the SVG scale to its container. Think about
what happens at different aspect ratios — a hero illustration needs to
work on both 16:9 desktop and 9:16 mobile.

### 7. Purpose-driven complexity

Every element should earn its place. Ask: "Does this shape serve the
composition, or am I adding it because the canvas feels empty?" If the
answer is the latter, try making existing elements larger or adjusting
spacing instead of adding more.

---

## Phase 3: Implementation

### SVG structure template

Every SVG should follow this structure:

```svg
<svg
  viewBox="0 0 800 600"
  xmlns="http://www.w3.org/2000/svg"
  role="img"           <!-- or aria-hidden="true" for decorative -->
  aria-labelledby="title desc"
>
  <title id="title">Short title</title>
  <desc id="desc">Longer description for screen readers</desc>

  <defs>
    <!-- Gradients, patterns, filters, clip paths -->
  </defs>

  <!-- Artwork layers, back to front -->
</svg>
```

For purely decorative SVGs (backgrounds, textures), use:
```svg
<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
```

### Inline vs CSS background

| Use inline `<svg>` when | Use CSS background when |
|---|---|
| The SVG is part of page content | It's a repeating pattern |
| It needs to be accessible | It's purely decorative texture |
| It interacts with page layout | It tiles or covers a section |
| It uses page CSS custom properties | It's a static background fill |

CSS background approach:
```css
.textured {
  background-image: url("data:image/svg+xml,...");
  /* or */
  background-image: url("data:image/svg+xml;base64,...");
}
```

### Color integration with page design

When the page uses CSS custom properties (from `frontend-design` or
`color-palettes.md`), reference them in SVG:

```svg
<!-- Inline SVG can use CSS custom properties directly -->
<rect fill="var(--surface-1)" />
<circle fill="var(--primary)" opacity="0.2" />
<path stroke="var(--border)" />
```

For CSS background SVGs (data URIs), bake the actual color values in
since CSS variables don't work inside data URIs.

### Performance budget

| Element | Budget | Why |
|---|---|---|
| Path nodes | < 500 per SVG | DOM rendering cost |
| Filter primitives | 2-3 per chain | Rasterization is expensive |
| Nested filters | Avoid | Compounds the cost exponentially |
| Animated elements | < 20 | Each triggers repaints |
| Total SVGs on page | < 10 complex ones | Memory + rendering |

If you need more complexity, consider:
- Combining paths with boolean operations
- Using `<use>` for repeated shapes
- Simplifying curves (fewer control points)
- Using CSS filters (`filter: blur()`, `opacity()`) instead of SVG
  filters where possible

---

## Page-Level Scroll Entrance Animations

When the page includes multiple sections (hero, badges, categories, data
viz), elements should reveal on scroll rather than appearing all at once on
load. This creates a curated, editorial feel — each section earns the
user's attention as they scroll to it.

**GSAP + ScrollTrigger** is the right tool for this when JavaScript is
available. Load via CDN:

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/ScrollTrigger.min.js"></script>
```

### Standard scroll entrance pattern

```javascript
gsap.registerPlugin(ScrollTrigger);

// Staggered card entrance (badges, categories, features)
gsap.utils.toArray('.badge-card').forEach((card, i) => {
  gsap.from(card, {
    y: 40,
    opacity: 0,
    duration: 0.8,
    delay: i * 0.15,
    ease: 'power2.out',
    scrollTrigger: {
      trigger: card,
      start: 'top 85%',
      toggleActions: 'play none none none'
    }
  });
});

// Section title fade-in
gsap.utils.toArray('.section-title').forEach(title => {
  gsap.from(title, {
    y: 20,
    opacity: 0,
    duration: 0.6,
    ease: 'power2.out',
    scrollTrigger: { trigger: title, start: 'top 85%' }
  });
});
```

### Data visualization animations on scroll

Animate chart elements when they enter the viewport — bars grow to their
final width, donut charts draw their arcs, sparklines trace their paths:

```javascript
// Bar chart: animate width from 0
gsap.utils.toArray('.bar-fill').forEach(bar => {
  const targetWidth = bar.style.width;
  bar.style.width = '0%';
  gsap.to(bar, {
    width: targetWidth,
    duration: 1.2,
    ease: 'power2.out',
    scrollTrigger: { trigger: bar, start: 'top 85%' }
  });
});

// Donut chart: animate stroke-dashoffset
gsap.from('.donut-value', {
  strokeDashoffset: circumference,
  duration: 1.5,
  ease: 'power2.out',
  scrollTrigger: { trigger: '.donut-chart', start: 'top 80%' }
});
```

**This is different from immersive-frontend.** Scroll entrance animations
are simple reveals (fade + slide, staggered timing). They don't need
Three.js, WebGL, or complex scroll choreography. Use GSAP+ScrollTrigger
directly in svg-art pages when the design benefits from progressive
disclosure on scroll.

---

## Anti-Patterns

These produce amateur-looking SVG art — avoid them:

| Anti-pattern | Why it's bad | Do instead |
|---|---|---|
| Random colors without palette | Looks chaotic, clashes with page | Use 2-4 colors from page tokens |
| Perfect symmetry everywhere | Feels mechanical, robotic | Introduce slight asymmetry |
| Clipart basic shapes | Circle + rectangle ≠ illustration | Combine shapes, use masks/clips, add curves |
| feTurbulence on everything | Visual clutter, not sophistication | Use noise purposefully, mask to areas |
| 5+ stacked SVG filters | Performance tanks, muddy results | Limit to 2-3 filter primitives |
| Inconsistent stroke widths | Looks sloppy and unintentional | Pick 1-2 weights, stick to them |
| No viewBox attribute | Breaks responsive scaling | Always define viewBox |
| Ignoring accessibility | Decorative SVGs pollute screen readers | aria-hidden="true" or role="img" + title/desc |
| Gradient as the only technique | Browser inconsistency, boring | Combine with shapes, texture, transparency |
| Too many competing elements | Eye fatigue, no focal point | 3-5 visual layers max, embrace whitespace |
| Line segments for curves | Jagged edges on organic shapes | Use C/Q bezier commands |
| Fixed width/height without viewBox | Doesn't scale, breaks on mobile | Use viewBox, let CSS control sizing |

---

## Relationship to Other Skills

| Skill | Relationship |
|---|---|
| `frontend-design` | Provides design direction (palette, temperature, creative seed). SVG art inherits these decisions. frontend-design may invoke svg-art when a design needs illustration. |
| `immersive-frontend` | Handles GSAP-driven SVG animation (MorphSVG, DrawSVG, motion paths). svg-art creates the artwork; immersive-frontend animates it. |
| `color-palettes.md` | SVG art should pull colors from the page's palette, not invent its own. |

---

## Reference Files

| Situation | Read |
|---|---|
| Noise, grain, glow, emboss, duotone, displacement | `references/filter-recipes.md` |
| Mathematical curves, grids, blobs, distributions | `references/generative-patterns.md` |
| Tile patterns, organic backgrounds, gradients | `references/decorative-backgrounds.md` |
| Hero art, dividers, compositions, icons, badges, data viz | `references/illustration-techniques.md` |
| Pulsing, floating, drawing-on, orbital, hover animations | `references/micro-animations.md` |
| viewBox, performance, accessibility, browser quirks | `references/svg-gotchas.md` |
