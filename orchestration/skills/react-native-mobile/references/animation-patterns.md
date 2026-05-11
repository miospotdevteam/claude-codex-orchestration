# Animation Patterns

Reanimated 4 (CSS API + worklets + shared values), spring physics, Moti
declarative API, shared element transitions, entering/exiting animations,
layout animations, Gesture Handler integration, and best practices.

---

## 1. Reanimated 4 CSS Animations API

Reanimated 4 introduces a CSS-like API for common animations. Use this
for simple state-driven transitions. Fall back to worklets for
gesture-driven or physics-based animations.

### CSS Transitions (State-Driven)

```tsx
import Animated, {
  CSSTransition,
  useAnimatedStyle,
} from 'react-native-reanimated';

function ExpandableCard({ isExpanded }: { isExpanded: boolean }) {
  const animatedStyle = useAnimatedStyle(() => ({
    height: isExpanded ? 200 : 80,
    opacity: isExpanded ? 1 : 0.8,
    transform: [{ scale: isExpanded ? 1 : 0.98 }],
    transition: {
      height: { duration: 300, timingFunction: 'ease-in-out' },
      opacity: { duration: 200 },
      transform: { duration: 300, timingFunction: 'ease-out' },
    },
  }));

  return <Animated.View style={animatedStyle} />;
}
```

### CSS Keyframes

```tsx
import Animated, { Keyframe } from 'react-native-reanimated';

const bounceIn = new Keyframe({
  0: { opacity: 0, transform: [{ scale: 0.3 }] },
  50: { opacity: 1, transform: [{ scale: 1.05 }] },
  70: { transform: [{ scale: 0.9 }] },
  100: { opacity: 1, transform: [{ scale: 1 }] },
});

function BounceInView({ children }: { children: React.ReactNode }) {
  return (
    <Animated.View entering={bounceIn.duration(600)}>
      {children}
    </Animated.View>
  );
}
```

---

## 2. Worklets and Shared Values

Worklets run on the UI thread — they bypass the JS thread entirely. Use
them for gesture-driven animations and anything that needs to update
every frame without bridge overhead.

### Shared Values — The Animation Primitives

```tsx
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

function ScaleButton({ onPress }: { onPress: () => void }) {
  const scale = useSharedValue(1);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  const handlePressIn = () => {
    scale.value = withSpring(0.95, { damping: 15, stiffness: 400 });
  };

  const handlePressOut = () => {
    scale.value = withSpring(1, { damping: 15, stiffness: 400 });
  };

  return (
    <Animated.View style={animatedStyle}>
      <Pressable
        onPressIn={handlePressIn}
        onPressOut={handlePressOut}
        onPress={onPress}
      >
        {/* button content */}
      </Pressable>
    </Animated.View>
  );
}
```

### Derived Values

```tsx
import { useDerivedValue, interpolate } from 'react-native-reanimated';

function ProgressIndicator({ progress }: { progress: Animated.SharedValue<number> }) {
  const width = useDerivedValue(() =>
    interpolate(progress.value, [0, 1], [0, 300])
  );

  const backgroundColor = useDerivedValue(() =>
    interpolateColor(progress.value, [0, 0.5, 1], ['#EF4444', '#F59E0B', '#22C55E'])
  );

  const animatedStyle = useAnimatedStyle(() => ({
    width: width.value,
    backgroundColor: backgroundColor.value,
  }));

  return <Animated.View style={[styles.bar, animatedStyle]} />;
}
```

### Worklet Callbacks

```tsx
import { runOnJS, runOnUI } from 'react-native-reanimated';

// Call JS from UI thread (e.g., update React state after animation)
const onAnimationEnd = () => {
  // This runs on JS thread
  setIsVisible(false);
};

const animatedStyle = useAnimatedStyle(() => {
  if (opacity.value === 0) {
    runOnJS(onAnimationEnd)();
  }
  return { opacity: opacity.value };
});

// Call UI thread from JS (e.g., start animation from event handler)
const startAnimation = () => {
  runOnUI(() => {
    'worklet';
    translateX.value = withSpring(100);
  })();
};
```

---

## 3. Spring Physics

Springs feel natural because they model real physical motion. Every
interactive animation should use springs, not timing curves.

### Spring Configuration Presets

```tsx
const SPRING_CONFIGS = {
  // Snappy response — buttons, toggles, small elements
  snappy: { damping: 15, stiffness: 400 },

  // Gentle — cards, modals, larger elements
  gentle: { damping: 20, stiffness: 150 },

  // Bouncy — playful interactions, celebrations
  bouncy: { damping: 8, stiffness: 200 },

  // Stiff — drag release, snap to position
  stiff: { damping: 20, stiffness: 400 },

  // Slow — page transitions, large movements
  slow: { damping: 25, stiffness: 80 },
} as const;
```

### How Spring Parameters Work

```
mass      — Weight of the object. Higher = slower, more momentum.
            Default: 1. Range: 0.5-3 for most UI.

stiffness — How "tight" the spring. Higher = faster snap.
            Default: 100. Range: 50-500 for most UI.

damping   — How quickly it settles. Higher = less bounce.
            Default: 10. Range: 5-30 for most UI.
            At critical damping (2 × √(stiffness × mass)), no overshoot.

velocity  — Initial speed. Pass gesture velocity for natural handoff.
```

### Velocity Handoff from Gestures

```tsx
import { Gesture, GestureDetector } from 'react-native-gesture-handler';

function DraggableCard() {
  const translateX = useSharedValue(0);

  const gesture = Gesture.Pan()
    .onUpdate((e) => {
      translateX.value = e.translationX;
    })
    .onEnd((e) => {
      // Pass gesture velocity to spring for natural feel
      translateX.value = withSpring(0, {
        velocity: e.velocityX,
        damping: 20,
        stiffness: 200,
      });
    });

  const style = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
  }));

  return (
    <GestureDetector gesture={gesture}>
      <Animated.View style={style} />
    </GestureDetector>
  );
}
```

---

## 4. Moti Declarative API

Moti wraps Reanimated with a simpler, Framer Motion-inspired API. Use it
for state-driven animations where you don't need gesture interaction.

### Basic Usage

```tsx
import { MotiView, MotiText } from 'moti';

function FadeInCard({ isVisible }: { isVisible: boolean }) {
  return (
    <MotiView
      from={{ opacity: 0, translateY: 20 }}
      animate={{ opacity: isVisible ? 1 : 0, translateY: isVisible ? 0 : 20 }}
      transition={{ type: 'spring', damping: 15, stiffness: 150 }}
    >
      <MotiText
        from={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        delay={200}
      >
        Card content
      </MotiText>
    </MotiView>
  );
}
```

### AnimatePresence (Enter/Exit)

```tsx
import { AnimatePresence, MotiView } from 'moti';

function Toast({ message, isVisible }: { message: string; isVisible: boolean }) {
  return (
    <AnimatePresence>
      {isVisible && (
        <MotiView
          key="toast"
          from={{ opacity: 0, translateY: -50, scale: 0.9 }}
          animate={{ opacity: 1, translateY: 0, scale: 1 }}
          exit={{ opacity: 0, translateY: -50, scale: 0.9 }}
          transition={{ type: 'spring', damping: 15 }}
        >
          <Text>{message}</Text>
        </MotiView>
      )}
    </AnimatePresence>
  );
}
```

### Staggered List

```tsx
import { MotiView } from 'moti';

function StaggeredList({ items }: { items: Item[] }) {
  return (
    <>
      {items.map((item, index) => (
        <MotiView
          key={item.id}
          from={{ opacity: 0, translateX: -20 }}
          animate={{ opacity: 1, translateX: 0 }}
          transition={{
            type: 'spring',
            damping: 15,
            delay: index * 50, // 50ms stagger between items
          }}
        >
          <ItemCard item={item} />
        </MotiView>
      ))}
    </>
  );
}
```

### Skeleton with Moti

```tsx
import { MotiView } from 'moti';

function Skeleton({ width, height }: { width: number; height: number }) {
  return (
    <MotiView
      from={{ opacity: 0.3 }}
      animate={{ opacity: 0.7 }}
      transition={{
        type: 'timing',
        duration: 1000,
        loop: true,
        repeatReverse: true,
      }}
      style={{
        width,
        height,
        borderRadius: 8,
        backgroundColor: '#E5E7EB',
      }}
    />
  );
}
```

---

## 5. Shared Element Transitions

Use for seamless transitions between screens — e.g., tapping a list item
to open a detail view where the image "morphs" into position.

### With Expo Router + Reanimated

```tsx
// List screen
import Animated, { SharedTransition } from 'react-native-reanimated';
import { Link } from 'expo-router';

function ListItem({ item }: { item: Item }) {
  return (
    <Link href={`/detail/${item.id}`} asChild>
      <Pressable>
        <Animated.Image
          sharedTransitionTag={`image-${item.id}`}
          source={{ uri: item.imageUrl }}
          style={styles.thumbnail}
        />
        <Animated.Text
          sharedTransitionTag={`title-${item.id}`}
          style={styles.title}
        >
          {item.title}
        </Animated.Text>
      </Pressable>
    </Link>
  );
}

// Detail screen
function DetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const item = useItem(id);

  return (
    <ScrollView>
      <Animated.Image
        sharedTransitionTag={`image-${id}`}
        source={{ uri: item.imageUrl }}
        style={styles.heroImage}
      />
      <Animated.Text
        sharedTransitionTag={`title-${id}`}
        style={styles.heroTitle}
      >
        {item.title}
      </Animated.Text>
    </ScrollView>
  );
}
```

### Custom Shared Transition

```tsx
import { SharedTransition, withSpring } from 'react-native-reanimated';

const customTransition = SharedTransition.custom((values) => {
  'worklet';
  return {
    originX: withSpring(values.targetOriginX, { damping: 20 }),
    originY: withSpring(values.targetOriginY, { damping: 20 }),
    width: withSpring(values.targetWidth, { damping: 20 }),
    height: withSpring(values.targetHeight, { damping: 20 }),
  };
});

<Animated.Image
  sharedTransitionTag={`image-${id}`}
  sharedTransitionStyle={customTransition}
  source={{ uri: imageUrl }}
/>
```

---

## 6. Entering / Exiting Animations

Built-in Reanimated animations for when components mount/unmount.

### Predefined Entering

```tsx
import Animated, {
  FadeIn,
  FadeInDown,
  FadeInUp,
  SlideInLeft,
  SlideInRight,
  ZoomIn,
  BounceIn,
} from 'react-native-reanimated';

// Usage — each returns a new modifier chain
<Animated.View entering={FadeInDown.duration(400).springify().damping(15)}>
  {children}
</Animated.View>

// With delay for staggering
<Animated.View entering={FadeInDown.delay(index * 100).springify()}>
  {children}
</Animated.View>

// With callback
<Animated.View
  entering={FadeIn.duration(300).withCallback((finished) => {
    'worklet';
    if (finished) {
      runOnJS(onEntryComplete)();
    }
  })}
>
```

### Predefined Exiting

```tsx
import Animated, {
  FadeOut,
  FadeOutDown,
  SlideOutLeft,
  ZoomOut,
} from 'react-native-reanimated';

<Animated.View exiting={FadeOutDown.duration(300)}>
  {children}
</Animated.View>

// Swipe-to-delete exit
<Animated.View exiting={SlideOutLeft.duration(300).springify()}>
  {children}
</Animated.View>
```

### Custom Entering/Exiting

```tsx
import { Keyframe } from 'react-native-reanimated';

const customEntering = new Keyframe({
  0: { opacity: 0, transform: [{ translateY: 50 }, { rotate: '-10deg' }] },
  50: { opacity: 0.8, transform: [{ translateY: -10 }, { rotate: '2deg' }] },
  100: { opacity: 1, transform: [{ translateY: 0 }, { rotate: '0deg' }] },
}).duration(500);

<Animated.View entering={customEntering}>
  {children}
</Animated.View>
```

---

## 7. Layout Animations

Automatically animate layout changes — items shifting when one is removed,
list reordering, size changes.

### Basic Layout Transition

```tsx
import Animated, { LinearTransition, FadeOut } from 'react-native-reanimated';

function AnimatedList({ items }: { items: Item[] }) {
  return (
    <Animated.FlatList
      data={items}
      itemLayoutAnimation={LinearTransition.springify().damping(15)}
      renderItem={({ item }) => (
        <Animated.View
          layout={LinearTransition.springify()}
          exiting={FadeOut.duration(200)}
        >
          <ListItem item={item} />
        </Animated.View>
      )}
    />
  );
}
```

### Sequenced Layout

```tsx
import { SequencedTransition } from 'react-native-reanimated';

// Items animate one after another instead of all at once
<Animated.View layout={SequencedTransition.duration(400)}>
  {children}
</Animated.View>
```

### Curved Layout Transition

```tsx
import { CurvedTransition } from 'react-native-reanimated';

// Items follow a curved path during layout change
<Animated.View layout={CurvedTransition.easingX(Easing.ease).duration(500)}>
  {children}
</Animated.View>
```

---

## 8. Gesture Handler Integration

Combine Gesture Handler v2 with Reanimated for gesture-driven animations
that run entirely on the UI thread.

### Pan + Spring (Swipeable Card)

```tsx
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
} from 'react-native-reanimated';

const SWIPE_THRESHOLD = 120;

function SwipeableCard({ onDismiss }: { onDismiss: () => void }) {
  const translateX = useSharedValue(0);
  const opacity = useSharedValue(1);

  const gesture = Gesture.Pan()
    .onUpdate((e) => {
      translateX.value = e.translationX;
      opacity.value = 1 - Math.abs(e.translationX) / 300;
    })
    .onEnd((e) => {
      if (Math.abs(e.translationX) > SWIPE_THRESHOLD) {
        const direction = e.translationX > 0 ? 1 : -1;
        translateX.value = withSpring(direction * 500, { velocity: e.velocityX });
        opacity.value = withSpring(0);
        runOnJS(onDismiss)();
      } else {
        translateX.value = withSpring(0, { velocity: e.velocityX });
        opacity.value = withSpring(1);
      }
    });

  const style = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
    opacity: opacity.value,
  }));

  return (
    <GestureDetector gesture={gesture}>
      <Animated.View style={style}>
        {/* card content */}
      </Animated.View>
    </GestureDetector>
  );
}
```

### Composed Gestures (Pinch + Pan)

```tsx
const panGesture = Gesture.Pan()
  .onUpdate((e) => {
    translateX.value = e.translationX + savedTranslateX.value;
    translateY.value = e.translationY + savedTranslateY.value;
  })
  .onEnd(() => {
    savedTranslateX.value = translateX.value;
    savedTranslateY.value = translateY.value;
  });

const pinchGesture = Gesture.Pinch()
  .onUpdate((e) => {
    scale.value = savedScale.value * e.scale;
  })
  .onEnd(() => {
    savedScale.value = scale.value;
  });

// Run both simultaneously
const composed = Gesture.Simultaneous(panGesture, pinchGesture);

<GestureDetector gesture={composed}>
  <Animated.View style={animatedStyle} />
</GestureDetector>
```

---

## 9. Best Practices

### Transform-Only Rule

```tsx
// GOOD — GPU composited, no layout recalculation
const style = useAnimatedStyle(() => ({
  transform: [
    { translateX: x.value },
    { translateY: y.value },
    { scale: s.value },
    { rotate: `${r.value}deg` },
  ],
  opacity: o.value,
}));

// BAD — triggers layout on every frame
const style = useAnimatedStyle(() => ({
  width: w.value,     // Layout recalc
  height: h.value,    // Layout recalc
  marginTop: m.value, // Layout recalc
  left: l.value,      // Layout recalc
}));
```

### Cancel Animations on Unmount

```tsx
import { cancelAnimation } from 'react-native-reanimated';

useEffect(() => {
  return () => {
    cancelAnimation(translateX);
    cancelAnimation(translateY);
    cancelAnimation(scale);
  };
}, []);
```

### Reduce Motion Respect

```tsx
import { useReducedMotion } from 'react-native-reanimated';

function AnimatedCard({ children }: { children: React.ReactNode }) {
  const reducedMotion = useReducedMotion();

  return (
    <MotiView
      from={{ opacity: 0, translateY: reducedMotion ? 0 : 20 }}
      animate={{ opacity: 1, translateY: 0 }}
      transition={reducedMotion
        ? { type: 'timing', duration: 0 }
        : { type: 'spring', damping: 15 }
      }
    >
      {children}
    </MotiView>
  );
}
```

### Animation Sequencing

```tsx
import {
  withSequence,
  withDelay,
  withRepeat,
} from 'react-native-reanimated';

// Shake animation (error feedback)
const shake = () => {
  translateX.value = withSequence(
    withTiming(10, { duration: 50 }),
    withRepeat(withTiming(-10, { duration: 100 }), 3, true),
    withTiming(0, { duration: 50 })
  );
};

// Delayed fade + slide
const enter = () => {
  opacity.value = withDelay(200, withTiming(1, { duration: 300 }));
  translateY.value = withDelay(200, withSpring(0, { damping: 15 }));
};
```

### Performance Tips

| Practice | Why |
|----------|-----|
| Use `useAnimatedStyle` not inline styles | Inline creates new objects each render |
| Avoid `runOnJS` in `onUpdate` | Bridges to JS thread every frame, defeats purpose |
| Use `withSpring` over `withTiming` for interactions | Springs handle velocity handoff naturally |
| Set `overflow: 'hidden'` on animated containers | Prevents off-screen render overhead |
| Cancel animations on unmount | Prevents updates to unmounted components |
| Use `SharedTransition` over manual sync | Built-in, optimized, handles edge cases |
| Batch shared value updates | Multiple `.value =` in same worklet are batched automatically |
