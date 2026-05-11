---
name: webapp-testing
description: "End-to-end webapp testing with Playwright MCP integration. Use when: writing Playwright tests, E2E testing, browser testing, webapp testing, visual regression testing, accessibility testing with axe-core, testing user flows through a web UI, verifying frontend behavior in a real browser. Integrates with test-driven-development skill for test-first browser tests and engineering-discipline for verification. Do NOT use when: unit tests only (no browser UI involved), API tests without UI, mobile native testing (use react-native-mobile), testing CLI tools, or writing backend-only integration tests."
---

# Webapp Testing

Test web applications through a real browser using Playwright. This skill
covers reconnaissance (exploring the app before writing tests), test strategy
selection, Playwright MCP integration for interactive exploration, and
structured test implementation.

**Announce at start:** "I'm using the webapp-testing skill to guide browser
test development."

**Prerequisite:** The project must have a web application with a UI. If
there is no UI to test, this skill does not apply.

---

## Decision Tree: Which Approach?

Before writing any tests, determine the application type:

```
Is there a web UI to test?
├── No → This skill does not apply. Use unit/integration tests.
└── Yes
    ├── Static HTML (no JS, no dynamic content)?
    │   └── Lightweight: use Playwright's built-in test runner
    │       with simple navigation + content assertions.
    │       No server lifecycle management needed if files are local.
    │
    └── Dynamic webapp (React, Vue, Svelte, Next.js, etc.)?
        ├── Already has Playwright configured?
        │   └── Use existing config. Read playwright.config.ts,
        │       understand baseURL, test directory, projects.
        │
        └── No Playwright setup?
            └── Set up from scratch:
                1. Install @playwright/test
                2. Create playwright.config.ts
                3. Configure webServer (or use with_server.py)
                4. Create first test file
```

### When to use Playwright's built-in test runner

Use `npx playwright test` when:
- The project already has `playwright.config.ts`
- You need parallel test execution
- You need HTML reporter, trace viewer, or retry logic
- You need `webServer` config to auto-start the dev server
- The tests will run in CI

### When to use manual test scripts

Use a standalone script (with `with_server.py`) when:
- Quick one-off verification during development
- Exploring app behavior before writing formal tests
- The project does not have Playwright configured and you need a fast check
- Debugging a specific user flow interactively

---

## Integration with Other Skills

**With test-driven-development:** When TDD is active, the RED phase writes
a failing Playwright test (browser assertion fails), the GREEN phase
implements the feature until the browser test passes, and REFACTOR cleans
up both test and implementation code. Each TDD cycle produces one user-
visible behavior verified through the browser.

**With engineering-discipline:** After tests are written, run the full
verification suite (type checker, linter, all tests including Playwright).

**With systematic-debugging:** When a test fails unexpectedly, use the
debugging skill's Phase 1 investigation before modifying test code. Trace
whether the failure is in the app, the test, or a timing issue.

---

## Phase 1: Reconnaissance (during Step 1 Explore)

**Do NOT write tests before understanding the application.** Explore first.

### 1. Examine the project

Read these files before opening a browser:
- `package.json` — scripts, dependencies, dev server command
- `playwright.config.ts` (if exists) — baseURL, test directory, projects
- Route definitions — Next.js `app/` or `pages/`, React Router config,
  Vue Router, SvelteKit `routes/`
- Authentication — how does login work? OAuth? Session cookies? JWT?

### 2. Start the dev server

Identify the correct command from `package.json` scripts. Common patterns:
- `npm run dev` / `yarn dev` / `pnpm dev`
- `npm start`
- Custom scripts

Use `with_server.py` (see `scripts/with_server.py`) to manage server
lifecycle, or use Playwright's `webServer` config. See
`references/server-recipes.md` for framework-specific configurations.

### 3. Explore with Playwright MCP

Use the Playwright MCP tools to navigate and understand the app:

```
Step 1: Navigate to the app
  → browser_navigate to the base URL

Step 2: Take an accessibility snapshot
  → browser_snapshot to see the page structure, interactive elements,
    and current state

Step 3: Interact with key flows
  → browser_click, browser_fill_form, browser_press_key to walk through
    the primary user journeys

Step 4: Check multiple routes
  → browser_navigate to each route, browser_snapshot each one

Step 5: Check responsive behavior
  → browser_resize to mobile (375px) and tablet (768px) widths
  → browser_snapshot at each size
```

**Document findings in `discovery.md`:**
- Available routes and their purpose
- Interactive elements and forms
- Authentication flow
- Loading states and error states
- Third-party integrations (payment, maps, analytics)
- Any observed bugs or inconsistencies

### 4. Identify what needs testing

Based on reconnaissance, categorize:

| Priority | What to test | Why |
|---|---|---|
| **Critical** | Authentication flows, payment/checkout, data submission | User-blocking if broken |
| **High** | Navigation between routes, search/filter, CRUD operations | Core functionality |
| **Medium** | Responsive layout, error states, loading states | Quality and edge cases |
| **Low** | Animations, tooltips, non-critical UI details | Nice-to-have |

---

## Phase 2: Test Strategy (during Step 2 Plan)

### Choose test granularity

| Approach | When | Example |
|---|---|---|
| **Smoke tests** | Verify the app loads and critical paths work | Navigate to /, verify heading visible |
| **Flow tests** | Test complete user journeys end-to-end | Sign up → verify email → log in → create item |
| **Component tests** | Test isolated interactive components | Date picker selects correct date, modal opens/closes |
| **Visual regression** | Verify UI appearance hasn't changed | Screenshot comparison of key pages |
| **Accessibility tests** | Verify WCAG compliance | axe-core scan of each route |

### Plan the test structure

```
tests/
├── e2e/
│   ├── auth.spec.ts          # Login, signup, logout flows
│   ├── navigation.spec.ts    # Route navigation, breadcrumbs
│   └── [feature].spec.ts     # One file per feature area
├── visual/
│   └── screenshots.spec.ts   # Visual regression tests
├── a11y/
│   └── accessibility.spec.ts # axe-core scans
└── fixtures/
    ├── auth.ts               # Authentication state setup
    └── test-data.ts           # Shared test data
```

### Server lifecycle strategy

Decide how the dev server will be managed:

**Option A: Playwright `webServer` config** (preferred for CI)
```typescript
// playwright.config.ts
export default defineConfig({
  webServer: {
    command: 'npm run dev',
    port: 3000,
    reuseExistingServer: !process.env.CI,
  },
});
```

**Option B: `with_server.py` script** (flexible, multi-server)
```bash
python3 scripts/with_server.py \
  --cmd "npm run dev" --port 3000 \
  --test-cmd "npx playwright test"
```

**Option C: External server** (already running)
```typescript
// playwright.config.ts
export default defineConfig({
  use: { baseURL: 'http://localhost:3000' },
  // No webServer — assumes server is already running
});
```

---

## Phase 3: Implementation (during Step 3 Execute)

### Writing tests

Read `references/playwright-patterns.md` for detailed patterns on:
- Selector strategies (role-based preferred)
- Assertions and waiting
- Page Object Model
- Authentication state reuse
- Network mocking
- Visual comparison
- Multi-tab handling

### Test-first with Playwright (TDD integration)

When the TDD skill is active, each cycle looks like:

1. **RED:** Write a Playwright test asserting the desired behavior
   ```typescript
   test('user can create a new project', async ({ page }) => {
     await page.goto('/dashboard');
     await page.getByRole('button', { name: 'New Project' }).click();
     await page.getByLabel('Project name').fill('My Project');
     await page.getByRole('button', { name: 'Create' }).click();
     await expect(page.getByText('My Project')).toBeVisible();
   });
   ```
2. **Run the test** — it fails (feature not implemented)
3. **GREEN:** Implement the feature until the test passes
4. **REFACTOR:** Clean up both test and implementation code
5. **Repeat** for the next user behavior

### Accessibility testing with @axe-core/playwright

Install and configure:
```bash
npm install -D @axe-core/playwright
```

Write accessibility tests:
```typescript
import AxeBuilder from '@axe-core/playwright';

test('home page has no accessibility violations', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

// Test specific sections
test('navigation is accessible', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page })
    .include('nav')
    .analyze();
  expect(results.violations).toEqual([]);
});

// Exclude known issues while fixing them
test('dashboard accessibility (excluding known issues)', async ({ page }) => {
  await page.goto('/dashboard');
  const results = await new AxeBuilder({ page })
    .disableRules(['color-contrast'])  // TODO: fix contrast on sidebar
    .analyze();
  expect(results.violations).toEqual([]);
});
```

Run accessibility tests on every route discovered in Phase 1.

### Visual regression testing

Playwright has built-in screenshot comparison:

```typescript
test('landing page visual regression', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveScreenshot('landing.png', {
    maxDiffPixelRatio: 0.01,
  });
});

// Component-level screenshots
test('pricing cards visual regression', async ({ page }) => {
  await page.goto('/pricing');
  const cards = page.getByTestId('pricing-cards');
  await expect(cards).toHaveScreenshot('pricing-cards.png');
});
```

**First run:** Creates baseline screenshots in `tests/*.spec.ts-snapshots/`.
Commit these to the repo.

**Subsequent runs:** Compares against baselines. If visuals changed
intentionally, update with `npx playwright test --update-snapshots`.

**Gotchas:**
- Screenshots vary across OS/font rendering — use Docker or Playwright's
  built-in Linux browser images for CI consistency
- Animations cause flaky screenshots — disable them:
  ```typescript
  await page.emulateMedia({ reducedMotion: 'reduce' });
  ```
- Dynamic content (dates, random data) — mock or hide before screenshot

---

## Phase 4: Verification

### Run all tests

```bash
# Run all Playwright tests
npx playwright test

# Run with UI mode for debugging
npx playwright test --ui

# Run specific test file
npx playwright test tests/e2e/auth.spec.ts

# Run with specific browser
npx playwright test --project=chromium

# Show HTML report
npx playwright show-report
```

### Verify coverage

Check that tests cover:
- [ ] All critical user flows identified in Phase 1
- [ ] Authentication (login, logout, session expiry)
- [ ] Form submissions and validation
- [ ] Error states (network errors, 404 pages, server errors)
- [ ] Responsive behavior at key breakpoints
- [ ] Accessibility (axe-core on all routes)
- [ ] Visual regression baselines committed

### Verify stability

Run tests 3 times to check for flakiness:
```bash
npx playwright test --repeat-each=3
```

If any test fails intermittently, fix it before declaring done. Common
causes of flakiness:
- Missing `await` on assertions
- Race conditions with network requests — use `page.waitForResponse()`
- Animations not completing — use `page.waitForTimeout()` as last resort
- Dynamic content — mock or wait for specific content

### Acceptance criteria

- [ ] All planned test cases pass
- [ ] No flaky tests (3 consecutive green runs)
- [ ] Accessibility violations at zero (or documented exceptions)
- [ ] Visual regression baselines committed
- [ ] Server lifecycle is automated (no manual server start needed)
- [ ] Tests run in CI configuration (if applicable)
- [ ] Test code follows project conventions (linter passes)

---

## Anti-Patterns

| Anti-Pattern | Why It Fails | Correct Approach |
|---|---|---|
| Testing without exploring the app first | You'll miss flows, write incomplete tests | Complete Phase 1 reconnaissance first |
| Selectors based on CSS classes or DOM structure | Brittle — breaks on any refactor | Use role-based selectors (`getByRole`, `getByLabel`) |
| `page.waitForTimeout(5000)` everywhere | Slow and flaky — fails under load | Use auto-wait, `waitForResponse`, `waitForSelector` |
| One giant test for the entire flow | Hard to debug, masks which step failed | One test per logical user action |
| No server lifecycle management | Tests fail because server isn't running | Use `webServer` config or `with_server.py` |
| Ignoring accessibility testing | Ships inaccessible product | Run axe-core on every route |
| Skipping visual regression | UI regressions slip through | Screenshot baselines for key pages |
| Testing implementation details via DOM | Couples tests to code structure | Test user-visible behavior |

---

## Supporting References

All paths relative to `${CLAUDE_PLUGIN_ROOT}/skills/webapp-testing/`.

| Reference | When to use |
|---|---|
| `references/playwright-patterns.md` | Writing test code — selectors, assertions, patterns |
| `references/server-recipes.md` | Configuring dev server for common frameworks |
| `scripts/with_server.py` | Managing dev server lifecycle for test runs |

**Related skills:**
- `test-driven-development` — for test-first browser tests
- `engineering-discipline` — for verification after tests
- `systematic-debugging` — for investigating test failures
