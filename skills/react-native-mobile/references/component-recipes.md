# Component Recipes

8 complete, copy-pasteable component implementations for common mobile
UI patterns. Each recipe is self-contained with imports and styles.

---

## 1. Skeleton Screen with Shimmer Animation

Placeholder UI shown while content loads. Uses Moti for shimmer effect.

```tsx
import { StyleSheet, View } from 'react-native';
import { MotiView } from 'moti';
import { useTheme } from '@/lib/theme';

function SkeletonBox({
  width,
  height,
  radius = 8,
}: {
  width: number | string;
  height: number;
  radius?: number;
}) {
  const theme = useTheme();

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
        borderRadius: radius,
        backgroundColor: theme.isDark ? '#1F2937' : '#E5E7EB',
      }}
    />
  );
}

function SkeletonCircle({ size }: { size: number }) {
  return <SkeletonBox width={size} height={size} radius={size / 2} />;
}

// Usage: Feed card skeleton
function FeedCardSkeleton() {
  return (
    <View style={styles.card}>
      <View style={styles.header}>
        <SkeletonCircle size={40} />
        <View style={styles.headerText}>
          <SkeletonBox width={120} height={14} />
          <SkeletonBox width={80} height={12} />
        </View>
      </View>
      <SkeletonBox width="100%" height={200} radius={12} />
      <View style={styles.footer}>
        <SkeletonBox width={180} height={14} />
        <SkeletonBox width={100} height={12} />
      </View>
    </View>
  );
}

// Full skeleton screen
function FeedSkeleton() {
  return (
    <View style={styles.container}>
      {Array.from({ length: 3 }).map((_, i) => (
        <FeedCardSkeleton key={i} />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { padding: 16, gap: 16 },
  card: { gap: 12 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  headerText: { gap: 6 },
  footer: { gap: 6 },
});
```

---

## 2. Error Boundary with Fallback UI

Catches JS errors in the component tree and shows a recovery screen.

```tsx
import { Component, ReactNode } from 'react';
import {
  StyleSheet,
  Text,
  View,
  Pressable,
  Image,
} from 'react-native';
import * as Haptics from 'expo-haptics';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    this.props.onError?.(error, errorInfo);
    // Log to crash reporting service (Sentry, Bugsnag, etc.)
  }

  handleRetry = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;

      return (
        <View style={styles.container}>
          <Text style={styles.emoji}>😵</Text>
          <Text style={styles.title}>Something went wrong</Text>
          <Text style={styles.message}>
            {this.state.error?.message ?? 'An unexpected error occurred'}
          </Text>
          <Pressable
            style={styles.button}
            onPress={this.handleRetry}
          >
            <Text style={styles.buttonText}>Try Again</Text>
          </Pressable>
        </View>
      );
    }

    return this.props.children;
  }
}

// Hook wrapper for functional component usage
function withErrorBoundary<P extends object>(
  WrappedComponent: React.ComponentType<P>,
  fallback?: ReactNode
) {
  return function WithErrorBoundary(props: P) {
    return (
      <ErrorBoundary fallback={fallback}>
        <WrappedComponent {...props} />
      </ErrorBoundary>
    );
  };
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  emoji: { fontSize: 64, marginBottom: 16 },
  title: { fontSize: 22, fontWeight: '700', marginBottom: 8, textAlign: 'center' },
  message: { fontSize: 16, color: '#6B7280', textAlign: 'center', marginBottom: 24 },
  button: {
    backgroundColor: '#3B82F6',
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 12,
  },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});

export { ErrorBoundary, withErrorBoundary };
```

---

## 3. Empty State with CTA

Shown when a list or screen has no content yet.

```tsx
import { StyleSheet, Text, View, Pressable, Platform } from 'react-native';
import Animated, { FadeInDown } from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { useTheme } from '@/lib/theme';

interface EmptyStateProps {
  icon: string;           // Emoji or icon name
  title: string;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
}

function EmptyState({
  icon,
  title,
  message,
  actionLabel,
  onAction,
}: EmptyStateProps) {
  const theme = useTheme();

  return (
    <Animated.View
      entering={FadeInDown.duration(400).springify().damping(15)}
      style={styles.container}
    >
      <Text style={styles.icon}>{icon}</Text>
      <Text style={[styles.title, { color: theme.colors.text }]}>
        {title}
      </Text>
      <Text style={[styles.message, { color: theme.colors.textSecondary }]}>
        {message}
      </Text>
      {actionLabel && onAction && (
        <Pressable
          style={[styles.button, { backgroundColor: theme.colors.primary }]}
          onPress={() => {
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
            onAction();
          }}
        >
          <Text style={styles.buttonText}>{actionLabel}</Text>
        </Pressable>
      )}
    </Animated.View>
  );
}

// Usage examples:
// <EmptyState
//   icon="📝"
//   title="No notes yet"
//   message="Create your first note to get started"
//   actionLabel="Create Note"
//   onAction={() => router.push('/notes/new')}
// />
//
// <EmptyState
//   icon="🔍"
//   title="No results"
//   message="Try a different search term"
// />

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
    minHeight: 300,
  },
  icon: { fontSize: 56, marginBottom: 16 },
  title: {
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 8,
  },
  message: {
    fontSize: 16,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 24,
  },
  button: {
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 12,
  },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});

export { EmptyState };
```

---

## 4. Loading State Hierarchy

Different loading treatments based on expected wait time.

```tsx
import { useState, useEffect, useRef } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { FadeIn, FadeOut } from 'react-native-reanimated';
import { MotiView } from 'moti';
import { useTheme } from '@/lib/theme';

/**
 * Loading state hierarchy:
 *
 * < 100ms:  No indicator. Content should appear instantly.
 *           If it doesn't, optimize the data fetch.
 *
 * 100ms-1s: Skeleton screen. Shows the shape of content
 *           that will appear, reducing perceived wait time.
 *
 * 1s-5s:    Skeleton + subtle progress. Add a progress bar
 *           or percentage if progress is deterministic.
 *
 * > 5s:     Full loading screen with progress, message, and
 *           cancel option. Explain what's happening.
 */

function useTimedLoading(isLoading: boolean) {
  const [tier, setTier] = useState<'none' | 'skeleton' | 'progress' | 'full'>(
    'none'
  );
  const startTime = useRef(0);

  useEffect(() => {
    if (isLoading) {
      startTime.current = Date.now();
      setTier('none');

      // Show skeleton after 100ms
      const t1 = setTimeout(() => setTier('skeleton'), 100);
      // Upgrade to progress after 1s
      const t2 = setTimeout(() => setTier('progress'), 1000);
      // Upgrade to full after 5s
      const t3 = setTimeout(() => setTier('full'), 5000);

      return () => {
        clearTimeout(t1);
        clearTimeout(t2);
        clearTimeout(t3);
      };
    } else {
      setTier('none');
    }
  }, [isLoading]);

  return tier;
}

// Skeleton tier (100ms-1s)
function LoadingSkeleton() {
  return (
    <Animated.View entering={FadeIn.duration(200)}>
      {/* Use your page-specific skeleton here */}
      <View style={styles.skeletonRow}>
        <SkeletonBox width={48} height={48} radius={24} />
        <View style={styles.skeletonText}>
          <SkeletonBox width={160} height={16} />
          <SkeletonBox width={120} height={14} />
        </View>
      </View>
    </Animated.View>
  );
}

// Progress tier (1s-5s)
function LoadingWithProgress({ message }: { message?: string }) {
  const theme = useTheme();

  return (
    <Animated.View
      entering={FadeIn.duration(200)}
      style={styles.centered}
    >
      <ActivityIndicator size="large" color={theme.colors.primary} />
      {message && (
        <Text style={[styles.loadingText, { color: theme.colors.textSecondary }]}>
          {message}
        </Text>
      )}
    </Animated.View>
  );
}

// Full tier (> 5s)
function LoadingFull({
  message,
  progress,
  onCancel,
}: {
  message: string;
  progress?: number;
  onCancel?: () => void;
}) {
  const theme = useTheme();

  return (
    <Animated.View
      entering={FadeIn.duration(200)}
      style={styles.fullContainer}
    >
      <ActivityIndicator size="large" color={theme.colors.primary} />
      <Text style={[styles.loadingTitle, { color: theme.colors.text }]}>
        {message}
      </Text>
      {progress !== undefined && (
        <View style={styles.progressBar}>
          <MotiView
            animate={{ width: `${Math.round(progress * 100)}%` }}
            transition={{ type: 'timing', duration: 300 }}
            style={[styles.progressFill, { backgroundColor: theme.colors.primary }]}
          />
        </View>
      )}
      {onCancel && (
        <Pressable onPress={onCancel} style={styles.cancelButton}>
          <Text style={[styles.cancelText, { color: theme.colors.textSecondary }]}>
            Cancel
          </Text>
        </Pressable>
      )}
    </Animated.View>
  );
}

// Skeleton helper
function SkeletonBox({
  width,
  height,
  radius = 8,
}: {
  width: number;
  height: number;
  radius?: number;
}) {
  return (
    <MotiView
      from={{ opacity: 0.3 }}
      animate={{ opacity: 0.7 }}
      transition={{ type: 'timing', duration: 1000, loop: true, repeatReverse: true }}
      style={{ width, height, borderRadius: radius, backgroundColor: '#E5E7EB' }}
    />
  );
}

const styles = StyleSheet.create({
  centered: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  loadingText: { marginTop: 12, fontSize: 15 },
  fullContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  loadingTitle: { marginTop: 16, fontSize: 17, fontWeight: '600' },
  progressBar: {
    width: '80%',
    height: 4,
    backgroundColor: '#E5E7EB',
    borderRadius: 2,
    marginTop: 16,
    overflow: 'hidden',
  },
  progressFill: { height: '100%', borderRadius: 2 },
  cancelButton: { marginTop: 24, padding: 12 },
  cancelText: { fontSize: 16 },
  skeletonRow: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 16 },
  skeletonText: { gap: 8 },
});

export { useTimedLoading, LoadingSkeleton, LoadingWithProgress, LoadingFull };
```

---

## 5. Animated List Item (Enter / Exit / Press)

List item with enter animation, press scale, and swipe-to-delete exit.

```tsx
import { memo } from 'react';
import { StyleSheet, Text, View, Pressable, Platform } from 'react-native';
import Animated, {
  FadeInDown,
  FadeOutLeft,
  LinearTransition,
  useSharedValue,
  useAnimatedStyle,
  withSpring,
} from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { useTheme } from '@/lib/theme';

interface AnimatedListItemProps {
  item: { id: string; title: string; subtitle: string };
  index: number;
  onPress: () => void;
  onDelete?: () => void;
}

const AnimatedListItem = memo(function AnimatedListItem({
  item,
  index,
  onPress,
  onDelete,
}: AnimatedListItemProps) {
  const theme = useTheme();
  const scale = useSharedValue(1);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View
      entering={FadeInDown.delay(index * 50).springify().damping(15)}
      exiting={FadeOutLeft.duration(200).springify()}
      layout={LinearTransition.springify().damping(15)}
    >
      <Pressable
        onPressIn={() => {
          scale.value = withSpring(0.97, { damping: 15, stiffness: 400 });
        }}
        onPressOut={() => {
          scale.value = withSpring(1, { damping: 15, stiffness: 400 });
        }}
        onPress={() => {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
          onPress();
        }}
        onLongPress={() => {
          if (onDelete) {
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
            onDelete();
          }
        }}
      >
        <Animated.View
          style={[
            styles.item,
            { backgroundColor: theme.colors.surfaceElevated },
            animatedStyle,
          ]}
        >
          <View style={styles.content}>
            <Text
              style={[styles.title, { color: theme.colors.text }]}
              numberOfLines={1}
            >
              {item.title}
            </Text>
            <Text
              style={[styles.subtitle, { color: theme.colors.textSecondary }]}
              numberOfLines={1}
            >
              {item.subtitle}
            </Text>
          </View>
          <Text style={[styles.chevron, { color: theme.colors.textTertiary }]}>
            ›
          </Text>
        </Animated.View>
      </Pressable>
    </Animated.View>
  );
});

const styles = StyleSheet.create({
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderRadius: 12,
    marginHorizontal: 16,
    marginBottom: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  content: { flex: 1, gap: 4 },
  title: { fontSize: 17, fontWeight: '600' },
  subtitle: { fontSize: 14 },
  chevron: { fontSize: 24, fontWeight: '300', marginLeft: 8 },
});

export { AnimatedListItem };
```

---

## 6. Toast / Snackbar Notification

A self-dismissing notification that slides in from the top.

```tsx
import { createContext, useContext, useCallback, useState, useRef } from 'react';
import { StyleSheet, Text, View, Pressable, Platform } from 'react-native';
import Animated, { FadeInUp, FadeOutUp } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';

type ToastType = 'success' | 'error' | 'info' | 'warning';

interface Toast {
  id: string;
  type: ToastType;
  message: string;
  action?: { label: string; onPress: () => void };
}

interface ToastContextValue {
  show: (type: ToastType, message: string, action?: Toast['action']) => void;
}

const ToastContext = createContext<ToastContextValue>({ show: () => {} });

export function useToast() {
  return useContext(ToastContext);
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const timers = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  const show = useCallback(
    (type: ToastType, message: string, action?: Toast['action']) => {
      const id = Math.random().toString(36).slice(2);
      const toast: Toast = { id, type, message, action };

      setToasts((prev) => [...prev, toast]);

      // Haptic feedback based on type
      switch (type) {
        case 'success':
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          break;
        case 'error':
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
          break;
        case 'warning':
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
          break;
        default:
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      }

      // Auto-dismiss after 3s (or 5s if there's an action)
      const timer = setTimeout(
        () => dismiss(id),
        action ? 5000 : 3000
      );
      timers.current.set(id, timer);
    },
    []
  );

  const dismiss = useCallback((id: string) => {
    const timer = timers.current.get(id);
    if (timer) {
      clearTimeout(timer);
      timers.current.delete(id);
    }
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return (
    <ToastContext.Provider value={{ show }}>
      {children}
      <ToastContainer toasts={toasts} onDismiss={dismiss} />
    </ToastContext.Provider>
  );
}

const TOAST_COLORS = {
  success: { bg: '#DCFCE7', text: '#166534', icon: '✓' },
  error: { bg: '#FEE2E2', text: '#991B1B', icon: '✕' },
  warning: { bg: '#FEF3C7', text: '#92400E', icon: '!' },
  info: { bg: '#DBEAFE', text: '#1E40AF', icon: 'i' },
};

function ToastContainer({
  toasts,
  onDismiss,
}: {
  toasts: Toast[];
  onDismiss: (id: string) => void;
}) {
  const insets = useSafeAreaInsets();

  return (
    <View
      style={[styles.toastContainer, { top: insets.top + 8 }]}
      pointerEvents="box-none"
    >
      {toasts.map((toast) => {
        const colors = TOAST_COLORS[toast.type];
        return (
          <Animated.View
            key={toast.id}
            entering={FadeInUp.springify().damping(15)}
            exiting={FadeOutUp.duration(200)}
          >
            <Pressable
              style={[styles.toast, { backgroundColor: colors.bg }]}
              onPress={() => onDismiss(toast.id)}
            >
              <Text style={[styles.toastIcon, { color: colors.text }]}>
                {colors.icon}
              </Text>
              <Text
                style={[styles.toastMessage, { color: colors.text }]}
                numberOfLines={2}
              >
                {toast.message}
              </Text>
              {toast.action && (
                <Pressable
                  onPress={() => {
                    toast.action?.onPress();
                    onDismiss(toast.id);
                  }}
                  hitSlop={8}
                >
                  <Text style={[styles.toastAction, { color: colors.text }]}>
                    {toast.action.label}
                  </Text>
                </Pressable>
              )}
            </Pressable>
          </Animated.View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  toastContainer: {
    position: 'absolute',
    left: 16,
    right: 16,
    zIndex: 9999,
    gap: 8,
  },
  toast: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderRadius: 14,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 6,
    gap: 10,
  },
  toastIcon: { fontSize: 16, fontWeight: '700', width: 20, textAlign: 'center' },
  toastMessage: { flex: 1, fontSize: 15, fontWeight: '500' },
  toastAction: { fontSize: 15, fontWeight: '700' },
});
```

---

## 7. Onboarding Flow (Progressive Disclosure)

A multi-step onboarding with page indicator and skip option.

```tsx
import { useState, useRef } from 'react';
import {
  StyleSheet,
  Text,
  View,
  Pressable,
  Dimensions,
  FlatList,
} from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  interpolate,
  interpolateColor,
  useAnimatedScrollHandler,
} from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { useTheme } from '@/lib/theme';
import { storage } from '@/lib/storage';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

interface OnboardingPage {
  icon: string;
  title: string;
  description: string;
  color: string;
}

const PAGES: OnboardingPage[] = [
  {
    icon: '👋',
    title: 'Welcome',
    description: 'Discover a better way to organize your daily life.',
    color: '#3B82F6',
  },
  {
    icon: '🎯',
    title: 'Stay Focused',
    description: 'Track your goals and build habits that stick.',
    color: '#8B5CF6',
  },
  {
    icon: '🚀',
    title: 'Get Started',
    description: 'Create your first project and start making progress.',
    color: '#10B981',
  },
];

function OnboardingFlow({ onComplete }: { onComplete: () => void }) {
  const theme = useTheme();
  const flatListRef = useRef<FlatList>(null);
  const scrollX = useSharedValue(0);
  const [currentPage, setCurrentPage] = useState(0);

  const scrollHandler = useAnimatedScrollHandler({
    onScroll: (e) => {
      scrollX.value = e.contentOffset.x;
    },
  });

  const handleNext = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    if (currentPage < PAGES.length - 1) {
      flatListRef.current?.scrollToIndex({ index: currentPage + 1 });
      setCurrentPage(currentPage + 1);
    } else {
      completeOnboarding();
    }
  };

  const handleSkip = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    completeOnboarding();
  };

  const completeOnboarding = () => {
    storage.set('onboarding.completed', true);
    onComplete();
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.colors.background }]}>
      {/* Skip button */}
      <View style={styles.skipContainer}>
        {currentPage < PAGES.length - 1 && (
          <Pressable onPress={handleSkip} hitSlop={12}>
            <Text style={[styles.skipText, { color: theme.colors.textSecondary }]}>
              Skip
            </Text>
          </Pressable>
        )}
      </View>

      {/* Pages */}
      <Animated.FlatList
        ref={flatListRef}
        data={PAGES}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        scrollEventThrottle={16}
        onScroll={scrollHandler}
        onMomentumScrollEnd={(e) => {
          const page = Math.round(e.nativeEvent.contentOffset.x / SCREEN_WIDTH);
          setCurrentPage(page);
        }}
        renderItem={({ item, index }) => (
          <OnboardingPage page={item} index={index} scrollX={scrollX} />
        )}
        keyExtractor={(_, i) => i.toString()}
      />

      {/* Page indicator */}
      <View style={styles.indicatorContainer}>
        {PAGES.map((_, i) => (
          <PageDot key={i} index={i} scrollX={scrollX} />
        ))}
      </View>

      {/* Next / Get Started button */}
      <View style={styles.buttonContainer}>
        <Pressable
          style={[styles.button, { backgroundColor: PAGES[currentPage].color }]}
          onPress={handleNext}
        >
          <Text style={styles.buttonText}>
            {currentPage === PAGES.length - 1 ? 'Get Started' : 'Next'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

function OnboardingPage({
  page,
  index,
  scrollX,
}: {
  page: OnboardingPage;
  index: number;
  scrollX: Animated.SharedValue<number>;
}) {
  const theme = useTheme();

  const style = useAnimatedStyle(() => {
    const inputRange = [
      (index - 1) * SCREEN_WIDTH,
      index * SCREEN_WIDTH,
      (index + 1) * SCREEN_WIDTH,
    ];

    return {
      opacity: interpolate(scrollX.value, inputRange, [0.5, 1, 0.5]),
      transform: [
        { scale: interpolate(scrollX.value, inputRange, [0.8, 1, 0.8]) },
        {
          translateY: interpolate(scrollX.value, inputRange, [20, 0, 20]),
        },
      ],
    };
  });

  return (
    <Animated.View style={[styles.page, style]}>
      <Text style={styles.pageIcon}>{page.icon}</Text>
      <Text style={[styles.pageTitle, { color: theme.colors.text }]}>
        {page.title}
      </Text>
      <Text style={[styles.pageDescription, { color: theme.colors.textSecondary }]}>
        {page.description}
      </Text>
    </Animated.View>
  );
}

function PageDot({
  index,
  scrollX,
}: {
  index: number;
  scrollX: Animated.SharedValue<number>;
}) {
  const style = useAnimatedStyle(() => {
    const inputRange = [
      (index - 1) * SCREEN_WIDTH,
      index * SCREEN_WIDTH,
      (index + 1) * SCREEN_WIDTH,
    ];

    return {
      width: interpolate(scrollX.value, inputRange, [8, 24, 8], 'clamp'),
      opacity: interpolate(scrollX.value, inputRange, [0.3, 1, 0.3], 'clamp'),
    };
  });

  return (
    <Animated.View
      style={[
        styles.dot,
        { backgroundColor: PAGES[index].color },
        style,
      ]}
    />
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  skipContainer: {
    position: 'absolute',
    top: 60,
    right: 24,
    zIndex: 10,
  },
  skipText: { fontSize: 16, fontWeight: '500' },
  page: {
    width: SCREEN_WIDTH,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  pageIcon: { fontSize: 80, marginBottom: 32 },
  pageTitle: { fontSize: 28, fontWeight: '800', textAlign: 'center', marginBottom: 12 },
  pageDescription: {
    fontSize: 17,
    textAlign: 'center',
    lineHeight: 24,
    paddingHorizontal: 16,
  },
  indicatorContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
    paddingBottom: 32,
  },
  dot: { height: 8, borderRadius: 4 },
  buttonContainer: { paddingHorizontal: 24, paddingBottom: 48 },
  button: {
    paddingVertical: 18,
    borderRadius: 16,
    alignItems: 'center',
  },
  buttonText: { color: '#fff', fontSize: 18, fontWeight: '700' },
});

export { OnboardingFlow };
```

---

## 8. Keyboard-Aware Form

Form that stays visible and accessible when the keyboard opens.

```tsx
import { useRef } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  Pressable,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import { useTheme } from '@/lib/theme';

function KeyboardAwareForm({
  onSubmit,
}: {
  onSubmit: (data: { name: string; email: string; message: string }) => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const emailRef = useRef<TextInput>(null);
  const messageRef = useRef<TextInput>(null);
  const scrollRef = useRef<ScrollView>(null);

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState('');

  const handleSubmit = () => {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    onSubmit({ name, email, message });
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={Platform.OS === 'ios' ? 88 : 0}
    >
      <ScrollView
        ref={scrollRef}
        contentContainerStyle={[
          styles.scrollContent,
          { paddingBottom: insets.bottom + 24 },
        ]}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        {/* Name field */}
        <View style={styles.field}>
          <Text style={[styles.label, { color: theme.colors.text }]}>
            Name
          </Text>
          <TextInput
            style={[
              styles.input,
              {
                backgroundColor: theme.colors.surface,
                color: theme.colors.text,
                borderColor: theme.colors.border,
              },
            ]}
            value={name}
            onChangeText={setName}
            placeholder="Your name"
            placeholderTextColor={theme.colors.textTertiary}
            returnKeyType="next"
            onSubmitEditing={() => emailRef.current?.focus()}
            autoCapitalize="words"
            autoCorrect={false}
          />
        </View>

        {/* Email field */}
        <View style={styles.field}>
          <Text style={[styles.label, { color: theme.colors.text }]}>
            Email
          </Text>
          <TextInput
            ref={emailRef}
            style={[
              styles.input,
              {
                backgroundColor: theme.colors.surface,
                color: theme.colors.text,
                borderColor: theme.colors.border,
              },
            ]}
            value={email}
            onChangeText={setEmail}
            placeholder="you@example.com"
            placeholderTextColor={theme.colors.textTertiary}
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="next"
            onSubmitEditing={() => messageRef.current?.focus()}
          />
        </View>

        {/* Message field */}
        <View style={styles.field}>
          <Text style={[styles.label, { color: theme.colors.text }]}>
            Message
          </Text>
          <TextInput
            ref={messageRef}
            style={[
              styles.input,
              styles.textArea,
              {
                backgroundColor: theme.colors.surface,
                color: theme.colors.text,
                borderColor: theme.colors.border,
              },
            ]}
            value={message}
            onChangeText={setMessage}
            placeholder="What's on your mind?"
            placeholderTextColor={theme.colors.textTertiary}
            multiline
            numberOfLines={4}
            textAlignVertical="top"
            returnKeyType="done"
            blurOnSubmit
            onFocus={() => {
              // Scroll to keep the field visible
              setTimeout(() => {
                scrollRef.current?.scrollToEnd({ animated: true });
              }, 200);
            }}
          />
        </View>

        {/* Submit button */}
        <Pressable
          style={[
            styles.submitButton,
            { backgroundColor: theme.colors.primary },
            (!name || !email) && styles.submitDisabled,
          ]}
          onPress={handleSubmit}
          disabled={!name || !email}
        >
          <Text style={styles.submitText}>Send Message</Text>
        </Pressable>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  scrollContent: { padding: 24, gap: 20 },
  field: { gap: 6 },
  label: { fontSize: 15, fontWeight: '600' },
  input: {
    height: 48,
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 16,
    fontSize: 16,
  },
  textArea: {
    height: 120,
    paddingTop: 14,
    paddingBottom: 14,
  },
  submitButton: {
    height: 52,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 8,
  },
  submitDisabled: { opacity: 0.5 },
  submitText: { color: '#fff', fontSize: 17, fontWeight: '700' },
});

export { KeyboardAwareForm };
```

### Form Best Practices

- **`returnKeyType`** — use `"next"` to chain focus between fields, `"done"` on the last field
- **`keyboardShouldPersistTaps="handled"`** — allows tapping buttons while keyboard is open
- **`autoCapitalize`** — `"words"` for names, `"none"` for email/password
- **`keyboardType`** — `"email-address"`, `"numeric"`, `"phone-pad"` for appropriate keyboards
- **`textContentType`** (iOS) — `"name"`, `"emailAddress"`, `"password"` for autofill
- **`autoComplete`** (Android) — `"name"`, `"email"`, `"password"` for autofill
- **Scroll on focus** — scroll the form to keep the focused field visible above the keyboard
