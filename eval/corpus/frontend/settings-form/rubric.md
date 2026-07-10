# Rubric: Notification preferences settings form

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the rendered result and the source together.

## Dimensions

### 1. Form structure & visual hierarchy
Is the form legible and well organized?
- **High (5):** Sections are clearly delineated with labels and helpful
  descriptions; related controls are grouped; consistent alignment and
  spacing; the page scans easily.
- **Low (0-1):** A flat undifferentiated list of controls, missing group
  labels, cramped or inconsistent layout.

### 2. State handling (dirty / save / cancel)
Does the save lifecycle behave correctly?
- **High (5):** Save is disabled until a real change, enabled on any
  change; Cancel accurately reverts to last-saved; Save confirms and
  resets dirty state; toggling back to original values correctly
  re-disables Save.
- **Low (0-1):** Save always enabled or never enables, Cancel doesn't
  revert, dirty state is wrong, or Save gives no feedback.

### 3. Edge-case & conditional logic
Are the special cases handled thoughtfully?
- **High (5):** Security alerts are on and clearly non-optional with an
  explanation; quiet-hours inputs sensibly reflect push state; digest is
  strictly single-select; time inputs validate from < to (or handle it
  gracefully).
- **Low (0-1):** Security alerts toggleable off, quiet hours disconnected
  from push state, multiple digest options selectable, or invalid time
  ranges silently accepted.

### 4. Accessibility
Is the form operable with keyboard and assistive tech?
- **High (5):** Every control has an associated label; toggles/radios use
  native or correctly-`role`d controls with keyboard support and visible
  focus; the disabled non-optional toggle communicates why; confirmation
  is announced.
- **Low (0-1):** Unlabeled controls, `div` toggles with no keyboard
  access, no focus states, or contrast failures.

### 5. Code clarity
Is the single-file source clean and maintainable?
- **High (5):** Form state modeled in one place and rendered from it;
  dirty-checking derived rather than hand-tracked per field; no
  duplicated control markup; readable CSS.
- **Low (0-1):** State scattered across the DOM, per-field boolean
  bookkeeping, copy-pasted control blocks, tangled event handlers.
