# Server Recipes for E2E Testing

Framework-specific configurations for starting dev servers during E2E tests.
Each recipe shows the command, default port, required env vars, Playwright
`webServer` config, and `with_server.py` usage.

---

## Next.js

### Development mode

```bash
# Command
npm run dev
# or: npx next dev

# Default port: 3000
# Override: npx next dev -p 4000
```

```typescript
// playwright.config.ts
webServer: {
  command: 'npm run dev',
  port: 3000,
  reuseExistingServer: !process.env.CI,
},
```

```bash
# with_server.py
python3 with_server.py --cmd "npm run dev" --port 3000 --test-cmd "npx playwright test"
```

**Env vars:**
- `PORT=4000` — custom port (Next.js 13.4+)
- `NODE_ENV=test` — enables test-specific behavior if configured

**Gotchas:**
- First request in dev mode compiles on-demand — the first test may be
  slow. Consider a warmup step or increase the test timeout.
- Next.js 13+ App Router: `loading.tsx` shows during route compilation,
  which can cause flaky tests. Wait for the actual content, not just the
  page load.
- API routes (`/api/*`) are part of the same server — no separate backend
  needed.

### Production build

```bash
# Build first, then start
npm run build && npm run start
# or: npx next build && npx next start

# Default port: 3000
```

```typescript
// playwright.config.ts (CI — build + start)
webServer: {
  command: 'npm run build && npm run start',
  port: 3000,
  timeout: 120000,  // Build can take a while
},
```

```bash
# with_server.py (pre-built)
python3 with_server.py --cmd "npm run start" --port 3000 --test-cmd "npx playwright test"
```

**Gotchas:**
- Build step can take 30-120 seconds. Set `timeout` accordingly.
- `output: 'export'` (static export) produces HTML files — serve with a
  static server instead: `npx serve out`.

---

## Vite

### Development mode

```bash
# Command
npm run dev
# or: npx vite

# Default port: 5173
# Override: npx vite --port 4000
```

```typescript
// playwright.config.ts
webServer: {
  command: 'npm run dev',
  port: 5173,
  reuseExistingServer: !process.env.CI,
},
```

```bash
# with_server.py
python3 with_server.py --cmd "npm run dev" --port 5173 --test-cmd "npx playwright test"
```

**Env vars:**
- `VITE_*` — custom env vars exposed to the client (prefix required)
- `--host 0.0.0.0` — expose to network (useful in Docker)

**Gotchas:**
- Vite's port auto-increments if busy (5173 → 5174). Pin the port with
  `--port 5173 --strictPort` to fail instead of silently using a different
  port.
- HMR WebSocket stays open — `networkidle` may never resolve. Use
  specific element waits instead.
- `vite preview` serves the built app (default port 4173) — use for
  production-like testing after `vite build`.

---

## Create React App

### Development mode

```bash
# Command
npm start
# or: npx react-scripts start

# Default port: 3000
```

```typescript
// playwright.config.ts
webServer: {
  command: 'npm start',
  port: 3000,
  reuseExistingServer: !process.env.CI,
  env: { BROWSER: 'none' },  // Prevent auto-opening browser
},
```

```bash
# with_server.py
BROWSER=none python3 with_server.py --cmd "npm start" --port 3000 --test-cmd "npx playwright test"
```

**Env vars:**
- `BROWSER=none` — prevent CRA from opening a browser tab on start
- `PORT=4000` — custom port
- `REACT_APP_*` — custom env vars exposed to the client

**Gotchas:**
- CRA opens a browser by default. Set `BROWSER=none` in the env.
- CRA's dev server prompts "Something is already running on port 3000.
  Would you like to run on another port?" interactively. Set
  `CI=true` to skip the prompt and fail instead.
- CRA is in maintenance mode. Consider migrating to Vite for new projects.

---

## Remix

### Development mode

```bash
# Command (Remix v2 with Vite)
npm run dev
# or: npx remix vite:dev

# Default port: 5173 (Vite-based Remix)
# Classic Remix: 3000
```

```typescript
// playwright.config.ts (Remix v2)
webServer: {
  command: 'npm run dev',
  port: 5173,
  reuseExistingServer: !process.env.CI,
},
```

```bash
# with_server.py
python3 with_server.py --cmd "npm run dev" --port 5173 --test-cmd "npx playwright test"
```

**Env vars:**
- `PORT=4000` — custom port (classic Remix only)
- `NODE_ENV=test` — enables test-specific behavior

**Gotchas:**
- Remix v2 uses Vite — same port and behavior as Vite section above.
- Classic Remix (v1) uses its own compiler — port 3000 by default.
- Loaders run server-side — mock external APIs at the loader level, not
  the browser network layer, for more reliable tests.
- Actions (form submissions) use progressive enhancement — test both
  JS-enabled and disabled if progressive enhancement is important.

---

## Astro

### Development mode

```bash
# Command
npm run dev
# or: npx astro dev

# Default port: 4321
# Override: npx astro dev --port 4000
```

```typescript
// playwright.config.ts
webServer: {
  command: 'npm run dev',
  port: 4321,
  reuseExistingServer: !process.env.CI,
},
```

```bash
# with_server.py
python3 with_server.py --cmd "npm run dev" --port 4321 --test-cmd "npx playwright test"
```

**Env vars:**
- `--host 0.0.0.0` — expose to network

**Gotchas:**
- Astro is primarily SSG (static site generation). Most pages are static
  HTML — tests load fast but interactive islands need JavaScript.
- Islands architecture: client-side components only hydrate when visible
  or on interaction. Wait for the specific island's interactive state,
  not just page load.
- `astro preview` serves the built site (default port 4321) — use for
  production-like testing after `astro build`.

---

## Express / Node Custom Server

### Development mode

```bash
# Command (varies by project)
node server.js
# or: npx nodemon server.js
# or: npx tsx watch src/server.ts

# Default port: typically 3000 or 8080 (check the code)
```

```typescript
// playwright.config.ts
webServer: {
  command: 'node server.js',
  port: 3000,
  reuseExistingServer: !process.env.CI,
  env: { NODE_ENV: 'test' },
},
```

```bash
# with_server.py
python3 with_server.py --cmd "node server.js" --port 3000 --test-cmd "npx playwright test"
```

**Env vars:**
- `PORT=3000` — most Express apps read this (check the code)
- `NODE_ENV=test` — enables test database, disables rate limiting, etc.
- `DATABASE_URL` — point to test database

**Gotchas:**
- No standard port or start command — read the project code to determine
  both.
- If the server connects to a database, ensure the test database is
  seeded before running tests. Use a setup script or API endpoint.
- `nodemon` restarts on file changes — can cause tests to fail mid-run
  if source files are modified. Use `node` directly for test runs.

### Separate frontend + backend

```bash
# with_server.py — start both
python3 with_server.py \
  --cmd "npm run dev" --port 3000 \
  --cmd "node api/server.js" --port 8080 \
  --test-cmd "npx playwright test"
```

```typescript
// playwright.config.ts — multiple webServers (Playwright 1.39+)
// Note: Playwright only supports a single webServer in config.
// For multiple servers, use with_server.py instead.
```

---

## Django

### Development mode

```bash
# Command
python manage.py runserver
# or: python manage.py runserver 0.0.0.0:8000

# Default port: 8000
```

```typescript
// playwright.config.ts
webServer: {
  command: 'python manage.py runserver --noreload',
  port: 8000,
  reuseExistingServer: !process.env.CI,
  env: { DJANGO_SETTINGS_MODULE: 'myproject.settings.test' },
},
```

```bash
# with_server.py
python3 with_server.py \
  --cmd "python manage.py runserver --noreload" \
  --port 8000 \
  --test-cmd "npx playwright test"
```

**Env vars:**
- `DJANGO_SETTINGS_MODULE=myproject.settings.test` — use test settings
- `DATABASE_URL` — point to test database

**Gotchas:**
- Use `--noreload` to prevent the auto-reloader from forking a child
  process that complicates cleanup.
- Django's dev server is single-threaded by default — concurrent test
  requests may queue. Use `--nothreading` to make this explicit, or use
  `gunicorn` for production-like testing.
- Static files: run `python manage.py collectstatic --noinput` before
  testing if the app serves static files.
- Database: use `python manage.py migrate --run-syncdb` with a test
  database before running tests. Consider Django's `--keepdb` flag for
  faster test database setup.

---

## Flask

### Development mode

```bash
# Command
flask run
# or: python app.py
# or: python -m flask run

# Default port: 5000 (macOS note: 5000 is used by AirPlay Receiver)
# Override: flask run --port 5001
```

```typescript
// playwright.config.ts
webServer: {
  command: 'flask run --port 5001',
  port: 5001,
  reuseExistingServer: !process.env.CI,
  env: {
    FLASK_APP: 'app.py',
    FLASK_ENV: 'testing',
  },
},
```

```bash
# with_server.py
python3 with_server.py \
  --cmd "flask run --port 5001" \
  --port 5001 \
  --test-cmd "npx playwright test"
```

**Env vars:**
- `FLASK_APP=app.py` — entry point (required if not auto-detected)
- `FLASK_ENV=testing` — enables testing config (Flask 2.2- only;
  use `FLASK_DEBUG=0` in Flask 2.3+)
- `FLASK_RUN_PORT=5001` — alternative to `--port`

**Gotchas:**
- macOS: port 5000 is used by AirPlay Receiver. Use 5001 or disable
  AirPlay Receiver in System Settings > General > AirDrop & Handoff.
- Flask's dev server is not production-grade. Use `gunicorn` or
  `waitress` for production-like testing.
- Flask does not serve static files efficiently in dev mode. For
  full-stack apps, consider a separate static file server or a bundler
  (Vite, Webpack) for the frontend.

---

## Rails

### Development mode

```bash
# Command
bin/rails server
# or: bundle exec rails server

# Default port: 3000
# Override: bin/rails server -p 4000
```

```typescript
// playwright.config.ts
webServer: {
  command: 'bin/rails server -p 4000 -e test',
  port: 4000,
  reuseExistingServer: !process.env.CI,
  env: { RAILS_ENV: 'test' },
},
```

```bash
# with_server.py
python3 with_server.py \
  --cmd "bin/rails server -p 4000 -e test" \
  --port 4000 \
  --test-cmd "npx playwright test"
```

**Env vars:**
- `RAILS_ENV=test` — use test environment
- `DATABASE_URL` — point to test database
- `SECRET_KEY_BASE=test-secret` — required in production mode

**Gotchas:**
- Use port 4000+ to avoid conflict with other tools (e.g., another
  Rails app, Vite proxy) on port 3000.
- Run `bin/rails db:test:prepare` before running tests to set up the
  test database.
- Rails uses CSRF protection by default. If tests submit forms, they
  need the authenticity token. Playwright handles this automatically
  when interacting through the UI (the token is in the form), but API
  requests need the token in headers.
- Turbo (Hotwire) in Rails 7+: page transitions may not trigger
  traditional navigation events. Wait for Turbo-specific events or
  content changes instead of URL changes.
- Asset pipeline: run `bin/rails assets:precompile` for production-like
  testing, or ensure `config.assets.debug = true` in test environment.

---

## Quick Reference Table

| Framework | Command | Port | Key Env Var |
|---|---|---|---|
| Next.js (dev) | `npm run dev` | 3000 | `PORT` |
| Next.js (prod) | `npm run build && npm run start` | 3000 | `PORT` |
| Vite | `npm run dev` | 5173 | `--strictPort` |
| Create React App | `npm start` | 3000 | `BROWSER=none` |
| Remix (v2) | `npm run dev` | 5173 | `PORT` |
| Astro | `npm run dev` | 4321 | — |
| Express | `node server.js` | varies | `PORT`, `NODE_ENV` |
| Django | `python manage.py runserver` | 8000 | `DJANGO_SETTINGS_MODULE` |
| Flask | `flask run --port 5001` | 5001 | `FLASK_APP` |
| Rails | `bin/rails server` | 3000 | `RAILS_ENV` |
