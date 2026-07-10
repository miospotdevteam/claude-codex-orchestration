---
name: react-native-mobile
description: "Build premium, native-feeling React Native mobile apps with spring animations, gesture-driven UI, haptic feedback, and platform-specific conventions. Use this skill whenever the user asks for: React Native app, mobile app, Expo app, native feel, gesture animations, haptic feedback, mobile UI, iOS/Android app, cross-platform mobile, Reanimated animations, bottom sheet, swipe gestures, pull-to-refresh, mobile navigation, tab bar, mobile onboarding, mobile performance, FlashList, MMKV storage, offline-first mobile, React Native new architecture, mobile dark mode, Dynamic Type, VoiceOver/TalkBack accessibility, Liquid Glass, or any request for building mobile applications that should feel indistinguishable from native apps. Also use when the user references apps like Things 3, Apollo, Spotify, Discord, Shopify, or Apple's HIG / Material Design 3. Do NOT use for: React web apps (use frontend-design), React Native Web without mobile focus, backend APIs, or admin dashboards — this skill is exclusively for native mobile experiences."
---

# React Native Mobile

Build mobile apps that feel indistinguishable from native. Spring-driven
animations, gesture-first interactions, haptic feedback on every state
change, and platform conventions that make iOS users feel at home on iOS
and Android users feel at home on Android.

The difference between a good React Native app and a premium one isn't the
framework — it's intentional design direction, consistent animation
personality, and platform-native materials. This skill prevents convergence
to the generic blue/gray/Inter template that plagues AI-generated mobile UI.

**Announce at start:** "I'm using the react-native-mobile skill to build
this mobile experience."

---

## Routing Directive

```text
UI/UX (animations, haptics, gestures, visual polish) → claude.
Code-heavy (data flow, networking, native modules, non-visual logic) → codex.
```

- If a step is mostly UI/UX (animation personality, haptic feel, gesture
  taste, visual layout, color, typography, native look-and-feel), implement
  it here with `owner: "claude-impl"`.
- If a step is mostly code-heavy (state wiring, networking, native module
  glue, storage, performance plumbing, tests), route it to the Codex-side
  `react-native-mobile` skill with `owner: "codex-impl"`.
- If a step mixes UI/UX and code-heavy work, split it into sequential steps
  with `dependsOn` instead of forcing one owner.

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Assessment + Design Direction) runs during Step 1 (Explore).
- **Phase 2** (Architecture) feeds into the masterPlan via `writing-plans`.
- **Phase 3** (Implementation) runs during Step 3 (Execute).
- **Phase 4** (Verification) runs after implementation.

If `brainstorming` ran first and produced design direction: use those
decisions and skip the Design Direction assessment in Phase 1.

---

## Integration with Other Skills

**After brainstorming:** If `brainstorming` produced a `design.md` with
visual direction (colors, typography, animation feel): skip the Design
Direction assessment. Use the approved choices directly. If the design
includes a **Creative Brief**, its Visual Direction maps to the App
Personality questions (animation feel, color temperature, visual
density), and its Copy Voice section guides all in-app text — from
onboarding copy to empty states to error messages.

**Full design treatment:** For apps that need serious aesthetic work
(consumer-facing, brand-driven), invoke `frontend-design` Phase 2 for
the full 6-axis Decision Matrix, creative seed, and concrete typography/color
choices. Then translate those outputs into mobile design tokens. This skill
handles the mobile implementation; `frontend-design` handles the aesthetic
decision-making.

**Web companion:** If the mobile app has a web counterpart, coordinate
design tokens with `frontend-design` so both platforms share the same
color system, typography scale, and animation philosophy.

**Design already decided:** If the user has a Figma file, design spec, or
brand guidelines: skip design direction entirely, proceed to Phase 2.

---

## Phase 1: Assessment — What Are We Building?

### Decision Tree

Answer these questions to determine scope and which references to read:

```
Does it need gesture-driven interactions?
├── YES → Read: references/gesture-cookbook.md
│   ├── Complex animations (shared elements, layout)? → Also read: references/animation-patterns.md
│   ├── Lists with swipe actions or drag-to-reorder? → Also read: references/performance-patterns.md
│   └── Platform-specific gesture conventions? → Also read: references/platform-patterns.md
│
└── NO (standard screens, forms, navigation)
    └── Read: references/component-recipes.md + references/platform-patterns.md
```

**Always read:** `references/architecture.md` for app structure, navigation,
state management, and storage — these apply to every React Native app.

### Complexity Tiers

| Tier | Description | Stack | Reference Files |
|------|-------------|-------|-----------------|
| **Polished Standard** | Clean screens, smooth navigation, proper platform conventions. No custom gestures. | Expo + Expo Router + Zustand + MMKV | architecture, platform-patterns, component-recipes |
| **Motion-Rich** | Spring animations, shared element transitions, animated lists, haptic feedback on interactions. | + Reanimated + Moti + expo-haptics | + animation-patterns, gesture-cookbook |
| **Full Premium** | Custom gesture-driven UI, drag-to-reorder, swipe choreography, physics-based interactions, offline-first. | + Gesture Handler + FlashList + TanStack Query + WatermelonDB | All reference files |

### Design Direction — App Personality

Most mobile apps converge on the same look: blue primary, gray surfaces,
Inter font, card-based layouts. Premium apps — Things 3, Spotify, Discord,
Shopify — feel distinct because their visual choices are intentional. Before
writing code, answer these four questions to define the app's personality:

**1. Animation Feel** — How should interactions feel?

| Personality | Reanimated Config | Feels Like |
|---|---|---|
| **Snappy** | `withSpring({ damping: 20, stiffness: 300 })` | Things 3, Apple apps — precise, responsive, no overshoot |
| **Bouncy** | `withSpring({ damping: 12, stiffness: 180 })` | Duolingo, playful apps — energetic, overshoots then settles |
| **Smooth** | `withSpring({ damping: 20, stiffness: 120 })` | Spotify, Calm — gentle, flowing, no overshoot |

Pick ONE personality and use it consistently across the app. Mixed animation
feels create incoherence — like a room with three different floor materials.

**2. Color Temperature** — Warm (organic, rounded, earthy tones) or cool
(geometric, precise, tech tones)? This guides the primary color away from
default blue. A fitness app might use warm coral; a finance app might use
cool teal; a creative tool might use warm amber. The color should feel
inevitable for this product, not arbitrary.

**3. Visual Density** — Spacious (generous padding, breathing room, fewer
items visible) or compact (dense information, tighter spacing, more
visible at once)? This maps directly to your spacing scale. Lifestyle apps
tend spacious; productivity apps tend compact.

**4. Typography Character** — Does the brand have a custom font? If not,
consider alternatives to Inter for the display/heading font:

| App Type | Consider | Character |
|---|---|---|
| Friendly / consumer | **Figtree**, **DM Sans** | Approachable, warm, rounded |
| Modern / geometric | **Satoshi**, **Outfit** | Clean, distinctive, contemporary |
| Professional / serious | **General Sans**, **Manrope** | Refined, trustworthy, neutral-warm |
| System-native feel | **SF Pro** (iOS) / **Roboto** (Android) | Platform-native, invisible, optimal |

Body text can stay with the system font — it has the best readability and
Dynamic Type support. The display/heading font is where brand personality
lives. Load custom fonts via `expo-font` or `@fontsource`.

**When to invoke `frontend-design`:** If you need the full aesthetic
treatment — 6-axis scoring, creative seed protocol, color palette
generation, complete typography pairing — invoke `frontend-design` Phase 2
and translate its outputs to mobile design tokens. The four questions above
are the quick path; `frontend-design` is the thorough path.

Document personality choices in `discovery.md` alongside complexity tier
and tech stack decisions.

---

## Phase 2: Architecture

### Quick-Start Structure (Every React Native App)

```
┌─────────────────────────────────────────┐
│  APP SHELL (Expo Router)                │  ← File-based routing, layouts
│  - _layout.tsx at each level            │
│  - Auth guard in root layout            │
│  - Tab navigator with platform styling  │
├─────────────────────────────────────────┤
│  SCREEN LAYER                           │  ← Feature-organized screens
│  - Each feature owns its screens        │
│  - Shared UI components in /components  │
│  - Platform-specific files: .ios / .android │
├─────────────────────────────────────────┤
│  DATA LAYER                             │  ← State + persistence
│  - Zustand for client state             │
│  - TanStack Query for server state      │
│  - MMKV for fast key-value storage      │
│  - Optimistic updates for offline       │
├─────────────────────────────────────────┤
│  NATIVE BRIDGE                          │  ← Platform APIs
│  - expo-haptics for tactile feedback    │
│  - Reanimated worklets on UI thread     │
│  - Gesture Handler for native gestures  │
│  - expo-* modules for device APIs       │
└─────────────────────────────────────────┘
```

### Technology Selection Guide

| Need | Use | Why |
|------|-----|-----|
| App framework | **Expo SDK 52+** | Managed workflow, EAS Build, OTA updates |
| Navigation | **Expo Router v4** | File-based routing, deep linking, type-safe |
| Animations | **Reanimated 4** | Worklets run on UI thread, 60fps guaranteed |
| Declarative animations | **Moti** | Reanimated wrapper, simpler API for common cases |
| Gestures | **Gesture Handler v2** | Native gesture recognition, composable |
| Lists | **FlashList** | Recycling, 5x faster than FlatList |
| Client state | **Zustand** | Minimal, no providers, works outside React |
| Server state | **TanStack Query v5** | Cache, background refresh, optimistic updates |
| Fast storage | **MMKV** | 30x faster than AsyncStorage, synchronous |
| Structured storage | **expo-sqlite** | SQL queries, migrations, larger datasets |
| Haptics | **expo-haptics** | Cross-platform haptic feedback |
| Icons | **expo-symbols** (iOS) + **Material Icons** | Platform-native icon sets |
| Forms | **React Hook Form + Zod** | Performant, type-safe validation |
| iOS 26 materials | **@callstack/liquid-glass** | Liquid Glass blur/refraction with Android fallback |
| Blur / vibrancy | **expo-blur** | Native blur on iOS, semi-transparent fallback on Android |
| Design tokens | **@shopify/restyle** *(optional)* | Type-enforced theming, Shopify-scale proven |

### iOS 26 Liquid Glass

Apple's Liquid Glass is the most significant visual shift since iOS 7 — a
translucent, refractive material that makes UI elements feel like physical
glass. Apps that adopt it look contemporary on iOS 26+.

**When to use:** Tab bars, navigation headers, floating action buttons,
cards that overlay scrollable content. Reserve for key UI chrome — not
every surface.

**Implementation:** `@callstack/liquid-glass` provides `LiquidGlassView`
and `LiquidGlassContainerView`. Use `isLiquidGlassSupported` to detect
capability and fall back to `expo-blur` BlurView or semi-transparent
backgrounds on older iOS / Android.

```tsx
import { LiquidGlassView, isLiquidGlassSupported } from '@callstack/liquid-glass';

<LiquidGlassView
  style={[
    styles.header,
    !isLiquidGlassSupported && { backgroundColor: theme.colors.surface },
  ]}
  effect="regular"
>
  {/* Navigation content */}
</LiquidGlassView>
```

**Performance:** GPU-accelerated but expensive if overused. Don't stack
multiple glass views or animate them aggressively. Test on older devices.

**Android:** Falls back to opaque/semi-transparent views. Don't fake the
effect — Android has its own Material You dynamic theming. Respect each
platform's design language.

---

## Phase 3: Implementation Rules

### 12 Critical Rules

1. **Springs over easing.** Use `withSpring()` for interactive animations,
   never `withTiming()` with easing curves for things the user touches.
   Springs have natural deceleration; easing curves feel artificial. Use
   the app's chosen spring personality (snappy/bouncy/smooth) consistently.

2. **FlashList always.** Never use `FlatList` or `ScrollView` for lists
   with more than ~20 items. FlashList recycles views, uses fraction of
   the memory, and maintains 60fps.

3. **MMKV always.** Never use `AsyncStorage` — it's async, slow, and
   JSON-serializes everything. MMKV is synchronous and 30x faster.

4. **Transform-only animations.** Animate `transform` (translateX/Y,
   scale, rotate) and `opacity` only. Never animate `width`, `height`,
   `top`, `left`, `margin`, `padding` — these trigger layout recalculation.

5. **Haptics on state changes.** Every meaningful state transition gets
   haptic feedback: toggle switches (`impactLight`), destructive actions
   (`notificationWarning`), success (`notificationSuccess`), button press
   (`impactMedium`), selection change (`selectionChanged`).

6. **Platform-specific conventions.** iOS gets SF Symbols, large titles,
   swipe-back navigation, sheets, Liquid Glass (iOS 26+). Android gets
   Material Icons, top app bar, predictive back gesture, bottom sheets,
   Material You theming. Use `.ios.tsx` / `.android.tsx` when conventions
   diverge significantly.

7. **Safe areas everywhere.** Use `useSafeAreaInsets()` from
   `react-native-safe-area-context`. Never hardcode status bar heights.
   Account for Dynamic Island, home indicator, and navigation bar.

8. **Dark mode from day one.** Use semantic color tokens that respond to
   `useColorScheme()`. Never hardcode colors. Define a theme object with
   `light` and `dark` variants. In dark mode: use near-black with a
   color tint (not pure `#000`), reduce shadow opacity, and adjust
   primary color saturation for dark backgrounds.

9. **Keyboard-aware forms.** Use `KeyboardAvoidingView` (with
   `behavior="padding"` on iOS, `behavior="height"` on Android) or
   `react-native-keyboard-aware-scroll-view`. Never let the keyboard
   obscure input fields.

10. **Accessible by default.** Every touchable has `accessibilityRole` and
    `accessibilityLabel`. Test with VoiceOver (iOS) and TalkBack (Android).
    Support Dynamic Type — never use fixed font sizes without scaling.

11. **Optimistic updates.** For any user-initiated mutation, update the UI
    immediately and sync in the background. Revert on failure with a toast.
    Users should never wait for a network round-trip to see their action.

12. **Preload before render.** Use `expo-splash-screen` to hold the splash
    until fonts, initial data, and auth state are loaded. No layout flash,
    no loading spinners on app open.

### Spring Personality Presets

Define the app's animation personality once and import everywhere. Don't
mix presets — consistency creates coherence.

```typescript
// src/lib/springs.ts
export const springs = {
  // Snappy: Things 3, Apple apps — precise, responsive
  snappy: { damping: 20, stiffness: 300 },
  // Bouncy: Duolingo, playful apps — energetic, overshoots
  bouncy: { damping: 12, stiffness: 180 },
  // Smooth: Spotify, Calm — gentle, flowing
  smooth: { damping: 20, stiffness: 120 },
} as const;

// Pick your app's personality
export const appSpring = springs.snappy;

// Interaction-specific variants
export const microSpring = { damping: 18, stiffness: 400 }; // Button press
export const sheetSpring = { damping: 25, stiffness: 200 }; // Bottom sheet
```

**Staggered reveals** for lists and screen entrances:
```typescript
withDelay(index * 80, withSpring(1, appSpring))
```

**Button press** — compression + spring recovery:
```typescript
withSequence(
  withTiming(0.95, { duration: 80 }),  // Quick compress
  withSpring(1, appSpring)              // Spring back
)
```

### Mobile Anti-Slop — What Generic Apps Look Like

Every design decision should be intentional. These patterns signal generic,
unconsidered output — the mobile equivalent of "purple gradient on white":

| Category | Generic Pattern | Intentional Alternative |
|---|---|---|
| Color | Blue-500 primary, gray-200 surfaces | Primary that reflects brand: coral for warmth, teal for trust, amber for energy |
| Color | Pure `#000` / `#fff` | Near-black with tint (`#0f0f14`) / warm white (`#fafaf8`) |
| Typography | Inter for everything | System font for body (readability + Dynamic Type); distinctive font for headings |
| Layout | Every screen is a FlatList with cards | Mix layouts: hero sections, inline actions, sectioned lists, full-bleed media |
| Animation | No animations, or `withTiming(300)` everywhere | Spring personality applied consistently; staggered reveals on key screens |
| Haptics | None | Haptic feedback on every meaningful state change |
| Tab bar | Default unstyled Expo tab bar | iOS: translucent blur background; Android: Material 3 indicator pill |
| Dark mode | Inverted colors or skipped | Semantic tokens, tinted near-black, adjusted primary saturation |
| Onboarding | Three static images with dots | Animated introduction that teaches gesture patterns |

### Anti-Patterns — What NOT to Do

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| `withTiming` for interactive elements | Feels robotic, no natural deceleration | `withSpring(target, appSpring)` |
| FlatList for long lists | No view recycling, memory grows linearly | FlashList with `estimatedItemSize` |
| AsyncStorage | Async, slow, JSON serialization overhead | MMKV for key-value, expo-sqlite for structured |
| Animating `width`/`height` | Triggers layout on every frame, drops to 30fps | Transform: `scale`, `translateX/Y` |
| Hardcoded status bar height | Breaks on notch, Dynamic Island, Android nav bar | `useSafeAreaInsets()` |
| `any` / `as any` in TypeScript | Hides bugs, no autocomplete, runtime crashes | Proper types, let inference work |
| `setTimeout` for animation sequencing | Unreliable timing, missed frames, no cancellation | `withSequence()`, `withDelay()`, or Moti transitions |
| Inline styles in animated components | Creates new style objects every render | `useAnimatedStyle()` with Reanimated |
| No haptic feedback | App feels lifeless, like a web wrapper | expo-haptics on every meaningful interaction |
| Fixed font sizes | Breaks for users with accessibility scaling | Use relative sizes, respect Dynamic Type |
| Synchronous heavy computation | Blocks JS thread, gestures freeze | Move to worklet or background thread |
| `useEffect` for data fetching | No cache, no background refresh, waterfall loads | TanStack Query with `useQuery` |
| Mixed spring configs across app | Incoherent motion, app feels scattered | Define `appSpring` once, import everywhere |

---

## Phase 4: Verification

### Mobile-Specific Checklist

- [ ] **60fps**: No frame drops during scrolling and animations (check Perf Monitor)
- [ ] **VoiceOver / TalkBack**: Full screen reader navigation works, all elements labeled
- [ ] **Dark mode**: All screens render correctly in both light and dark
- [ ] **Dynamic Type**: Text scales with system font size settings
- [ ] **Platform gestures**: Swipe-back (iOS), predictive back (Android) work correctly
- [ ] **Haptics**: Meaningful haptic feedback on state changes and interactions
- [ ] **Offline**: App handles no-network gracefully (cached data, error states)
- [ ] **Safe areas**: Content respects notch, Dynamic Island, home indicator
- [ ] **Keyboard**: Forms remain visible and usable with keyboard open
- [ ] **Splash screen**: No layout flash or loading spinner on app launch
- [ ] **Animation coherence**: All springs use the app's chosen personality consistently
- [ ] **Design intention**: No generic blue/gray/Inter defaults unless explicitly chosen

### Standard Checks (from engineering-discipline)

- [ ] Type checker passes (`tsc --noEmit` or `npx expo-doctor`)
- [ ] Linter passes
- [ ] No `any` / `as any` in TypeScript
- [ ] Tests pass (if test infrastructure exists)

---

## Reference Files

| File | Contents | When to Read |
|------|----------|--------------|
| `references/architecture.md` | App structure, Expo Router, state management, storage tiers, offline patterns | Every React Native project |
| `references/animation-patterns.md` | Reanimated 4, springs, shared elements, Moti, entering/exiting, layout animations | Any animation work |
| `references/gesture-cookbook.md` | 8 complete gesture implementations (pull-to-refresh, swipe, bottom sheet, etc.) | Building gesture-driven UI |
| `references/platform-patterns.md` | iOS vs Android conventions, safe areas, haptics, dark mode, typography | Platform-specific decisions |
| `references/performance-patterns.md` | FlashList, startup optimization, bundle analysis, images, MMKV, New Architecture | Performance optimization |
| `references/component-recipes.md` | 8 complete component implementations (skeleton, error boundary, toast, etc.) | Building common UI patterns |

### Routing to Other Skills

| Need | Skill |
|------|-------|
| Full design direction (6-axis matrix, creative seed, color system) | `frontend-design` Phase 2 — translate outputs to mobile tokens |
| Web companion with consistent design | `frontend-design` — share design tokens across platforms |
| Creative direction brainstorming | `brainstorming` |
| Implementation planning | `writing-plans` |
| Testing strategy | `test-driven-development` |
| Debugging issues | `systematic-debugging` |
| WebView-based immersive sections | `immersive-frontend` (rare — only for WebGL content in WebViews) |

---

## Output Contract

This skill produces:

1. **Design direction** in `discovery.md` — app personality (animation feel,
   color temperature, density, typography), tier selection, tech stack,
   platform strategy
2. **Working code** — TypeScript React Native components with Expo, Reanimated,
   Gesture Handler, proper platform conventions, consistent spring personality
3. **Verification results** in masterPlan step Results — fps confirmed,
   accessibility tested, dark mode verified, haptics working, animation
   coherence confirmed
