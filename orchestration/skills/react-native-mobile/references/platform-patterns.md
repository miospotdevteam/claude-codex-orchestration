# Platform Patterns

iOS vs Android conventions, safe areas and device cutouts, haptic feedback
patterns, tab bar design, dark mode implementation, typography and font
scaling, touch targets, and thumb zone ergonomics.

---

## 1. iOS vs Android Convention Comparison

| Aspect | iOS (HIG) | Android (Material 3) |
|--------|-----------|----------------------|
| **Back navigation** | Swipe from left edge | System back button / predictive back gesture |
| **Navigation bar** | Large title that collapses on scroll | Top app bar (small, medium, or large) |
| **Tab bar position** | Bottom (always) | Bottom (Material 3) or top tabs |
| **Tab bar style** | Translucent blur, thin border | Elevated or tonal surface |
| **Action placement** | Top-right (navigation bar) | FAB or bottom app bar |
| **Destructive actions** | Red text, action sheets from bottom | Dialog from center |
| **Confirmation** | Action sheets (bottom slide-up) | Dialogs (center modal) |
| **Search** | Search bar in navigation bar, pull-down to reveal | Search bar in top app bar |
| **Toggle** | UISwitch (rounded, green/gray) | Material Switch (pill shape, theme color) |
| **Date picker** | Inline wheels or compact popup | Calendar dialog |
| **Segmented control** | Native segmented control | Segmented button (Material 3) |
| **List separators** | Inset dividers (indented from leading edge) | Full-width dividers or none |
| **Swipe actions** | Swipe left for actions (delete, archive) | Swipe for single action only |
| **Pull to refresh** | Native spinner (top) | CircularProgressIndicator (top) |
| **Haptics** | Rich haptic engine (Taptic Engine) | Limited (varies by device) |
| **System font** | SF Pro (automatically used) | Roboto (automatically used) |
| **Icons** | SF Symbols | Material Symbols |
| **Status bar** | Light/dark content | Light/dark, can be colored |
| **Keyboard** | Return key types, input accessory view | IME options, no accessory view |

### Platform-Specific Components

```tsx
// Use .ios.tsx and .android.tsx for significant differences
// components/ActionSheet.ios.tsx
// components/ActionSheet.android.tsx

// For minor differences, use Platform.select
import { Platform } from 'react-native';

const styles = StyleSheet.create({
  container: {
    ...Platform.select({
      ios: {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.1,
        shadowRadius: 8,
      },
      android: {
        elevation: 4,
      },
    }),
  },
});
```

---

## 2. Safe Areas and Device Cutouts

### The Problem

Modern devices have irregular display shapes: notches (iPhone 12-14),
Dynamic Island (iPhone 14 Pro+), camera punch-holes (Android), rounded
corners, home indicators (iPhone X+), and navigation bars (Android).

### The Solution: react-native-safe-area-context

```tsx
// Wrap entire app in SafeAreaProvider (in root layout)
import { SafeAreaProvider } from 'react-native-safe-area-context';

// In app/_layout.tsx
<SafeAreaProvider>
  <App />
</SafeAreaProvider>
```

```tsx
// Option 1: Hook (most flexible)
import { useSafeAreaInsets } from 'react-native-safe-area-context';

function MyScreen() {
  const insets = useSafeAreaInsets();

  return (
    <View style={{
      paddingTop: insets.top,
      paddingBottom: insets.bottom,
      paddingLeft: insets.left,
      paddingRight: insets.right,
    }}>
      {/* content */}
    </View>
  );
}
```

```tsx
// Option 2: SafeAreaView (simpler but less flexible)
import { SafeAreaView } from 'react-native-safe-area-context';

function MyScreen() {
  return (
    <SafeAreaView style={{ flex: 1 }} edges={['top', 'bottom']}>
      {/* content */}
    </SafeAreaView>
  );
}
```

### When to Apply Safe Areas

| Screen Element | Apply Safe Area? | Which Edges? |
|---------------|-----------------|--------------|
| Full-screen content | Yes | All 4 |
| Tab screens | Top only (tab bar handles bottom) | `['top']` |
| Modal sheets | Bottom only (handle/header at top) | `['bottom']` |
| Scrollable content | Top + bottom (via contentInset or padding) | `['top', 'bottom']` |
| Fixed header | Top only | `['top']` |
| Fixed bottom bar | Bottom only | `['bottom']` |
| Landscape mode | Left + right (notch can be on side) | `['left', 'right']` |

### Dynamic Island Awareness

```tsx
// The Dynamic Island is handled by safe area insets automatically.
// The top inset is larger on Dynamic Island devices (~59pt vs ~47pt).
// Do NOT try to detect Dynamic Island specifically — use insets.
```

---

## 3. Haptic Feedback Patterns

### When to Use Each Type

| Interaction | Haptic Type | iOS API | Expo API |
|------------|-------------|---------|----------|
| Button press | Impact (medium) | `.medium` | `impactAsync(Medium)` |
| Toggle on/off | Impact (light) | `.light` | `impactAsync(Light)` |
| Selection change (picker, tab) | Selection | `.selectionChanged` | `selectionAsync()` |
| Drag snap to position | Impact (medium) | `.medium` | `impactAsync(Medium)` |
| Drop item into place | Impact (heavy) | `.heavy` | `impactAsync(Heavy)` |
| Destructive action confirm | Notification (warning) | `.warning` | `notificationAsync(Warning)` |
| Action succeeded | Notification (success) | `.success` | `notificationAsync(Success)` |
| Action failed | Notification (error) | `.error` | `notificationAsync(Error)` |
| Pull-to-refresh threshold | Impact (medium) | `.medium` | `impactAsync(Medium)` |
| Long press activate | Impact (heavy) | `.heavy` | `impactAsync(Heavy)` |
| Slider tick | Selection | `.selectionChanged` | `selectionAsync()` |
| Swipe past threshold | Impact (light) | `.light` | `impactAsync(Light)` |

### Implementation Rules

1. **One haptic per gesture phase** — don't fire multiple haptics for one
   user action. One tap = one haptic, not three.

2. **Threshold haptics** — when a gesture crosses a meaningful threshold
   (e.g., pull-to-refresh trigger point, swipe-to-delete threshold), fire
   exactly one haptic at the crossing point.

3. **No haptics on scroll** — scrolling is continuous, haptics would be
   noise. Exception: scroll picker (one selection haptic per detent).

4. **No haptics on typing** — keyboard has its own haptics.

5. **Test on device** — haptics don't work in simulator. Always test on
   a real device.

### Haptic Wrapper Pattern

```tsx
// src/lib/haptics.ts — see architecture.md for full implementation
// Use the wrapper everywhere instead of calling expo-haptics directly.
// This centralizes haptic logic and makes it easy to add a user
// preference toggle (Settings > Haptics > On/Off).

import { haptics } from '@/lib/haptics';

// In components:
<Pressable onPress={() => {
  haptics.medium();
  handlePress();
}}>
```

---

## 4. Tab Bar Design

### iOS Tab Bar

```tsx
// iOS conventions:
// - Always at bottom
// - Translucent blur background
// - 5 tabs maximum (more → "More" tab)
// - Icon + label always visible
// - Active: filled icon + tint color
// - Inactive: outline icon + gray
// - Badge: red circle, top-right of icon

import { BlurView } from 'expo-blur';

// Custom iOS-style translucent tab bar
<Tabs
  screenOptions={{
    tabBarStyle: {
      position: 'absolute',
      backgroundColor: 'transparent',
      borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: 'rgba(0,0,0,0.1)',
    },
    tabBarBackground: () => (
      <BlurView
        intensity={100}
        tint={isDark ? 'dark' : 'light'}
        style={StyleSheet.absoluteFill}
      />
    ),
  }}
/>
```

### Android Bottom Navigation (Material 3)

```tsx
// Material 3 conventions:
// - 3-5 destinations
// - Active: filled icon + label + indicator pill
// - Inactive: outlined icon + label (optional)
// - No translucent blur — solid surface color
// - Elevation shadow

<Tabs
  screenOptions={{
    tabBarStyle: {
      backgroundColor: theme.colors.surface,
      elevation: 8,
      borderTopWidth: 0,
      height: 80,
      paddingBottom: 16,
    },
    tabBarActiveTintColor: theme.colors.primary,
    tabBarInactiveTintColor: theme.colors.textTertiary,
    tabBarActiveBackgroundColor: `${theme.colors.primary}14`, // 8% opacity pill
  }}
/>
```

### Tab Bar Rules

- Maximum 5 tabs (4 is ideal)
- Every tab has an icon AND a label — icon-only tabs are ambiguous
- The first tab is "Home" or the primary destination
- Tab presses at the current tab scroll to top
- Tab long-press shows tooltip with full label (accessibility)

---

## 5. Dark Mode

### Semantic Color Tokens

Never hardcode colors. Always use semantic tokens that adapt to the color
scheme.

```tsx
// See architecture.md for the complete theme system.
// Key principle: define colors by their role, not their value.

const colors = {
  // Backgrounds
  background: '#FFFFFF',    // → '#000000' in dark
  surface: '#F9FAFB',      // → '#030712' in dark
  surfaceElevated: '#FFF', // → '#111827' in dark

  // Text
  text: '#111827',         // → '#FFFFFF' in dark
  textSecondary: '#6B7280',// → '#9CA3AF' in dark
  textTertiary: '#9CA3AF', // → '#6B7280' in dark

  // Borders
  border: '#E5E7EB',       // → '#1F2937' in dark

  // Semantic
  primary: '#2563EB',      // → '#3B82F6' in dark (slightly lighter)
  error: '#EF4444',        // Same in both
  success: '#22C55E',      // Same in both
};
```

### System Dark Mode Integration

```tsx
import { useColorScheme, Appearance } from 'react-native';

// Reactive hook (re-renders on change)
const scheme = useColorScheme(); // 'light' | 'dark' | null

// Subscribe to changes
Appearance.addChangeListener(({ colorScheme }) => {
  // Update theme
});
```

### Dark Mode Checklist

- [ ] All colors use semantic tokens (no hardcoded hex in components)
- [ ] Images have dark variants OR use `tintColor` for icons
- [ ] Shadows are adjusted (lighter shadows in dark mode are invisible)
- [ ] Status bar style matches (`light-content` on dark, `dark-content` on light)
- [ ] Maps, WebViews, and third-party views have dark mode configured
- [ ] Splash screen has both light and dark variants

### Images in Dark Mode

```tsx
import { useColorScheme, Image } from 'react-native';

function Logo() {
  const scheme = useColorScheme();
  const source = scheme === 'dark'
    ? require('@/assets/logo-light.png')   // Light logo on dark bg
    : require('@/assets/logo-dark.png');    // Dark logo on light bg

  return <Image source={source} />;
}

// For simple icons, use tintColor instead of separate assets
<Image
  source={require('@/assets/icon.png')}
  style={{ tintColor: theme.colors.text }}
/>
```

---

## 6. Typography and Font Scaling

### iOS Type Scale (SF Pro)

| Style | Size | Weight | Line Height | Use For |
|-------|------|--------|-------------|---------|
| Large Title | 34pt | Bold | 41pt | Top-level screen titles |
| Title 1 | 28pt | Bold | 34pt | Section headers |
| Title 2 | 22pt | Bold | 28pt | Sub-section headers |
| Title 3 | 20pt | Semibold | 25pt | Group headers |
| Headline | 17pt | Semibold | 22pt | Emphasized body text |
| Body | 17pt | Regular | 22pt | Primary content |
| Callout | 16pt | Regular | 21pt | Secondary content |
| Subhead | 15pt | Regular | 20pt | Tertiary content |
| Footnote | 13pt | Regular | 18pt | Metadata, timestamps |
| Caption 1 | 12pt | Regular | 16pt | Labels, annotations |
| Caption 2 | 11pt | Medium | 13pt | Small labels |

### Dynamic Type Support

```tsx
// React Native automatically supports Dynamic Type on iOS.
// Text components scale with the system font size setting.

// To OPT OUT of scaling for specific text (use sparingly):
<Text allowFontScaling={false}>Fixed size</Text>

// To set a maximum scale factor (recommended over disabling):
<Text maxFontSizeMultiplier={1.5}>Capped scaling</Text>

// Common pattern: cap scaling on UI elements, allow full scaling on content
const styles = StyleSheet.create({
  buttonLabel: {
    fontSize: 16,
    // Cap at 1.2x to prevent button overflow
  },
  bodyText: {
    fontSize: 17,
    // Allow full scaling for readability
  },
});
```

### Custom Fonts

```tsx
// Load custom fonts in root layout (see architecture.md)
// Use Inter (or your custom font) consistently

// Font weight mapping
const fontFamily = {
  regular: 'Inter-Regular',    // 400
  medium: 'Inter-Medium',      // 500
  semibold: 'Inter-SemiBold',  // 600
  bold: 'Inter-Bold',          // 700
};

// NEVER use fontWeight with custom fonts on Android — it doesn't work.
// Instead, use the specific font file for each weight.

// BAD (Android ignores fontWeight with custom fonts)
{ fontFamily: 'Inter', fontWeight: 'bold' }

// GOOD
{ fontFamily: 'Inter-Bold' }
```

### Android Typography (Roboto)

Android uses Roboto by default. Material 3 type scale:

| Style | Size | Weight | Use For |
|-------|------|--------|---------|
| Display Large | 57sp | Regular | Hero text |
| Display Medium | 45sp | Regular | Large headers |
| Display Small | 36sp | Regular | Section headers |
| Headline Large | 32sp | Regular | Page titles |
| Headline Medium | 28sp | Regular | Section titles |
| Title Large | 22sp | Regular | Top app bar |
| Title Medium | 16sp | Medium | Cards, dialogs |
| Body Large | 16sp | Regular | Primary content |
| Body Medium | 14sp | Regular | Secondary content |
| Label Large | 14sp | Medium | Buttons, tabs |
| Label Medium | 12sp | Medium | Small labels |

---

## 7. Touch Targets and Thumb Zone

### Minimum Touch Targets

| Platform | Minimum Size | Recommended |
|----------|-------------|-------------|
| iOS (HIG) | 44x44pt | 48x48pt |
| Android (Material 3) | 48x48dp | 48x48dp |
| React Native | 44x44pt | 48x48pt |

```tsx
// Enforce minimum touch target even when visual element is smaller
<Pressable
  hitSlop={12} // Extends touch area 12pt in each direction
  style={styles.iconButton}
>
  <Icon size={20} /> {/* Visual is 20pt, touch target is 44pt */}
</Pressable>
```

### Thumb Zone

```
┌─────────────────────────┐
│     Hard to reach       │  ← Top 1/3: navigation, less-used actions
│                         │
├─────────────────────────┤
│                         │
│    Natural reach        │  ← Middle: scrollable content
│                         │
├─────────────────────────┤
│                         │
│    Easy reach           │  ← Bottom 1/3: primary actions, tab bar
│    (thumb zone)         │
│                         │
│  ┌─── FAB ───┐          │  ← FAB: bottom-right for right-handed
└──┴───────────┴──────────┘
     Home indicator
```

### Design Rules

1. **Primary actions at the bottom** — buttons, FABs, tab bar. The thumb
   naturally rests here.

2. **Secondary actions at the top** — search, settings, filters. Require
   intentional reach.

3. **Destructive actions require reach** — place cancel/delete where
   accidental taps are unlikely (top or behind confirmation).

4. **Spacing between targets** — minimum 8pt between touchable elements
   to prevent mis-taps.

5. **Swipe gestures are thumb-friendly** — horizontal swipes from edges
   are natural thumb movements. Use for navigation and actions.

6. **Bottom sheets over alerts** — bottom sheets are in the thumb zone;
   centered alerts require reaching to the middle of the screen.

### Pressable Feedback

```tsx
import { Pressable, StyleSheet } from 'react-native';

// iOS-style opacity feedback
<Pressable
  style={({ pressed }) => [
    styles.button,
    pressed && { opacity: 0.7 },
  ]}
>

// Android-style ripple
<Pressable
  android_ripple={{ color: 'rgba(0,0,0,0.1)', borderless: false }}
  style={styles.button}
>

// Combined (platform-appropriate)
<Pressable
  style={({ pressed }) => [
    styles.button,
    Platform.OS === 'ios' && pressed && { opacity: 0.7 },
  ]}
  android_ripple={{
    color: `${theme.colors.primary}20`,
    borderless: false,
  }}
>
```
