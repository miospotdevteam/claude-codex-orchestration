# Performance Patterns

FlashList setup, startup optimization, bundle analysis, memory management,
image optimization, MMKV patterns, New Architecture, and performance budgets.

---

## 1. FlashList — The Default List Component

FlashList recycles views instead of creating new ones. It uses a fraction
of FlatList's memory and maintains 60fps on lists of any size.

### Basic Setup

```tsx
import { FlashList } from '@shopify/flash-list';

function Feed({ items }: { items: FeedItem[] }) {
  return (
    <FlashList
      data={items}
      estimatedItemSize={120}  // REQUIRED — measure your average item height
      renderItem={({ item }) => <FeedCard item={item} />}
      keyExtractor={(item) => item.id}
    />
  );
}
```

### Migration from FlatList

```tsx
// FlatList → FlashList migration checklist:
// 1. Replace import
//    FlatList → FlashList from '@shopify/flash-list'
//
// 2. Add estimatedItemSize (REQUIRED)
//    Measure your average item height. Wrong values = blank cells.
//    Use the FlashList performance warning in dev to calibrate.
//
// 3. Remove getItemLayout (FlashList doesn't use it)
//
// 4. Remove initialNumToRender, windowSize, maxToRenderPerBatch
//    FlashList manages these internally
//
// 5. Items must have a stable height or use overrideItemLayout
//    For variable-height items:
overrideItemLayout={(layout, item) => {
  layout.size = item.type === 'header' ? 200 : 80;
}}
```

### Multiple Item Types

```tsx
<FlashList
  data={items}
  estimatedItemSize={100}
  getItemType={(item) => item.type} // 'header' | 'post' | 'ad'
  renderItem={({ item }) => {
    switch (item.type) {
      case 'header': return <SectionHeader item={item} />;
      case 'post': return <PostCard item={item} />;
      case 'ad': return <AdBanner item={item} />;
    }
  }}
/>
```

### Optimized List Item

```tsx
import { memo } from 'react';

// ALWAYS memo list items — FlashList recycles, but React still diffs
const FeedCard = memo(function FeedCard({ item }: { item: FeedItem }) {
  return (
    <View style={styles.card}>
      <Text>{item.title}</Text>
    </View>
  );
});
```

---

## 2. Startup Optimization

### Hermes Engine

Hermes is the default JS engine for React Native. It precompiles JS to
bytecode during build time, reducing startup parse time by ~50%.

```json
// app.json — Hermes is enabled by default in Expo SDK 50+
{
  "expo": {
    "jsEngine": "hermes"
  }
}
```

### Splash Screen Hold

```tsx
// Prevent the splash screen from hiding until app is ready
import * as SplashScreen from 'expo-splash-screen';

SplashScreen.preventAutoHideAsync();

// In root layout:
useEffect(() => {
  if (fontsLoaded && authResolved && initialDataLoaded) {
    SplashScreen.hideAsync();
  }
}, [fontsLoaded, authResolved, initialDataLoaded]);
```

### Lazy Loading Screens

```tsx
// Expo Router lazy-loads screens by default.
// For heavy components within a screen, use React.lazy:

import { Suspense, lazy } from 'react';

const HeavyChart = lazy(() => import('@/components/HeavyChart'));

function AnalyticsScreen() {
  return (
    <View>
      <Text>Analytics</Text>
      <Suspense fallback={<Skeleton width={300} height={200} />}>
        <HeavyChart />
      </Suspense>
    </View>
  );
}
```

### Startup Checklist

1. **Splash screen** — hold until fonts + auth + initial data ready
2. **Hermes** — ensure it's enabled (default in Expo 50+)
3. **Font preload** — load fonts before hiding splash
4. **Auth state** — read from MMKV (synchronous, no async wait)
5. **Initial data** — prefetch critical screen data in root layout
6. **Lazy screens** — Expo Router handles this automatically
7. **No large imports at root** — heavy libs only imported where used

### Measuring Startup

```bash
# iOS — measure Time to Interactive
npx react-native-performance --platform ios

# Android — measure cold start
adb shell am start -W com.yourapp/.MainActivity

# Expo — use expo-dev-client with performance overlay
```

---

## 3. Bundle Analysis

### expo-atlas

```bash
# Generate bundle analysis
EXPO_ATLAS=1 npx expo export

# Opens interactive treemap visualization
# Shows package sizes, duplicate modules, heavy imports
```

### source-map-explorer

```bash
npx source-map-explorer dist/bundle.js dist/bundle.js.map
```

### Common Bundle Bloat Sources

| Package | Typical Size | Alternative |
|---------|-------------|-------------|
| `moment` | 280KB | `date-fns` (tree-shakeable, 5-20KB) |
| `lodash` | 70KB | `lodash-es` (tree-shakeable) or native methods |
| `aws-sdk` | 200KB+ | `@aws-sdk/client-*` (modular) |
| `firebase` | 150KB+ | `@react-native-firebase/*` (native modules) |
| Heavy icon sets | 100KB+ | Only import needed icons |

### Import Discipline

```tsx
// BAD — imports entire library
import { format } from 'date-fns';

// GOOD — imports only what you need (tree-shaking)
import format from 'date-fns/format';

// BAD — imports all icons
import * as Icons from '@expo/vector-icons';

// GOOD — import specific icon component
import { Ionicons } from '@expo/vector-icons';
```

---

## 4. Memory Management

### Common Memory Leaks

```tsx
// 1. Unsubscribed listeners
useEffect(() => {
  const sub = EventEmitter.addListener('event', handler);
  return () => sub.remove(); // ALWAYS clean up
}, []);

// 2. Uncancelled async operations
useEffect(() => {
  let cancelled = false;

  async function load() {
    const data = await fetchData();
    if (!cancelled) {
      setData(data);
    }
  }

  load();
  return () => { cancelled = true; };
}, []);

// 3. Uncancelled animations
useEffect(() => {
  return () => {
    cancelAnimation(translateX);
    cancelAnimation(opacity);
  };
}, []);

// 4. Growing arrays/caches
// Use LRU cache or WeakMap for caches, not plain objects
```

### Image Memory

```tsx
// Large images consume significant memory.
// A 4000x3000 image = 48MB uncompressed in memory.

// Rules:
// 1. Resize before loading — never load full-res into a thumbnail
// 2. Use expo-image (or react-native-fast-image) for caching
// 3. Set explicit width/height to avoid layout shifts
// 4. Use WebP format for 25-30% size reduction
```

### Monitoring

```tsx
// Enable React Native Performance Monitor (dev only)
// Shake device → "Show Perf Monitor"
// Shows: RAM usage, JS thread FPS, UI thread FPS

// For production monitoring, use expo-updates + Sentry
```

---

## 5. Image Optimization

### expo-image (Recommended)

```tsx
import { Image } from 'expo-image';

function Avatar({ uri }: { uri: string }) {
  return (
    <Image
      source={uri}
      style={styles.avatar}
      placeholder={blurhash}         // BlurHash for instant placeholder
      contentFit="cover"
      transition={200}               // Fade-in duration
      cachePolicy="memory-disk"      // Cache in memory AND disk
      recyclingKey={uri}             // Stable key for FlashList recycling
    />
  );
}
```

### BlurHash Placeholders

```tsx
// BlurHash encodes an image into a tiny string (20-30 chars)
// that decodes into a beautiful blurred placeholder.

// Generate blurhash server-side, store with image metadata.
// Display immediately while full image loads.

<Image
  source={item.imageUrl}
  placeholder={{ blurhash: item.blurhash }}
  transition={300}
/>
```

### Image Size Guidelines

| Context | Max Width | Format | Quality |
|---------|----------|--------|---------|
| Thumbnail (avatar, icon) | 100px | WebP | 80% |
| List item image | 400px | WebP | 85% |
| Card image | 800px | WebP | 85% |
| Full-screen hero | 1200px | WebP | 90% |
| Background | Device width × DPR (capped at 2) | WebP | 85% |

### Preloading Critical Images

```tsx
import { Image } from 'expo-image';

// Preload images before navigating to a screen
async function preloadImages(urls: string[]) {
  await Promise.all(urls.map((url) => Image.prefetch(url)));
}

// In navigation handler:
const handleNavigate = async () => {
  await preloadImages([item.heroImage, item.authorAvatar]);
  router.push(`/detail/${item.id}`);
};
```

---

## 6. MMKV Performance Patterns

### Batch Reads on Startup

```tsx
// MMKV reads are synchronous and fast (~0.01ms each).
// Reading 100 keys at startup is fine.

// Initialize stores synchronously in module scope:
const preferences = {
  theme: storage.getString('pref.theme') ?? 'system',
  haptics: storage.getBoolean('pref.haptics') ?? true,
  notifications: storage.getBoolean('pref.notifications') ?? true,
};
```

### MMKV vs State: When to Skip State

```tsx
// For preferences that rarely change, read directly from MMKV
// instead of putting them in React state. This avoids re-renders.

function usePreference(key: string) {
  // Only re-renders when the value actually changes
  const listener = storage.addOnValueChangedListener((changedKey) => {
    if (changedKey === key) {
      // Force re-render
    }
  });

  return storage.getString(key);
}
```

### Encrypted Storage

```tsx
// For sensitive data (tokens, PII), use encrypted MMKV
import { MMKV } from 'react-native-mmkv';

const secureStorage = new MMKV({
  id: 'secure-storage',
  encryptionKey: 'your-encryption-key', // Derive from Keychain/Keystore
});
```

---

## 7. New Architecture (JSI, TurboModules, Fabric)

### What It Is

The New Architecture replaces the old Bridge with direct JavaScript
Interface (JSI) calls, enabling synchronous native module access and
concurrent rendering.

| Component | Old Architecture | New Architecture |
|-----------|-----------------|-----------------|
| **JS ↔ Native** | Bridge (async, JSON serialization) | JSI (synchronous, direct calls) |
| **Native Modules** | Bridge Modules | TurboModules (lazy-loaded) |
| **Rendering** | Old Renderer | Fabric (concurrent, synchronous layout) |
| **Event Handling** | Async bridge events | Synchronous JSI events |

### Enabling in Expo

```json
// app.json
{
  "expo": {
    "newArchEnabled": true
  }
}
```

### Benefits for Performance

1. **Synchronous native calls** — no async bridge overhead for MMKV,
   Reanimated worklets, Gesture Handler
2. **Concurrent rendering** — Fabric supports React 18 concurrent features
3. **Lazy module loading** — TurboModules load on first use, not at startup
4. **Shared C++ layer** — enables Reanimated worklets to call native code
   directly from the UI thread

### Compatibility

Most major libraries support New Architecture:
- Reanimated ✅
- Gesture Handler ✅
- FlashList ✅
- MMKV ✅
- expo-image ✅

Check library compatibility at reactnative.directory before adopting.

---

## 8. Performance Budget

### Frame Budget

At 60fps: **16.67ms** per frame.
- JS thread: ≤12ms (leaves 4ms for native rendering)
- UI thread: ≤16ms (animations, gestures)

At 120fps (ProMotion): **8.33ms** per frame.
- JS thread: ≤6ms
- UI thread: ≤8ms

### App Size Budget

| Category | Target | Max |
|----------|--------|-----|
| App binary (iOS) | < 30MB | 50MB |
| App binary (Android) | < 25MB | 40MB |
| JS bundle | < 2MB | 4MB |
| Assets (images, fonts) | < 10MB | 20MB |
| Total download | < 40MB | 60MB |

### Runtime Budgets

| Metric | Target | Unacceptable |
|--------|--------|-------------|
| Cold start (splash → interactive) | < 1.5s | > 3s |
| Screen transition | < 300ms | > 500ms |
| List scroll FPS | 60fps | < 45fps |
| Gesture response latency | < 16ms | > 50ms |
| Memory (typical usage) | < 200MB | > 400MB |
| API response + render | < 1s | > 3s |
| Animation FPS | 60fps | < 50fps |
| Image load (cached) | < 50ms | > 200ms |
| Image load (network) | < 2s | > 5s |
| MMKV read | < 1ms | > 5ms |

### Monitoring in Development

```tsx
// Enable Performance Monitor
// 1. Shake device → "Show Perf Monitor"
// 2. Watch: JS FPS, UI FPS, RAM

// FlashList blank area warning (dev only)
// If you see "%.2f% blank area" in console:
// → Your estimatedItemSize is wrong
// → Your render items are too slow
// → You need to memo your list items

// React DevTools Profiler
// 1. Open React DevTools
// 2. Profiler tab → Record
// 3. Interact with the app
// 4. Stop recording → analyze flame graph
// Look for: unnecessary re-renders, slow renders (>16ms)
```

### Performance Optimization Priority

When performance is bad, optimize in this order:

1. **Lists** — FlashList, memo items, estimatedItemSize
2. **Re-renders** — memo, useMemo, useCallback, Zustand selectors
3. **Images** — expo-image, proper sizing, caching, WebP
4. **Animations** — Reanimated (UI thread), transform-only
5. **Bundle** — tree shaking, lazy imports, code splitting
6. **Startup** — splash hold, lazy screens, Hermes
7. **Memory** — cleanup subscriptions, cancel animations, image sizing
