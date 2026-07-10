# Rubric: Plugin hook interface

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the proposed interface in `design.md`.

## Dimensions

### 1. Ergonomics for the plugin author
Is a simple plugin simple to write?
- **High (5):** A one-hook plugin is a few lines; the factory/options
  pattern is clean; shared context arrives via the hook (e.g. `this` or a
  ctx arg) rather than being threaded manually; the "defer to next"
  sentinel is obvious and low-friction.
- **Low (0-1):** Even a trivial plugin needs heavy boilerplate, context
  must be passed by hand everywhere, or the defer mechanism is unclear.

### 2. Naming & consistency
Are hook names and signatures uniform and predictable?
- **High (5):** Hook names map cleanly to the phases (resolve/load/
  transform/buildStart/buildEnd); argument and return shapes are parallel
  across hooks; one convention for async and for defer.
- **Low (0-1):** Ad hoc hook names, inconsistent argument order, or each
  hook invents its own return convention.

### 3. Composition semantics
Is multi-plugin behavior defined precisely?
- **High (5):** Clearly specifies resolve/load first-non-null-wins,
  transform chaining order, and a working `pre`/`post` ordering control;
  the rules are unambiguous and cover ties.
- **Low (0-1):** Composition left undefined, contradictory, or no way to
  control ordering.

### 4. Error handling & diagnostics
Can plugins fail and warn well?
- **High (5):** A first-class diagnostic API ties warnings/errors to a
  file + position; `buildEnd` receives the error on failure; hook errors
  have defined semantics (abort vs continue); async errors are handled.
- **Low (0-1):** No diagnostic channel (just `throw`/`console.log`), no
  error surface in lifecycle hooks, or undefined failure behavior.

### 5. Extensibility
Can the interface grow without breaking existing plugins?
- **High (5):** New hooks are additive (a plugin implements only what it
  needs); new context capabilities can be added without changing existing
  hook signatures; the growth path is explained and the example type-checks
  against the types.
- **Low (0-1):** Adding a hook or context field would break every existing
  plugin, or the example contradicts the declared types.
