# Illustration Techniques

Principles and patterns for creating SVG illustrations, compositions,
dividers, brand marks, icons, and data visualizations.

## Table of Contents

1. [Composition Rules](#composition-rules) — visual hierarchy, balance, focal points
2. [Hero Art](#hero-art) — full-width hero illustrations
3. [Section Dividers](#section-dividers) — when to use, color direction, responsive scaling
4. [Abstract Compositions](#abstract-compositions) — decorative artwork
5. [Brand Marks](#brand-marks) — simple logo-like shapes
6. [Icon Systems](#icon-systems) — UI icons, category icons, optical sizing, warmth
7. [Trust Badges](#trust-badges) — tinted containers, consistent icon style, dark mode
8. [Data Visualization](#data-visualization) — charts and data art

---

## Composition Rules

These rules apply to ALL SVG illustrations regardless of style. They're
what makes the difference between professional and amateur output.

### Rule of Thirds

Divide the viewBox into a 3×3 grid. Place focal elements at the
intersection points, not dead center. For a viewBox of `0 0 900 600`:

```
Intersections at:
  (300, 200)  (600, 200)
  (300, 400)  (600, 400)
```

Center composition is static. Off-center creates visual tension and
interest.

### Visual Weight

Larger, darker, or more saturated elements feel "heavier." Balance
heavy elements with lighter ones on the opposite side. A small, bright
accent can balance a large, muted shape.

### Foreground / Midground / Background

Layer at least 2-3 depth planes:
- **Background**: large, low-opacity shapes or textures
- **Midground**: main compositional elements
- **Foreground**: small accent details, closest to viewer

Apply blur to background layers and full opacity to foreground for
atmospheric depth:

```svg
<!-- Background: blurred, low opacity -->
<g opacity="0.15" filter="url(#bg-blur)">
  <circle cx="200" cy="300" r="200" fill="var(--primary)" />
</g>

<!-- Midground: main shapes -->
<g opacity="0.8">
  <path d="..." fill="var(--accent)" />
</g>

<!-- Foreground: crisp accents -->
<circle cx="400" cy="250" r="8" fill="var(--primary)" />
```

### Rhythm and Repetition

Repeating elements at varying scales creates rhythm. Not identical
copies — varied sizes, rotations, or opacities of the same motif:

```svg
<!-- Same circle motif at different scales and positions -->
<circle cx="100" cy="200" r="40" opacity="0.3" />
<circle cx="250" cy="150" r="25" opacity="0.5" />
<circle cx="380" cy="220" r="60" opacity="0.2" />
<circle cx="500" cy="180" r="15" opacity="0.7" />
```

### Breathing Room

Leave at least 20-30% of the viewBox as negative space. Crowded
compositions feel suffocating. If an illustration feels cluttered,
remove elements rather than shrinking them.

---

## Hero Art

### Abstract Geometric Hero

Overlapping geometric shapes with transparency:

```svg
<svg viewBox="0 0 600 400" xmlns="http://www.w3.org/2000/svg"
  role="img" aria-labelledby="hero-title">
  <title id="hero-title">Abstract geometric composition</title>
  <defs>
    <linearGradient id="hero-grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="var(--primary)" stop-opacity="0.15" />
      <stop offset="100%" stop-color="var(--accent)" stop-opacity="0.08" />
    </linearGradient>
  </defs>

  <!-- Large background circle, off-center -->
  <circle cx="420" cy="180" r="220" fill="url(#hero-grad)" />

  <!-- Overlapping rectangles -->
  <rect x="280" y="80" width="200" height="200"
    fill="var(--primary)" opacity="0.08" rx="4"
    transform="rotate(12 380 180)" />
  <rect x="320" y="120" width="160" height="160"
    fill="var(--accent)" opacity="0.06" rx="4"
    transform="rotate(-8 400 200)" />

  <!-- Accent line -->
  <line x1="300" y1="100" x2="520" y2="280"
    stroke="var(--primary)" stroke-width="1" opacity="0.2" />

  <!-- Small accent dots (rhythm) -->
  <circle cx="350" cy="140" r="4" fill="var(--primary)" opacity="0.4" />
  <circle cx="480" cy="250" r="3" fill="var(--accent)" opacity="0.5" />
  <circle cx="310" cy="280" r="5" fill="var(--primary)" opacity="0.3" />
</svg>
```

### Organic Hero

Layered organic blobs for a softer feel:

```svg
<svg viewBox="0 0 800 500" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <filter id="hero-soft">
      <feGaussianBlur stdDeviation="20" />
    </filter>
  </defs>

  <!-- Layer 1: large background blob -->
  <path d="M 500 50 C 700 30, 780 200, 700 350
           S 500 480, 350 400 C 200 350, 250 100, 500 50 Z"
    fill="var(--primary)" opacity="0.06"
    filter="url(#hero-soft)" />

  <!-- Layer 2: midground shape -->
  <path d="M 450 100 C 600 80, 680 220, 620 320
           S 400 420, 300 350 C 220 300, 280 130, 450 100 Z"
    fill="var(--accent)" opacity="0.08" />

  <!-- Layer 3: sharp accent -->
  <circle cx="550" cy="200" r="80"
    fill="none" stroke="var(--primary)" stroke-width="1" opacity="0.15" />
</svg>
```

### Dark Dramatic Hero

The most impactful hero pattern — a dark charcoal background with organic
glowing shapes, scattered accent elements, and layered depth. Creates
immediate drama and premium feel. Best for brands that want presence over
minimalism.

```svg
<svg viewBox="0 0 1000 500" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <radialGradient id="glow-1" cx="30%" cy="40%">
      <stop offset="0%" stop-color="var(--primary)" stop-opacity="0.15"/>
      <stop offset="100%" stop-color="var(--primary)" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glow-2" cx="70%" cy="60%">
      <stop offset="0%" stop-color="var(--accent)" stop-opacity="0.1"/>
      <stop offset="100%" stop-color="var(--accent)" stop-opacity="0"/>
    </radialGradient>
    <filter id="atmos-blur">
      <feGaussianBlur stdDeviation="30"/>
    </filter>
  </defs>

  <!-- Dark charcoal background (not pure black) -->
  <rect width="1000" height="500" fill="#2a2420"/>

  <!-- Atmosphere: large blurred glow pools -->
  <circle cx="300" cy="200" r="200" fill="url(#glow-1)"
    filter="url(#atmos-blur)"/>
  <circle cx="700" cy="300" r="180" fill="url(#glow-2)"
    filter="url(#atmos-blur)"/>

  <!-- Organic blob with soft blur -->
  <path d="M200,150 C250,80 400,120 380,200 S300,280 200,250 Z"
    fill="var(--primary)" opacity="0.08"
    filter="url(#atmos-blur)"/>

  <!-- Connection lines with gradient stroke fade -->
  <line x1="250" y1="180" x2="650" y2="280"
    stroke="var(--primary)" stroke-width="0.5" opacity="0.15"/>

  <!-- Brand marks at 3 scales (asymmetric placement) -->
  <g opacity="0.6" transform="translate(350 100) scale(0.4)">
    <!-- Largest brand mark here -->
  </g>
  <g opacity="0.3" transform="translate(720 160) scale(0.25)">
    <!-- Medium mark -->
  </g>
  <g opacity="0.15" transform="translate(150 350) scale(0.15)">
    <!-- Smallest mark -->
  </g>

  <!-- Community dot clusters (4-8 dots in organic groups) -->
  <g opacity="0.4">
    <circle cx="500" cy="350" r="3" fill="var(--primary)"/>
    <circle cx="515" cy="345" r="2" fill="var(--primary)"/>
    <circle cx="508" cy="360" r="2.5" fill="var(--primary)"/>
    <circle cx="525" cy="355" r="1.5" fill="var(--primary)"/>
  </g>

  <!-- Concentric decorative rings (off-center) -->
  <g transform="translate(750 180)" opacity="0.1">
    <circle r="40" fill="none" stroke="var(--primary)" stroke-width="0.5"/>
    <circle r="60" fill="none" stroke="var(--primary)" stroke-width="0.5"/>
    <circle r="80" fill="none" stroke="var(--primary)" stroke-width="0.5"/>
  </g>

  <!-- Foreground: breathing dots with SMIL -->
  <circle cx="180" cy="120" r="3" fill="var(--primary)" opacity="0.5">
    <animate attributeName="r" values="3;4;3" dur="4s"
      calcMode="spline" keySplines="0.4 0 0.6 1; 0.4 0 0.6 1"
      repeatCount="indefinite"/>
    <animate attributeName="opacity" values="0.5;0.8;0.5" dur="4s"
      calcMode="spline" keySplines="0.4 0 0.6 1; 0.4 0 0.6 1"
      repeatCount="indefinite"/>
  </circle>
</svg>
```

**Key elements:**
- **Dark charcoal, not black** — `#2a2420` (warm) or `#1a1f2e` (cool).
  Pure `#000` feels flat and empty.
- **Blurred atmosphere blobs** — large circles with radial gradients and
  `feGaussianBlur`. These create ambient light pools that give depth.
- **Brand marks at 3 scales** — largest at 40-60% opacity, medium at 25%,
  smallest at 15%. Placed asymmetrically. Creates brand presence without
  being wallpaper.
- **Community dot clusters** — groups of 4-8 small dots in organic layouts.
  Scatter 2-3 clusters to suggest network/community.
- **Connection lines** with gradient strokes that fade at endpoints.
- **Concentric rings** at low opacity, off-center, as compositional anchors.
- **SMIL breathing dots** — 3-5 foreground dots with staggered `begin`
  offsets for ambient life.
- **Cultural motifs** (optional) — for brands with geographic identity, add
  one subtle motif (Mediterranean arch, Nordic pattern, wave form) at under
  5% opacity as background texture.

### Placement Strategy

Hero art typically goes in one of these positions:
- **Behind text**: full-width, low opacity, in the hero section
  background. Content must remain readable.
- **Side illustration**: positioned right or left of text using CSS
  grid. Can be higher opacity since it doesn't overlap text.
- **Decorative corner**: small composition anchored to a corner,
  fading toward the center.

For behind-text placement, keep opacity below 0.15 for light themes
and below 0.1 for dark themes to maintain text contrast.

---

## Section Dividers

### When to use dividers — and when not to

The highest-end marketing sites (Linear, Stripe, Vercel) rarely use shape
dividers at all. They transition sections with whitespace + background
color changes. Shape dividers belong on playful or organic brands, not
minimal/tech aesthetics. Before reaching for a shape divider, ask: would
a simple background-color change with generous padding look better?

**Use shape dividers when:**
- The brand is warm, organic, or playful (not minimal/tech)
- Two adjacent sections have the same background color and need separation
- The design calls for an illustrative or hand-crafted feel

**Skip shape dividers when:**
- The site has a clean/minimal aesthetic
- A background-color change already creates sufficient contrast
- The page already has 2+ shape dividers (more than 2-3 per page is
  excessive — they lose their impact)

### The color direction rule

The fill color of a divider matches the **destination section** (below),
not the source (above). The divider is the "leading edge" of the next
section reaching up into the current one:

```
┌─────────────────────────────┐
│  Section A (--surface-0)    │
│                             │
│  ~~~~~~~~~~~~~ ←── fill matches Section B, not A
├─────────────────────────────┤
│  Section B (--surface-1)    │
│                             │
└─────────────────────────────┘
```

### Responsive scaling

Shape dividers must not have a fixed pixel height — they look too thin on
wide screens and too thick on narrow ones. Use `clamp()` for responsive
height:

```css
.section-divider {
  width: 100%;
  height: clamp(40px, 5vw, 80px); /* scales with viewport */
  display: block;
}
```

Always set `preserveAspectRatio="none"` on the SVG so the shape stretches
to fill the container width without maintaining proportions.

### Curved Divider

The simplest and most versatile shape. Works for most brands:

```svg
<svg viewBox="0 0 1440 80" preserveAspectRatio="none" aria-hidden="true"
  class="section-divider">
  <path d="M 0 80 Q 720 0 1440 80" fill="var(--surface-1)" />
</svg>
```

### Layered Wave

Multiple overlapping curves at different opacities create depth. More
premium than a single curve — the layering suggests craft:

```svg
<svg viewBox="0 0 1440 120" preserveAspectRatio="none" aria-hidden="true"
  class="section-divider">
  <!-- Back wave: lighter, offset -->
  <path d="M 0 120 Q 360 40 720 80 T 1440 60 L 1440 120 Z"
    fill="var(--surface-1)" opacity="0.3" />
  <!-- Front wave: full opacity -->
  <path d="M 0 120 Q 360 60 720 90 T 1440 70 L 1440 120 Z"
    fill="var(--surface-1)" />
</svg>
```

### Angled Divider

Clean diagonal. Works well for tech and professional brands:

```svg
<svg viewBox="0 0 1440 80" preserveAspectRatio="none" aria-hidden="true"
  class="section-divider">
  <polygon points="0,80 1440,0 1440,80" fill="var(--surface-1)" />
</svg>
```

### Torn Paper Edge

Irregular edge using midpoint displacement for organic/craft brands:

```svg
<svg viewBox="0 0 1440 60" preserveAspectRatio="none" aria-hidden="true"
  class="section-divider">
  <path d="M 0 30
    L 60 28 L 120 35 L 180 25 L 240 32 L 300 22
    L 360 33 L 420 27 L 480 36 L 540 24 L 600 31
    L 660 26 L 720 34 L 780 23 L 840 30 L 900 28
    L 960 35 L 1020 25 L 1080 32 L 1140 27 L 1200 33
    L 1260 24 L 1320 31 L 1380 26 L 1440 30
    L 1440 60 L 0 60 Z"
    fill="var(--surface-1)" />
</svg>
```

For more organic edges, use the `terrainPath()` function from
`generative-patterns.md` § Terrain.

### Decorative Line Dividers (often better than shapes)

For many designs, a decorative SVG line is more elegant than a full-width
shape divider. These work within the page's max-width container and feel
more intentional than generic curves:

**Gradient fade line:**
```css
.section-separator {
  border: none;
  height: 1px;
  background: linear-gradient(to right, transparent, var(--sand), transparent);
  margin: 0 40px;
  max-width: 1120px;
}
```

**Dual wave with gradient fade:**
```svg
<svg viewBox="0 0 1200 60" preserveAspectRatio="none" aria-hidden="true"
  style="width: 100%; height: 60px;">
  <defs>
    <linearGradient id="wave-grad" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="var(--primary)" stop-opacity="0"/>
      <stop offset="50%" stop-color="var(--primary)" stop-opacity="0.25"/>
      <stop offset="100%" stop-color="var(--primary)" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <path d="M0,30 C200,10 400,50 600,30 C800,10 1000,50 1200,30"
    fill="none" stroke="url(#wave-grad)" stroke-width="2"/>
  <path d="M0,36 C150,18 350,54 600,36 C850,18 1050,54 1200,36"
    fill="none" stroke="url(#wave-grad)" stroke-width="1" opacity="0.5"/>
</svg>
```

**Brand motif divider** — use the brand's logo or icon as a centered
ornament with fading dot trails or lines extending to each side:
```svg
<svg viewBox="0 0 1200 40" preserveAspectRatio="xMidYMid meet"
  aria-hidden="true" style="width: 100%; height: 40px;">
  <defs>
    <linearGradient id="dot-fade-l" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="var(--primary)" stop-opacity="0"/>
      <stop offset="100%" stop-color="var(--primary)" stop-opacity="0.3"/>
    </linearGradient>
    <linearGradient id="dot-fade-r" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="var(--primary)" stop-opacity="0.3"/>
      <stop offset="100%" stop-color="var(--primary)" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <!-- Left trail -->
  <line x1="100" y1="20" x2="560" y2="20"
    stroke="url(#dot-fade-l)" stroke-width="1" stroke-dasharray="2 8"/>
  <!-- Center brand mark (scaled down) -->
  <g transform="translate(588, 5) scale(0.4)">
    <!-- Insert the brand's logo/icon SVG path here -->
  </g>
  <!-- Right trail -->
  <line x1="640" y1="20" x2="1100" y2="20"
    stroke="url(#dot-fade-r)" stroke-width="1" stroke-dasharray="2 8"/>
</svg>
```

**Geometric pattern band** — a repeating pattern with edge fade mask:
```svg
<svg viewBox="0 0 1200 24" preserveAspectRatio="none" aria-hidden="true"
  style="width: 100%; height: 24px;">
  <defs>
    <pattern id="geo" x="0" y="0" width="48" height="24"
      patternUnits="userSpaceOnUse">
      <path d="M0,12 L12,0 L24,12 L12,24Z" fill="var(--primary)"
        opacity="0.08"/>
      <path d="M24,12 L36,0 L48,12 L36,24Z" fill="var(--primary)"
        opacity="0.05"/>
    </pattern>
    <linearGradient id="geo-mask-g" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="white" stop-opacity="0"/>
      <stop offset="20%" stop-color="white" stop-opacity="1"/>
      <stop offset="80%" stop-color="white" stop-opacity="1"/>
      <stop offset="100%" stop-color="white" stop-opacity="0"/>
    </linearGradient>
    <mask id="geo-fade">
      <rect width="1200" height="24" fill="url(#geo-mask-g)"/>
    </mask>
  </defs>
  <rect width="1200" height="24" fill="url(#geo)" mask="url(#geo-fade)"/>
</svg>
```

### Decorative Horizontal Rule

Replace `<hr>` with a styled SVG element for inline content separation
within a section (between paragraphs, cards, etc.):

```svg
<svg viewBox="0 0 200 20" xmlns="http://www.w3.org/2000/svg"
  aria-hidden="true" style="width: 120px; height: 12px; margin: 2rem auto;">
  <circle cx="10" cy="10" r="3" fill="var(--primary)" opacity="0.4" />
  <line x1="25" y1="10" x2="175" y2="10"
    stroke="var(--border)" stroke-width="1" />
  <circle cx="190" cy="10" r="3" fill="var(--primary)" opacity="0.4" />
</svg>
```

### Common mistakes

| Mistake | Why it looks amateur | Fix |
|---|---|---|
| Fixed px height (e.g. `height: 60px`) | Too thin on 4K, too thick on mobile | Use `clamp(40px, 5vw, 80px)` |
| Fill matches source section | Divider looks pasted-on, wrong visual weight | Fill matches DESTINATION section |
| Missing `preserveAspectRatio="none"` | Shape doesn't stretch to viewport width | Always set it on full-width dividers |
| 4+ dividers on one page | Each one loses impact, page feels choppy | Max 2-3, use whitespace for the rest |
| Shape divider on a minimal/tech site | Clashes with clean aesthetic | Use decorative lines or background-color change |
| Overly complex shapes (multi-layer fractals) | Draws attention to itself, distracts from content | Simpler shapes work better |
| Only knowing shape dividers | Generic curves/angles when a brand motif divider would be more distinctive | Try the gradient-fade or brand-motif patterns above |

---

## Abstract Compositions

### Geometric Constellation

Connected dots forming a network pattern:

```svg
<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <style>
      .node { fill: var(--primary); }
      .edge { stroke: var(--border); stroke-width: 0.5; opacity: 0.3; }
    </style>
  </defs>

  <!-- Edges (lines between nodes) -->
  <line class="edge" x1="80" y1="60" x2="200" y2="120" />
  <line class="edge" x1="200" y1="120" x2="320" y2="80" />
  <line class="edge" x1="200" y1="120" x2="150" y2="220" />
  <line class="edge" x1="320" y1="80" x2="300" y2="200" />
  <line class="edge" x1="150" y1="220" x2="300" y2="200" />
  <line class="edge" x1="80" y1="60" x2="50" y2="180" />

  <!-- Nodes (dots) -->
  <circle class="node" cx="80" cy="60" r="4" opacity="0.6" />
  <circle class="node" cx="200" cy="120" r="6" opacity="0.8" />
  <circle class="node" cx="320" cy="80" r="3" opacity="0.5" />
  <circle class="node" cx="150" cy="220" r="5" opacity="0.7" />
  <circle class="node" cx="300" cy="200" r="4" opacity="0.6" />
  <circle class="node" cx="50" cy="180" r="3" opacity="0.4" />
</svg>
```

Vary node sizes to create hierarchy. The largest node is the focal
point.

### Concentric Rings

```svg
<svg viewBox="0 0 400 400" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <g transform="translate(200 200)">
    <circle r="40" fill="none" stroke="var(--primary)" stroke-width="1" opacity="0.6" />
    <circle r="80" fill="none" stroke="var(--primary)" stroke-width="0.8" opacity="0.4" />
    <circle r="120" fill="none" stroke="var(--primary)" stroke-width="0.6" opacity="0.25" />
    <circle r="160" fill="none" stroke="var(--primary)" stroke-width="0.5" opacity="0.15" />
    <!-- Accent dot on one ring -->
    <circle cx="80" cy="0" r="5" fill="var(--accent)" opacity="0.8" />
  </g>
</svg>
```

### Overlapping Translucent Shapes

```svg
<svg viewBox="0 0 500 400" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <rect x="100" y="80" width="200" height="200" rx="8"
    fill="var(--primary)" opacity="0.08" transform="rotate(5 200 180)" />
  <circle cx="300" cy="200" r="120"
    fill="var(--accent)" opacity="0.06" />
  <rect x="220" y="140" width="150" height="150" rx="8"
    fill="var(--primary)" opacity="0.05" transform="rotate(-10 295 215)" />
</svg>
```

---

## Brand Marks

Simple geometric shapes that work as decorative brand elements. Not
logos (those need designers), but geometric motifs that give a page
identity.

### Rules for brand marks:
- **Maximum 3 shapes** — simplicity is key
- **Works at all sizes** — test at 24px and 200px
- **Single or two-color** — use page's primary + accent
- **No fine detail** — strokes ≥ 2px, gaps ≥ 4px
- **Avoid 4-fold symmetry** — marks with identical top/right/bottom/left
  quadrants feel generic and compass-like. Break symmetry: make one arm
  thicker, add a notch, offset the center, or use 3-fold rotation instead.
- **Prefer asymmetry** — the most memorable marks have a "this way up"
  orientation. A mark that looks the same at any rotation is forgettable.

### Creative strategies for brand marks

Instead of starting with geometric primitives (circles, squares),
start with the *concept* the brand represents:

1. **Negative space** — the mark IS the gap between shapes. Two shapes
   create a third implied shape in the space between them.
2. **Letterform extraction** — take the initial letter and simplify it
   into 2-3 strokes. Not the whole letter — just its most distinctive
   feature (the crossbar of an A, the bowl of a P).
3. **Metaphor collision** — combine two unrelated shapes that together
   suggest the brand's domain (leaf + circuit = green tech).
4. **Incomplete shape** — an almost-closed circle, a broken square.
   The brain completes it, making it more engaging than a closed shape.

### Examples

**Stacked circles (with asymmetry):**
```svg
<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
  <circle cx="18" cy="14" r="10" fill="var(--primary)" />
  <circle cx="24" cy="28" r="8" fill="var(--accent)" opacity="0.6" />
</svg>
```

**Corner bracket:**
```svg
<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
  <path d="M 8 8 L 8 32 L 20 32" fill="none"
    stroke="var(--primary)" stroke-width="3" stroke-linecap="round" />
</svg>
```

**Negative-space arrow (two shapes create an implied arrow):**
```svg
<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
  <rect x="4" y="4" width="14" height="32" rx="3" fill="var(--primary)" />
  <rect x="22" y="10" width="14" height="20" rx="3" fill="var(--primary)" />
  <!-- The gap between shapes implies forward motion -->
</svg>
```

**Broken circle (incomplete, memorable):**
```svg
<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
  <path d="M 28 8 A 14 14 0 1 0 32 22" fill="none"
    stroke="var(--primary)" stroke-width="3" stroke-linecap="round" />
  <circle cx="30" cy="22" r="3" fill="var(--accent)" />
</svg>
```

### Favicons & App Icons

Favicons are the hardest brand mark challenge: they must be instantly
recognizable at 16×16px in a browser tab, yet look polished at 256px.

**Design process — small to large, not large to small:**

1. **Start at 16px.** Sketch the mark in a 16×16 grid. If it doesn't
   read at this size, no amount of detail at larger sizes will save it.
2. **Use filled shapes, not strokes.** At 16px, a 2px stroke is 12.5%
   of the width — it dominates. Filled polygons/paths give more control.
3. **Test against a busy tab bar.** The mark competes with 10+ other
   favicons. It needs to be distinctive in silhouette, not just color.
4. **Scale up last.** Once the 16px version works, scale to 32, 64, 256.
   Add subtle detail at larger sizes if needed, but the core shape must
   be the same.

**Favicon-specific rules:**
- **viewBox: `0 0 32 32`** — standard favicon grid. Even coordinates
  align to the 16px pixel grid when halved.
- **2px padding** from viewBox edges (content between 2,2 and 30,30)
- **Integer coordinates only** — sub-pixel values blur at small sizes
- **Maximum 2 colors** — one color + white/transparent is ideal
- **No text** — unreadable below 32px
- **Test silhouette** — fill the entire mark black on white. If you
  can still identify it, the shape is strong enough.
- **Avoid the symmetry trap** — 4-fold symmetric marks (pinwheels,
  plus signs, crosshairs) are the most common AI-generated favicon
  pattern. They look generic. Break symmetry deliberately.

**Favicon concepts that work well at 16px:**
- A single bold letterform (the app's initial, heavily stylized)
- An asymmetric abstract mark (tilted square with a notch, offset dot)
- A container + element (circle with off-center dot, square with corner cut)
- A negative-space trick (two shapes creating a third implied shape)

**App icon (mobile home screen) additions:**
- Show the mark on a colored background (60px rounded square)
- White mark on brand color is the standard pattern
- Test on both iOS (13.5px radius) and Android (adaptive icon circle)
- The mark should fill ~60% of the icon area — too small looks lost,
  too large looks cramped

**Presentation format for favicon deliverables:**
```
1. Size grid: 16, 32, 48, 64, 128, 256px — on light AND dark backgrounds
2. Browser tab mock: favicon at 16px next to app name text
3. Mobile home screen mock: 60px rounded icon on branded background
4. Design rationale: concept, color choice, 16px strategy
```

Use `<symbol>` + `<use>` to define the icon once and reuse it across
all sizes and contexts. This keeps the HTML DRY and ensures consistency.

---

## Icon Systems

### Two tiers of icons

Icons serve two distinct purposes that require different design parameters:

| | UI Icons | Category / Feature Icons |
|---|---|---|
| **Purpose** | Navigation, actions, controls | Represent concepts, categories, features |
| **viewBox** | `0 0 24 24` | `0 0 48 48` |
| **Stroke width** | 1.5–2px | 2.5–3px |
| **Detail level** | Minimal — must read at 16px | Moderate — displayed at 32–64px |
| **Color** | `currentColor` (inherits text color) | Accent color, duotone, or on tinted background |
| **Examples** | Arrows, close, menu, check | "Security", "Analytics", "Collaboration" |

### Warmth through geometry

The single biggest factor in whether icons feel warm or clinical is the
cap and join style. This is a design choice, not a default:

| Property | Warm / Friendly | Technical / Precise |
|---|---|---|
| `stroke-linecap` | `round` | `square` or `butt` |
| `stroke-linejoin` | `round` | `miter` |
| Corner radius | `rx="2"` on rects | Sharp corners (`rx="0"`) |
| Overall feel | Approachable, human | Precise, engineered |

Most brands benefit from round caps/joins. Reserve square/butt for
developer tools, code editors, and engineering-focused products.

### UI Icon Template

```svg
<svg viewBox="0 0 24 24" width="24" height="24"
  fill="none" stroke="currentColor" stroke-width="2"
  stroke-linecap="round" stroke-linejoin="round">
  <!-- Icon paths here — stay within 2px padding (4,4 to 20,20) -->
</svg>
```

### UI Icon Design Rules

1. **Same viewBox** for all icons in a set (24×24 standard)
2. **Stroke-width-to-viewBox ratio**: 6–8% (1.5–2px on 24px). Below 6%
   looks spindly; above 10% looks heavy.
3. **Same cap and join** across the entire icon set — never mix round
   and square within one system
4. **2px padding** from viewBox edges — nothing touches the boundary
5. **Pixel-aligned** — align key coordinates to the half-pixel grid
   (e.g., 4.5, 12) for crisp rendering at 1× scale
6. **Filled vs outlined** — pick one style and commit. Never mix filled
   and outlined icons in the same context (e.g., navigation).

### Optical sizing with keyline shapes

Not all shapes have the same perceived size at the same dimensions. A
circle looks smaller than a square at the same pixel width. Use keyline
shapes to normalize perceived size within a 48px grid:

```
48px total grid
├── 2px padding each side → 44px live area
│
│   Keyline shapes (all feel the same visual size):
│   ├── Circle:    diameter 42px (fills most of live area)
│   ├── Square:    36×36px (optically balanced with circle)
│   ├── Landscape: 44×36px
│   └── Portrait:  36×44px
```

The circle is largest because circles have less visual mass per pixel
than rectangles. These ratios ensure icons feel balanced when placed
side-by-side.

### The blur test

After designing an icon set, apply a Gaussian blur (or squint). All icons
should have approximately the same visual weight — the same amount of
"ink" when blurred to a blob. If one icon is noticeably lighter or darker
than the others, adjust its stroke width or filled area.

### Common UI Icon Shapes

```svg
<!-- Arrow right -->
<path d="M 5 12 L 19 12 M 13 6 L 19 12 L 13 18" />

<!-- Check -->
<path d="M 5 12 L 10 17 L 19 7" />

<!-- Plus -->
<path d="M 12 5 L 12 19 M 5 12 L 19 12" />

<!-- Menu (hamburger) -->
<path d="M 4 7 L 20 7 M 4 12 L 20 12 M 4 17 L 20 17" />

<!-- Close (X) -->
<path d="M 6 6 L 18 18 M 18 6 L 6 18" />

<!-- External link -->
<path d="M 10 4 L 20 4 L 20 14 M 20 4 L 8 16" />
<rect x="4" y="8" width="12" height="12" rx="2" />
```

### Category / Feature Icon Template

Category icons represent concepts (security, analytics, speed) rather
than actions. They're larger, more detailed, and typically displayed on
tinted backgrounds in feature grids or pricing tables:

```svg
<svg viewBox="0 0 48 48" width="48" height="48"
  fill="none" stroke="var(--primary)" stroke-width="2.5"
  stroke-linecap="round" stroke-linejoin="round">
  <!-- Icon content — use 4px padding (content within 4,4 to 44,44) -->
</svg>
```

### Category icon color treatment

The best category icon systems use **domain-specific colors** — each
category gets a hue that intuitively maps to its concept. This is more
useful for navigation than painting everything the brand accent color,
because users can scan by color:

```css
/* Domain-specific color mapping */
.cat-plumbing .icon-wrap  { background: #e8f4fd; } /* water blue */
.cat-plumbing svg          { color: #2b7bb9; }
.cat-electrical .icon-wrap { background: #fff8e1; } /* energy yellow */
.cat-electrical svg        { color: #d4a017; }
.cat-cleaning .icon-wrap   { background: #e8f5e9; } /* fresh green */
.cat-cleaning svg          { color: #4a6741; }
.cat-painting .icon-wrap   { background: #fdebd6; } /* warm terracotta */
.cat-painting svg          { color: #d9613d; }
```

**How to pick domain colors**: choose a hue that the user would
instinctively associate with the concept (blue=water, yellow=electricity,
green=nature). Then create a very light tint (90-95% white mixed in) for
the background and a medium-saturated shade for the icon stroke.

**When to use unified brand color instead**: if the categories are
abstract (pricing tiers, feature lists) rather than domain-specific, use
the brand accent color for all icons. Domain-specific colors only work
when the categories have real-world associations.

### Category icon containers

Large rounded-rectangle containers (96px with 24px radius) make category
icons feel substantial and scannable. The icon sits centered inside:

```css
.category-icon-wrap {
  width: 96px;
  height: 96px;
  border-radius: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: box-shadow 0.3s ease;
}
.category-icon-wrap:hover {
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
}
.category-icon-wrap svg {
  width: 44px;
  height: 44px;
}
```

### Category icon detail level

Category icons at 44×48px display size can be more detailed and
illustrative than UI icons. They should be **specific to the domain**,
not abstract:

- Plumbing: faucet with valve handle and water drops (not a generic wrench)
- Electrical: lightning bolt with spark dots (not a plain circle)
- Cleaning: spray bottle with sparkle lines (not a checkmark)
- Gardening: plant pot with leaves (not a generic leaf)

Add subtle details — filled shapes at low opacity for depth, small
accent dots or lines at 25-40% opacity for polish. These details make
icons feel crafted rather than stock.

### Reuse with `<symbol>` + `<use>`

Define icons once and reuse them to keep HTML DRY:

```svg
<svg style="display: none;">
  <symbol id="icon-check" viewBox="0 0 24 24">
    <path d="M 5 12 L 10 17 L 19 7" fill="none"
      stroke="currentColor" stroke-width="2"
      stroke-linecap="round" stroke-linejoin="round" />
  </symbol>
</svg>

<!-- Use anywhere -->
<svg width="24" height="24"><use href="#icon-check" /></svg>
<svg width="16" height="16"><use href="#icon-check" /></svg>
```

---

## Trust Badges

Trust badges (security seals, certification marks, guarantee shields)
need to feel premium and specific to the brand — not like generic stock
clipart. The difference is restraint in color and detail, but generosity
in size and spacing.

### The badge card pattern (default)

The best trust badges are white cards with a centered SVG icon above
descriptive text. The icon is large enough to be detailed and specific
to the concept, but uses only the brand's accent color:

```html
<div class="badge-card">
  <div class="badge-icon">
    <svg viewBox="0 0 72 72" fill="none">
      <!-- Outer shape with brand-tinted fill -->
      <path d="M36 6L10 18v18c0 16.56 11.1 32.04 26 36
               14.9-3.96 26-19.44 26-36V18L36 6z"
        fill="var(--accent-pale)" stroke="var(--primary)"
        stroke-width="1.5"/>
      <!-- Inner detail -->
      <path d="M24 36l8 8 16-16" stroke="var(--primary)"
        stroke-width="3" stroke-linecap="round"
        stroke-linejoin="round" fill="none"/>
    </svg>
  </div>
  <div class="badge-title">Verified Providers</div>
  <div class="badge-subtitle">
    Every professional is identity-checked and reviewed
  </div>
</div>
```

```css
.badge-card {
  background: white;
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 20px;
  padding: 32px 24px;
  text-align: center;
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.04),
    0 8px 24px rgba(0, 0, 0, 0.03);
  transition: transform 0.3s ease, box-shadow 0.3s ease;
}
.badge-card:hover {
  transform: translateY(-4px);
  box-shadow:
    0 4px 12px rgba(0, 0, 0, 0.06),
    0 16px 40px rgba(0, 0, 0, 0.06);
}
.badge-icon { width: 72px; height: 72px; margin: 0 auto 20px; }
```

### Badge icon design

Badge icons at 72×72 viewBox can afford more detail than UI icons —
they're displayed large. But they still follow rules:

1. **Brand accent color only** — use the brand's accent for strokes and
   a pale tint of it for fills. No multi-color icons.
2. **Tinted fill shapes** — the main shape gets a pale brand-tint fill
   (e.g., `#fdebd6` for an orange brand) with a thin brand-color stroke.
   This creates depth without looking flat or garish.
3. **One conceptual layer** — a shield with a checkmark, a lock with a
   shackle, a headset with signal waves. Not a shield containing another
   shield containing a checkmark inside a circle.
4. **Subtle accent details** — shimmer lines at 25% opacity, small dots
   for sparks, thin secondary strokes. These add polish without clutter.
5. **Consistent treatment across all badges** — same fill-tint + stroke
   approach, same level of detail, same opacity range.

### Compact inline badges (secondary pattern)

For tight spaces (below CTAs, in footers, checkout flows), use smaller
inline badges with a tinted background:

```html
<div style="
  display: inline-flex; align-items: center; gap: 8px;
  padding: 8px 14px;
  background: rgba(var(--primary-rgb), 0.06);
  border: 1px solid rgba(var(--primary-rgb), 0.10);
  border-radius: 8px;
">
  <svg viewBox="0 0 24 24" width="18" height="18"
    fill="none" stroke="var(--primary)" stroke-width="2"
    stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 3L4 7v5c0 5 3.5 8.5 8 10 4.5-1.5 8-5 8-10V7l-8-4z" />
    <path d="M9 12l2 2 4-4" />
  </svg>
  <span style="font-size: 13px; font-weight: 500;">256-bit encryption</span>
</div>
```

### What still looks clipart-y

Even with the card pattern, these kill the premium feel:

| Mistake | Fix |
|---|---|
| "Seal" or "ribbon" shapes with ribbon tails | Use shields, circles, or rounded rects |
| Filled star-inside-circle-inside-ribbon | One concept per icon, one layer |
| Icons in different visual styles across badges | Same fill-tint + stroke treatment |
| Generic stock imagery (globe, checkmark) | Specific to the actual claim |
| Bright saturated fills | Pale brand-tint fills (the brand color at 10-15% opacity) |

### Badge layout

```css
/* 4-column grid for badge cards */
.badges-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 24px;
}
@media (max-width: 900px) {
  .badges-grid { grid-template-columns: repeat(2, 1fr); }
}
```

---

## Data Visualization

### Donut Chart

```svg
<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg"
  role="img" aria-labelledby="donut-title">
  <title id="donut-title">Usage: 72%</title>

  <!-- Background ring -->
  <circle cx="60" cy="60" r="50" fill="none"
    stroke="var(--surface-2)" stroke-width="12" />

  <!-- Value arc (72% = 0.72 × 314.16 circumference) -->
  <circle cx="60" cy="60" r="50" fill="none"
    stroke="var(--primary)" stroke-width="12"
    stroke-dasharray="226.2 314.16"
    stroke-linecap="round"
    transform="rotate(-90 60 60)" />

  <!-- Center label -->
  <text x="60" y="64" text-anchor="middle"
    font-size="20" font-weight="600" fill="var(--text-primary)">72%</text>
</svg>
```

**Calculating stroke-dasharray:**
- Circumference = 2 × π × r = 2 × 3.14159 × 50 = 314.16
- Filled portion = percentage × circumference
- `stroke-dasharray="filled gap"` where gap ≥ remaining circumference

### Horizontal Bar Chart

```svg
<svg viewBox="0 0 300 120" xmlns="http://www.w3.org/2000/svg"
  role="img" aria-label="Performance metrics">

  <!-- Labels -->
  <text x="0" y="22" font-size="12" fill="var(--text-secondary)">Speed</text>
  <text x="0" y="52" font-size="12" fill="var(--text-secondary)">Quality</text>
  <text x="0" y="82" font-size="12" fill="var(--text-secondary)">Value</text>

  <!-- Bar backgrounds -->
  <rect x="60" y="12" width="230" height="16" rx="4" fill="var(--surface-2)" />
  <rect x="60" y="42" width="230" height="16" rx="4" fill="var(--surface-2)" />
  <rect x="60" y="72" width="230" height="16" rx="4" fill="var(--surface-2)" />

  <!-- Bar fills -->
  <rect x="60" y="12" width="184" height="16" rx="4" fill="var(--primary)" />
  <rect x="60" y="42" width="207" height="16" rx="4" fill="var(--primary)" opacity="0.8" />
  <rect x="60" y="72" width="161" height="16" rx="4" fill="var(--accent)" />

  <!-- Values -->
  <text x="248" y="25" font-size="11" fill="var(--text-primary)" font-weight="500">80%</text>
  <text x="271" y="55" font-size="11" fill="var(--text-primary)" font-weight="500">90%</text>
  <text x="225" y="85" font-size="11" fill="var(--text-primary)" font-weight="500">70%</text>
</svg>
```

### Area Chart (Mini)

```svg
<svg viewBox="0 0 200 80" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <linearGradient id="area-fill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="var(--primary)" stop-opacity="0.3" />
      <stop offset="100%" stop-color="var(--primary)" stop-opacity="0" />
    </linearGradient>
  </defs>

  <!-- Area fill -->
  <path d="M 0 60 C 20 55, 40 40, 60 45
           S 100 20, 120 30 S 160 15, 180 25 L 200 20
           L 200 80 L 0 80 Z"
    fill="url(#area-fill)" />

  <!-- Line -->
  <path d="M 0 60 C 20 55, 40 40, 60 45
           S 100 20, 120 30 S 160 15, 180 25 L 200 20"
    fill="none" stroke="var(--primary)" stroke-width="2"
    stroke-linecap="round" />
</svg>
```

### Combined Data Dashboard Card

The most impactful data visualization combines multiple chart types in one
card — a large score with stars, a donut chart, a bar breakdown, and a
sparkline trend. This creates a "review dashboard" that feels rich and
specific:

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  ┌──── Left half ────┐  ┌──── Right half ─────────┐ │
│  │  4.8              │  │  ★★★★★ Plumbing    142  │ │
│  │  ★★★★★½           │  │  ████████████▒▒▒▒▒      │ │
│  │                   │  │  ★★★★★ Electrical  98   │ │
│  │  ┌─── Donut ───┐  │  │  ██████████▒▒▒▒▒▒▒     │ │
│  │  │   1,247     │  │  │  ★★★★★ Cleaning   156  │ │
│  │  │   reviews   │  │  │  ████████████████▒▒     │ │
│  │  └─────────────┘  │  │                         │ │
│  │  Last 12 months   │  │  ┌── Sparkline ───────┐ │ │
│  └───────────────────┘  │  │  ╱╲  ╱──╲  ╱──     │ │ │
│                         │  └────────────────────┘ │ │
│                         └─────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

**Key elements:**
- **Large score number** (4.8) as the dominant focal point
- **Star row** with partial fill on the last star using `clipPath`
- **Donut chart** showing overall rating distribution with center label
- **Bar breakdown by category** with actual review counts (not percentages)
- **Sparkline** showing rating trend over time
- **Contextual labels** — "1,247 reviews", "Last 12 months"

The star partial-fill technique:
```svg
<defs>
  <clipPath id="star-clip">
    <rect x="0" y="0" width="50%" height="100%"/>
  </clipPath>
</defs>
<!-- Full star outline -->
<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 18l-6.2 3 1.2-6.8-5-4.9
  6.9-1z" fill="none" stroke="var(--primary)" stroke-width="1"/>
<!-- Partial fill clipped to percentage -->
<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 18l-6.2 3 1.2-6.8-5-4.9
  6.9-1z" fill="var(--primary)" clip-path="url(#star-clip)"/>
```

### Contextual Realism

Data and statistics feel authentic when they include specific, plausible
numbers rather than round placeholders. This applies to any section with
counts or metrics:

| Generic (feels template-y) | Contextual (feels real) |
|---|---|
| "100+ providers" | "142 providers" |
| "Many reviews" | "1,247 reviews" |
| "Top rated" | "4.8 out of 5" |
| "Fast service" | "Avg. response: 2.4 hours" |
| "Popular" | "Last 12 months" |

**Under category icons**, add provider counts ("142 providers", "98
providers") — these make categories feel populated and active. Vary the
numbers to avoid looking generated (don't use all round numbers).

**In data viz sections**, include time periods ("Last 12 months", "Since
March 2024") and total counts ("Based on 1,247 verified reviews"). These
anchor the data in reality.

For programmatic sparklines and bar charts from data arrays, see
`generative-patterns.md` § Data-Driven Art.
