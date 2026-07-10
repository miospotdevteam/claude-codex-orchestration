# Rubric: Dashboard empty state

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Judge the rendered result and the source together.

## Dimensions

### 1. Tone & copy
Does the empty state feel inviting and explain the value of a project?
- **High (5):** Warm, concise copy that orients a first-time user and
  motivates the first action; no jargon, no dead "No data" placeholder
  phrasing.
- **Low (0-1):** Cold or generic ("Nothing here"), missing the "what/why"
  of a project, or wordy and cluttered.

### 2. Action hierarchy
Are primary, secondary, and tertiary paths clearly ranked?
- **High (5):** "Create your first project" is the obvious primary
  action; "Import from a template" is present but visibly secondary; the
  help link is clearly tertiary. One focal point, no competition.
- **Low (0-1):** Two buttons with equal weight, or the primary action is
  not visually dominant, or the help link competes with the CTA.

### 3. Visual composition & illustration
Is the empty state balanced and is the graphic tasteful?
- **High (5):** Centered, well-proportioned composition; the illustration
  suits the context and adds warmth without noise; confident use of
  whitespace.
- **Low (0-1):** Awkward alignment, an oversized or off-topic graphic, or
  a barren layout that reads as broken.

### 4. Accessibility
Is the page usable with keyboard and assistive tech?
- **High (5):** Semantic landmarks/headings, focusable actions with
  visible focus, adequate contrast, and the decorative illustration is
  hidden from assistive tech (e.g. `aria-hidden`) rather than announced.
- **Low (0-1):** No focus states, poor contrast, non-semantic buttons, or
  the decorative SVG is exposed as meaningful content.

### 5. Code clarity
Is the single-file source clean?
- **High (5):** Semantic HTML, coherent CSS naming, no dead code, layout
  achieved with modern CSS rather than hacks.
- **Low (0-1):** Div soup, magic numbers, inline-style clutter, or copy
  duplicated across markup.
