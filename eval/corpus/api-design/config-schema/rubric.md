# Rubric: Static-site generator config schema

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the proposed schema in `design.md`.

## Dimensions

### 1. Ergonomics (minimal-to-rich gradient)
Is the easy case tiny and the powerful case reachable?
- **High (5):** A minimal config is a few lines because defaults are
  pervasive; advanced needs (collections, plugins, env overrides) are
  expressible without ceremony; the common case isn't taxed by the rare
  one.
- **Low (0-1):** Even a basic site requires a large config; or advanced
  features are impossible/hacky to express.

### 2. Naming & consistency
Are field names clear and uniform across the schema?
- **High (5):** Predictable, uniform naming (e.g. consistent casing,
  consistent plural/singular, parallel structure across nav/collections);
  no synonyms for the same concept.
- **Low (0-1):** Inconsistent casing or terminology, surprising names, or
  the same idea named two ways.

### 3. Structure & modeling
Are the nested structures modeled well?
- **High (5):** Collections keyed sensibly (e.g. a keyed record vs a
  list), nav nesting expressed cleanly (and genuinely one level deep),
  ordering modeled as a small closed set + direction, theme options kept
  as an intentionally open bag; the model matches the domain.
- **Low (0-1):** Awkward or ambiguous nesting, unbounded nav depth that
  contradicts the spec, ordering as a free string, or a muddled model.

### 4. Environment overrides & defaults
Are per-environment config and defaults handled cleanly?
- **High (5):** A clear, non-duplicative mechanism for dev/prod overrides
  (e.g. an `env` overlay or function form); every defaultable field's
  default is stated; overrides compose predictably with the base.
- **Low (0-1):** No env mechanism (or one that forces full duplication),
  or defaults left unspecified so the minimal config is ambiguous.

### 5. Extensibility
Can the schema grow without breaking existing configs?
- **High (5):** New top-level options, orderings, or theme option keys
  can be added additively; the open/closed choices (closed enums where
  safety matters, open bags where themes vary) are deliberate and
  explained.
- **Low (0-1):** Rigid shapes that would force existing configs to change,
  or everything left open so nothing is validated.
