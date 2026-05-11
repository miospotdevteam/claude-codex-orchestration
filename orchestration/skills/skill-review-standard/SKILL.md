---
name: skill-review-standard
description: "Post-creation quality gate for skills. Runs structural validation, a functional with/without test, and trigger overlap analysis to produce a SHIP/REVISE/BLOCK verdict. Use after finishing a skill with skill-creator, or when reviewing any skill before shipping. Also use when the user asks to 'review my skill', 'check skill quality', 'is this skill ready to ship', or 'validate this skill'. Do NOT use for: creating skills from scratch (use skill-creator), learning skill conventions (use plugin-dev:skill-development), or reviewing application code."
---

# Skill Review Standard

A quality gate that answers one question: **should this skill ship?**

Not a prose rubric. Not a checklist. A functional test backed by structural
validation. If the skill doesn't add value over baseline Claude, it doesn't
ship.

**Announce at start:** "Running the skill review quality gate."

---

## Phase 1: Structural Validation

Run the automated validation script on the target skill directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/skill-review-standard/scripts/validate-structure.sh <skill-directory>
```

The script checks:
- SKILL.md exists with valid frontmatter (name + description)
- Description includes negative trigger guidance ("do not use when")
- SKILL.md is under 500 lines
- All referenced files (references/, scripts/) exist on disk
- No orphaned files in references/ or scripts/

**If any FAIL:** Stop here. Verdict is **BLOCK**. Report the failures and
what needs fixing. Structural problems must be resolved before functional
testing — there's no point testing a skill that references nonexistent files.

**If all PASS/WARN:** Continue to Phase 2.

---

## Phase 2: Functional Test

This is the core of the review. A skill that doesn't add value over
baseline Claude has no reason to exist.

### 2.1 Generate a test prompt

Create 1 realistic test prompt — the kind of thing a real user would say
that should trigger this skill. Make it substantive enough that a skill
would genuinely help (not a trivial one-liner Claude can handle without
any skill).

Present the prompt to the user: "I'll test the skill with this prompt.
Does it look realistic?"

### 2.2 Run with-skill vs without-skill

Spawn 2 subagents in parallel:

**With-skill agent:**
```
Read the skill at <skill-path>/SKILL.md, then follow its instructions to
complete this task: <test prompt>
Save your output to <workspace>/with_skill/output.md
```

**Without-skill agent:**
```
Complete this task using your best judgment (no special skill or rubric):
<test prompt>
Save your output to <workspace>/without_skill/output.md
```

### 2.3 Compare outputs

Read both outputs. Answer these questions:

1. **Structure:** Did the with-skill output follow a more consistent,
   repeatable format?
2. **Completeness:** Did the with-skill output cover things the baseline
   missed?
3. **Quality:** Was the with-skill output more useful to the end user?

If the skill added clear value on at least one dimension without degrading
the others, it passes. If the outputs are essentially equivalent — or the
baseline was better — the skill fails this phase.

**If no value added:** Verdict is **BLOCK**. The skill doesn't justify its
existence. Report what both outputs looked like and why the skill didn't help.

**If value added:** Continue to Phase 3.

---

## Phase 3: Trigger Overlap

Check whether the skill's description conflicts with other installed skills.

### 3.1 Collect adjacent skill descriptions

Read the available skills list from your context (the skill descriptions
injected at session start). If not available, scan installed skill
directories for SKILL.md frontmatter.

### 3.2 Compare for overlap

For each installed skill, check: could a user's prompt reasonably trigger
both this skill and the other? Look for:

- Shared keywords or domains without explicit boundary ("both claim
  refactoring")
- Scope creep clauses ("also use for X" where X belongs to another skill)
- Missing negative triggers that would disambiguate

### 3.3 Report overlaps

Flag any overlaps found. An overlap is blocking if both skills would
produce conflicting guidance for the same prompt. An overlap is a warning
if the skills have related but distinct scopes that could be clarified
with better description boundaries.

---

## Verdict

Produce the review report in this format:

```
# Review: <skill-name>

## Structural Checks
<output from validate-structure.sh, one line per check>

## Functional Test
Prompt: "<the test prompt used>"
With skill: <1-sentence summary>
Without skill: <1-sentence summary>
Value added: Yes/No — <1-sentence why>

## Trigger Overlap
Checked against <N> installed skills.
<list any overlaps, or "No overlaps found.">

## Verdict: SHIP / REVISE / BLOCK
<1-2 sentences explaining the verdict>
```

### Verdict criteria

- **SHIP** — All structural checks pass, functional test shows clear value,
  no blocking trigger overlaps.
- **REVISE** — Structural warnings (not failures), or minor trigger overlap
  that can be fixed by tightening the description, but the skill adds
  genuine value.
- **BLOCK** — Any structural failure, no value over baseline, or dangerous
  trigger overlap that would cause the skill to hijack prompts from a more
  appropriate skill.

---

## Phase 4: Quantitative Evaluation

After the verdict is determined, optionally run quantitative benchmarks to
measure skill performance with statistical rigor. This phase is recommended
for skills that will be used frequently or where trigger precision matters.

### 4.1 Run evaluation

Use the eval scripts in `scripts/`:

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/skills/skill-review-standard/scripts"

# Run 3 evaluation rounds with the test prompt from Phase 2
python3 "$SCRIPTS/run_eval.py" \
  --skill-dir <skill-directory> \
  --prompt "<test prompt from Phase 2>" \
  --output-dir .temp/eval-results/ \
  --runs 3
```

This runs the skill against the prompt multiple times and grades each run
on structure (1-5), completeness (1-5), and quality (1-5).

### 4.2 Aggregate results

```bash
python3 "$SCRIPTS/aggregate_benchmark.py" \
  --results-dir .temp/eval-results/ \
  --output .temp/eval-results/aggregate.json
```

Reports mean, stddev, min, max per dimension. **Pass threshold: overall
mean >= 3.5.** High variance (stddev > 1.0) signals inconsistent skill
behavior — investigate before shipping.

### 4.3 Improve description (optional)

If trigger precision is a concern (overlaps found in Phase 3, or the skill
fires on prompts it shouldn't):

```bash
python3 "$SCRIPTS/improve_description.py" \
  --skill-dir <skill-directory> \
  --dry-run
```

Reviews the description against all installed skills and suggests
improvements for better trigger accuracy. Remove `--dry-run` to apply.

### 4.4 Generate report

```bash
python3 "$SCRIPTS/generate_report.py" \
  --results-dir .temp/eval-results/ \
  --skill-name <skill-name> \
  --output .temp/eval-results/report.html
```

Produces a self-contained HTML report with pass/fail indicators, per-run
scores, and the overall verdict. Share with the team or attach to the
skill's PR.

---

## Boundaries

This skill must NOT:
- Modify the skill under review (it's a gate, not an editor)
- Skip the functional test (Phase 2 is mandatory)
- Produce verbose prose findings or severity-rated issues (that's the old
  approach — keep the output compact and data-driven)
- Replace skill-creator's iterative improvement loop (this is a one-shot
  ship/no-ship decision)

The user may proceed autonomously through all three phases. User
confirmation is only needed for the test prompt (2.1) and when reporting
the final verdict.
