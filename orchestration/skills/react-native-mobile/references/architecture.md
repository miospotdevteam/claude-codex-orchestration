# Architecture Patterns

Feature-based folder structure, Expo Router navigation, state management
(Zustand + TanStack Query), storage tiers (MMKV → SQLite → WatermelonDB),
offline-first patterns, and complete application skeleton.

---

## 1. Feature-Based Folder Structure

```
app/                          # Expo Router file-based routing
  _layout.tsx                 # Root layout (providers, fonts, splash)
  (tabs)/                     # Tab navigator group
    _layout.tsx               # Tab bar configuration
    index.tsx                 # Home tab
    search.tsx                # Search tab
    profile.tsx               # Profile tab
  (auth)/                     # Auth group (no tabs)
    _layout.tsx               # Auth layout (no back gesture)
    sign-in.tsx
    sign-up.tsx
    forgot-password.tsx
  [id].tsx                    # Dynamic route
  modal.tsx                   # Presented as modal
  +not-found.tsx              # 404 screen

src/
  features/                   # Feature modules
    home/
      components/             # Feature-specific components
        FeedCard.tsx
        StoryRow.tsx
      hooks/
        useFeed.ts
      api/
        feed.ts               # TanStack Query hooks for this feature
    profile/
      components/
      hooks/
      api/

  components/                 # Shared UI components
    ui/                       # Design system primitives
      Button.tsx
      Text.tsx
      Card.tsx
      Input.tsx
      Spacer.tsx
    layout/
      Screen.tsx              # SafeAreaView + StatusBar wrapper
      KeyboardScreen.tsx      # Keyboard-aware screen wrapper

  lib/                        # Utilities and configuration
    api-client.ts             # Fetch wrapper with auth
    storage.ts                # MMKV instance and helpers
    haptics.ts                # Haptic feedback wrapper
    theme.ts                  # Color tokens, spacing, typography
    constants.ts              # App-wide constants

  stores/                     # Zustand stores
    auth.ts
    preferences.ts

  types/                      # Shared TypeScript types
    api.ts
    navigation.ts
```

### Naming Conventions

- **Components**: PascalCase (`FeedCard.tsx`)
- **Hooks**: camelCase with `use` prefix (`useFeed.ts`)
- **Utilities**: camelCase (`haptics.ts`)
- **Platform-specific**: suffix with `.ios.tsx` / `.android.tsx`
- **Test files**: colocated as `ComponentName.test.tsx`

---

## 2. Expo Router Navigation

### Root Layout (Providers + Initialization)

```tsx
// app/_layout.tsx
import { Slot, SplashScreen } from 'expo-router';
import { useEffect } from 'react';
import { useFonts } from 'expo-font';
import { ThemeProvider } from '@/lib/theme';
import { QueryProvider } from '@/lib/query';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    'Inter-Regular': require('@/assets/fonts/Inter-Regular.otf'),
    'Inter-Medium': require('@/assets/fonts/Inter-Medium.otf'),
    'Inter-Bold': require('@/assets/fonts/Inter-Bold.otf'),
  });

  useEffect(() => {
    if (fontsLoaded) {
      SplashScreen.hideAsync();
    }
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <QueryProvider>
        <ThemeProvider>
          <Slot />
        </ThemeProvider>
      </QueryProvider>
    </GestureHandlerRootView>
  );
}
```

### Tab Navigator

```tsx
// app/(tabs)/_layout.tsx
import { Tabs } from 'expo-router';
import { Platform } from 'react-native';
import { useTheme } from '@/lib/theme';
import * as Haptics from 'expo-haptics';

export default function TabLayout() {
  const theme = useTheme();

  return (
    <Tabs
      screenOptions={{
        tabBarActiveTintColor: theme.colors.primary,
        tabBarInactiveTintColor: theme.colors.textTertiary,
        tabBarStyle: {
          backgroundColor: theme.colors.surface,
          borderTopColor: theme.colors.border,
          ...(Platform.OS === 'ios' && {
            position: 'absolute',
            backgroundColor: 'transparent',
          }),
        },
        tabBarLabelStyle: {
          fontSize: 11,
          fontFamily: 'Inter-Medium',
        },
        headerShown: false,
      }}
      screenListeners={{
        tabPress: () => {
          Haptics.selectionAsync();
        },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Home',
          tabBarIcon: ({ color, size }) => (
            <HomeIcon color={color} size={size} />
          ),
        }}
      />
      <Tabs.Screen
        name="search"
        options={{
          title: 'Search',
          tabBarIcon: ({ color, size }) => (
            <SearchIcon color={color} size={size} />
          ),
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          title: 'Profile',
          tabBarIcon: ({ color, size }) => (
            <ProfileIcon color={color} size={size} />
          ),
        }}
      />
    </Tabs>
  );
}
```

### Auth Guard

```tsx
// app/(auth)/_layout.tsx
import { Redirect, Stack } from 'expo-router';
import { useAuthStore } from '@/stores/auth';

export default function AuthLayout() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);

  if (isAuthenticated) {
    return <Redirect href="/(tabs)" />;
  }

  return (
    <Stack screenOptions={{ headerShown: false, gestureEnabled: false }} />
  );
}
```

### Deep Linking

```json
// app.json
{
  "expo": {
    "scheme": "myapp",
    "plugins": [
      [
        "expo-router",
        {
          "origin": "https://myapp.com"
        }
      ]
    ]
  }
}
```

### Modal Presentation

```tsx
// app/_layout.tsx — add modal route to root stack
import { Stack } from 'expo-router';

export default function RootLayout() {
  return (
    <Stack>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="(auth)" options={{ headerShown: false }} />
      <Stack.Screen
        name="modal"
        options={{
          presentation: 'modal',
          headerShown: false,
        }}
      />
    </Stack>
  );
}
```

---

## 3. State Management

### Zustand — Client State

```tsx
// src/stores/auth.ts
import { create } from 'zustand';
import { storage } from '@/lib/storage';

interface AuthState {
  token: string | null;
  isAuthenticated: boolean;
  setToken: (token: string) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  token: storage.getString('auth.token') ?? null,
  isAuthenticated: storage.contains('auth.token'),

  setToken: (token) => {
    storage.set('auth.token', token);
    set({ token, isAuthenticated: true });
  },

  logout: () => {
    storage.delete('auth.token');
    set({ token: null, isAuthenticated: false });
  },
}));
```

### TanStack Query — Server State

```tsx
// src/lib/query.ts
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      gcTime: 1000 * 60 * 30,   // 30 minutes
      retry: 2,
      refetchOnWindowFocus: true,
    },
  },
});

export function QueryProvider({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}
```

```tsx
// src/features/home/api/feed.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/lib/api-client';

interface FeedItem {
  id: string;
  title: string;
  body: string;
  createdAt: string;
}

export function useFeed() {
  return useQuery({
    queryKey: ['feed'],
    queryFn: () => apiClient.get<FeedItem[]>('/feed'),
  });
}

export function useLikePost() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (postId: string) => apiClient.post(`/feed/${postId}/like`),

    // Optimistic update
    onMutate: async (postId) => {
      await queryClient.cancelQueries({ queryKey: ['feed'] });
      const previous = queryClient.getQueryData<FeedItem[]>(['feed']);

      queryClient.setQueryData<FeedItem[]>(['feed'], (old) =>
        old?.map((item) =>
          item.id === postId ? { ...item, isLiked: true } : item
        )
      );

      return { previous };
    },

    onError: (_err, _postId, context) => {
      queryClient.setQueryData(['feed'], context?.previous);
    },

    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['feed'] });
    },
  });
}
```

---

## 4. Storage Tiers

### Tier 1: MMKV — Fast Key-Value (default)

Use for: auth tokens, user preferences, feature flags, cached IDs,
small JSON blobs. Synchronous, 30x faster than AsyncStorage.

```tsx
// src/lib/storage.ts
import { MMKV } from 'react-native-mmkv';

export const storage = new MMKV({ id: 'app-storage' });

// Typed helpers
export const Storage = {
  getString: (key: string) => storage.getString(key),
  setString: (key: string, value: string) => storage.set(key, value),
  getNumber: (key: string) => storage.getNumber(key),
  setNumber: (key: string, value: number) => storage.set(key, value),
  getBoolean: (key: string) => storage.getBoolean(key),
  setBoolean: (key: string, value: boolean) => storage.set(key, value),
  getObject: <T>(key: string): T | null => {
    const json = storage.getString(key);
    return json ? JSON.parse(json) : null;
  },
  setObject: <T>(key: string, value: T) => {
    storage.set(key, JSON.stringify(value));
  },
  delete: (key: string) => storage.delete(key),
  contains: (key: string) => storage.contains(key),
  clearAll: () => storage.clearAll(),
};
```

### Tier 2: expo-sqlite — Structured Data

Use for: large datasets, complex queries, relationships, full-text search,
data that needs indexing.

```tsx
// src/lib/database.ts
import * as SQLite from 'expo-sqlite';

const db = SQLite.openDatabaseSync('app.db');

// Run migrations on app start
export function initDatabase() {
  db.execSync(`
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      conversationId TEXT NOT NULL,
      body TEXT NOT NULL,
      senderId TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      syncedAt TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_messages_conversation
      ON messages(conversationId, createdAt);
  `);
}

// Typed query helper
export function getMessages(conversationId: string) {
  return db.getAllSync<Message>(
    'SELECT * FROM messages WHERE conversationId = ? ORDER BY createdAt DESC LIMIT 50',
    [conversationId]
  );
}
```

### Tier 3: WatermelonDB — Offline-First with Sync

Use for: apps that need robust offline support with background sync,
conflict resolution, and large datasets (thousands of records).

```tsx
// Only reach for WatermelonDB when you need:
// - Lazy-loaded collections (doesn't load all records into memory)
// - Built-in sync protocol (push/pull with conflict resolution)
// - Reactive queries (UI updates automatically when data changes)
// - Relations between models

// Most apps should start with MMKV + TanStack Query and only
// add WatermelonDB if offline-first with sync is a core requirement.
```

### Decision Guide

| Data Type | Size | Access Pattern | Use |
|-----------|------|----------------|-----|
| Auth token, preferences | < 1KB | Read on startup | MMKV |
| User profile, settings | 1-10KB | Read/write occasionally | MMKV |
| Search history, recent items | 10-100KB | Append, query recent | MMKV (JSON) |
| Messages, posts, products | > 100KB | Query, filter, search | expo-sqlite |
| Full offline app with sync | Any | Read/write offline, sync later | WatermelonDB |

---

## 5. Offline-First Patterns

### Optimistic Updates with TanStack Query

The core pattern: update UI immediately, sync in the background, revert
on failure.

```tsx
// See the useLikePost() example in section 3 above.
// The pattern is:
// 1. Cancel in-flight queries (prevent overwrites)
// 2. Snapshot current data (for rollback)
// 3. Optimistically update the cache
// 4. On error: roll back to snapshot
// 5. On settled: invalidate to get server truth
```

### Network Status Awareness

```tsx
// src/hooks/useNetworkStatus.ts
import NetInfo from '@react-native-community/netinfo';
import { useEffect, useState } from 'react';
import { onlineManager } from '@tanstack/react-query';

export function useNetworkStatus() {
  const [isConnected, setIsConnected] = useState(true);

  useEffect(() => {
    return NetInfo.addEventListener((state) => {
      const connected = state.isConnected ?? true;
      setIsConnected(connected);
      // TanStack Query pauses mutations when offline
      onlineManager.setOnline(connected);
    });
  }, []);

  return isConnected;
}
```

### Offline Queue for Mutations

```tsx
// src/lib/offline-queue.ts
import { storage } from '@/lib/storage';

interface QueuedMutation {
  id: string;
  endpoint: string;
  method: 'POST' | 'PUT' | 'DELETE';
  body: unknown;
  createdAt: number;
}

const QUEUE_KEY = 'offline-mutation-queue';

export const offlineQueue = {
  add(mutation: Omit<QueuedMutation, 'id' | 'createdAt'>) {
    const queue = this.getAll();
    queue.push({
      ...mutation,
      id: Math.random().toString(36).slice(2),
      createdAt: Date.now(),
    });
    storage.set(QUEUE_KEY, JSON.stringify(queue));
  },

  getAll(): QueuedMutation[] {
    const json = storage.getString(QUEUE_KEY);
    return json ? JSON.parse(json) : [];
  },

  remove(id: string) {
    const queue = this.getAll().filter((m) => m.id !== id);
    storage.set(QUEUE_KEY, JSON.stringify(queue));
  },

  async flush(apiClient: { request: (url: string, opts: unknown) => Promise<unknown> }) {
    const queue = this.getAll();
    for (const mutation of queue) {
      try {
        await apiClient.request(mutation.endpoint, {
          method: mutation.method,
          body: mutation.body,
        });
        this.remove(mutation.id);
      } catch {
        break; // Stop on first failure, retry later
      }
    }
  },
};
```

---

## 6. Complete Application Skeleton

```tsx
// app/_layout.tsx — the orchestrator
import { useEffect } from 'react';
import { Stack, SplashScreen } from 'expo-router';
import { useFonts } from 'expo-font';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { QueryProvider } from '@/lib/query';
import { ThemeProvider, useTheme } from '@/lib/theme';
import { initDatabase } from '@/lib/database';

SplashScreen.preventAutoHideAsync();

function AppContent() {
  const theme = useTheme();
  const [fontsLoaded] = useFonts({
    'Inter-Regular': require('@/assets/fonts/Inter-Regular.otf'),
    'Inter-Medium': require('@/assets/fonts/Inter-Medium.otf'),
    'Inter-Bold': require('@/assets/fonts/Inter-Bold.otf'),
  });

  useEffect(() => {
    initDatabase();
  }, []);

  useEffect(() => {
    if (fontsLoaded) {
      SplashScreen.hideAsync();
    }
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: theme.colors.surface },
        headerTintColor: theme.colors.text,
        headerTitleStyle: { fontFamily: 'Inter-Bold' },
        contentStyle: { backgroundColor: theme.colors.background },
      }}
    >
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="(auth)" options={{ headerShown: false }} />
      <Stack.Screen
        name="modal"
        options={{ presentation: 'modal', headerShown: false }}
      />
    </Stack>
  );
}

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <QueryProvider>
        <ThemeProvider>
          <AppContent />
        </ThemeProvider>
      </QueryProvider>
    </GestureHandlerRootView>
  );
}
```

### Screen Wrapper Component

```tsx
// src/components/layout/Screen.tsx
import { View, StyleSheet, StatusBar, Platform } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '@/lib/theme';

interface ScreenProps {
  children: React.ReactNode;
  edges?: ('top' | 'bottom' | 'left' | 'right')[];
  statusBarStyle?: 'light' | 'dark';
}

export function Screen({
  children,
  edges = ['top'],
  statusBarStyle,
}: ScreenProps) {
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const barStyle = statusBarStyle ?? (theme.isDark ? 'light' : 'dark');

  return (
    <View
      style={[
        styles.container,
        { backgroundColor: theme.colors.background },
        edges.includes('top') && { paddingTop: insets.top },
        edges.includes('bottom') && { paddingBottom: insets.bottom },
      ]}
    >
      <StatusBar
        barStyle={`${barStyle}-content`}
        backgroundColor={
          Platform.OS === 'android' ? theme.colors.background : undefined
        }
      />
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
});
```

### Theme System

```tsx
// src/lib/theme.ts
import { createContext, useContext } from 'react';
import { useColorScheme } from 'react-native';

const palette = {
  blue500: '#3B82F6',
  blue600: '#2563EB',
  gray50: '#F9FAFB',
  gray100: '#F3F4F6',
  gray200: '#E5E7EB',
  gray400: '#9CA3AF',
  gray500: '#6B7280',
  gray800: '#1F2937',
  gray900: '#111827',
  gray950: '#030712',
  white: '#FFFFFF',
  black: '#000000',
  red500: '#EF4444',
  green500: '#22C55E',
};

const lightTheme = {
  isDark: false,
  colors: {
    primary: palette.blue600,
    background: palette.white,
    surface: palette.gray50,
    surfaceElevated: palette.white,
    text: palette.gray900,
    textSecondary: palette.gray500,
    textTertiary: palette.gray400,
    border: palette.gray200,
    error: palette.red500,
    success: palette.green500,
  },
  spacing: { xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48 },
  radius: { sm: 6, md: 10, lg: 16, xl: 24, full: 9999 },
  typography: {
    largeTitle: { fontSize: 34, lineHeight: 41, fontFamily: 'Inter-Bold' },
    title1: { fontSize: 28, lineHeight: 34, fontFamily: 'Inter-Bold' },
    title2: { fontSize: 22, lineHeight: 28, fontFamily: 'Inter-Bold' },
    title3: { fontSize: 20, lineHeight: 25, fontFamily: 'Inter-Medium' },
    headline: { fontSize: 17, lineHeight: 22, fontFamily: 'Inter-Medium' },
    body: { fontSize: 17, lineHeight: 22, fontFamily: 'Inter-Regular' },
    callout: { fontSize: 16, lineHeight: 21, fontFamily: 'Inter-Regular' },
    subhead: { fontSize: 15, lineHeight: 20, fontFamily: 'Inter-Regular' },
    footnote: { fontSize: 13, lineHeight: 18, fontFamily: 'Inter-Regular' },
    caption1: { fontSize: 12, lineHeight: 16, fontFamily: 'Inter-Regular' },
    caption2: { fontSize: 11, lineHeight: 13, fontFamily: 'Inter-Medium' },
  },
} as const;

const darkTheme = {
  ...lightTheme,
  isDark: true,
  colors: {
    ...lightTheme.colors,
    primary: palette.blue500,
    background: palette.black,
    surface: palette.gray950,
    surfaceElevated: palette.gray900,
    text: palette.white,
    textSecondary: palette.gray400,
    textTertiary: palette.gray500,
    border: palette.gray800,
  },
} as const;

export type Theme = typeof lightTheme;

const ThemeContext = createContext<Theme>(lightTheme);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const scheme = useColorScheme();
  const theme = scheme === 'dark' ? darkTheme : lightTheme;

  return (
    <ThemeContext.Provider value={theme}>{children}</ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
```

### Haptics Wrapper

```tsx
// src/lib/haptics.ts
import * as Haptics from 'expo-haptics';

// Safe to call on both platforms
export const haptics = {
  /** Light tap — toggle, selection change */
  light: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light),
  /** Medium tap — button press, drag snap */
  medium: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium),
  /** Heavy tap — significant action, drop into place */
  heavy: () => Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy),
  /** Selection tick — picker scroll, stepping through values */
  selection: () => Haptics.selectionAsync(),
  /** Success — task completed, saved */
  success: () =>
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success),
  /** Warning — destructive action confirmation */
  warning: () =>
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning),
  /** Error — action failed */
  error: () =>
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error),
};
```
