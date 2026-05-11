# Gesture Cookbook

8 complete, copy-pasteable gesture implementations using React Native
Gesture Handler v2 and Reanimated. Each recipe is self-contained — copy
the component and its imports.

---

## 1. Pull-to-Refresh with Haptic Feedback

Custom pull-to-refresh with spring physics and haptic trigger point.

```tsx
import { useCallback, useState } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Platform } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  interpolate,
  runOnJS,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

const PULL_THRESHOLD = 80;

function PullToRefresh({
  onRefresh,
  children,
}: {
  onRefresh: () => Promise<void>;
  children: React.ReactNode;
}) {
  const [refreshing, setRefreshing] = useState(false);
  const pullDistance = useSharedValue(0);
  const hasTriggeredHaptic = useSharedValue(false);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await onRefresh();
    setRefreshing(false);
  }, [onRefresh]);

  const indicatorStyle = useAnimatedStyle(() => ({
    transform: [
      {
        translateY: interpolate(
          pullDistance.value,
          [0, PULL_THRESHOLD],
          [-40, 20],
          'clamp'
        ),
      },
      {
        rotate: `${interpolate(
          pullDistance.value,
          [0, PULL_THRESHOLD],
          [0, 180]
        )}deg`,
      },
      {
        scale: interpolate(
          pullDistance.value,
          [0, PULL_THRESHOLD * 0.8, PULL_THRESHOLD],
          [0.5, 0.8, 1],
          'clamp'
        ),
      },
    ],
    opacity: interpolate(pullDistance.value, [0, PULL_THRESHOLD * 0.5], [0, 1]),
  }));

  return (
    <ScrollView
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={handleRefresh}
          tintColor="transparent" // Hide default indicator on iOS
          colors={['transparent']} // Hide on Android
        />
      }
      onScroll={(e) => {
        const y = e.nativeEvent.contentOffset.y;
        if (y < 0) {
          pullDistance.value = Math.abs(y);
          // Haptic at threshold
          if (Math.abs(y) >= PULL_THRESHOLD && !hasTriggeredHaptic.value) {
            hasTriggeredHaptic.value = true;
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
          } else if (Math.abs(y) < PULL_THRESHOLD) {
            hasTriggeredHaptic.value = false;
          }
        }
      }}
      scrollEventThrottle={16}
    >
      <Animated.View style={[styles.indicator, indicatorStyle]}>
        {/* Custom refresh indicator (e.g., animated icon) */}
      </Animated.View>
      {children}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  indicator: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    alignItems: 'center',
    justifyContent: 'center',
    height: 40,
  },
});
```

---

## 2. Swipe-to-Reveal Actions (iOS Mail Style)

Reveals action buttons behind a list item on horizontal swipe.

```tsx
import { Dimensions, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  interpolate,
  runOnJS,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

const ACTION_WIDTH = 80;
const FULL_SWIPE_THRESHOLD = Dimensions.get('window').width * 0.6;

function SwipeableRow({
  children,
  onDelete,
  onArchive,
}: {
  children: React.ReactNode;
  onDelete: () => void;
  onArchive: () => void;
}) {
  const translateX = useSharedValue(0);
  const hasPassedThreshold = useSharedValue(false);

  const gesture = Gesture.Pan()
    .activeOffsetX([-10, 10])
    .failOffsetY([-5, 5])
    .onUpdate((e) => {
      // Allow left swipe only (reveal right actions)
      translateX.value = Math.min(0, e.translationX);

      // Haptic at full-swipe threshold
      if (
        Math.abs(e.translationX) > FULL_SWIPE_THRESHOLD &&
        !hasPassedThreshold.value
      ) {
        hasPassedThreshold.value = true;
        runOnJS(Haptics.impactAsync)(Haptics.ImpactFeedbackStyle.Heavy);
      } else if (Math.abs(e.translationX) < FULL_SWIPE_THRESHOLD) {
        hasPassedThreshold.value = false;
      }
    })
    .onEnd((e) => {
      if (Math.abs(e.translationX) > FULL_SWIPE_THRESHOLD) {
        // Full swipe — delete
        translateX.value = withTiming(-Dimensions.get('window').width, {
          duration: 200,
        });
        runOnJS(onDelete)();
      } else if (Math.abs(e.translationX) > ACTION_WIDTH) {
        // Partial swipe — reveal actions
        translateX.value = withSpring(-ACTION_WIDTH * 2, {
          damping: 20,
          stiffness: 200,
        });
      } else {
        // Snap back
        translateX.value = withSpring(0, { damping: 20, stiffness: 200 });
      }
    });

  const rowStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
  }));

  const actionsStyle = useAnimatedStyle(() => ({
    width: interpolate(
      translateX.value,
      [-ACTION_WIDTH * 2, 0],
      [ACTION_WIDTH * 2, 0],
      'clamp'
    ),
  }));

  return (
    <View style={styles.container}>
      <Animated.View style={[styles.actions, actionsStyle]}>
        <ActionButton
          label="Archive"
          color="#3B82F6"
          onPress={() => {
            translateX.value = withSpring(0);
            onArchive();
          }}
        />
        <ActionButton
          label="Delete"
          color="#EF4444"
          onPress={() => {
            translateX.value = withTiming(-Dimensions.get('window').width, {
              duration: 200,
            });
            onDelete();
          }}
        />
      </Animated.View>
      <GestureDetector gesture={gesture}>
        <Animated.View style={[styles.row, rowStyle]}>{children}</Animated.View>
      </GestureDetector>
    </View>
  );
}

function ActionButton({
  label,
  color,
  onPress,
}: {
  label: string;
  color: string;
  onPress: () => void;
}) {
  return (
    <Pressable
      style={[styles.actionButton, { backgroundColor: color }]}
      onPress={onPress}
    >
      <Text style={styles.actionLabel}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { overflow: 'hidden' },
  row: { backgroundColor: '#fff' },
  actions: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: 0,
    flexDirection: 'row',
  },
  actionButton: {
    width: ACTION_WIDTH,
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionLabel: { color: '#fff', fontWeight: '600', fontSize: 13 },
});
```

---

## 3. Bottom Sheet with Snap Points

A draggable bottom sheet that snaps to predefined heights.

```tsx
import { Dimensions, StyleSheet, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  interpolate,
  runOnJS,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

const SCREEN_HEIGHT = Dimensions.get('window').height;

interface BottomSheetProps {
  snapPoints: number[]; // e.g., [0.25, 0.5, 0.9] as fractions of screen height
  children: React.ReactNode;
  onClose?: () => void;
}

function BottomSheet({ snapPoints, children, onClose }: BottomSheetProps) {
  const snapHeights = snapPoints
    .map((p) => SCREEN_HEIGHT * (1 - p))
    .sort((a, b) => b - a); // Highest Y first (lowest sheet position)

  const translateY = useSharedValue(snapHeights[0]);
  const context = useSharedValue(0);
  const lastSnapIndex = useSharedValue(0);

  const findClosestSnap = (y: number) => {
    'worklet';
    let closest = 0;
    let minDist = Math.abs(y - snapHeights[0]);
    for (let i = 1; i < snapHeights.length; i++) {
      const dist = Math.abs(y - snapHeights[i]);
      if (dist < minDist) {
        minDist = dist;
        closest = i;
      }
    }
    return closest;
  };

  const gesture = Gesture.Pan()
    .onStart(() => {
      context.value = translateY.value;
    })
    .onUpdate((e) => {
      const newY = context.value + e.translationY;
      // Clamp between highest and lowest snap + some overscroll
      translateY.value = Math.max(
        snapHeights[snapHeights.length - 1] - 20,
        Math.min(SCREEN_HEIGHT, newY)
      );
    })
    .onEnd((e) => {
      // Factor in velocity for natural feel
      const projectedY = translateY.value + e.velocityY * 0.1;
      const snapIndex = findClosestSnap(projectedY);

      // Haptic on snap change
      if (snapIndex !== lastSnapIndex.value) {
        lastSnapIndex.value = snapIndex;
        runOnJS(Haptics.impactAsync)(Haptics.ImpactFeedbackStyle.Light);
      }

      // Dismiss if dragged below lowest snap
      if (projectedY > SCREEN_HEIGHT * 0.85) {
        translateY.value = withSpring(SCREEN_HEIGHT, {
          velocity: e.velocityY,
          damping: 20,
        });
        if (onClose) runOnJS(onClose)();
      } else {
        translateY.value = withSpring(snapHeights[snapIndex], {
          velocity: e.velocityY,
          damping: 20,
          stiffness: 200,
        });
      }
    });

  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  const backdropStyle = useAnimatedStyle(() => ({
    opacity: interpolate(
      translateY.value,
      [snapHeights[snapHeights.length - 1], snapHeights[0]],
      [0.5, 0]
    ),
  }));

  return (
    <>
      <Animated.View
        style={[StyleSheet.absoluteFill, styles.backdrop, backdropStyle]}
        pointerEvents="box-none"
      />
      <GestureDetector gesture={gesture}>
        <Animated.View style={[styles.sheet, sheetStyle]}>
          <View style={styles.handle} />
          {children}
        </Animated.View>
      </GestureDetector>
    </>
  );
}

const styles = StyleSheet.create({
  backdrop: { backgroundColor: '#000' },
  sheet: {
    position: 'absolute',
    left: 0,
    right: 0,
    height: SCREEN_HEIGHT,
    backgroundColor: '#fff',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -3 },
    shadowOpacity: 0.1,
    shadowRadius: 10,
    elevation: 10,
  },
  handle: {
    width: 36,
    height: 5,
    borderRadius: 3,
    backgroundColor: '#D1D5DB',
    alignSelf: 'center',
    marginTop: 8,
    marginBottom: 8,
  },
});
```

---

## 4. Drag-to-Reorder List

Drag items to reorder with haptic feedback and smooth layout animations.

```tsx
import { useState, useCallback } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  useAnimatedReaction,
  withSpring,
  withTiming,
  runOnJS,
  LinearTransition,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

const ITEM_HEIGHT = 60;

function DraggableList({ initialItems }: { initialItems: string[] }) {
  const [items, setItems] = useState(initialItems);
  const activeIndex = useSharedValue(-1);
  const activeTranslateY = useSharedValue(0);

  const moveItem = useCallback(
    (from: number, to: number) => {
      setItems((prev) => {
        const next = [...prev];
        const [moved] = next.splice(from, 1);
        next.splice(to, 0, moved);
        return next;
      });
    },
    []
  );

  return (
    <View style={styles.list}>
      {items.map((item, index) => (
        <DraggableItem
          key={item}
          item={item}
          index={index}
          itemCount={items.length}
          activeIndex={activeIndex}
          activeTranslateY={activeTranslateY}
          onReorder={moveItem}
        />
      ))}
    </View>
  );
}

function DraggableItem({
  item,
  index,
  itemCount,
  activeIndex,
  activeTranslateY,
  onReorder,
}: {
  item: string;
  index: number;
  itemCount: number;
  activeIndex: Animated.SharedValue<number>;
  activeTranslateY: Animated.SharedValue<number>;
  onReorder: (from: number, to: number) => void;
}) {
  const isActive = useSharedValue(false);
  const offsetY = useSharedValue(0);

  const gesture = Gesture.Pan()
    .activateAfterLongPress(200)
    .onStart(() => {
      isActive.value = true;
      activeIndex.value = index;
      runOnJS(Haptics.impactAsync)(Haptics.ImpactFeedbackStyle.Medium);
    })
    .onUpdate((e) => {
      activeTranslateY.value = e.translationY;

      // Calculate new position
      const newIndex = Math.round(
        Math.max(0, Math.min(itemCount - 1, index + e.translationY / ITEM_HEIGHT))
      );

      if (newIndex !== activeIndex.value) {
        activeIndex.value = newIndex;
        runOnJS(Haptics.selectionAsync)();
      }
    })
    .onEnd(() => {
      const targetIndex = activeIndex.value;
      isActive.value = false;
      activeTranslateY.value = 0;
      activeIndex.value = -1;

      if (targetIndex !== index) {
        runOnJS(onReorder)(index, targetIndex);
      }
    });

  const animatedStyle = useAnimatedStyle(() => {
    if (isActive.value) {
      return {
        transform: [
          { translateY: activeTranslateY.value },
          { scale: withSpring(1.05) },
        ],
        zIndex: 100,
        shadowOpacity: withSpring(0.2),
        elevation: 5,
      };
    }

    // Non-active items shift to make room
    if (activeIndex.value >= 0) {
      const shouldShiftUp =
        index > Math.min(activeIndex.value, index) &&
        index <= Math.max(activeIndex.value, index);

      return {
        transform: [
          {
            translateY: shouldShiftUp
              ? withSpring(
                  activeIndex.value > index ? ITEM_HEIGHT : -ITEM_HEIGHT
                )
              : withSpring(0),
          },
          { scale: 1 },
        ],
        zIndex: 0,
      };
    }

    return {
      transform: [{ translateY: withSpring(0) }, { scale: 1 }],
      zIndex: 0,
    };
  });

  return (
    <GestureDetector gesture={gesture}>
      <Animated.View style={[styles.item, animatedStyle]}>
        <Text style={styles.itemText}>{item}</Text>
        <Text style={styles.grip}>☰</Text>
      </Animated.View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  list: { padding: 16 },
  item: {
    height: ITEM_HEIGHT,
    backgroundColor: '#fff',
    borderRadius: 12,
    paddingHorizontal: 16,
    marginBottom: 8,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
  },
  itemText: { fontSize: 16, fontWeight: '500' },
  grip: { fontSize: 18, color: '#9CA3AF' },
});
```

---

## 5. Pinch-to-Zoom Image Viewer

Full image viewer with pinch-to-zoom and pan, with double-tap to toggle zoom.

```tsx
import { Dimensions, StyleSheet } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');
const MIN_SCALE = 1;
const MAX_SCALE = 5;

function ImageViewer({ uri }: { uri: string }) {
  const scale = useSharedValue(1);
  const savedScale = useSharedValue(1);
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const savedTranslateX = useSharedValue(0);
  const savedTranslateY = useSharedValue(0);
  const focalX = useSharedValue(0);
  const focalY = useSharedValue(0);

  const pinch = Gesture.Pinch()
    .onStart((e) => {
      focalX.value = e.focalX;
      focalY.value = e.focalY;
    })
    .onUpdate((e) => {
      const newScale = Math.min(MAX_SCALE, Math.max(MIN_SCALE * 0.5, savedScale.value * e.scale));
      scale.value = newScale;
    })
    .onEnd(() => {
      if (scale.value < MIN_SCALE) {
        scale.value = withSpring(MIN_SCALE, { damping: 15 });
        translateX.value = withSpring(0);
        translateY.value = withSpring(0);
      }
      savedScale.value = scale.value;
      savedTranslateX.value = translateX.value;
      savedTranslateY.value = translateY.value;
    });

  const pan = Gesture.Pan()
    .minPointers(scale.value > 1 ? 1 : 2) // Single finger pan only when zoomed
    .onUpdate((e) => {
      if (scale.value > 1) {
        translateX.value = savedTranslateX.value + e.translationX;
        translateY.value = savedTranslateY.value + e.translationY;
      }
    })
    .onEnd(() => {
      // Clamp to image bounds
      const maxX = ((scale.value - 1) * SCREEN_WIDTH) / 2;
      const maxY = ((scale.value - 1) * SCREEN_HEIGHT) / 2;

      if (Math.abs(translateX.value) > maxX) {
        translateX.value = withSpring(
          Math.sign(translateX.value) * maxX,
          { damping: 20 }
        );
      }
      if (Math.abs(translateY.value) > maxY) {
        translateY.value = withSpring(
          Math.sign(translateY.value) * maxY,
          { damping: 20 }
        );
      }

      savedTranslateX.value = translateX.value;
      savedTranslateY.value = translateY.value;
    });

  const doubleTap = Gesture.Tap()
    .numberOfTaps(2)
    .onStart((e) => {
      if (scale.value > 1) {
        // Zoom out
        scale.value = withSpring(1, { damping: 15 });
        translateX.value = withSpring(0);
        translateY.value = withSpring(0);
        savedScale.value = 1;
        savedTranslateX.value = 0;
        savedTranslateY.value = 0;
      } else {
        // Zoom in to 2.5x centered on tap point
        const targetScale = 2.5;
        const originX = e.x - SCREEN_WIDTH / 2;
        const originY = e.y - SCREEN_HEIGHT / 2;

        scale.value = withSpring(targetScale, { damping: 15 });
        translateX.value = withSpring(-originX * (targetScale - 1));
        translateY.value = withSpring(-originY * (targetScale - 1));
        savedScale.value = targetScale;
        savedTranslateX.value = -originX * (targetScale - 1);
        savedTranslateY.value = -originY * (targetScale - 1);
      }
    });

  const composed = Gesture.Simultaneous(
    pinch,
    pan,
    Gesture.Exclusive(doubleTap)
  );

  const imageStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: translateX.value },
      { translateY: translateY.value },
      { scale: scale.value },
    ],
  }));

  return (
    <GestureDetector gesture={composed}>
      <Animated.Image
        source={{ uri }}
        style={[styles.image, imageStyle]}
        resizeMode="contain"
      />
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  image: {
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
  },
});
```

---

## 6. Double-Tap to Like (Instagram Style)

Heart animation that pops in on double-tap with haptic feedback.

```tsx
import { StyleSheet, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withDelay,
  withSequence,
  withTiming,
  runOnJS,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

function DoubleTapToLike({
  children,
  onLike,
}: {
  children: React.ReactNode;
  onLike: () => void;
}) {
  const heartScale = useSharedValue(0);
  const heartOpacity = useSharedValue(0);

  const doubleTap = Gesture.Tap()
    .numberOfTaps(2)
    .onStart(() => {
      runOnJS(Haptics.notificationAsync)(
        Haptics.NotificationFeedbackType.Success
      );
      runOnJS(onLike)();

      // Heart pop-in
      heartOpacity.value = 1;
      heartScale.value = withSequence(
        withSpring(1.2, { damping: 8, stiffness: 300 }),
        withDelay(
          400,
          withTiming(0, { duration: 200 })
        )
      );
      heartOpacity.value = withDelay(400, withTiming(0, { duration: 200 }));
    });

  const heartStyle = useAnimatedStyle(() => ({
    transform: [{ scale: heartScale.value }],
    opacity: heartOpacity.value,
  }));

  return (
    <GestureDetector gesture={doubleTap}>
      <View style={styles.container}>
        {children}
        <Animated.Text style={[styles.heart, heartStyle]}>
          ❤️
        </Animated.Text>
      </View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  heart: {
    position: 'absolute',
    fontSize: 80,
  },
});
```

---

## 7. Long-Press Context Menu

A native-feeling context menu with haptic trigger and spring animation.

```tsx
import { useState, useCallback } from 'react';
import { StyleSheet, Text, View, Pressable, Modal } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  FadeIn,
  FadeOut,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

interface MenuItem {
  label: string;
  icon?: string;
  destructive?: boolean;
  onPress: () => void;
}

function LongPressMenu({
  children,
  items,
}: {
  children: React.ReactNode;
  items: MenuItem[];
}) {
  const [visible, setVisible] = useState(false);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const scale = useSharedValue(1);

  const longPress = Gesture.LongPress()
    .minDuration(400)
    .onStart((e) => {
      scale.value = withSpring(0.95, { damping: 15, stiffness: 400 });
      setPosition({ x: e.absoluteX, y: e.absoluteY });
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
      setVisible(true);
    })
    .onEnd(() => {
      scale.value = withSpring(1, { damping: 15, stiffness: 400 });
    });

  const contentStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  const close = useCallback(() => {
    setVisible(false);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  return (
    <>
      <GestureDetector gesture={longPress}>
        <Animated.View style={contentStyle}>{children}</Animated.View>
      </GestureDetector>

      <Modal visible={visible} transparent animationType="none">
        <Pressable style={styles.overlay} onPress={close}>
          <Animated.View
            entering={FadeIn.duration(150)}
            exiting={FadeOut.duration(100)}
            style={[
              styles.menu,
              {
                top: Math.min(position.y, 500),
                left: Math.min(position.x - 100, 250),
              },
            ]}
          >
            {items.map((item, i) => (
              <Pressable
                key={i}
                style={[styles.menuItem, i < items.length - 1 && styles.menuItemBorder]}
                onPress={() => {
                  close();
                  Haptics.selectionAsync();
                  item.onPress();
                }}
              >
                {item.icon && <Text style={styles.menuIcon}>{item.icon}</Text>}
                <Text
                  style={[
                    styles.menuLabel,
                    item.destructive && styles.destructive,
                  ]}
                >
                  {item.label}
                </Text>
              </Pressable>
            ))}
          </Animated.View>
        </Pressable>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.3)',
  },
  menu: {
    position: 'absolute',
    width: 200,
    backgroundColor: '#fff',
    borderRadius: 14,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.15,
    shadowRadius: 20,
    elevation: 10,
    overflow: 'hidden',
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  menuItemBorder: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#E5E7EB',
  },
  menuIcon: { fontSize: 18, marginRight: 12 },
  menuLabel: { fontSize: 16, color: '#1F2937' },
  destructive: { color: '#EF4444' },
});
```

---

## 8. Swipe-to-Dismiss Card

Card that can be swiped away in any direction with velocity-based throw.

```tsx
import { Dimensions, StyleSheet, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  interpolate,
  runOnJS,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');
const DISMISS_THRESHOLD = 120;
const VELOCITY_THRESHOLD = 800;

function SwipeToDismissCard({
  children,
  onDismiss,
}: {
  children: React.ReactNode;
  onDismiss: (direction: 'left' | 'right' | 'up' | 'down') => void;
}) {
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);

  const gesture = Gesture.Pan()
    .onUpdate((e) => {
      translateX.value = e.translationX;
      translateY.value = e.translationY;
    })
    .onEnd((e) => {
      const absX = Math.abs(e.translationX);
      const absY = Math.abs(e.translationY);
      const absVelocityX = Math.abs(e.velocityX);
      const absVelocityY = Math.abs(e.velocityY);

      // Check if threshold is met (distance OR velocity)
      const shouldDismissX =
        absX > DISMISS_THRESHOLD || absVelocityX > VELOCITY_THRESHOLD;
      const shouldDismissY =
        absY > DISMISS_THRESHOLD || absVelocityY > VELOCITY_THRESHOLD;

      if (shouldDismissX || shouldDismissY) {
        // Determine primary direction
        let direction: 'left' | 'right' | 'up' | 'down';
        let targetX = 0;
        let targetY = 0;

        if (absX > absY) {
          direction = e.translationX > 0 ? 'right' : 'left';
          targetX = (e.translationX > 0 ? 1 : -1) * SCREEN_WIDTH * 1.5;
          targetY = e.translationY * 2;
        } else {
          direction = e.translationY > 0 ? 'down' : 'up';
          targetY = (e.translationY > 0 ? 1 : -1) * SCREEN_HEIGHT * 1.5;
          targetX = e.translationX * 2;
        }

        translateX.value = withTiming(targetX, { duration: 300 });
        translateY.value = withTiming(targetY, { duration: 300 });
        runOnJS(Haptics.impactAsync)(Haptics.ImpactFeedbackStyle.Medium);
        runOnJS(onDismiss)(direction);
      } else {
        // Snap back
        translateX.value = withSpring(0, {
          velocity: e.velocityX,
          damping: 20,
          stiffness: 200,
        });
        translateY.value = withSpring(0, {
          velocity: e.velocityY,
          damping: 20,
          stiffness: 200,
        });
      }
    });

  const cardStyle = useAnimatedStyle(() => {
    const distance = Math.sqrt(
      translateX.value ** 2 + translateY.value ** 2
    );
    const rotation = interpolate(
      translateX.value,
      [-SCREEN_WIDTH / 2, 0, SCREEN_WIDTH / 2],
      [-15, 0, 15]
    );

    return {
      transform: [
        { translateX: translateX.value },
        { translateY: translateY.value },
        { rotate: `${rotation}deg` },
        {
          scale: interpolate(distance, [0, DISMISS_THRESHOLD], [1, 0.95], 'clamp'),
        },
      ],
      opacity: interpolate(distance, [0, SCREEN_WIDTH], [1, 0.5]),
    };
  });

  return (
    <GestureDetector gesture={gesture}>
      <Animated.View style={[styles.card, cardStyle]}>{children}</Animated.View>
    </GestureDetector>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    borderRadius: 20,
    padding: 24,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 5,
  },
});
```
