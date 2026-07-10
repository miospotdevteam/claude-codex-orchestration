# Task: Design a config file schema for a static-site generator

Design the **user-facing configuration schema** for a static-site
generator called **Strand**. This is the `strand.config` file (and its
types) that a user authors to configure a build. You are designing the
*shape of the configuration a user writes* — not the build engine.

## Domain & requirements

Strand takes a directory of Markdown + assets and produces a static
site. Users need to configure at least:

- **Site basics**: title, description, canonical base URL, default
  language, and a favicon/logo path.
- **Build**: input/content directory, output directory, and whether
  drafts are included.
- **Navigation**: an ordered set of nav items (label + link), allowing
  nested items one level deep.
- **Markdown options**: enable/disable syntax highlighting, a heading-
  anchor toggle, and the ability to register additional remark/rehype-
  style plugins with per-plugin options.
- **Theme**: select a theme by name and pass theme-specific options (an
  open bag whose exact keys depend on the chosen theme).
- **Collections**: named groups of content (e.g. `blog`, `docs`), each
  with its own source glob, a route prefix, an ordering (by date or
  title, asc/desc), and pagination size.
- **Environment awareness**: some values (e.g. base URL, drafts) commonly
  differ between `development` and `production` builds — the schema must
  make per-environment overrides possible without duplicating the whole
  config.

Sensible **defaults** must exist for everything that can have one, so a
minimal config is tiny; power users can override deeply.

## What to deliver

Produce a single Markdown document, `design.md`, presenting:

- The **schema as TypeScript types** (the `StrandConfig` type and its
  nested types), with each field's type, whether it's required or
  optional, and its default noted in a comment.
- A **minimal example** config (the smallest thing that builds) and a
  **rich example** exercising collections, nav nesting, markdown plugins,
  a theme option bag, and a per-environment override.
- A short rationale for the **key structural decisions** (how collections
  are keyed, how plugins are registered, how environment overrides are
  expressed, how theme options stay open).
- A note on **extensibility**: how a new top-level option, a new
  collection ordering, or a new theme's options can be added without
  breaking existing configs.

You are proposing the schema — make and state the decisions. Keep it
self-consistent; a value defined in one place must be usable everywhere
it's referenced.

## Deliverable

A single `design.md`.
