# SVG Filter Recipes

Copy-paste filter definitions for common visual effects. Each recipe
includes the `<filter>` definition and usage example.

## Table of Contents

1. [Texture Filters](#texture-filters) — grain, paper, wood, stone
2. [Color Treatments](#color-treatments) — duotone, sepia, grayscale, hue shift
3. [Glow Effects](#glow-effects) — soft glow, neon, pulse
4. [Lighting Effects](#lighting-effects) — emboss, metallic, 3D surface
5. [Displacement](#displacement) — warp, ripple, organic distortion
6. [Composite Recipes](#composite-recipes) — layered multi-filter effects

---

## Texture Filters

### Grain / Film Noise

The workhorse texture. Uses `feTurbulence` to generate Perlin noise.

```svg
<filter id="grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence
    type="fractalNoise"
    baseFrequency="0.65"
    numOctaves="3"
    stitchTiles="stitch"
    result="noise"
  />
  <feColorMatrix
    in="noise"
    type="saturate"
    values="0"
    result="mono-noise"
  />
  <feBlend in="SourceGraphic" in2="mono-noise" mode="multiply" />
</filter>
```

**Key parameters:**
- `baseFrequency` — grain size. Higher = finer grain. 0.5-0.8 for
  subtle film grain. 0.1-0.3 for coarser texture.
- `numOctaves` — detail layers. 1 = smooth, 3 = detailed, 5 = very
  fine. Diminishing returns above 5.
- `stitchTiles="stitch"` — seamless tiling (always include this).
- `type="fractalNoise"` — smooth Perlin noise. Use `"turbulence"`
  for harsher, more cloud-like patterns.

### Grain overlay (CSS approach)

For applying grain over a gradient background without affecting content:

```css
.grainy-section {
  position: relative;
  background: linear-gradient(135deg, var(--primary), var(--accent));
}

.grainy-section::after {
  content: '';
  position: absolute;
  inset: 0;
  background: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='g'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.65' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23g)'/%3E%3C/svg%3E");
  opacity: 0.08;
  mix-blend-mode: overlay;
  pointer-events: none;
}
```

### Paper / Canvas Texture

Uses diffuse lighting on noise to simulate surface texture:

```svg
<filter id="paper" x="0" y="0" width="100%" height="100%">
  <feTurbulence
    type="fractalNoise"
    baseFrequency="0.04"
    numOctaves="5"
    result="noise"
  />
  <feDiffuseLighting
    in="noise"
    lighting-color="white"
    surfaceScale="2"
    result="lit"
  >
    <feDistantLight azimuth="45" elevation="60" />
  </feDiffuseLighting>
  <feComposite
    in="SourceGraphic"
    in2="lit"
    operator="arithmetic"
    k1="1" k2="0" k3="0" k4="0"
  />
</filter>
```

**Parameters to adjust:**
- `surfaceScale` — depth of the texture. 1 = subtle, 3 = pronounced.
- `azimuth` — light direction (degrees). 45 = upper-left.
- `elevation` — light angle. 60 = moderate, 90 = directly above (flat).

### Wood Grain

Asymmetric `baseFrequency` creates elongated streaks:

```svg
<filter id="wood">
  <feTurbulence
    type="fractalNoise"
    baseFrequency="0.1 0.01"
    numOctaves="2"
    result="noise"
  />
  <feColorMatrix
    in="noise"
    type="matrix"
    values="0 0 0 .11 .69
            0 0 0 .09 .38
            0 0 0 .08 .14
            0 0 0  0   1"
  />
</filter>
```

The two-value `baseFrequency` (horizontal, vertical) creates directional
texture. `0.1 0.01` = horizontal grain. `0.01 0.1` = vertical grain.

### Starry Sky / Speckle

High-contrast threshold on noise creates scattered dots:

```svg
<filter id="stars">
  <feTurbulence
    baseFrequency="0.2"
    type="fractalNoise"
    numOctaves="1"
  />
  <feColorMatrix
    type="matrix"
    values="0 0 0 9 -4
            0 0 0 9 -4
            0 0 0 9 -4
            0 0 0 0  1"
  />
</filter>
```

The `9 -4` values multiply the noise channel by 9 then subtract 4,
pushing most values to 0 (black) and a few to 1 (white) — creating
a star field effect. Adjust the subtraction value (-4 to -6) to
control star density.

### Contour / Topographic Lines

Discrete step function creates bands from smooth noise:

```svg
<filter id="contour">
  <feTurbulence
    type="fractalNoise"
    baseFrequency="0.015"
    numOctaves="3"
    result="noise"
  />
  <feComponentTransfer in="noise">
    <feFuncR type="discrete" tableValues="0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1" />
    <feFuncG type="discrete" tableValues="0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1" />
    <feFuncB type="discrete" tableValues="0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1" />
  </feComponentTransfer>
</filter>
```

Fewer table values = wider bands = fewer contour lines. More table
values = finer detail. Low `baseFrequency` (0.01-0.02) gives the
sweeping curves of topographic maps.

---

## Color Treatments

### feColorMatrix Explained

The 5×4 matrix transforms input RGBA to output RGBA:

```
| R' |   | a1 a2 a3 a4 a5 |   | R |
| G' | = | b1 b2 b3 b4 b5 | × | G |
| B' |   | c1 c2 c3 c4 c5 |   | B |
| A' |   | d1 d2 d3 d4 d5 |   | A |
                                | 1 |
```

Column 5 is the offset (added after multiplication). The `| 1 |` row
makes the offset work.

### Grayscale (Perceptual Luminance)

```svg
<feColorMatrix type="matrix"
  values="0.299 0.587 0.114 0 0
          0.299 0.587 0.114 0 0
          0.299 0.587 0.114 0 0
          0     0     0     1 0" />
```

Or the shorthand: `<feColorMatrix type="saturate" values="0" />`

### Sepia

```svg
<feColorMatrix type="matrix"
  values="0.393 0.769 0.189 0 0
          0.349 0.686 0.168 0 0
          0.272 0.534 0.131 0 0
          0     0     0     1 0" />
```

### Duotone

Maps grayscale values to two colors. The `tableValues` for each channel
are `shadow_value highlight_value` (each 0-1, calculated from the
desired hex color / 255):

```svg
<filter id="duotone">
  <!-- Step 1: Convert to grayscale -->
  <feColorMatrix type="matrix" result="gray"
    values="1 0 0 0 0
            1 0 0 0 0
            1 0 0 0 0
            0 0 0 1 0" />
  <!-- Step 2: Map gray to two colors -->
  <feComponentTransfer in="gray" color-interpolation-filters="sRGB">
    <feFuncR type="table" tableValues="0.122 0.988" />  <!-- shadow R, highlight R -->
    <feFuncG type="table" tableValues="0.055 0.733" />  <!-- shadow G, highlight G -->
    <feFuncB type="table" tableValues="0.490 0.051" />  <!-- shadow B, highlight B -->
    <feFuncA type="table" tableValues="0 1" />
  </feComponentTransfer>
</filter>
```

**To calculate tableValues from hex colors:**
- Shadow color #1F0E7D → R: 31/255=0.122, G: 14/255=0.055, B: 125/255=0.490
- Highlight color #FC BB 0D → R: 252/255=0.988, G: 187/255=0.733, B: 13/255=0.051

### Hue Rotation

```svg
<feColorMatrix type="hueRotate" values="90" />
```

Values in degrees (0-360). Useful for creating color variants of the
same SVG artwork.

### Brightness / Contrast

```svg
<!-- Increase brightness -->
<feComponentTransfer>
  <feFuncR type="linear" slope="1.2" intercept="0.1" />
  <feFuncG type="linear" slope="1.2" intercept="0.1" />
  <feFuncB type="linear" slope="1.2" intercept="0.1" />
</feComponentTransfer>

<!-- Increase contrast -->
<feComponentTransfer>
  <feFuncR type="linear" slope="1.5" intercept="-0.15" />
  <feFuncG type="linear" slope="1.5" intercept="-0.15" />
  <feFuncB type="linear" slope="1.5" intercept="-0.15" />
</feComponentTransfer>
```

`slope` controls amplification (>1 = more contrast/brightness).
`intercept` shifts the midpoint.

---

## Glow Effects

### Soft Glow

Layer a blurred copy behind the sharp original:

```svg
<filter id="soft-glow" x="-20%" y="-20%" width="140%" height="140%">
  <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur" />
  <feMerge>
    <feMergeNode in="blur" />
    <feMergeNode in="SourceGraphic" />
  </feMerge>
</filter>
```

The `x/y/width/height` on the filter element extends the filter region
beyond the shape bounds — without this, the blur clips at the edges.

### Neon Glow

Stack multiple blur layers at different radii for realistic neon:

```svg
<filter id="neon" x="-30%" y="-30%" width="160%" height="160%"
        filterUnits="userSpaceOnUse">
  <!-- Inner glow -->
  <feGaussianBlur in="SourceAlpha" stdDeviation="3" result="blur1" />
  <feColorMatrix in="blur1" result="glow1"
    values="0 0 0 0 1    0 0 0 0 0.2    0 0 0 0 0.8    0 0 0 1 0" />

  <!-- Mid glow -->
  <feGaussianBlur in="SourceAlpha" stdDeviation="7" result="blur2" />
  <feColorMatrix in="blur2" result="glow2"
    values="0 0 0 0 1    0 0 0 0 0.2    0 0 0 0 0.8    0 0 0 0.7 0" />

  <!-- Outer glow -->
  <feGaussianBlur in="SourceAlpha" stdDeviation="14" result="blur3" />
  <feColorMatrix in="blur3" result="glow3"
    values="0 0 0 0 1    0 0 0 0 0.2    0 0 0 0 0.8    0 0 0 0.4 0" />

  <feMerge>
    <feMergeNode in="glow3" />
    <feMergeNode in="glow2" />
    <feMergeNode in="glow1" />
    <feMergeNode in="SourceGraphic" />
  </feMerge>
</filter>
```

The `feColorMatrix` values map: columns 1-4 of row 5 set the RGB color
of the glow. Adjust `0 0 0 0 R  0 0 0 0 G  0 0 0 0 B` to change
glow color.

### Neon Flicker Animation

```css
@keyframes flicker {
  0%, 19%, 21%, 23%, 25%, 54%, 56%, 100% { opacity: 1; }
  20%, 24%, 55% { opacity: 0.4; }
}
.neon-text { animation: flicker 3s infinite; }
```

---

## Lighting Effects

### Emboss / Raised Surface

Specular lighting creates a 3D raised effect:

```svg
<filter id="emboss">
  <feGaussianBlur in="SourceAlpha" stdDeviation="2" result="blur" />
  <feSpecularLighting
    in="blur"
    surfaceScale="5"
    specularConstant="0.75"
    specularExponent="20"
    lighting-color="#fff"
    result="spec"
  >
    <fePointLight x="100" y="50" z="200" />
  </feSpecularLighting>
  <feComposite
    in="SourceGraphic" in2="spec"
    operator="arithmetic"
    k1="0" k2="1" k3="1" k4="0"
  />
</filter>
```

**Parameters:**
- `surfaceScale` — height of the emboss (1-10). Higher = more
  pronounced 3D effect.
- `specularExponent` — shininess (1-128). 1 = matte, 128 = mirror.
- `specularConstant` — brightness of the highlight (0-1).
- Light position (x, y, z) — z controls how "far" the light is.
  Higher z = more diffuse, lower z = more dramatic.

### Light types

```svg
<!-- Directional (sun-like, parallel rays) -->
<feDistantLight azimuth="45" elevation="60" />

<!-- Point (bulb-like, radiates from a point) -->
<fePointLight x="100" y="100" z="200" />

<!-- Spot (cone-shaped) -->
<feSpotLight x="100" y="100" z="200"
  pointsAtX="200" pointsAtY="200" pointsAtZ="0"
  specularExponent="10" limitingConeAngle="30" />
```

### Metallic Surface

```svg
<filter id="metallic">
  <feTurbulence baseFrequency="0.05 0.02" numOctaves="3" result="noise" />
  <feDiffuseLighting in="noise" surfaceScale="3" lighting-color="#e0e0e0">
    <feDistantLight azimuth="135" elevation="50" />
  </feDiffuseLighting>
</filter>
```

Asymmetric `baseFrequency` creates directional brushed-metal streaks.

---

## Displacement

### Basic Warp

Displaces pixels based on a noise map:

```svg
<filter id="warp" x="-10%" y="-10%" width="120%" height="120%">
  <feTurbulence
    type="fractalNoise"
    baseFrequency="0.02"
    numOctaves="3"
    result="noise"
  />
  <feDisplacementMap
    in="SourceGraphic"
    in2="noise"
    scale="20"
    xChannelSelector="R"
    yChannelSelector="G"
  />
</filter>
```

**How displacement works:**
- `scale` — intensity. 0 = no displacement, 50+ = heavy distortion.
- Channel value of 128 (middle gray) = no displacement.
- Above 128 → shift in positive direction.
- Below 128 → shift in negative direction.
- `xChannelSelector` / `yChannelSelector` — which color channel drives
  horizontal/vertical displacement (R, G, B, or A).

### Animated Distortion

SMIL animation on filter parameters creates living textures:

```svg
<feTurbulence baseFrequency="0.02" numOctaves="2" result="noise">
  <animate
    attributeName="baseFrequency"
    values="0.02;0.04;0.02"
    dur="8s"
    repeatCount="indefinite"
  />
</feTurbulence>
<feDisplacementMap in="SourceGraphic" in2="noise" scale="15" />
```

### Ripple / Water Effect

Use `turbulence` type (not `fractalNoise`) with low frequency:

```svg
<filter id="ripple">
  <feTurbulence
    type="turbulence"
    baseFrequency="0.01 0.05"
    numOctaves="2"
    result="waves"
  />
  <feDisplacementMap in="SourceGraphic" in2="waves" scale="25"
    xChannelSelector="R" yChannelSelector="B" />
</filter>
```

Asymmetric frequency (low horizontal, higher vertical) creates
horizontal wave-like displacement.

---

## Composite Recipes

### Frosted Glass

Blur + noise overlay:

```svg
<filter id="frosted" x="-5%" y="-5%" width="110%" height="110%">
  <feGaussianBlur in="SourceGraphic" stdDeviation="8" result="blur" />
  <feTurbulence type="fractalNoise" baseFrequency="0.8"
    numOctaves="4" stitchTiles="stitch" result="noise" />
  <feColorMatrix in="noise" type="saturate" values="0" result="mono" />
  <feBlend in="blur" in2="mono" mode="soft-light" />
</filter>
```

### Vintage / Aged

Grain + sepia + vignette:

```svg
<filter id="vintage" x="-5%" y="-5%" width="110%" height="110%">
  <!-- Sepia tone -->
  <feColorMatrix type="matrix"
    values="0.393 0.769 0.189 0 0
            0.349 0.686 0.168 0 0
            0.272 0.534 0.131 0 0
            0     0     0     1 0"
    result="sepia" />
  <!-- Add grain -->
  <feTurbulence type="fractalNoise" baseFrequency="0.6"
    numOctaves="3" stitchTiles="stitch" result="grain" />
  <feColorMatrix in="grain" type="saturate" values="0" result="mono-grain" />
  <feBlend in="sepia" in2="mono-grain" mode="multiply" result="grainy" />
  <!-- Vignette -->
  <feFlood flood-color="black" flood-opacity="0.3" result="dark" />
  <feComposite in="dark" in2="SourceAlpha" operator="in" result="vignette" />
  <feGaussianBlur in="vignette" stdDeviation="40" result="vignette-blur" />
  <feBlend in="grainy" in2="vignette-blur" mode="multiply" />
</filter>
```

### Noise Constrained to Shape

Apply noise only within a shape's bounds (not the full canvas):

```svg
<filter id="shape-noise">
  <feTurbulence type="fractalNoise" baseFrequency="0.5"
    numOctaves="4" result="noise" />
  <feComposite operator="in" in="noise" in2="SourceAlpha"
    result="clipped" />
  <feBlend in="SourceGraphic" in2="clipped" mode="overlay" />
</filter>
```

The `feComposite operator="in"` masks the noise to the shape's alpha
channel — noise only appears where the shape is.
