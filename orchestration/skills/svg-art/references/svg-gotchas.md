# SVG Gotchas

Common mistakes, performance pitfalls, browser quirks, and accessibility
requirements. Read this before writing any SVG.

## Table of Contents

1. [viewBox and Coordinates](#viewbox-and-coordinates)
2. [Responsive SVG](#responsive-svg)
3. [Performance](#performance)
4. [Accessibility](#accessibility)
5. [Browser Compatibility](#browser-compatibility)
6. [Common Mistakes](#common-mistakes)

---

## viewBox and Coordinates

### Always use viewBox

Without `viewBox`, SVG doesn't scale:

```svg
<!-- WRONG: fixed size, won't scale -->
<svg width="800" height="600">

<!-- RIGHT: responsive with viewBox -->
<svg viewBox="0 0 800 600">

<!-- ALSO RIGHT: viewBox with CSS sizing -->
<svg viewBox="0 0 800 600" style="width: 100%; height: auto;">
```

`viewBox="minX minY width height"` defines the internal coordinate
system. The SVG scales to fit its container while preserving these
proportions.

### preserveAspectRatio

Controls how the viewBox maps to the container when aspect ratios
don't match:

| Value | Behavior | CSS equivalent |
|---|---|---|
| `xMidYMid meet` (default) | Scale to fit, centered, shows all | `object-fit: contain` |
| `xMidYMid slice` | Scale to fill, centered, clips | `object-fit: cover` |
| `none` | Stretch to fill, distorts | `object-fit: fill` |

**Use `none` for section dividers** — they should stretch to fill
width regardless of height:

```svg
<svg viewBox="0 0 1440 80" preserveAspectRatio="none"
  style="width: 100%; height: 60px;">
```

### Coordinate system

All coordinates in SVG are relative to the viewBox, not the rendered
size. In `viewBox="0 0 800 600"`:
- (0, 0) is top-left
- (800, 600) is bottom-right
- (400, 300) is center

If you shift `minX`/`minY` (e.g., `viewBox="-100 -100 1000 800"`),
the origin moves — useful for panning effects.

### Transform origin in SVG

SVG transforms default to the origin (0, 0) of the SVG coordinate
system, NOT the element's center:

```svg
<!-- Rotates around (0,0), not the rectangle's center -->
<rect x="100" y="100" width="50" height="50" transform="rotate(45)" />

<!-- Rotates around the rectangle's center -->
<rect x="100" y="100" width="50" height="50" transform="rotate(45 125 125)" />
```

For `rotate(angle cx cy)`, always specify the center point. For
`scale`, wrap in a `<g>` with translate:

```svg
<g transform="translate(125 125) scale(1.5) translate(-125 -125)">
  <rect x="100" y="100" width="50" height="50" />
</g>
```

---

## Responsive SVG

### Sizing with CSS

```css
/* Fill container width, maintain aspect ratio */
svg { width: 100%; height: auto; }

/* Fixed height, stretch width (for dividers) */
svg { width: 100%; height: 60px; }

/* Fill container completely */
svg { position: absolute; inset: 0; width: 100%; height: 100%; }
```

### Inline SVG vs img/object

| Method | CSS customizable | Animatable | Accessible | Cacheable |
|---|---|---|---|---|
| Inline `<svg>` | Yes (CSS vars work) | Yes | Yes | No |
| `<img src="file.svg">` | No | No (SMIL only) | Alt text only | Yes |
| `<object data="file.svg">` | No | Yes | Partial | Yes |
| CSS `background-image` | No | No | No | Yes |
| CSS `background-image` (data URI) | No | No | No | Inline |

**Use inline SVG** when the artwork needs to use CSS custom properties,
respond to hover states, or be accessible. Use data URIs for repeating
patterns and purely decorative textures.

### Removing inline gap

Inline SVGs have a small gap below them (like `<img>`). Fix with:

```css
svg { display: block; }
```

---

## Performance

### Filter costs

SVG filters force rasterization — the browser renders the filtered
area to a bitmap, then composites it. This is expensive:

| Filter primitive | Relative cost | Notes |
|---|---|---|
| `feFlood` | Very low | Just fills with color |
| `feColorMatrix` | Low | Per-pixel math |
| `feMerge` | Low | Compositing only |
| `feComposite` | Low | Per-pixel boolean |
| `feComponentTransfer` | Low | Channel remapping |
| `feGaussianBlur` | Medium | Increases with stdDeviation |
| `feTurbulence` | High | Generates noise per pixel |
| `feDiffuseLighting` | High | Per-pixel lighting calc |
| `feSpecularLighting` | High | More expensive than diffuse |
| `feDisplacementMap` | High | Reads from two sources |
| `feConvolveMatrix` | Very high | Custom kernel per pixel |

**Budget:** 2-3 filter primitives per chain. Stacking more degrades
performance, especially on mobile and Safari.

### Filter region

Filters clip to the element bounds by default. For effects that
extend beyond the shape (blur, glow), extend the filter region:

```svg
<!-- Without extension: glow clips at shape edges -->
<filter id="glow">

<!-- With extension: glow renders fully -->
<filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
```

Rule of thumb: extend by the blur radius. For `stdDeviation="10"`,
extend by at least 15% on each side.

### Element count

| Elements | Performance | Strategy |
|---|---|---|
| < 100 | Fine | No optimization needed |
| 100-500 | Watch | Combine paths, use `<use>` |
| 500-1000 | Slow | Simplify, reduce nodes |
| > 1000 | Don't | Use Canvas or WebGL instead |

### Optimization techniques

1. **Combine paths** — merge shapes with the same fill into one
   `<path>` element with multiple subpaths:
   ```svg
   <!-- 3 elements -->
   <circle cx="10" cy="10" r="5" />
   <circle cx="30" cy="10" r="5" />
   <circle cx="50" cy="10" r="5" />

   <!-- 1 element (same visual) -->
   <path d="M 15 10 A 5 5 0 1 0 5 10 A 5 5 0 1 0 15 10
            M 35 10 A 5 5 0 1 0 25 10 A 5 5 0 1 0 35 10
            M 55 10 A 5 5 0 1 0 45 10 A 5 5 0 1 0 55 10" />
   ```

2. **Use `<use>`** for repeated shapes:
   ```svg
   <defs>
     <circle id="dot" r="3" />
   </defs>
   <use href="#dot" x="10" y="10" fill="red" />
   <use href="#dot" x="30" y="10" fill="blue" />
   ```

3. **Simplify paths** — use the `simplifyPath()` function from
   `generative-patterns.md` to reduce point count.

4. **`shape-rendering`** attribute:
   - `auto` (default) — anti-aliased, smooth
   - `crispEdges` — pixel-aligned, removes anti-aliasing gaps between
     adjacent shapes (good for grids/patterns)
   - `geometricPrecision` — highest quality curves (slight perf cost)

5. **CSS vs SVG filters** — prefer CSS when possible:
   ```css
   /* CSS (GPU-accelerated) */
   .blurred { filter: blur(8px); }

   /* SVG filter (rasterized) */
   <filter id="blur"><feGaussianBlur stdDeviation="8"/></filter>
   ```

### Animation performance

- Animate `transform` and `opacity` (composited, GPU-friendly)
- Avoid animating `fill`, `stroke`, `d` attribute (causes repaints)
- Use `will-change: transform` on animated SVG elements
- SMIL `<animate>` works but CSS animations are usually faster
- For complex animation, use GSAP (see `immersive-frontend` skill)

---

## Accessibility

### Decorative SVG

For SVGs that are purely visual (backgrounds, textures, decorative
shapes), hide from assistive technology:

```svg
<svg aria-hidden="true" viewBox="0 0 800 600">
  <!-- No title or desc needed -->
</svg>
```

### Meaningful SVG

For SVGs that convey information (icons with meaning, charts, illustrations
that add context):

```svg
<svg role="img" aria-labelledby="svg-title svg-desc" viewBox="0 0 800 600">
  <title id="svg-title">Revenue trend</title>
  <desc id="svg-desc">Line chart showing revenue increasing 23% from
    January to June 2024</desc>
  <!-- ... -->
</svg>
```

**Rules:**
- Use `role="img"` to ensure consistent screen reader behavior
- Use `aria-labelledby` referencing both `<title>` and `<desc>`
- Do NOT use `aria-describedby` (inconsistent browser support)
- Keep `<title>` under 50 characters (acts like alt text)
- Keep `<desc>` under 250 characters
- `<title>` must be the FIRST child of `<svg>` for best support

### Interactive SVG elements

```svg
<a href="/details" aria-label="View details">
  <rect ... />
</a>

<g role="button" tabindex="0" aria-label="Toggle view"
  onclick="toggleView()">
  <rect ... />
</g>
```

### Data visualization accessibility

Charts and graphs need more than just visual representation:
- Include a `<desc>` that summarizes the key insight
- Consider a hidden data table as alternative:
  ```html
  <div class="sr-only">
    <table>
      <tr><th>Month</th><th>Revenue</th></tr>
      <tr><td>Jan</td><td>$12,000</td></tr>
      <!-- ... -->
    </table>
  </div>
  ```

---

## Browser Compatibility

### Known issues

| Issue | Browsers | Workaround |
|---|---|---|
| SVG filters in `<img>` tags | All | Use inline SVG or `<object>` |
| `feImage` with external href | Safari | Use data URIs instead |
| `mix-blend-mode` rendering | Safari vs Chrome | Test both, may need fallback |
| `feGaussianBlur` > 100px | Firefox | Caps at 100px stdDeviation |
| SMIL `<animate>` | All modern | Works everywhere (was deprecated then un-deprecated) |
| CSS `transform-origin` on SVG | Older Safari | Use SVG `transform="rotate(a cx cy)"` |
| SVG inside `<img>` animation | All | Only SMIL works, not CSS animation |
| `paint-order` | Good support | Check caniuse for older browsers |
| SVG `<foreignObject>` | Varies | Don't rely on for critical content |

### Safe SVG features (use freely)

- `viewBox`, `preserveAspectRatio`
- Basic shapes: `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<path>`
- `<g>`, `<defs>`, `<use>`, `<symbol>`
- `<linearGradient>`, `<radialGradient>`
- `<pattern>`, `<clipPath>`, `<mask>`
- All filter primitives (with performance caveats)
- `<text>`, `<tspan>`
- CSS styling of SVG elements
- `transform` attribute

---

## Common Mistakes

### 1. Missing xmlns

Inline SVG in HTML doesn't need it, but standalone SVG files and
data URIs do:

```svg
<!-- In HTML: works without xmlns -->
<svg viewBox="0 0 100 100">

<!-- In .svg file or data URI: REQUIRES xmlns -->
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
```

### 2. Forgetting display: block

Inline SVGs render as inline elements with a small gap below:

```css
svg { display: block; } /* Remove the gap */
```

### 3. Hard-coding colors

```svg
<!-- BAD: hard-coded, can't theme -->
<circle fill="#3b82f6" />

<!-- GOOD: uses page tokens (inline SVG only) -->
<circle fill="var(--primary)" />

<!-- GOOD: uses currentColor (inherits text color) -->
<circle fill="currentColor" />
```

### 4. Ignoring filter region

```svg
<!-- BAD: blur clips at shape edges -->
<filter id="glow">
  <feGaussianBlur stdDeviation="10" />
</filter>

<!-- GOOD: extended region for blur overflow -->
<filter id="glow" x="-25%" y="-25%" width="150%" height="150%">
  <feGaussianBlur stdDeviation="10" />
</filter>
```

### 5. Wrong coordinate space for transforms

```svg
<!-- BAD: rotates around (0,0), shape flies off screen -->
<rect x="200" y="200" width="50" height="50" transform="rotate(45)" />

<!-- GOOD: rotates around shape's center -->
<rect x="200" y="200" width="50" height="50" transform="rotate(45 225 225)" />
```

### 6. Using CSS transforms on SVG elements

CSS `transform-origin: center` works differently on SVG elements
across browsers. Use the SVG `transform` attribute instead:

```svg
<!-- Unreliable -->
<rect style="transform: rotate(45deg); transform-origin: center;" />

<!-- Reliable -->
<rect transform="rotate(45 225 225)" />
```

### 7. Decorative SVG without aria-hidden

```svg
<!-- BAD: screen reader announces "image" with no useful info -->
<svg viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="40" />
</svg>

<!-- GOOD: hidden from assistive tech -->
<svg viewBox="0 0 100 100" aria-hidden="true">
  <circle cx="50" cy="50" r="40" />
</svg>
```

### 8. Too many decimal places

Path data with excessive precision bloats file size:

```svg
<!-- BAD: 14 decimal places per coordinate -->
<path d="M 12.34567890123456 78.90123456789012 L ..." />

<!-- GOOD: 1-2 decimal places is sufficient -->
<path d="M 12.35 78.9 L ..." />
```

Round coordinates to 1-2 decimal places. For viewBoxes under 1000,
even integers are fine.
