# GSAP Text Plugins

Text splitting, decode effects, and content animation. SplitText is now
free with significant new features (mask, autoSplit, aria accessibility).

> **GSAP is 100% free** — all plugins included with `bun add gsap`.

---

## 1. SplitText — Text Splitting for Animation

Split text into characters, words, and/or lines for individual animation.
Handles emoji, ligatures, RTL, nested elements, and screen readers.

```javascript
import { SplitText } from 'gsap/SplitText';
gsap.registerPlugin(SplitText);
```

### Basic Usage

```javascript
// Split into chars, words, and/or lines
const split = new SplitText('.hero-title', {
  type: 'chars,words,lines', // any combination
});

split.chars;  // array of character elements
split.words;  // array of word elements
split.lines;  // array of line elements

// Animate
gsap.from(split.chars, {
  y: 50, opacity: 0, stagger: 0.03, duration: 0.6, ease: 'power3.out',
});
```

### Constructor Options

```javascript
new SplitText(target, {
  type: 'chars,words,lines',  // what to split into
  mask: 'lines',              // NEW: built-in overflow:hidden wrappers
  autoSplit: true,            // NEW: auto re-split on resize
  onSplit: (self) => {},      // NEW: callback on split and every re-split
  aria: 'auto',               // NEW: automatic aria handling
  charsClass: 'char',         // custom class for char elements
  wordsClass: 'word',         // custom class for word elements
  linesClass: 'line',         // custom class for line elements
  tag: 'span',                // wrapper element type (default: span)
  reduceWhiteSpace: true,     // collapse whitespace
  specialChars: ['&amp;'],    // treat as single characters
});
```

### mask — Built-in Overflow Hidden (NEW)

Previously you had to manually wrap each line in a `<div>` with
`overflow: hidden` for masked reveals. Now it's built in:

```javascript
// OLD WAY (manual wrappers — no longer needed)
split.lines.forEach(line => {
  const wrapper = document.createElement('div');
  wrapper.style.overflow = 'hidden';
  line.parentNode.insertBefore(wrapper, line);
  wrapper.appendChild(line);
});

// NEW WAY
const split = new SplitText('.text', {
  type: 'lines',
  mask: 'lines',  // automatic overflow:hidden wrappers!
});

gsap.from(split.lines, {
  yPercent: 100, // slides up from below the mask
  duration: 0.8, ease: 'power4.out', stagger: 0.12,
});
```

The `mask` property accepts the same values as `type`: `'chars'`,
`'words'`, `'lines'`, or combinations.

### autoSplit + onSplit — Responsive Text (NEW)

Text line breaks change on resize. `autoSplit` automatically re-splits
when the element resizes, and `onSplit` fires each time so you can
recreate animations.

```javascript
const split = new SplitText('.responsive-text', {
  type: 'lines',
  mask: 'lines',
  autoSplit: true,
  onSplit: (self) => {
    // This fires on initial split AND every re-split
    gsap.from(self.lines, {
      yPercent: 100,
      duration: 0.8,
      ease: 'power4.out',
      stagger: 0.1,
      scrollTrigger: {
        trigger: self.elements[0],
        start: 'top 80%',
      },
    });
  },
});
```

Without `autoSplit`, you'd need to manually handle resize:
```javascript
// OLD WAY (still valid if not using autoSplit)
window.addEventListener('resize', () => {
  split.revert();
  // re-create split and animations
});
```

### aria — Accessibility (NEW)

SplitText automatically manages aria attributes so screen readers
read the original text, not individual characters.

```javascript
new SplitText('.text', {
  type: 'chars',
  aria: 'auto', // default — handles accessibility automatically
});
// Result: parent gets aria-label with full text,
// individual chars get aria-hidden="true"
```

### propIndex — CSS Variable Index (NEW)

Each split element gets a `--prop-index` CSS variable for stagger-like
CSS effects.

```javascript
new SplitText('.text', { type: 'chars' });
// Each char span gets style="--prop-index: 0", "--prop-index: 1", etc.
```

```css
.char {
  /* CSS-only stagger using the index */
  animation-delay: calc(var(--prop-index) * 0.05s);
}
```

### deepSlice() — Range Selection (NEW)

Select a precise range of split elements.

```javascript
const split = new SplitText('.text', { type: 'chars,words' });

// Get chars 5-10
const subset = split.deepSlice(5, 10);

// Animate just that range
gsap.from(subset, { opacity: 0, y: 20, stagger: 0.05 });
```

### Properties & Methods

```javascript
split.chars;     // character elements array
split.words;     // word elements array
split.lines;     // line elements array
split.elements;  // original target elements
split.isSplit;   // boolean

split.revert();  // restore original text (cleanup)
split.split({});  // re-split with new config
```

---

## Common SplitText Patterns

### Character Cascade Reveal

```javascript
const split = new SplitText('.hero-title', { type: 'chars,words' });

gsap.fromTo(split.chars, {
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

### Line-by-Line Masked Reveal

```javascript
const split = new SplitText('.paragraph', {
  type: 'lines',
  mask: 'lines',
  autoSplit: true,
  onSplit: (self) => {
    gsap.from(self.lines, {
      yPercent: 100,
      duration: 0.8,
      ease: 'power4.out',
      stagger: 0.12,
      scrollTrigger: {
        trigger: self.elements[0],
        start: 'top 85%',
      },
    });
  },
});
```

### Word Fade-Up

```javascript
const split = new SplitText('.tagline', { type: 'words' });

gsap.from(split.words, {
  y: 40, opacity: 0,
  duration: 0.6, ease: 'power2.out',
  stagger: 0.08,
});
```

### Per-Character Color Wave

```javascript
const split = new SplitText('.rainbow', { type: 'chars' });

gsap.to(split.chars, {
  color: '#00e5ff',
  duration: 0.3,
  stagger: {
    each: 0.05,
    from: 'start',
    repeat: -1,
    yoyo: true,
  },
});
```

### React Cleanup

```javascript
import { useGSAP } from '@gsap/react';

function AnimatedTitle({ text }) {
  const ref = useRef(null);

  useGSAP(() => {
    const split = new SplitText(ref.current, {
      type: 'chars',
      mask: 'chars',
    });

    gsap.from(split.chars, {
      yPercent: 100, opacity: 0,
      stagger: 0.03, duration: 0.6,
    });

    // split.revert() called automatically by context cleanup
  }, { scope: ref });

  return <h1 ref={ref}>{text}</h1>;
}
```

---

## 2. ScrambleText — Hacker Decode Effect

Randomizes text characters before revealing the final string.

```javascript
import { ScrambleTextPlugin } from 'gsap/ScrambleTextPlugin';
gsap.registerPlugin(ScrambleTextPlugin);
```

### Basic Usage

```javascript
gsap.to('.terminal-text', {
  duration: 2,
  scrambleText: {
    text: 'ACCESS GRANTED',
    chars: 'upperCase',       // character set for scramble
    revealDelay: 0.5,         // delay before chars start resolving
    speed: 0.3,               // how fast chars cycle (lower = faster)
  },
});
```

### Configuration

```javascript
scrambleText: {
  text: 'Final text',         // target text (or 'original' to revert)
  chars: 'upperCase',         // 'upperCase', 'lowerCase', custom string
  // chars: 'XO!#*@',         // custom character set
  revealDelay: 0.5,           // seconds before resolution starts
  speed: 0.3,                 // scramble speed (0.1-1)
  delimiter: '',              // split by ('' = chars, ' ' = words)
  tweenLength: true,          // animate text length change
  newClass: 'scrambled',      // class for unrevealed chars
  oldClass: 'revealed',       // class for resolved chars
  rightToLeft: false,         // reveal direction
}
```

### Hacker Terminal Decode

```javascript
const lines = gsap.utils.toArray('.terminal-line');
const tl = gsap.timeline();

lines.forEach((line, i) => {
  tl.to(line, {
    duration: 1.5,
    scrambleText: {
      text: line.dataset.text,
      chars: '01!@#$%^&*',
      revealDelay: 0.3,
      speed: 0.4,
    },
  }, i * 0.3);
});
```

### Scramble on Scroll Enter

```javascript
ScrollTrigger.batch('.scramble-text', {
  onEnter: (elements) => {
    elements.forEach(el => {
      gsap.to(el, {
        scrambleText: {
          text: el.textContent,
          chars: 'lowerCase',
          revealDelay: 0.3,
        },
        duration: 1.5,
      });
    });
  },
  start: 'top 85%',
  once: true,
});
```

---

## 3. TextPlugin — Simple Text Replacement

Animate the text content of an element, replacing character by character.

```javascript
import { TextPlugin } from 'gsap/TextPlugin';
gsap.registerPlugin(TextPlugin);
```

### Typewriter Effect

```javascript
gsap.to('.typewriter', {
  duration: 3,
  text: 'Hello, I am a developer.',
  ease: 'none', // linear for typewriter feel
});
```

### Word-by-Word

```javascript
gsap.to('.output', {
  duration: 2,
  text: {
    value: 'This replaces word by word',
    delimiter: ' ', // split by spaces
  },
});
```

### Cycling Text

```javascript
const phrases = ['Developer', 'Designer', 'Creator'];
const tl = gsap.timeline({ repeat: -1 });

phrases.forEach(phrase => {
  tl.to('.role', { duration: 1, text: phrase, ease: 'none' })
    .to({}, { duration: 2 }); // pause
});
```

---

## When to Use Which

| Plugin | Best For |
|--------|----------|
| **SplitText** | Character/word/line animation, reveals, staggers, any text where individual elements need to move |
| **ScrambleText** | Hacker/decode effects, dramatic text reveals, terminal aesthetics |
| **TextPlugin** | Typewriter effects, content replacement, cycling text |

### Manual Split Alternative

Manual splitting is still valid for minimal bundle size, but SplitText
handles edge cases that manual splitting misses:
- Emoji (multi-codepoint characters)
- Ligatures
- RTL text
- Nested HTML elements inside text
- Screen reader accessibility
- Responsive re-splitting on resize

For most projects, just use SplitText — it's free and handles everything.
