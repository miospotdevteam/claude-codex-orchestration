# Rubric: CLI README usage section

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Compare against the source of truth in the spec.

## Dimensions

### 1. Accuracy / fidelity to the source
Do the documented commands, options, and behaviors match `snap` exactly?
- **High (5):** Every command, flag, naming rule, and exit code matches
  the source; no invented flags or behaviors; the `--force` /
  `--dry-run` / overwrite / refuse-on-local-changes semantics are stated
  correctly.
- **Low (0-1):** Invented or missing flags, wrong behavior, or
  contradicts the source (e.g. claims `save` overwrites by default).

### 2. Completeness
Is everything a user needs present?
- **High (5):** All four commands, global options, per-command options,
  naming rules, and exit codes are covered.
- **Low (0-1):** Missing commands, options, or exit codes.

### 3. Quickstart & task orientation
Can a new user get to a first success fast?
- **High (5):** A quickstart shows the common save → list → restore flow
  as copy-pasteable commands early in the doc; the reader can act within
  seconds.
- **Low (0-1):** No quickstart, or it buries the common path under
  exhaustive reference material.

### 4. Example quality
Are the examples correct, realistic, and illustrative?
- **High (5):** At least two non-trivial examples (e.g. `save` with
  `--message` and `--exclude`, a `--dry-run` restore) that are valid per
  the documented syntax and naming rules and show real value.
- **Low (0-1):** No examples, invalid commands, or examples that violate
  the naming/option rules.

### 5. Structure & clarity
Is it well organized and readable?
- **High (5):** Clear sections (intro → quickstart → commands → options →
  exit codes → examples), consistent formatting of commands/flags,
  scannable; concise prose.
- **Low (0-1):** Disorganized, inconsistent code formatting, hard to find
  a given command, or rambling.
