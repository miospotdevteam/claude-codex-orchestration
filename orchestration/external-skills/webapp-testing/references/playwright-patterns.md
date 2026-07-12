# Playwright Patterns Reference

Practical patterns for writing reliable, maintainable Playwright tests.
This is a reference file — read it when writing test code, not upfront.

---

## Selector Strategies

Prefer selectors in this order. Higher is better — more resilient to
refactors, more accessible, and more readable.

### 1. Role-based selectors (preferred)

```typescript
// Buttons
page.getByRole('button', { name: 'Submit' })
page.getByRole('button', { name: /submit/i })  // case-insensitive

// Links
page.getByRole('link', { name: 'Home' })

// Headings
page.getByRole('heading', { name: 'Dashboard', level: 1 })

// Form inputs
page.getByLabel('Email address')
page.getByPlaceholder('Enter your email')

// Text content
page.getByText('Welcome back')
page.getByText(/welcome/i)  // partial, case-insensitive

// Combo: label + role
page.getByRole('textbox', { name: 'Email' })
page.getByRole('combobox', { name: 'Country' })
page.getByRole('checkbox', { name: 'Accept terms' })
```

**Why role-based:** These selectors mirror how assistive technology and
users perceive the page. If a role-based selector can't find an element,
it usually means the HTML has an accessibility problem worth fixing.

### 2. Test ID selectors (when roles aren't sufficient)

```typescript
// For elements without semantic roles
page.getByTestId('sidebar-toggle')
page.getByTestId('user-avatar')

// Configure the test ID attribute in playwright.config.ts:
// use: { testIdAttribute: 'data-testid' }
```

Use `data-testid` when:
- The element has no meaningful role or label
- Multiple identical elements exist and you need a specific one
- The component is a custom widget without ARIA roles

### 3. CSS selectors (last resort)

```typescript
// Only when no semantic alternative exists
page.locator('.custom-chart-container')
page.locator('#unique-element')

// Combining with has/hasText for precision
page.locator('div').filter({ hasText: 'Total' })
page.locator('tr').filter({ has: page.getByText('Active') })
```

### Avoid: XPath

XPath selectors are fragile, hard to read, and break on any DOM change.
Never use them unless you're scraping a third-party page you don't control.

### Avoid: nth-child / CSS structural selectors

```typescript
// Bad — breaks if order changes
page.locator('.card:nth-child(2)')

// Good — identify by content or test ID
page.locator('.card').filter({ hasText: 'Premium Plan' })
```

---

## Assertions

### Element state assertions

```typescript
// Visibility
await expect(page.getByText('Success')).toBeVisible();
await expect(page.getByText('Loading')).toBeHidden();

// Enabled/disabled
await expect(page.getByRole('button', { name: 'Submit' })).toBeEnabled();
await expect(page.getByRole('button', { name: 'Submit' })).toBeDisabled();

// Checked (checkboxes, radio buttons)
await expect(page.getByRole('checkbox', { name: 'Agree' })).toBeChecked();
await expect(page.getByRole('checkbox', { name: 'Agree' })).not.toBeChecked();

// Focused
await expect(page.getByLabel('Search')).toBeFocused();
```

### Content assertions

```typescript
// Text content
await expect(page.getByRole('heading')).toHaveText('Dashboard');
await expect(page.getByRole('heading')).toContainText('Dash');

// Input values
await expect(page.getByLabel('Name')).toHaveValue('John');
await expect(page.getByLabel('Name')).toHaveValue(/john/i);

// Attributes
await expect(page.getByRole('link')).toHaveAttribute('href', '/home');

// CSS classes
await expect(page.locator('.card')).toHaveClass(/active/);

// Count
await expect(page.getByRole('listitem')).toHaveCount(5);
```

### Page-level assertions

```typescript
// URL
await expect(page).toHaveURL('/dashboard');
await expect(page).toHaveURL(/\/dashboard/);

// Title
await expect(page).toHaveTitle('My App - Dashboard');

// Screenshots (visual regression)
await expect(page).toHaveScreenshot('dashboard.png');
await expect(page.getByTestId('chart')).toHaveScreenshot('chart.png');
```

### Soft assertions (non-blocking)

```typescript
// Collect multiple failures instead of stopping at first
await expect.soft(page.getByText('Name')).toBeVisible();
await expect.soft(page.getByText('Email')).toBeVisible();
await expect.soft(page.getByText('Phone')).toBeVisible();
// Test continues even if one fails — all failures reported at end
```

---

## Waiting Strategies

### Auto-wait (default — use this)

Playwright automatically waits for elements to be actionable before
interacting. These all auto-wait:

```typescript
// These wait for the element to exist, be visible, and be stable
await page.getByRole('button', { name: 'Submit' }).click();
await page.getByLabel('Email').fill('test@example.com');
await expect(page.getByText('Success')).toBeVisible();
```

Default timeout is 30 seconds (configurable in `playwright.config.ts`).
Auto-wait handles most cases — add explicit waits only when needed.

### Waiting for network

```typescript
// Wait for a specific API response
const responsePromise = page.waitForResponse('**/api/users');
await page.getByRole('button', { name: 'Load Users' }).click();
const response = await responsePromise;
expect(response.status()).toBe(200);

// Wait for a specific request
const requestPromise = page.waitForRequest('**/api/submit');
await page.getByRole('button', { name: 'Submit' }).click();
const request = await requestPromise;
expect(request.method()).toBe('POST');

// Wait for network to settle (use sparingly)
await page.waitForLoadState('networkidle');
```

### Waiting for navigation

```typescript
// Wait for navigation after click
await page.getByRole('link', { name: 'Dashboard' }).click();
await page.waitForURL('/dashboard');

// Wait for navigation with pattern
await page.waitForURL(/\/dashboard/);
```

### Explicit waits (when auto-wait isn't enough)

```typescript
// Wait for element to appear in DOM (even if hidden)
await page.waitForSelector('[data-loaded="true"]');

// Wait for a function to return truthy
await page.waitForFunction(() => {
  return document.querySelectorAll('.item').length >= 10;
});

// Hardcoded timeout — absolute last resort
await page.waitForTimeout(1000);  // Avoid if possible
```

### networkidle pitfalls

`waitForLoadState('networkidle')` waits for no network requests for
500ms. Problems:
- Polling endpoints (analytics, WebSockets) prevent it from resolving
- Long-polling APIs keep it waiting forever
- It's slow by design (adds 500ms minimum)

**Prefer:** Wait for specific UI elements or API responses instead of
networkidle. Only use it for server-rendered pages with no polling.

---

## Page Object Model

For large test suites, encapsulate page interactions in page objects.

```typescript
// pages/login-page.ts
import { type Locator, type Page, expect } from '@playwright/test';

export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.getByLabel('Email');
    this.passwordInput = page.getByLabel('Password');
    this.submitButton = page.getByRole('button', { name: 'Sign in' });
    this.errorMessage = page.getByRole('alert');
  }

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }

  async expectError(message: string) {
    await expect(this.errorMessage).toHaveText(message);
  }

  async expectLoggedIn() {
    await expect(this.page).toHaveURL('/dashboard');
  }
}
```

```typescript
// tests/auth.spec.ts
import { test } from '@playwright/test';
import { LoginPage } from '../pages/login-page';

test('successful login', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.goto();
  await loginPage.login('user@example.com', 'password123');
  await loginPage.expectLoggedIn();
});

test('invalid credentials', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.goto();
  await loginPage.login('user@example.com', 'wrong');
  await loginPage.expectError('Invalid email or password');
});
```

**When to use Page Objects:**
- Test suite has 10+ tests for the same pages
- Multiple tests share the same interaction patterns
- Page structure is complex with many elements

**When to skip Page Objects:**
- Small test suite (< 10 tests)
- Each test covers a unique page
- Quick smoke tests

---

## Authentication State Reuse

Avoid logging in before every test. Save and reuse auth state.

### Setup: create auth state file

```typescript
// auth.setup.ts — runs once before all tests
import { test as setup } from '@playwright/test';

setup('authenticate', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('test@example.com');
  await page.getByLabel('Password').fill('password123');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL('/dashboard');

  // Save storage state (cookies + localStorage)
  await page.context().storageState({ path: '.auth/user.json' });
});
```

### Configure in playwright.config.ts

```typescript
export default defineConfig({
  projects: [
    // Setup project — runs first
    { name: 'setup', testMatch: /.*\.setup\.ts/ },

    // Tests use saved auth state
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
});
```

### Tests start already authenticated

```typescript
test('dashboard loads', async ({ page }) => {
  // No login needed — storage state is pre-loaded
  await page.goto('/dashboard');
  await expect(page.getByRole('heading')).toHaveText('Dashboard');
});
```

**Add `.auth/` to `.gitignore`** — auth state files contain session tokens.

---

## Screenshot and Visual Comparison

### Full page screenshots

```typescript
test('landing page', async ({ page }) => {
  await page.goto('/');
  // Disable animations for deterministic screenshots
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(page).toHaveScreenshot('landing.png', {
    fullPage: true,
    maxDiffPixelRatio: 0.01,
  });
});
```

### Component screenshots

```typescript
test('pricing cards', async ({ page }) => {
  await page.goto('/pricing');
  const cards = page.getByTestId('pricing-section');
  await expect(cards).toHaveScreenshot('pricing.png');
});
```

### Masking dynamic content

```typescript
test('dashboard with masked dynamic content', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page).toHaveScreenshot('dashboard.png', {
    mask: [
      page.getByTestId('timestamp'),
      page.getByTestId('random-avatar'),
      page.locator('.live-counter'),
    ],
  });
});
```

### Update baselines

```bash
# Update all snapshots
npx playwright test --update-snapshots

# Update snapshots for specific test
npx playwright test tests/visual.spec.ts --update-snapshots
```

---

## Network Mocking

### Mock API responses

```typescript
test('displays user list from API', async ({ page }) => {
  // Intercept API call and return mock data
  await page.route('**/api/users', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 1, name: 'Alice' },
        { id: 2, name: 'Bob' },
      ]),
    });
  });

  await page.goto('/users');
  await expect(page.getByRole('listitem')).toHaveCount(2);
  await expect(page.getByText('Alice')).toBeVisible();
});
```

### Mock error responses

```typescript
test('handles API error gracefully', async ({ page }) => {
  await page.route('**/api/users', async (route) => {
    await route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ error: 'Internal server error' }),
    });
  });

  await page.goto('/users');
  await expect(page.getByText('Something went wrong')).toBeVisible();
});
```

### Mock slow responses

```typescript
test('shows loading state', async ({ page }) => {
  await page.route('**/api/data', async (route) => {
    // Delay response by 2 seconds
    await new Promise((resolve) => setTimeout(resolve, 2000));
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ items: [] }),
    });
  });

  await page.goto('/data');
  // Loading state should be visible during the delay
  await expect(page.getByText('Loading...')).toBeVisible();
  // Then it resolves
  await expect(page.getByText('No items found')).toBeVisible();
});
```

### Modify real responses (passthrough with modification)

```typescript
await page.route('**/api/config', async (route) => {
  const response = await route.fetch();
  const json = await response.json();
  // Modify the real response
  json.featureFlags.newDashboard = true;
  await route.fulfill({ response, body: JSON.stringify(json) });
});
```

---

## Multi-Tab and Popup Handling

### Handling new tabs

```typescript
test('external link opens in new tab', async ({ page, context }) => {
  await page.goto('/');

  // Wait for the new page (tab) to open
  const [newPage] = await Promise.all([
    context.waitForEvent('page'),
    page.getByRole('link', { name: 'Documentation' }).click(),
  ]);

  // Work with the new tab
  await newPage.waitForLoadState();
  await expect(newPage).toHaveURL(/docs\.example\.com/);
  await expect(newPage.getByRole('heading')).toHaveText('Documentation');
});
```

### Handling popups (OAuth, payment)

```typescript
test('OAuth login popup', async ({ page }) => {
  const [popup] = await Promise.all([
    page.waitForEvent('popup'),
    page.getByRole('button', { name: 'Sign in with Google' }).click(),
  ]);

  // Interact with the popup
  await popup.waitForLoadState();
  await popup.getByLabel('Email').fill('user@gmail.com');
  await popup.getByRole('button', { name: 'Next' }).click();

  // Popup closes, main page updates
  await expect(page.getByText('Welcome, User')).toBeVisible();
});
```

### Handling dialogs (alert, confirm, prompt)

```typescript
test('confirm dialog', async ({ page }) => {
  // Set up dialog handler BEFORE triggering it
  page.on('dialog', async (dialog) => {
    expect(dialog.message()).toBe('Are you sure?');
    await dialog.accept();
  });

  await page.getByRole('button', { name: 'Delete' }).click();
  await expect(page.getByText('Item deleted')).toBeVisible();
});
```

---

## Mobile Viewport Testing

### Configure viewports in config

```typescript
// playwright.config.ts
import { devices } from '@playwright/test';

export default defineConfig({
  projects: [
    { name: 'Desktop Chrome', use: { ...devices['Desktop Chrome'] } },
    { name: 'Mobile Chrome', use: { ...devices['Pixel 5'] } },
    { name: 'Mobile Safari', use: { ...devices['iPhone 13'] } },
    { name: 'Tablet', use: { ...devices['iPad Mini'] } },
  ],
});
```

### Per-test viewport

```typescript
test('mobile navigation menu', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 667 });
  await page.goto('/');

  // Desktop nav should be hidden
  await expect(page.getByRole('navigation')).toBeHidden();

  // Mobile menu button should be visible
  await page.getByRole('button', { name: 'Menu' }).click();
  await expect(page.getByRole('navigation')).toBeVisible();
});
```

### Touch interactions

```typescript
test('swipe to dismiss', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 667 });
  await page.goto('/notifications');

  const notification = page.getByTestId('notification-1');
  const box = await notification.boundingBox();

  // Simulate swipe gesture
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x - 200, box.y + box.height / 2, { steps: 10 });
  await page.mouse.up();

  await expect(notification).toBeHidden();
});
```

---

## Common Anti-Patterns to Avoid

### 1. Using `page.waitForTimeout()` as a fix for flakiness

```typescript
// Bad — slow, still flaky under load
await page.getByRole('button', { name: 'Save' }).click();
await page.waitForTimeout(3000);
await expect(page.getByText('Saved')).toBeVisible();

// Good — wait for the specific signal
await page.getByRole('button', { name: 'Save' }).click();
await expect(page.getByText('Saved')).toBeVisible();  // auto-waits
```

### 2. Asserting on stale locators

```typescript
// Bad — locator resolved before the update
const count = await page.getByTestId('count').textContent();
await page.getByRole('button', { name: 'Add' }).click();
const newCount = await page.getByTestId('count').textContent();
expect(Number(newCount)).toBe(Number(count) + 1);

// Good — use Playwright's auto-retrying assertions
await page.getByRole('button', { name: 'Add' }).click();
await expect(page.getByTestId('count')).toHaveText('1');
```

### 3. Not cleaning up test data

```typescript
// Bad — tests depend on each other's state
test('create item', async ({ page }) => { /* creates an item */ });
test('list items', async ({ page }) => { /* assumes item exists */ });

// Good — each test sets up its own state
test('list items', async ({ page }) => {
  // Create via API (faster than UI)
  await page.request.post('/api/items', { data: { name: 'Test Item' } });
  await page.goto('/items');
  await expect(page.getByText('Test Item')).toBeVisible();
});
```

### 4. Testing across test boundaries

```typescript
// Bad — tests share state through the page
test.describe('sequential tests', () => {
  test('step 1: login', async ({ page }) => { /* ... */ });
  test('step 2: create', async ({ page }) => { /* depends on step 1 */ });
});

// Good — each test is independent, use beforeEach for shared setup
test.describe('creation flow', () => {
  test.beforeEach(async ({ page }) => {
    // Shared setup via storageState or API
  });
  test('create item', async ({ page }) => { /* independent */ });
  test('create and edit item', async ({ page }) => { /* independent */ });
});
```

### 5. Ignoring test isolation

```typescript
// Bad — modifies shared database without cleanup
test('delete all items', async ({ page }) => {
  await page.getByRole('button', { name: 'Delete All' }).click();
});

// Good — use test-specific data or reset state
test('delete all items', async ({ page }) => {
  // Seed test-specific data via API
  await page.request.post('/api/test/seed', {
    data: { items: ['Item 1', 'Item 2'] },
  });
  await page.goto('/items');
  await page.getByRole('button', { name: 'Delete All' }).click();
  await expect(page.getByText('No items')).toBeVisible();
});
```
