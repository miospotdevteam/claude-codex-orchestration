---
name: frontend-design
description: "Create distinctive, production-grade frontend interfaces with intentional design direction — landing pages, portfolios, dashboards, marketing sites, pricing pages, sign-up flows, blog templates, documentation sites, product pages, or any web UI where visual quality matters. Make sure to use this skill whenever the user asks to build, design, or redesign a website, web page, or UI component — especially when they mention wanting it to look 'modern', 'polished', 'premium', 'beautiful', 'professional', 'clean', or 'fresh', or when they care about typography, color palette, visual hierarchy, or design systems. Also trigger when the user says 'make it look good', 'needs a visual refresh', 'feels dated', or 'doesn't stand out'. Covers greenfield (new designs) and integration (extending existing design systems) with framework-specific guidance for HTML/CSS, React, Vue, Svelte, Tailwind, and shadcn/ui. Do NOT use when: fixing a CSS bug with no design change, making backend-only changes, or building WebGL/Three.js/shader/scroll-driven immersive experiences (use immersive-frontend instead). When brainstorming preceded this skill, skip Phases 1-2 and start at Phase 3."
---

# Frontend Design

Build frontend interfaces that are distinctive, intentional, and
production-grade. This skill replaces vague "be creative" advice with a
structured process that produces consistently high-quality results while
preventing the generic aesthetic convergence that plagues AI-generated UIs.

**Announce at start:** "I'm using the frontend-design skill to guide the
design and implementation."

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Context Scan) runs during Step 1 (Explore) and feeds
  `discovery.md`.
- **Phase 2** (Design Direction) runs between Step 1 and Step 2 — its
  outputs are consumed by `writing-plans` when creating the masterPlan.
- **Phases 3-4** (Implementation, Verification) run during Step 3 (Execute).

---

## Integration with Other Skills

**After brainstorming:** If `brainstorming` ran first and produced a
`design.md` with visual direction (typography, colors, layout choices):
**skip Phases 1-2 entirely**. Use the approved design and proceed to
Phase 3. If the design includes a **Creative Brief**, its Visual
Direction informs the Decision Matrix scores if Phase 2 still runs, and
its Copy Voice section guides all text content decisions (headlines,
CTAs, microcopy, empty states, error messages) during implementation.

**After immersive-frontend request:** If `immersive-frontend` invoked
this skill for design direction only, run Phase 2 (Design Direction) and
return the approved choices. Do NOT proceed to Phase 3 — immersive-frontend
handles implementation.

**Standalone:** If neither preceded this skill, run the full flow
(Phases 1-4) with the user approval checkpoint in Phase 2.

**Design already decided:** If the user's request is purely "build this
mockup/design" (design already decided): skip Phase 2, proceed to Phase 3.

---

## Phase 1: Context Scan

Determine the operating mode before making any design decisions.

### Detect the mode

**Greenfield mode** — you have full creative freedom:
- Building a standalone page, component, or prototype
- No `tailwind.config` custom theme, no CSS variables, no component library,
  no theme files
- User explicitly says "from scratch" or "new design"

**Integration mode** — you work within an existing system:
- Project has Tailwind config with custom theme, CSS variables, or a
  component library
- Existing pages/components establish clear patterns
- User is adding to or modifying an existing UI

### Greenfield scan

Note these before proceeding:
- **Framework**: vanilla HTML/CSS, React, Vue, Svelte, etc.
- **Constraints**: must work without JS? SSR-compatible? Performance budget?
- **Delivery format**: single HTML file? Component library? Full app?
- **Audience and purpose**: who uses this and why?

### Integration scan

Read these before proceeding:
- `tailwind.config` / CSS variables / theme files — extract the token system
- 2-3 existing pages/components — learn the visual language
- Component library docs (Shadcn, MUI, Chakra, etc.) — know what's available
- Note what's working well and what could be elevated

In integration mode, also read:
- `references/ui-consistency-checklist.md` — consistency rules
- `references/ui-consistency-guide.md` — design token discipline

**Both modes:** Write findings to `discovery.md` as part of the conductor's
Step 1 exploration.

**Failure path:** If the project has no discernible design system and isn't
greenfield (e.g., inconsistent styles, no tokens), treat it as greenfield
with the constraint of matching existing code conventions.

---

## Phase 2: Design Direction

### Greenfield — Decision Matrix

Score each axis on a 1-5 scale based on the project context. The combination
narrows the aesthetic space before any visual decisions are made.

| Axis | 1 | 5 |
|---|---|---|
| **Audience** | Technical / developer | General public / consumer |
| **Formality** | Corporate / institutional | Casual / personal |
| **Energy** | Calm / restrained | Dynamic / energetic |
| **Density** | Spacious / minimal | Dense / information-rich |
| **Era** | Classic / timeless | Contemporary / trendy |
| **Temperature** | Warm (organic, rounded) | Cool (geometric, precise) |

**Example:** A developer documentation site — Technical (5), Formal (3),
Calm (4), Dense (4), Contemporary (4), Cool (5) — narrows to:
monospace-influenced typography, cool neutral palette with one accent, generous
line-height but compact layout, subtle animations, geometric shapes.

**Example:** A children's educational app — General (5), Casual (5),
Energetic (5), Spacious (2), Contemporary (4), Warm (5) — narrows to:
rounded display font, bright primary palette, generous whitespace, bouncy
animations, organic shapes.

**Example:** A creative design agency — General (4), Casual (4),
Moderate (3), Spacious (2), Contemporary (4), Warm (2) — narrows to:
light cream/warm background (warm + casual = light, NOT dark), editorial
display font paired with clean body sans, warm accent color (burnt orange,
terracotta, coral), generous whitespace, grain/noise texture for craft
feel, asymmetric layouts that showcase creative confidence.

#### Light vs dark mode selection

Before choosing colors, decide the base theme. This is not a stylistic
preference — it's a brand decision driven by the axes:

| Choose light when | Choose dark when |
|---|---|
| Temperature 1-3 (warm) | Temperature 4-5 (cool) AND Audience 1-2 (technical) |
| Formality 3-5 (casual to corporate) | The product is a dev tool, dashboard, or code-adjacent |
| The brand is warm, friendly, creative, or approachable | The user explicitly requests dark mode |
| It's a creative agency, portfolio, lifestyle, food, fashion, education | It's a terminal, IDE, analytics tool, or night-use app |

**Dark mode is not "more premium."** A creative agency on a dark background
looks like a developer tool. A warm brand on dark looks cold. Match the
theme to what the brand actually *is*, not to what feels technically
impressive. When in doubt, choose light — it's harder to make dark feel
warm and inviting, and getting it wrong alienates the audience.

If the user asks for dark mode support (toggle), still choose the *default*
theme based on the brand, and make dark mode the alternative.

#### Creative seed protocol

After scoring the axes, pick ONE unexpected element to anchor the design.
This prevents convergence — it's the memorable thing that makes this design
THIS design, not a generic template.

**The seed must serve the brand, not just surprise.** A chartreuse accent
on a dark background is unexpected, but if the brand is a warm creative
agency, it's the wrong kind of unexpected — it makes the brand feel
technical and cold. Ask: "Would the brand's target audience find this
element delightful or alienating?"

Good creative seeds (matched to context):
- **Warm/creative brands**: a distinctive warm accent (terracotta, coral,
  golden amber), grain/noise texture, hand-drawn-feeling illustration
  style, editorial oversized typography, organic asymmetric layouts
- **Technical/cool brands**: a sharp accent color on dark neutrals,
  monospace typography accents, data-visualization-inspired elements,
  precise geometric patterns, topographic or grid textures
- **Any brand**: a distinctive display font that sets the tone, an
  unconventional layout technique (asymmetric grid, bento, overlapping
  elements), a signature animation moment (page load choreography)

Bad creative seeds (overused or context-blind):
- Purple-to-blue gradient on white
- Card grid with rounded corners and subtle shadows
- Fade-in-up animations on scroll
- Inter or Space Grotesk as the display font
- Dark theme + neon/fluorescent accent on a warm brand (looks like a
  developer tool, not the brand it's supposed to represent)

#### Concrete choices

With the axes scored, theme selected, and creative seed chosen, select:

1. **Typography**: Display font + body font (consult
   `references/frontend-design-guide.md` for sourcing)
2. **Color**: Start from a curated palette, not from scratch.
   Read `references/color-palettes.md` and pick the palette that matches
   your Temperature axis and brand context:
   - **Warm Cream** (Temperature 1-3) — cream backgrounds, warm neutrals
   - **Cool Slate** (Temperature 4-5) — blue-gray base, sharp accents
   - **Dark Gallery** (editorial/photography) — warm-tinted near-blacks
   - **Neutral Minimal** (content-focused) — clean zinc grays
   Copy the CSS variables, then swap the primary/accent hue to match the
   brand (keep the lightness relationships — they're tuned for contrast).
   For npm-based projects, also consider **Radix Colors**
   (`@radix-ui/colors`), **Open Color** (`open-color`), or **Palx**
   (`palx`) — all installed globally. See
   `references/frontend-design-guide.md` § Pre-built Palette Libraries.
   If generating manually, use HSL shift, OKLCH, or complementary methods
   (see § Palette Generation Methods). State which source/method you used.
3. **Motion**: Animation philosophy + key moments (load, hover, transitions)
4. **Layout**: Grid system, spacing scale, composition approach
5. **Texture**: Backgrounds, borders, shadows, depth treatment

**Present all choices to the user before proceeding.** Walk through the axis
scores, creative seed, and concrete selections. When offering alternatives
or asking the user to choose between options, use the `AskUserQuestion`
tool for a structured selection UI rather than listing choices in plain text.
Do NOT proceed to Phase 3 until the user approves the direction. If the
user disagrees, iterate on the specific choices they reject.

Document all approved choices in the masterPlan before writing code.

#### Motion tier assessment

Based on the Energy axis score and the user's vision, classify the motion
needs:

| Tier | Signals | Implementation |
|---|---|---|
| **Standard** | Energy 1-3, CSS transitions, hover states, simple page transitions | This skill (Phase 3) |
| **Enhanced** | Energy 3-4, scroll-driven reveals, parallax, text choreography, GSAP-level animation | `immersive-frontend` (Motion-Enhanced tier) |
| **Immersive** | Energy 5, WebGL, 3D scenes, custom shaders, canvas experiences, Awwwards-style | `immersive-frontend` (WebGL-Lite or Full Immersive tier) |

If the motion tier is **Enhanced** or **Immersive**: this skill's job ends
after the user approves the design direction. Write the handoff document
to `discovery.md` or `design.md` using this structure, then invoke
`immersive-frontend`:

```markdown
## Design Handoff → immersive-frontend
- **Axis scores**: [all 6 scores]
- **Creative seed**: [description]
- **Typography**: [display + body fonts, weights, scale]
- **Color system**: [primary, secondary, accent, neutrals with hex/oklch]
- **Dark mode**: [yes/no, if yes: adaptation notes]
- **Animation philosophy**: [key moments, easing, duration scale]
- **Motion tier**: [Enhanced / Immersive]
- **Scope**: [full-page / hybrid section — if hybrid, which sections]
```

`immersive-frontend` will consume this and handle technical architecture
and implementation.

#### Hybrid project scope partition

For projects with both standard UI and immersive sections, this skill and
`immersive-frontend` split ownership:

| Aspect | `frontend-design` owns | `immersive-frontend` owns |
|---|---|---|
| Design direction | All design decisions (both skills) | — |
| Standard UI pages | Implementation + verification | — |
| Immersive sections | — | Implementation + verification |
| Shared design tokens | Defines tokens | Consumes tokens |
| Transition zones | Provides CSS for entering/exiting | Provides canvas setup |

If the motion tier is **Standard**: proceed to Phase 3 in this skill.

#### Failure paths

- If the chosen font is unavailable or has insufficient weights, select
  the next alternative from the same category in the guide.
- If the creative seed produces poor results during implementation, revisit
  it — pick a new seed and adjust the concrete choices before continuing.

### Integration — Design System Extension

When working within an existing system, creativity operates WITHIN the
constraints:

1. **Audit the existing system** — identify its strongest and weakest aspects
2. **Propose 1-2 elevation opportunities** — better animation, more
   intentional spacing, refined typography within the existing type scale
3. **Stay within the token system** — extend it only if the user approves
4. **Match existing patterns** — loading states, error states, component
   structure

The goal is not to redesign the system but to raise the quality bar for the
new work within its vocabulary.

---

## Phase 3: Implementation

### Anti-slop philosophy

Every design decision must be intentional. These patterns signal generic,
unconsidered output — avoid them:

| Category | Avoid | Use instead |
|---|---|---|
| Fonts | Inter, Roboto, Arial, system-ui as display | Satoshi, General Sans, DM Sans, Outfit, Manrope |
| Colors | Purple-to-blue gradient on white | Start from Temperature axis; use OKLCH palette from brand color |
| Colors | Pure black on pure white (#000/#fff) | Near-black on near-white (`#1a1a2e` / `#fafaf9`) |
| Layout | Symmetric 3-card grid with identical shadows | Bento, masonry, asymmetric splits, varied card sizes |
| Animation | Fade-in-up on every scroll section | Animate 2-3 key moments; leave the rest static |
| Patterns | Glassmorphism with no purpose | Solid surfaces with texture (grain, noise) or accent borders |
| Theme | Dark bg for warm/creative/casual brands | Light theme for warm brands; dark only for tech/dev/night-use |
| Theme | Neon/fluorescent accent on non-tech brand | Accent color that matches the brand's warmth and personality |

The full blacklist is in `references/frontend-design-guide.md` § Anti-Slop
Blacklist. Also read `references/anti-slop.md` for the shared cross-skill
banlist covering typography, color, layout, animation, illustration, and copy.

### Content separation: whitespace over containers

The default instinct is to wrap every content group in a bordered,
shadowed, background-colored card. Resist it. Most content groups don't
need a container — they need whitespace, typography hierarchy, and
subtle dividers to establish visual separation.

**When a container IS warranted:**
- Interactive cards (clickable, hoverable — the container signals affordance)
- Data that needs grouping (pricing tiers, stat cards, testimonials)
- Content that needs visual distinction from its surroundings (callouts,
  alerts, featured items)

**When a container is NOT needed:**
- Feature descriptions — use a heading + paragraph with generous spacing
- Section content — use section padding and `<hr>` or subtle borders
- Lists of items — use whitespace between items, not boxes around each one
- Informational text blocks — let typography do the work

**Alternatives to containers:**
- **Whitespace** — generous padding between groups creates clear separation
  without visual noise
- **Typography weight/size shifts** — a bold heading + lighter body text
  creates hierarchy without boxing
- **Subtle horizontal rules** — a thin `1px` border or `<hr>` between
  groups is cleaner than wrapping each in a card
- **Background color bands** — alternate section backgrounds (e.g.,
  `--surface-0` and `--surface-1`) to group content without borders
- **Indent or margin shifts** — a left border accent or left margin
  change signals grouping without full enclosure

When you do use containers, vary them: not every card needs the same
border, shadow, and padding. Feature the important one, mute the rest.

### Whitespace quality

Whitespace is not just "empty space" — it's a design tool. Bad whitespace
is wasted space that makes a page feel unfinished. Good whitespace creates
rhythm, directs attention, and makes content breathe.

- **Fill the viewport width intentionally** — content should feel like it
  belongs on the page, not floating in a void. If there are large empty
  margins on desktop, the content area or layout should expand to use them
- **Grid items should fill their cells** — portfolio grids, feature grids,
  and card layouts should feel complete and balanced, not sparse
- **Section spacing should create rhythm** — consistent vertical rhythm
  between sections (e.g., 6rem/8rem between major sections) is good. Random
  amounts of empty space between sections is not
- **Edge-to-edge on mobile** — on small viewports, eliminate unnecessary
  horizontal padding. Content should feel full-width, not squeezed into a
  narrow column with huge side margins

### Vanilla HTML/CSS

- CSS custom properties for all design tokens
- CSS-only animations (`@keyframes`, `transition`)
- Google Fonts with `font-display: swap` and system font fallbacks
- Semantic HTML (`<header>`, `<nav>`, `<main>`, `<section>`, `<article>`)
- Responsive with CSS Grid/Flexbox and `clamp()` for fluid typography

### React

- CSS modules or styled-components (match project convention)
- Motion library (`motion/react`) for orchestrated animations
- Component composition — small, focused components over monoliths
- Font loading with `next/font` (Next.js) or `@fontsource` (other React)
- `prefers-reduced-motion` media query respected in all animations

### Tailwind projects

- Extend `tailwind.config` for custom tokens — don't fight the system
- Custom plugin for unique design tokens when the config is insufficient
- Arbitrary values (`text-[17px]`) only when no token exists
- `@apply` sparingly — prefer utility classes in markup
- Use the project's existing spacing/color patterns; introduce new values
  only with justification

### Font sourcing

Consult `references/frontend-design-guide.md` for the full font sourcing
protocol. Quick reference:

| Source | When | How |
|---|---|---|
| Google Fonts | Default for web | `<link>` tag, `font-display: swap` |
| `@fontsource` | React/Next.js | `npm install @fontsource/font-name` |
| `next/font` | Next.js | Built-in optimization, auto subset |
| Variable fonts | When available | Single file, `font-variation-settings` |
| System fonts | Fallbacks only | Font stack with system-ui |

### Dark mode

When the design supports dark and light themes:

1. **Semantic tokens, not raw values.** Define `--surface`, `--on-surface`,
   `--muted`, `--border`, `--ring` etc. as CSS variables. Toggle them via a
   class (`.dark`) or `prefers-color-scheme`.
2. **Dark ≠ inverted.** Don't flip every color. Dark backgrounds need:
   - Near-black with a warm or cool tint (`#0f0f12`, not `#000`)
   - Reduced text contrast — `#e0e0e0` on dark, not pure white
   - Lowered shadow opacity (shadows are less visible on dark surfaces)
   - Borders and dividers become lighter/more subtle, not darker
3. **Elevation via lightness.** In dark mode, higher surfaces are *lighter*
   (opposite of light mode where elevation = shadow). Use 2-3 surface tiers:
   `--surface-0` (darkest), `--surface-1`, `--surface-2` (lightest).
4. **Primary color adaptation.** Saturated primaries that work on white may
   need desaturation or lightness adjustment for dark backgrounds. Test
   contrast at both themes.
5. **Tailwind**: use the `dark:` variant with `darkMode: 'class'` in config.
   **Vanilla CSS**: use `[data-theme="dark"]` or `.dark` class on `<html>`.

See `references/frontend-design-guide.md` § Dark Mode Color Adaptation for
the full adaptation rules.

### Micro-interactions

Purposeful micro-interactions make interfaces feel alive. Add them to the
moments that matter, not everywhere.

| Interaction | Pattern | Timing |
|---|---|---|
| **Hover lift** | `transform: translateY(-2px)` + shadow increase | 200ms ease-out |
| **Button press** | `transform: scale(0.97)` on `:active` | 100ms ease-in |
| **Focus ring** | `box-shadow: 0 0 0 3px var(--ring)` on `:focus-visible` | instant (no transition on focus) |
| **Toggle switch** | Thumb slides with `transform: translateX()` + bg color transition | 200ms ease |
| **Dropdown open** | `transform: scaleY(0→1)` from `transform-origin: top` + `opacity` | 150ms ease-out |
| **Card hover** | Border color shift or subtle glow, not just shadow lift | 200ms ease |
| **Link underline** | Width grows from left via `background-size` or `clip-path` | 250ms ease-out |

Rules:
- Use `transition` for user-triggered interactions, `@keyframes` for
  entrance choreography
- Always pair visual feedback with `:focus-visible` for keyboard users
- All micro-interactions must respect `prefers-reduced-motion` (disable or
  simplify)
- Consistent easing — pick one curve for the whole project

### Component composition

Define scales for the building blocks so components compose consistently:

**Spacing scale** (padding/gap inside components):
```
compact:  px-2 py-1   (8px / 4px)   — tags, badges, dense tables
default:  px-4 py-2   (16px / 8px)  — buttons, inputs, cards
spacious: px-6 py-3   (24px / 12px) — hero sections, feature cards
```

**Border radius scale:**
```
none: 0        — tables, full-bleed sections
sm:   4px      — inputs, small buttons
md:   8px      — cards, modals, standard buttons
lg:   12-16px  — feature cards, large containers
full: 9999px   — pills, avatars, toggle tracks
```

**Shadow scale** (elevation tiers):
```
sm:  0 1px 2px rgba(0,0,0,0.05)                         — subtle lift
md:  0 4px 6px -1px rgba(0,0,0,0.07)                    — cards, dropdowns
lg:  0 10px 15px -3px rgba(0,0,0,0.08)                  — modals, popovers
xl:  0 20px 25px -5px rgba(0,0,0,0.1)                   — large modals, hero elements
```

In Tailwind, extend these in `tailwind.config`. In vanilla CSS, define as
custom properties. Shadows need adaptation for dark mode (reduce opacity,
increase blur).

### Match complexity to vision

Maximalist designs need elaborate code: extensive animations, layered
textures, complex compositions. Minimalist designs need restraint and
precision: careful spacing, typography refinement, subtle details. The
implementation must match the aesthetic — don't write minimal code for a
maximalist vision or bloated code for a minimal one.

---

## Phase 4: Verification

Run the `references/frontend-design-checklist.md` checklist. The key
domains:

**Accessibility:**
- Color contrast passes WCAG AA (4.5:1 text, 3:1 large text)
- Semantic HTML (headings, landmarks, buttons not divs)
- Keyboard navigable with visible focus styles
- `prefers-reduced-motion` respected

**Responsive:**
- Works at 375px (mobile), 768px (tablet), 1280px (desktop)
- No horizontal scroll at any breakpoint
- Touch targets at least 44x44px on mobile
- Typography scales (not just shrinks)

**Performance:**
- Fonts loaded with `font-display: swap` or `optional`
- Animations use `transform` and `opacity` (GPU-composited)
- No excessive DOM depth from decorative wrappers

**Coherence:**
- All colors from defined tokens (no raw hex in components)
- Spacing follows a consistent scale
- Typography uses defined type scale
- Animation timing/easing consistent across elements

### Verification commands

Run the project's own commands first (check `package.json`, `Makefile`,
`CLAUDE.md`). Supplement with:

- **Type check**: `tsc --noEmit` (or project equivalent)
- **Lint**: `eslint`, `biome`, or project linter
- **Accessibility audit**: browser DevTools Accessibility panel, or
  `axe-core` / `@axe-core/cli` if installed
- **Contrast check**: verify specific color pairs meet WCAG AA (4.5:1 body,
  3:1 large text) using browser DevTools or a contrast ratio tool
- **Responsive check**: browser DevTools responsive mode at 375px, 768px,
  1280px

### Failure paths

- If contrast checks fail after implementation, adjust the failing colors
  to meet WCAG AA while staying within the chosen palette's hue — do not
  switch to a completely different palette.
- If the overall result feels generic despite the creative seed, revisit
  the seed and the concrete choices before shipping. The seed should be
  visibly present in the final result.
- If a font fails to load or renders poorly, swap to the next alternative
  from the same category and update the fallback stack.

---

## Acceptance Criteria

- [ ] Design direction presented to user and approved (greenfield mode)
- [ ] All colors from defined tokens — no raw hex in components
- [ ] Accessibility: contrast AA, semantic HTML, keyboard navigation, reduced-motion
- [ ] Responsive at 375px, 768px, 1280px — no horizontal scroll
- [ ] Animations use transform/opacity only
- [ ] No anti-slop patterns present (check full blacklist in guide)
- [ ] Type checker and linter pass
- [ ] Integration mode: side-by-side comparison with existing pages done

---

## Output Contract

This skill produces:

1. **Design decisions** in `discovery.md` or `design.md` (Phase 2) — axis
   scores, creative seed, typography, color, motion, layout, texture choices
2. **Implemented code files** (Phase 3)
3. **Verification results** noted in the masterPlan step's Result field
   (Phase 4) — which checklist items passed, any issues found and resolved

---

## Routing to Other References

| Situation | Read / Invoke |
|---|---|
| Choosing a color palette | `references/color-palettes.md` — curated CSS variable sets |
| Working within existing design system | `references/ui-consistency-checklist.md` + `references/ui-consistency-guide.md` |
| Adding font/animation dependencies | `references/dependency-checklist.md` |
| User input rendered in UI | `references/security-checklist.md` |
| Testing UI components | `references/testing-checklist.md` |
| Design calls for SVG illustrations, patterns, or textures | Invoke `svg-art` — pass design direction (palette, temperature) |
| Motion tier is Enhanced or Immersive | Invoke `immersive-frontend` — pass design direction |

For the full font sourcing protocol, aesthetic axis deep-dives, animation
patterns, color systems, and the extended anti-slop blacklist, read
`references/frontend-design-guide.md`.
