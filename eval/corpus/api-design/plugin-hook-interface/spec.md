# Task: Design a plugin hook interface for a build pipeline

Design the **plugin interface** for a JavaScript bundler called
**Packt**. Third parties will write plugins that hook into Packt's build
to transform files, resolve imports, inject assets, and react to build
lifecycle events. You are designing the *contract a plugin author
implements* — not Packt's core.

## Domain & requirements

A Packt build runs in phases: it **resolves** import specifiers to
module ids, **loads** a module's source, **transforms** source, then
**bundles**, and finally **writes** output. Plugin authors need to hook
these. The design must support:

- A **plugin** as a named unit that registers one or more hooks. A plugin
  may be parameterized (a factory that takes options and returns the
  plugin).
- **Resolve** hook: given an import specifier and the importer, a plugin
  may return a resolved id (or defer to the next plugin).
- **Load** hook: given a resolved id, a plugin may return the module's
  source (or defer).
- **Transform** hook: given source + id, a plugin may return transformed
  source (and ideally a source map), or defer. Multiple transforms chain.
- **Lifecycle** hooks: `buildStart` and `buildEnd` (with the build result
  or the error), for setup/teardown and reporting.
- **Emitting assets**: a plugin must be able to emit an additional output
  file (e.g. a manifest) into the build.
- Hooks must be able to be **async**, must have a way to **report a
  diagnostic** (warning/error tied to a file+position), and must have
  access to **shared build context** (e.g. mode = dev/prod, the root dir)
  without threading it through every call by hand.
- **Ordering / control**: the design must define how multiple plugins
  compose on the same hook — who wins on resolve/load (first non-null),
  how transforms chain — and offer a way for a plugin to run
  `pre`/`post` relative to others.

## What to deliver

Produce a single Markdown document, `design.md`, presenting:

- The **types**: the `Plugin` shape, each hook's signature (arguments and
  return contract, including the "defer to next" sentinel), the shared
  **context** object passed to hooks, and the diagnostic / emit-asset
  APIs.
- A precise statement of **composition semantics**: resolve/load
  first-wins, transform chaining order, and the `pre`/`post` ordering
  control.
- A **worked example plugin** (e.g. one that resolves a virtual module,
  or transforms a file type and emits a manifest) implemented against the
  interface.
- A note on **extensibility**: how a new hook or a new context capability
  can be added without breaking existing plugins.

You are proposing the interface — make and state the decisions. Keep the
contract self-consistent (the example must type-check against the types).

## Deliverable

A single `design.md`.
