# Effects Cookbook

Eight complete, production-ready implementations. Each effect is
self-contained with HTML, CSS, and JS — copy, adapt, ship.

---

## 1. Preloader with Percentage Counter

Gate the experience behind a loading screen with smooth counting.

```javascript
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import gsap from 'gsap';

// --- DOM ---
const counter = document.querySelector('.preloader-counter');
const fill = document.querySelector('.preloader-fill');
const preloader = document.getElementById('preloader');

// --- Loaders ---
const manager = new THREE.LoadingManager();
const textureLoader = new THREE.TextureLoader(manager);
const gltfLoader = new GLTFLoader(manager);

// --- Smooth progress ---
const state = { progress: 0 };

manager.onProgress = (url, loaded, total) => {
  gsap.to(state, {
    progress: (loaded / total) * 100,
    duration: 0.4,
    ease: 'power2.out',
    onUpdate: () => {
      const val = Math.round(state.progress);
      counter.textContent = val;
      fill.style.width = val + '%';
    },
  });
};

manager.onLoad = () => {
  // Ensure counter hits 100 before reveal
  gsap.to(state, {
    progress: 100,
    duration: 0.3,
    onUpdate: () => {
      counter.textContent = Math.round(state.progress);
      fill.style.width = Math.round(state.progress) + '%';
    },
    onComplete: revealSite,
  });
};

function revealSite() {
  const tl = gsap.timeline({
    onComplete: () => {
      preloader.remove();
      document.body.style.overflow = '';
      window.dispatchEvent(new Event('preloader:complete'));
    },
  });

  tl.to(counter, { scale: 1.2, opacity: 0, duration: 0.5, ease: 'power3.in' })
    .to(fill.parentElement, { opacity: 0, duration: 0.3 }, '<')
    .to(preloader, {
      clipPath: 'inset(0 0 100% 0)',
      duration: 0.8,
      ease: 'power4.inOut',
    });
}

// --- Queue assets ---
textureLoader.load('/textures/hero.jpg');
textureLoader.load('/textures/noise.png');
gltfLoader.load('/models/scene.glb');
```

```html
<div id="preloader" style="
  position: fixed; inset: 0; z-index: 9999;
  background: #0a0a0a;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
">
  <div class="preloader-counter" style="
    font-size: 8vw; font-weight: 300; color: white;
    font-variant-numeric: tabular-nums;
  ">0</div>
  <div style="width: 200px; height: 2px; background: rgba(255,255,255,0.1); margin-top: 2rem;">
    <div class="preloader-fill" style="
      width: 0%; height: 100%; background: white;
      transition: none;
    "></div>
  </div>
</div>
```

**Rules:**
- `font-variant-numeric: tabular-nums` prevents layout shift
- Remove the preloader node after exit to free memory
- `overflow: hidden` on body during load, restore after reveal
- Render loop does NOT start until `preloader:complete` fires

---

## 2. Smooth Scroll Setup

Complete Lenis + GSAP + Three.js ticker integration.

```javascript
import Lenis from 'lenis';
import 'lenis/dist/lenis.css'; // Lenis ships its own required CSS
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

// --- Lenis ---
const lenis = new Lenis({
  autoRaf: false,        // IMPORTANT: disable internal RAF when using GSAP ticker
  duration: 1.2,
  easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
  smoothWheel: true,
  syncTouch: false,      // renamed from smoothTouch in recent versions
});

// --- Connect Lenis → ScrollTrigger ---
lenis.on('scroll', ScrollTrigger.update);

// --- Single ticker drives everything ---
gsap.ticker.add((time) => {
  lenis.raf(time * 1000);
  // Add renderer.render(scene, camera) here when using Three.js
});
gsap.ticker.lagSmoothing(0);
```

**Why `autoRaf: false`**: Lenis defaults to running its own internal
requestAnimationFrame loop. When using GSAP's ticker to drive everything,
disable Lenis's internal loop to avoid double-updating scroll position.

**Why `lagSmoothing(0)`**: Prevents GSAP from trying to "catch up" after
dropped frames. With Lenis, any catchup creates visible tearing between
the scroll position and rendered frame.

---

## 3. Text Split + Staggered Reveal

Four variants from subtle to theatrical.

### 3a. Character Cascade

```javascript
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

// Split into characters using safe DOM methods
function splitChars(el) {
  const text = el.textContent;
  el.textContent = '';

  text.split(' ').forEach((word, i) => {
    const wordSpan = document.createElement('span');
    wordSpan.style.display = 'inline-block';
    wordSpan.style.whiteSpace = 'nowrap';

    word.split('').forEach(char => {
      const charSpan = document.createElement('span');
      charSpan.textContent = char;
      charSpan.style.display = 'inline-block';
      charSpan.classList.add('char');
      wordSpan.appendChild(charSpan);
    });

    el.appendChild(wordSpan);

    if (i < text.split(' ').length - 1) {
      const space = document.createElement('span');
      space.textContent = '\u00A0';
      space.style.display = 'inline-block';
      el.appendChild(space);
    }
  });

  return el.querySelectorAll('.char');
}

const chars = splitChars(document.querySelector('.hero-title'));

gsap.fromTo(chars, {
  y: 80, rotationX: -90, opacity: 0,
}, {
  y: 0, rotationX: 0, opacity: 1,
  duration: 0.8, ease: 'power3.out',
  stagger: { amount: 0.6, from: 'start' },
  scrollTrigger: {
    trigger: '.hero-title',
    start: 'top 80%',
    toggleActions: 'play none none reverse',
  },
});
```

```css
.hero-title {
  perspective: 600px;
  overflow: hidden;
}
.hero-title .char {
  display: inline-block;
  will-change: transform, opacity;
}
```

### 3b. Words Fade Up

```javascript
function splitWords(el) {
  const text = el.textContent;
  el.textContent = '';

  return text.split(' ').map((word, i) => {
    const span = document.createElement('span');
    span.textContent = word;
    span.style.display = 'inline-block';
    span.classList.add('word');
    el.appendChild(span);

    if (i < text.split(' ').length - 1) {
      const space = document.createTextNode(' ');
      el.appendChild(space);
    }
    return span;
  });
}

const words = splitWords(document.querySelector('.subtitle'));

gsap.from(words, {
  y: 40, opacity: 0,
  duration: 0.6, ease: 'power2.out',
  stagger: 0.08,
  scrollTrigger: {
    trigger: '.subtitle',
    start: 'top 85%',
  },
});
```

### 3c. Lines Slide Up (Masked)

```javascript
function splitLines(el) {
  // Wrap lines using Range API for accurate line detection
  const words = el.textContent.split(' ');
  el.textContent = '';

  const spans = words.map((word, i) => {
    const span = document.createElement('span');
    span.textContent = word;
    span.style.display = 'inline';
    el.appendChild(span);
    if (i < words.length - 1) {
      el.appendChild(document.createTextNode(' '));
    }
    return span;
  });

  // Group spans into lines based on their vertical position
  const lines = [];
  let currentLine = [];
  let currentTop = spans[0]?.offsetTop;

  spans.forEach(span => {
    if (span.offsetTop !== currentTop) {
      lines.push(currentLine);
      currentLine = [];
      currentTop = span.offsetTop;
    }
    currentLine.push(span);
  });
  if (currentLine.length) lines.push(currentLine);

  // Wrap each line in a mask container
  el.textContent = '';
  return lines.map(lineSpans => {
    const mask = document.createElement('div');
    mask.style.overflow = 'hidden';

    const inner = document.createElement('div');
    inner.classList.add('line');
    lineSpans.forEach((span, i) => {
      inner.appendChild(span);
      if (i < lineSpans.length - 1) {
        inner.appendChild(document.createTextNode(' '));
      }
    });

    mask.appendChild(inner);
    el.appendChild(mask);
    return inner;
  });
}

const lines = splitLines(document.querySelector('.paragraph'));

gsap.from(lines, {
  yPercent: 105,
  duration: 0.8,
  ease: 'power4.out',
  stagger: 0.12,
  scrollTrigger: {
    trigger: '.paragraph',
    start: 'top 85%',
  },
});
```

### 3d. Scrub-Linked Word Reveal

Words color in one by one as user scrolls.

```javascript
function splitWordsForScrub(el) {
  const text = el.textContent;
  el.textContent = '';

  return text.split(' ').map((word, i) => {
    const span = document.createElement('span');
    span.textContent = word;
    span.style.display = 'inline-block';
    span.style.color = 'rgba(255, 255, 255, 0.15)';
    span.classList.add('scrub-word');
    el.appendChild(span);
    if (i < text.split(' ').length - 1) {
      el.appendChild(document.createTextNode(' '));
    }
    return span;
  });
}

const words = splitWordsForScrub(document.querySelector('.scroll-text'));

gsap.to(words, {
  color: 'rgba(255, 255, 255, 1)',
  stagger: 0.05,
  scrollTrigger: {
    trigger: '.scroll-text',
    start: 'top 80%',
    end: 'bottom 40%',
    scrub: 0.5,
  },
});
```

---

## 4. Infinite Horizontal Marquee

```javascript
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

function createMarquee(selector, speed = 40) {
  const el = document.querySelector(selector);
  const track = el.querySelector('.marquee-track');
  const items = Array.from(track.children);

  // Clone items for seamless loop
  items.forEach(item => {
    const clone = item.cloneNode(true);
    clone.setAttribute('aria-hidden', 'true');
    track.appendChild(clone);
  });

  const tween = gsap.to(track, {
    xPercent: -50,
    ease: 'none',
    duration: speed,
    repeat: -1,
  });

  // Pause on hover with smooth deceleration
  el.addEventListener('mouseenter', () => {
    gsap.to(tween, { timeScale: 0, duration: 0.5 });
  });
  el.addEventListener('mouseleave', () => {
    gsap.to(tween, { timeScale: 1, duration: 0.5 });
  });

  // Speed up with scroll velocity
  ScrollTrigger.create({
    trigger: el,
    start: 'top bottom',
    end: 'bottom top',
    onUpdate: (self) => {
      const velocity = Math.abs(self.getVelocity());
      gsap.to(tween, {
        timeScale: 1 + velocity / 1000,
        duration: 0.3,
        overwrite: true,
      });
    },
  });

  return tween;
}
```

```html
<div class="marquee">
  <div class="marquee-track">
    <span class="marquee-item">Creative Development</span>
    <span class="marquee-item">&mdash;</span>
    <span class="marquee-item">WebGL Experiences</span>
    <span class="marquee-item">&mdash;</span>
    <span class="marquee-item">Award-Winning Design</span>
    <span class="marquee-item">&mdash;</span>
  </div>
</div>
```

```css
.marquee {
  overflow: hidden;
  white-space: nowrap;
  padding: 2rem 0;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}
.marquee-track {
  display: inline-flex;
}
.marquee-item {
  flex-shrink: 0;
  padding: 0 2rem;
  font-size: clamp(2rem, 5vw, 5rem);
  font-weight: 300;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
```

---

## 5. Magnetic Cursor

Custom cursor that's drawn to interactive elements.

```javascript
class MagneticCursor {
  constructor() {
    this.cursor = document.querySelector('.custom-cursor');
    this.dot = document.querySelector('.cursor-dot');
    this.pos = { x: 0, y: 0 };
    this.mouse = { x: 0, y: 0 };
    this.speed = 0.15;

    window.addEventListener('pointermove', (e) => {
      this.mouse.x = e.clientX;
      this.mouse.y = e.clientY;
    });

    this.setupMagnets();
    this.render();
  }

  setupMagnets() {
    document.querySelectorAll('[data-magnetic]').forEach(el => {
      el.addEventListener('pointerenter', () => this.onMagnetEnter(el));
      el.addEventListener('pointerleave', () => this.onMagnetLeave(el));
      el.addEventListener('pointermove', (e) => this.onMagnetMove(e, el));
    });
  }

  onMagnetEnter(el) {
    this.cursor.classList.add('is-magnetic');
    gsap.to(this.cursor, { scale: 2.5, duration: 0.4, ease: 'power2.out' });
  }

  onMagnetLeave(el) {
    this.cursor.classList.remove('is-magnetic');
    gsap.to(this.cursor, { scale: 1, duration: 0.4, ease: 'power2.out' });
    gsap.to(el, { x: 0, y: 0, duration: 0.4, ease: 'elastic.out(1, 0.3)' });
  }

  onMagnetMove(e, el) {
    const rect = el.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const strength = el.dataset.magneticStrength || 0.3;

    gsap.to(el, {
      x: (e.clientX - centerX) * strength,
      y: (e.clientY - centerY) * strength,
      duration: 0.3,
      ease: 'power2.out',
    });
  }

  render() {
    this.pos.x += (this.mouse.x - this.pos.x) * this.speed;
    this.pos.y += (this.mouse.y - this.pos.y) * this.speed;

    this.cursor.style.transform =
      `translate3d(${this.pos.x}px, ${this.pos.y}px, 0) translate(-50%, -50%)`;
    this.dot.style.transform =
      `translate3d(${this.mouse.x}px, ${this.mouse.y}px, 0) translate(-50%, -50%)`;

    requestAnimationFrame(() => this.render());
  }
}
```

```html
<div class="custom-cursor"></div>
<div class="cursor-dot"></div>
<a href="#" data-magnetic data-magnetic-strength="0.3">Hover Me</a>
```

```css
.custom-cursor {
  position: fixed; top: 0; left: 0; z-index: 9999;
  width: 40px; height: 40px;
  border: 1px solid rgba(255, 255, 255, 0.5);
  border-radius: 50%;
  pointer-events: none;
  mix-blend-mode: difference;
  transition: width 0.3s, height 0.3s;
}
.custom-cursor.is-magnetic {
  background: rgba(255, 255, 255, 0.05);
}
.cursor-dot {
  position: fixed; top: 0; left: 0; z-index: 9999;
  width: 6px; height: 6px;
  background: white;
  border-radius: 50%;
  pointer-events: none;
}

/* Hide on touch devices */
@media (hover: none) {
  .custom-cursor, .cursor-dot { display: none; }
}
```

---

## 6. Image Hover Distortion (WebGL)

DOM images replaced by WebGL planes with shader distortion on hover.

```javascript
import * as THREE from 'three';

class ImageDistortion {
  constructor({ canvas, images }) {
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 100);
    this.camera.position.z = 5;

    this.renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));

    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2(-10, -10);
    this.textureLoader = new THREE.TextureLoader();

    this.viewport = this.getViewSize();
    this.medias = images.map(el => this.createMedia(el));

    window.addEventListener('pointermove', (e) => {
      this.pointer.x = (e.clientX / window.innerWidth) * 2 - 1;
      this.pointer.y = -(e.clientY / window.innerHeight) * 2 + 1;
    });

    window.addEventListener('resize', () => this.onResize());
  }

  getViewSize() {
    const fov = (this.camera.fov * Math.PI) / 180;
    const h = 2 * Math.tan(fov / 2) * this.camera.position.z;
    return { width: h * this.camera.aspect, height: h };
  }

  createMedia(el) {
    const img = el.querySelector('img');
    const texture = this.textureLoader.load(img.src);
    texture.colorSpace = THREE.SRGBColorSpace;

    const material = new THREE.ShaderMaterial({
      uniforms: {
        uTexture: { value: texture },
        uHover: { value: 0 },
        uTime: { value: 0 },
      },
      vertexShader: /* glsl */ `
        uniform float uHover;
        uniform float uTime;
        varying vec2 vUv;

        void main() {
          vUv = uv;
          vec3 pos = position;
          float dist = distance(uv, vec2(0.5));
          pos.z += sin(dist * 10.0 - uTime * 2.0) * 0.1 * uHover;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        uniform sampler2D uTexture;
        uniform float uHover;
        uniform float uTime;
        varying vec2 vUv;

        void main() {
          vec2 uv = vUv;
          // Barrel distortion on hover
          vec2 center = uv - 0.5;
          float dist = length(center);
          uv += center * dist * 0.3 * uHover;

          // RGB split
          float offset = 0.01 * uHover;
          float r = texture2D(uTexture, uv + vec2(offset, 0.0)).r;
          float g = texture2D(uTexture, uv).g;
          float b = texture2D(uTexture, uv - vec2(offset, 0.0)).b;

          gl_FragColor = vec4(r, g, b, 1.0);
        }
      `,
    });

    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1, 32, 32), material);
    this.scene.add(mesh);

    return { el, mesh, material };
  }

  updatePositions(scrollY) {
    const sw = window.innerWidth;
    const sh = window.innerHeight;

    this.medias.forEach(({ el, mesh }) => {
      const rect = el.getBoundingClientRect();
      mesh.scale.x = (rect.width / sw) * this.viewport.width;
      mesh.scale.y = (rect.height / sh) * this.viewport.height;
      mesh.position.x = ((rect.left + rect.width / 2) / sw) * this.viewport.width - this.viewport.width / 2;
      mesh.position.y = -((rect.top + rect.height / 2) / sh) * this.viewport.height + this.viewport.height / 2;
    });
  }

  update(time) {
    this.updatePositions();

    // Raycasting for hover detection
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const meshes = this.medias.map(m => m.mesh);
    const hits = this.raycaster.intersectObjects(meshes);
    const hitMesh = hits.length > 0 ? hits[0].object : null;

    this.medias.forEach(({ mesh, material }) => {
      const target = mesh === hitMesh ? 1 : 0;
      material.uniforms.uHover.value += (target - material.uniforms.uHover.value) * 0.1;
      material.uniforms.uTime.value = time;
    });

    this.renderer.render(this.scene, this.camera);
  }

  onResize() {
    this.camera.aspect = window.innerWidth / window.innerHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.viewport = this.getViewSize();
  }

  destroy() {
    this.medias.forEach(({ mesh, material }) => {
      mesh.geometry.dispose();
      material.uniforms.uTexture.value.dispose();
      material.dispose();
      this.scene.remove(mesh);
    });
    this.renderer.dispose();
  }
}
```

```html
<canvas id="webgl" style="position:fixed; inset:0; z-index:0;"></canvas>
<div class="gallery" style="position:relative; z-index:1;">
  <div class="gallery-item" data-webgl-media>
    <img src="image1.jpg" alt="" style="width:100%; visibility:hidden;" />
  </div>
  <div class="gallery-item" data-webgl-media>
    <img src="image2.jpg" alt="" style="width:100%; visibility:hidden;" />
  </div>
</div>
```

**Key:** The DOM images are `visibility: hidden` — they're just position
markers. The WebGL planes render the actual visual with shader effects.

---

## 7. Parallax Depth Layers

### 7a. CSS/GSAP Parallax (no WebGL needed)

```javascript
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

// Each layer moves at a different speed
document.querySelectorAll('[data-parallax]').forEach(el => {
  const speed = parseFloat(el.dataset.parallax) || 0.5;

  gsap.to(el, {
    y: () => window.innerHeight * speed * -0.5,
    ease: 'none',
    scrollTrigger: {
      trigger: el.closest('section'),
      start: 'top bottom',
      end: 'bottom top',
      scrub: true,
    },
  });
});
```

```html
<section class="parallax-section" style="position:relative; overflow:hidden; height:100vh;">
  <img data-parallax="0.3" src="bg-far.jpg" style="position:absolute; inset:-20%; width:140%; object-fit:cover;" />
  <img data-parallax="0.6" src="bg-mid.jpg" style="position:absolute; inset:-10%; width:120%; object-fit:cover;" />
  <h2 data-parallax="0.1" style="position:relative; z-index:2;">Heading</h2>
</section>
```

**Speed values:**
- `0.1` — barely moves (foreground text)
- `0.3` — subtle (mid-ground elements)
- `0.6` — noticeable (background layers)
- `1.0` — full speed (moves with scroll, like fixed)

### 7b. Three.js Parallax (depth planes)

```javascript
// Planes at different Z depths create real perspective parallax
const layers = [
  { z: -5, texture: 'bg-far.jpg', scale: 3 },
  { z: -2, texture: 'bg-mid.jpg', scale: 2 },
  { z: 0, texture: 'fg.jpg', scale: 1.2 },
];

layers.forEach(({ z, texture, scale }) => {
  const tex = textureLoader.load(texture);
  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshBasicMaterial({ map: tex, transparent: true })
  );
  mesh.position.z = z;
  mesh.scale.set(scale, scale, 1);
  scene.add(mesh);
});

// Mouse parallax — camera shift
window.addEventListener('pointermove', (e) => {
  const x = (e.clientX / window.innerWidth - 0.5) * 0.5;
  const y = -(e.clientY / window.innerHeight - 0.5) * 0.5;
  gsap.to(camera.position, { x, y, duration: 1, ease: 'power2.out' });
});
```

---

## 8. Scroll-Driven Camera Path

Camera follows a spline as the user scrolls through a 3D scene.

```javascript
import * as THREE from 'three';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

// --- Scene setup ---
const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x0a0a0a, 0.05);
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 200);
const renderer = new THREE.WebGLRenderer({ canvas: document.getElementById('webgl'), antialias: true });
renderer.setSize(innerWidth, innerHeight);
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));

// --- Camera path (CatmullRom spline) ---
const cameraPath = new THREE.CatmullRomCurve3([
  new THREE.Vector3(0, 2, 20),
  new THREE.Vector3(10, 4, 10),
  new THREE.Vector3(15, 2, 0),
  new THREE.Vector3(10, 0, -10),
  new THREE.Vector3(0, 3, -20),
  new THREE.Vector3(-10, 1, -30),
]);

// Look-at target path (can be different from camera path)
const lookAtPath = new THREE.CatmullRomCurve3([
  new THREE.Vector3(0, 0, 15),
  new THREE.Vector3(5, 2, 5),
  new THREE.Vector3(10, 0, -5),
  new THREE.Vector3(5, 0, -15),
  new THREE.Vector3(0, 1, -25),
  new THREE.Vector3(-5, 0, -35),
]);

// --- Scene objects (placed along the path) ---
const geometry = new THREE.IcosahedronGeometry(1, 1);
const material = new THREE.MeshStandardMaterial({ color: 0x8b5cf6, roughness: 0.3, metalness: 0.8 });

for (let i = 0; i < 30; i++) {
  const mesh = new THREE.Mesh(geometry, material);
  const t = i / 30;
  const point = cameraPath.getPointAt(t);
  mesh.position.set(
    point.x + (Math.random() - 0.5) * 10,
    point.y + (Math.random() - 0.5) * 5,
    point.z + (Math.random() - 0.5) * 10
  );
  mesh.scale.setScalar(0.3 + Math.random() * 0.7);
  scene.add(mesh);
}

scene.add(new THREE.AmbientLight(0xffffff, 0.3));
const dirLight = new THREE.DirectionalLight(0xffffff, 1.2);
dirLight.position.set(5, 10, 5);
scene.add(dirLight);

// --- Smooth scroll ---
const lenis = new Lenis({ autoRaf: false, duration: 1.2, smoothWheel: true });
lenis.on('scroll', ScrollTrigger.update);

// --- ScrollTrigger drives camera ---
const lookAtTarget = new THREE.Vector3();

ScrollTrigger.create({
  trigger: '#experience',
  start: 'top top',
  end: 'bottom bottom',
  scrub: 2,
  onUpdate: (self) => {
    // getPointAt uses arc-length parameterization = constant speed
    const pos = cameraPath.getPointAt(self.progress);
    const look = lookAtPath.getPointAt(Math.min(self.progress + 0.05, 1));

    camera.position.copy(pos);
    lookAtTarget.lerp(look, 0.1);
    camera.lookAt(lookAtTarget);
  },
});

// --- Single ticker ---
gsap.ticker.add((time) => {
  lenis.raf(time * 1000);
  renderer.render(scene, camera);
});
gsap.ticker.lagSmoothing(0);

// --- Resize ---
window.addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});
```

```html
<canvas id="webgl" style="position:fixed; inset:0; z-index:0;"></canvas>
<div id="experience" style="position:relative; z-index:1; height:500vh;">
  <section style="height:100vh; display:flex; align-items:center; justify-content:center;">
    <h1 style="color:white; mix-blend-mode:difference; pointer-events:none;">Welcome</h1>
  </section>
  <section style="height:100vh; display:flex; align-items:center; justify-content:center;">
    <h2 style="color:white; mix-blend-mode:difference; pointer-events:none;">Explore</h2>
  </section>
  <section style="height:100vh; display:flex; align-items:center; justify-content:center;">
    <h2 style="color:white; mix-blend-mode:difference; pointer-events:none;">Discover</h2>
  </section>
  <section style="height:100vh; display:flex; align-items:center; justify-content:center;">
    <h2 style="color:white; mix-blend-mode:difference; pointer-events:none;">Create</h2>
  </section>
  <section style="height:100vh; display:flex; align-items:center; justify-content:center;">
    <h2 style="color:white; mix-blend-mode:difference; pointer-events:none;">Ship</h2>
  </section>
</div>
```

**Key details:**
- `getPointAt()` (not `getPoint()`) — arc-length parameterized = constant speed
- `scrub: 2` gives a cinematic 2-second lag
- `lookAtTarget.lerp()` smooths camera rotation to avoid snapping
- DOM text with `mix-blend-mode: difference` overlays the 3D scene
- `height: 500vh` creates the scroll distance for the journey

---

## Quick Reference: Which Effect for Which Project

| Effect | Complexity | Dependencies | Best for |
|--------|-----------|-------------|----------|
| Preloader | Low | GSAP | Every immersive site |
| Smooth scroll | Low | Lenis, GSAP | Every site with scroll animations |
| Text reveal | Low-Med | GSAP | Hero sections, headings |
| Marquee | Low | GSAP | Branding, testimonials |
| Magnetic cursor | Medium | GSAP | Portfolios, agency sites |
| Image distortion | High | Three.js, GLSL | Galleries, portfolios |
| Parallax layers | Low-Med | GSAP or Three.js | Landing pages, storytelling |
| Camera path | High | Three.js, GSAP, Lenis | Product showcases, experiences |
