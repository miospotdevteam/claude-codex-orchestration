---
name: "react-native-mobile"
description: "Codex-facing React Native mobile implementation skill for code-heavy Expo and React Native work: data flow, networking, native modules, storage, list virtualization, performance, tests, and non-visual logic. Route UI/UX animation, haptic feel, gesture taste, and visual polish to Claude per the Routing Directive."
---

# React Native Mobile — Codex Implementation

Use this skill for code-heavy React Native and Expo implementation where the
primary work is wiring behavior, data, native modules, storage, performance,
or tests. This is the Codex-facing companion to the Claude
`react-native-mobile` skill.

## Routing Directive

```text
UI/UX (animations, haptics, gestures, visual polish) → claude.
Code-heavy (data flow, networking, native modules, non-visual logic) → codex.
```

- If a step is mostly UI/UX, do not implement it here. Route it to
  `owner: "claude"`, `mode: "claude-impl"`.
- If a step is mostly code-heavy, implement it with `owner: "codex"`,
  `mode: "codex-impl"`.
- If a step mixes UI/UX and code-heavy work, split it into sequential steps
  with `dependsOn` instead of forcing one owner.

## Scope

Codex-appropriate React Native work includes:

- State-machine wiring, reducers, stores, selectors, cache invalidation, and
  optimistic mutation rollback.
- Networking and server-state plumbing with request cancellation, retries,
  stale-response guards, authentication headers, and error normalization.
- Native module integration where the API contract is known: permissions,
  device APIs, Expo modules, push notifications, file system access, camera,
  location, secure storage, haptics calls, and platform capability checks.
- Storage and offline logic with MMKV, SQLite, migrations, hydration,
  conflict handling, and no-network fallbacks.
- List virtualization, pagination, memoization, startup loading, bundle
  hygiene, and other performance-sensitive plumbing.
- Tests, type safety, lint fixes, accessibility props required by existing
  components, and non-visual platform-specific branches.

Out of scope for this Codex skill:

- Choosing animation personality, haptic feel, gesture taste, native
  look-and-feel, visual layout, color, typography, or polish.
- Inventing a mobile design direction or changing the product's interaction
  model without an approved plan.

## Implementation Rules

1. Read the existing app structure first: navigation, feature folders, state
   stores, API clients, storage adapters, and platform-specific files.
2. Prefer the app's established stack and helpers. Do not introduce Expo,
   React Navigation, TanStack Query, Zustand, MMKV, SQLite, or native modules
   unless the project already uses them or the plan explicitly requires them.
3. Keep data ownership clear. Server state belongs in the existing query/cache
   layer; client-only UI state belongs in the local store or component state
   pattern already used by the app.
4. Guard async transitions: request failure, retry, cancellation,
   stale-response arrival, item switching while a request is in flight, and
   offline/no-network paths.
5. Preserve platform contracts. Use `.ios.tsx`, `.android.tsx`, `Platform`,
   permission APIs, and capability detection when behavior differs by OS.
6. Keep native-module glue isolated behind typed wrappers when the codebase has
   that pattern. Validate permissions and unsupported-platform fallbacks before
   calling native APIs.
7. Use virtualized lists for large data sets and keep item renderers stable.
   Avoid broad re-renders from unstable callbacks, inline derived data, or
   store subscriptions that select too much state.
8. Do not use `any` or `as any`. Type native-module responses, API payloads,
   persisted state, route params, and mutation inputs.
9. Do not swallow errors. Normalize them into the project's existing error
   surface, logging, toast, boundary, or retry pattern.
10. Keep UI changes minimal when the step is code-heavy. Do not make visual
    taste calls beyond what is necessary to expose the behavior.

## Data Flow Checklist

- Identify the source of truth for each field before writing mutations.
- Trace every write path from UI event to state update to persistence or API
  call.
- For optimistic updates, implement rollback and cache reconciliation.
- For forms, ensure displayed defaults are also in form state before save.
- For persisted stores, handle schema versioning, hydration ordering, and
  corrupted or missing values.
- For item switching, ensure late async results cannot overwrite the currently
  selected item.

## Networking Checklist

- Reuse the existing API client, auth injection, error shape, and retry policy.
- Represent loading, success, empty, offline, and failure states in the data
  layer so screens do not infer them from partial values.
- Cancel or ignore stale requests when route params, filters, or selected
  entities change.
- Keep pagination cursors, pull-to-refresh, and background refresh behavior
  consistent with nearby screens.
- Add tests around failures and stale transitions when the codebase has
  relevant test infrastructure.

## Native Module Checklist

- Confirm the dependency is installed before importing it.
- Add platform guards for unsupported APIs and simulator-only limitations.
- Request and re-check permissions through the project's permission pattern.
- Keep native calls behind small typed functions when multiple screens need
  the capability.
- Test both permission-granted and permission-denied paths where practical.

## Verification

Run the project's relevant checks after implementation:

- Type checker (`tsc --noEmit`, `npx tsc --noEmit`, `bun run typecheck`, or
  the project-specific equivalent).
- Linter, if configured.
- Unit or integration tests for touched stores, hooks, API clients, storage,
  native wrappers, and affected screens.
- Expo or React Native diagnostics when dependencies, native modules, or app
  config changed (`npx expo-doctor` when available and relevant).
- Manual or automated checks for offline, failure, stale-response, and
  permission-denied paths when those paths were touched.

Report any UI/UX work that should be split out to Claude instead of folding it
into the Codex implementation.
