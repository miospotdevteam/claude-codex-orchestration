# Shader Recipes

Complete, copy-pasteable GLSL for common immersive website effects.
Each recipe includes vertex shader, fragment shader, and Three.js setup.

---

## Simplex Noise Function (shared utility)

Used by multiple recipes below. Include in any vertex shader that needs noise.

```glsl
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 10.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
  const vec2 C = vec2(1.0/6.0, 1.0/3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

  vec3 i = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);

  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);

  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;

  i = mod289(i);
  vec4 p = permute(permute(permute(
    i.z + vec4(0.0, i1.z, i2.z, 1.0))
  + i.y + vec4(0.0, i1.y, i2.y, 1.0))
  + i.x + vec4(0.0, i1.x, i2.x, 1.0));

  float n_ = 0.142857142857;
  vec3 ns = n_ * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);
  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));
  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);

  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
  p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;

  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m*m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}
```

---

## 1. Noise Displacement — Morphing Blob (Vertex)

Creates organic, undulating surfaces. The signature creative coding effect.

### Vertex Shader

```glsl
uniform float uTime;
uniform float uNoiseScale;    // try 1.5
uniform float uNoiseStrength; // try 0.3
uniform float uSpeed;         // try 0.4

varying vec3 vNormal;
varying vec3 vPosition;
varying float vDisplacement;

// Include snoise() function from above

void main() {
  vec3 pos = position;

  // Fractal Brownian Motion: layer noise at multiple frequencies
  float noise = snoise(pos * uNoiseScale + uTime * uSpeed);
  noise += 0.5 * snoise(pos * uNoiseScale * 2.0 + uTime * uSpeed * 1.3);
  noise += 0.25 * snoise(pos * uNoiseScale * 4.0 + uTime * uSpeed * 1.7);

  float displacement = noise * uNoiseStrength;
  pos += normal * displacement;

  vNormal = normal;
  vPosition = pos;
  vDisplacement = displacement;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
}
```

### Fragment Shader

```glsl
uniform vec3 uColor1;       // deep purple #4a0e8f
uniform vec3 uColor2;       // bright cyan #00e5ff
uniform float uFresnelPower; // try 2.0

varying vec3 vNormal;
varying vec3 vPosition;
varying float vDisplacement;

void main() {
  vec3 normal = normalize(vNormal);
  vec3 lightDir = normalize(vec3(0.5, 1.0, 0.8));
  float diffuse = max(dot(normal, lightDir), 0.0);

  float colorMix = smoothstep(-0.2, 0.4, vDisplacement);
  vec3 color = mix(uColor1, uColor2, colorMix);
  color *= 0.3 + 0.7 * diffuse;

  // Fresnel edge glow
  vec3 viewDir = normalize(-vPosition);
  float fresnel = pow(1.0 - max(dot(viewDir, normal), 0.0), uFresnelPower);
  color += fresnel * uColor2 * 0.5;

  gl_FragColor = vec4(color, 1.0);
}
```

### Three.js Setup

```javascript
const material = new THREE.ShaderMaterial({
  uniforms: {
    uTime:          { value: 0 },
    uNoiseScale:    { value: 1.5 },
    uNoiseStrength: { value: 0.3 },
    uSpeed:         { value: 0.4 },
    uColor1:        { value: new THREE.Color('#4a0e8f') },
    uColor2:        { value: new THREE.Color('#00e5ff') },
    uFresnelPower:  { value: 2.0 },
  },
  vertexShader, fragmentShader,
});

// High subdivision for smooth noise detail
const geometry = new THREE.IcosahedronGeometry(1, 64);
const mesh = new THREE.Mesh(geometry, material);
```

---

## 2. Chromatic Aberration (Fragment — Post-Processing)

Splits RGB channels radially from center. Commonly linked to scroll velocity.

```glsl
uniform sampler2D tDiffuse;
uniform float uIntensity; // 0.002 to 0.02 — very sensitive

varying vec2 vUv;

void main() {
  vec2 dir = vUv - 0.5;
  float dist = length(dir);
  float strength = uIntensity * pow(dist, 2.0);
  vec2 offset = normalize(dir) * strength;

  float r = texture2D(tDiffuse, vUv + offset).r;
  float g = texture2D(tDiffuse, vUv).g;
  float b = texture2D(tDiffuse, vUv - offset).b;

  gl_FragColor = vec4(r, g, b, 1.0);
}
```

### Dynamic intensity from scroll velocity

```javascript
ScrollTrigger.create({
  onUpdate: (self) => {
    const velocity = Math.abs(self.getVelocity()) / 1000;
    caPass.uniforms.uIntensity.value +=
      (Math.min(velocity * 0.05, 0.02) - caPass.uniforms.uIntensity.value) * 0.1;
  }
});
```

---

## 3. Image Distortion / Displacement Transition (Fragment)

Classic portfolio hover: two images cross-fade with noise-distorted UVs.

```glsl
uniform sampler2D uTexture1;
uniform sampler2D uTexture2;
uniform sampler2D uDisplacement; // grayscale noise texture
uniform float uProgress;         // 0.0 = image1, 1.0 = image2
uniform float uIntensity;        // 0.3 to 1.0

varying vec2 vUv;

void main() {
  vec4 disp = texture2D(uDisplacement, vUv);

  vec2 uv1 = vec2(
    vUv.x + disp.r * uIntensity * uProgress,
    vUv.y + disp.r * uIntensity * uProgress
  );
  vec2 uv2 = vec2(
    vUv.x - (1.0 - disp.r) * uIntensity * (1.0 - uProgress),
    vUv.y - (1.0 - disp.r) * uIntensity * (1.0 - uProgress)
  );

  vec4 tex1 = texture2D(uTexture1, uv1);
  vec4 tex2 = texture2D(uTexture2, uv2);

  gl_FragColor = mix(tex1, tex2, uProgress);
}
```

### Directional Wipe Variant

```glsl
uniform float uWipeWidth; // edge softness, try 0.3

void main() {
  float disp = texture2D(uDisplacement, vUv).r;
  float threshold = uProgress * (1.0 + uWipeWidth) - uWipeWidth * 0.5;
  float mixFactor = smoothstep(
    threshold - uWipeWidth * 0.5,
    threshold + uWipeWidth * 0.5,
    vUv.x + disp * uIntensity
  );

  float distortion = smoothstep(0.0, 1.0, 1.0 - abs(mixFactor - 0.5) * 2.0) * uIntensity;
  vec2 uv1 = vUv + vec2(distortion * disp, 0.0);
  vec2 uv2 = vUv - vec2(distortion * (1.0 - disp), 0.0);

  gl_FragColor = mix(texture2D(uTexture1, uv1), texture2D(uTexture2, uv2), mixFactor);
}
```

### GSAP Hover Trigger

```javascript
container.addEventListener('mouseenter', () => {
  gsap.to(material.uniforms.uProgress, { value: 1, duration: 1.2, ease: 'power2.inOut' });
});
container.addEventListener('mouseleave', () => {
  gsap.to(material.uniforms.uProgress, { value: 0, duration: 1.2, ease: 'power2.inOut' });
});
```

---

## 4. Film Grain Overlay (Fragment — Post-Processing)

```glsl
uniform sampler2D tDiffuse;
uniform float uTime;
uniform float uIntensity; // 0.03 to 0.15

varying vec2 vUv;

float random(vec2 st) {
  return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main() {
  vec4 color = texture2D(tDiffuse, vUv);

  float grain = (random(gl_FragCoord.xy + fract(uTime * 13.7)) * 2.0 - 1.0);

  // Luminance-weighted: less grain in bright areas (matches real film)
  float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
  color.rgb += grain * uIntensity * (1.0 - luminance * 0.5);
  color.rgb = clamp(color.rgb, 0.0, 1.0);

  gl_FragColor = color;
}
```

---

## 5. Ripple / Wave Effect (Vertex)

Sine-wave vertex displacement with layered frequencies and mouse interaction.

### Vertex Shader

```glsl
uniform float uTime;
uniform float uAmplitude;   // try 0.15
uniform float uFrequency;   // try 3.0
uniform float uSpeed;       // try 1.5
uniform vec2 uMouse;        // normalized [0,1]
uniform float uMouseRadius; // try 0.3

varying vec2 vUv;
varying float vElevation;

void main() {
  vUv = uv;
  vec3 pos = position;

  // Layer 1: Global waves
  float wave1 = sin(pos.x * uFrequency + uTime * uSpeed) * uAmplitude;
  float wave2 = sin(pos.y * uFrequency * 0.8 + uTime * uSpeed * 0.7) * uAmplitude * 0.6;

  // Layer 2: High-frequency detail
  float detail = sin(pos.x * uFrequency * 2.5 - uTime * uSpeed * 1.3)
               * sin(pos.y * uFrequency * 2.0 + uTime * uSpeed * 0.9)
               * uAmplitude * 0.15;

  // Layer 3: Mouse-driven concentric ripple
  float dist = distance(uv, uMouse);
  float mouseRipple = sin(dist * 30.0 - uTime * 5.0)
                    * uAmplitude * 0.3
                    * exp(-dist * dist / (uMouseRadius * uMouseRadius));

  float elevation = wave1 + wave2 + detail + mouseRipple;
  pos.z += elevation;
  vElevation = elevation;

  gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
}
```

### Fragment Shader

```glsl
uniform vec3 uBaseColor; // dark blue #0a1628
uniform vec3 uPeakColor; // lighter blue #3a7bd5

varying float vElevation;

void main() {
  float colorMix = smoothstep(-0.15, 0.2, vElevation);
  gl_FragColor = vec4(mix(uBaseColor, uPeakColor, colorMix), 1.0);
}
```

### Geometry: Use high subdivision

```javascript
const geometry = new THREE.PlaneGeometry(4, 4, 256, 256);
```

---

## 6. Vignette (Fragment — Post-Processing)

```glsl
uniform sampler2D tDiffuse;
uniform float uIntensity;  // 0.3 to 1.5
uniform float uSmoothness; // 0.4 to 0.8

varying vec2 vUv;

void main() {
  vec4 color = texture2D(tDiffuse, vUv);
  float dist = length(vUv - 0.5);
  color.rgb *= smoothstep(uSmoothness, uSmoothness - uIntensity, dist);
  gl_FragColor = color;
}
```

---

## 7. Fresnel Edge Glow

### Vertex Shader

```glsl
varying vec3 vNormal;
varying vec3 vViewDir;

void main() {
  vNormal = normalize(normalMatrix * normal);
  vec4 mvPos = modelViewMatrix * vec4(position, 1.0);
  vViewDir = -normalize(mvPos.xyz);
  gl_Position = projectionMatrix * mvPos;
}
```

### Fragment Shader

```glsl
uniform vec3 uBaseColor;     // #0a0a2e
uniform vec3 uFresnelColor;  // #00e5ff
uniform float uFresnelPower; // 2.0 to 5.0
uniform float uFresnelScale; // 1.0 to 2.0
uniform float uTime;

varying vec3 vNormal;
varying vec3 vViewDir;

void main() {
  vec3 normal = normalize(vNormal);
  vec3 viewDir = normalize(vViewDir);

  // Fresnel: 1.0 at edges (perpendicular to view), 0.0 facing camera
  float fresnel = pow(1.0 - max(dot(viewDir, normal), 0.0), uFresnelPower);
  fresnel *= uFresnelScale;

  vec3 glow = uFresnelColor * (0.8 + 0.2 * sin(uTime * 2.0));
  gl_FragColor = vec4(uBaseColor + fresnel * glow, 1.0);
}
```

---

## 8. UV Distortion with Mouse (Fragment)

Magnetic lens / gravitational distortion around the cursor.

```glsl
uniform sampler2D tDiffuse;
uniform vec2 uMouse;     // UV space [0,1]
uniform float uRadius;   // try 0.25
uniform float uStrength;  // try 0.1

varying vec2 vUv;

void main() {
  vec2 toMouse = uMouse - vUv;
  float dist = length(toMouse);
  float influence = smoothstep(uRadius, 0.0, dist);

  vec2 offset = vec2(0.0);
  if (dist > 0.001) {
    offset = normalize(toMouse) * influence * uStrength;
  }

  gl_FragColor = texture2D(tDiffuse, vUv + offset);
}
```

### Swirl Variant

```glsl
void main() {
  vec2 toMouse = vUv - uMouse;
  float dist = length(toMouse);
  float influence = smoothstep(uRadius, 0.0, dist);
  float angle = influence * uStrength;

  float s = sin(angle), c = cos(angle);
  vec2 rotated = vec2(toMouse.x * c - toMouse.y * s, toMouse.x * s + toMouse.y * c);

  gl_FragColor = texture2D(tDiffuse, uMouse + rotated);
}
```

### Smooth mouse tracking (critical for premium feel)

```javascript
const target = new THREE.Vector2(0.5, 0.5);
const current = new THREE.Vector2(0.5, 0.5);

window.addEventListener('mousemove', (e) => {
  target.set(e.clientX / window.innerWidth, 1.0 - e.clientY / window.innerHeight);
});

// In render loop: lerp factor 0.08 = buttery, 0.2 = snappy
gsap.ticker.add(() => {
  current.lerp(target, 0.08);
  material.uniforms.uMouse.value.copy(current);
});
```

---

## 9. Color Grading / ACES Tone Mapping (Fragment — Post-Processing)

```glsl
uniform sampler2D tDiffuse;
uniform float uExposure;    // 1.0 to 2.0
uniform float uContrast;    // 1.0 to 1.5
uniform float uSaturation;  // 0 = grayscale, 1 = normal, >1 = vivid
uniform vec3 uTint;          // (1.05, 1.0, 0.95) for warmth

varying vec2 vUv;

vec3 ACESFilm(vec3 x) {
  float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
  vec3 color = texture2D(tDiffuse, vUv).rgb;
  color *= uExposure;
  color = ACESFilm(color);
  color = (color - 0.5) * uContrast + 0.5;
  float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(lum), color, uSaturation);
  color *= uTint;
  gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
```

---

## 10. Full Post-Processing Chain

Recommended order for a cinematic immersive site:

```javascript
const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));       // 1. Scene
composer.addPass(bloomPass);                            // 2. Bloom
composer.addPass(chromaticAberrationPass);              // 3. Chromatic aberration
composer.addPass(colorGradingPass);                     // 4. Color grading
composer.addPass(filmGrainPass);                        // 5. Film grain
composer.addPass(vignettePass);                         // 6. Vignette (last visual)
composer.addPass(new OutputPass());                     // 7. Color space (always last)
```

**Order matters:** Bloom before CA prevents color-split halos from blooming.
Color grading near the end. Grain and vignette last so they are not affected
by other effects. OutputPass handles sRGB conversion.

---

## Uniform Ranges Quick Reference

| Effect | Uniform | Range | Default |
|--------|---------|-------|---------|
| Morph Blob | uNoiseStrength | 0.1 - 0.5 | 0.3 |
| Morph Blob | uNoiseScale | 1.0 - 3.0 | 1.5 |
| Chromatic Aberration | uIntensity | 0.002 - 0.02 | 0.005 |
| Image Transition | uIntensity | 0.2 - 1.0 | 0.5 |
| Film Grain | uIntensity | 0.03 - 0.15 | 0.08 |
| Ripple | uAmplitude | 0.05 - 0.3 | 0.15 |
| Vignette | uIntensity | 0.3 - 1.5 | 0.7 |
| Fresnel | uFresnelPower | 1.0 - 5.0 | 3.0 |
| Mouse Distortion | uStrength | 0.05 - 0.2 | 0.1 |
