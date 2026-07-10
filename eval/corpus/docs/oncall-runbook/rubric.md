# Rubric: On-call runbook

Judge-only. Score each dimension **0-5**; the task score is the mean of
the dimensions. Compare against the source of truth in the spec.

## Dimensions

### 1. Accuracy & safety fidelity
Are the facts correct and the safety caveats preserved?
- **High (5):** Commands, endpoints, and causes match the source; the
  critical caveat (naive scale-up worsens DB pool pressure and is unsafe;
  rollback/restart are safe) is stated clearly and correctly; no invented
  infrastructure.
- **Low (0-1):** Recommends the dangerous scale-up as a default, invents
  tools/commands, or gets the causes wrong.

### 2. Diagnostic flow (actionability under pressure)
Can a groggy responder follow it to a diagnosis fast?
- **High (5):** An ordered, decision-tree-like triage that references the
  specific Grafana panels, log query, and `/readyz` check to distinguish
  DB saturation vs Stripe vs bad deploy; each step says what to look at
  and what the result means.
- **Low (0-1):** Vague "investigate the issue" prose, no ordering, or no
  reference to the concrete signals.

### 3. Completeness
Are all required sections present and useful?
- **High (5):** Header/summary, prerequisites, triage, per-cause
  mitigation, escalation (with the 20-minute trigger and who to page),
  and a verification step are all present.
- **Low (0-1):** Missing escalation, verification, prerequisites, or
  mitigation for a known cause.

### 4. Structure & skimmability
Is it laid out for 3am use?
- **High (5):** Clear headings, short numbered/bulleted steps, copyable
  commands in code blocks, the critical warning visually called out;
  scannable, not a wall of prose.
- **Low (0-1):** Dense paragraphs, buried commands, warning easy to miss.

### 5. Clarity & tone
Is it precise and calm without hand-waving?
- **High (5):** Direct, unambiguous instructions; distinguishes "safe" vs
  "dangerous" actions explicitly; no assumed deep knowledge of the
  service.
- **Low (0-1):** Ambiguous, assumes tribal knowledge, or hedges so much
  the responder can't act.
