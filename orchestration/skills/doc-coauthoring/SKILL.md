---
name: doc-coauthoring
description: "Collaborative document authoring through structured dialogue — RFCs, design docs, ADRs, specs, proposals, technical writing, runbooks, onboarding guides, API documentation, decision docs, postmortems, and any prose artifact where clarity and completeness matter. Use whenever the user wants to write, draft, or co-author documentation, specifications, technical proposals, architecture decision records, runbooks, onboarding guides, API docs, or any structured prose document. Also trigger when the user says 'help me write', 'draft an RFC', 'document this decision', 'write a spec', 'I need a design doc', or 'help me explain this'. Do NOT use when: making code changes without documentation output, implementing features, debugging, doing code review without documentation deliverables, writing inline code comments, updating README files as part of a code change, or adding JSDoc/docstrings as part of implementation work."
---

# Doc Coauthoring

Co-author documents through structured dialogue. Your job is not to
generate text — it is to draw out what the author knows, organize it into
something readers can act on, and then verify that readers actually
understand it.

Most documentation fails not because the writing is bad, but because the
author skipped one of three things: understanding the audience, iterating
on structure, or testing comprehension. This skill enforces all three.

**Announce at start:** "I'm using the doc-coauthoring skill to co-author
this document through structured dialogue."

**No full drafts in one shot.** The document is built section by section,
with the user reviewing and steering at each step. Dumping a complete
document and asking "does this look good?" produces mediocre results
because users approve things they haven't carefully read.

---

## Prerequisites

This skill operates within the conductor's phases:

- **Stage 1** (Context Gathering) runs during Step 1 (Explore) — the
  exploration here is conversational, not codebase-oriented. You are
  exploring the author's knowledge and the document's requirements.
- **Stage 2** (Refinement & Structure) runs during Step 3 (Execute) —
  the execution here is iterative drafting with the Edit tool, not code.
- **Stage 3** (Reader Testing) runs as a verification step — analogous
  to Step 4 (Verify) but testing comprehension instead of compilation.

Because the "codebase" is a document, the engineering-discipline rules
adapt: "read before editing" means reading what the user has already
written or said. "Track blast radius" means tracking how a change to one
section affects the coherence of others. "Verify" means reader testing.

---

## Integration with Other Skills

**After brainstorming:** If `brainstorming` ran first and produced a
`design.md`, consume its outputs as raw material for the document. The
design's Problem, Scope, Chosen Approach, Alternatives Considered, and
Key Decisions sections map directly to corresponding sections in a design
doc or RFC. Do NOT re-ask questions that brainstorming already answered —
use the design.md and fill gaps only.

**Standalone:** If no brainstorming preceded this skill, run the full
Stage 1 context gathering. The user's brain-dump replaces the
brainstorming design as the raw material.

**Orbit integration:** After Stage 2 produces a complete draft, present
it for user approval via Orbit (`orbit_await_review`). After Stage 3
reader testing, present revisions via Orbit if substantive changes were
made.

---

## Stage 1: Context Gathering

The goal is to extract everything the author knows before imposing any
structure. Structure too early kills ideas; structure too late produces
incoherent documents.

### 1.1 Meta-questions

Ask these first — they constrain every decision that follows:

1. **Who is the audience?** Not "engineers" — which engineers? Backend
   engineers who know the system? New hires who don't? External partners
   with no codebase access? The audience determines vocabulary, assumed
   knowledge, and level of detail.

2. **What is the document's goal?** What should someone DO after reading
   it? Approve a proposal? Follow a procedure? Understand a decision that
   was already made? The goal determines whether the tone is persuasive,
   instructional, or explanatory.

3. **What format fits?** Each format has conventions that readers expect:

   | Format | When to use | Key sections |
   |---|---|---|
   | **RFC** | Proposing a change that needs buy-in | Problem, Proposal, Alternatives, Migration |
   | **ADR** | Recording a decision already made | Context, Decision, Consequences |
   | **Design doc** | Explaining how something will work | Goals, Non-goals, Design, Trade-offs |
   | **Spec** | Defining exact behavior for implementers | Requirements, Behavior, Edge cases |
   | **Runbook** | Guiding operators through procedures | Prerequisites, Steps, Rollback, Escalation |
   | **Onboarding guide** | Getting new people productive | Setup, Concepts, First tasks, References |
   | **API documentation** | Enabling consumers to integrate | Authentication, Endpoints, Examples, Errors |
   | **Postmortem** | Learning from an incident | Timeline, Root cause, Impact, Action items |
   | **Proposal** | Pitching an idea to stakeholders | Problem, Solution, Cost, Timeline, Risks |

4. **What's the lifecycle?** Will this document be updated regularly
   (living doc) or is it a snapshot (decision record)? Living docs need
   clear ownership and update triggers. Snapshots need enough context to
   be understood without the original author.

5. **What exists already?** Are there prior documents, Slack threads,
   meeting notes, or code comments that contain relevant context? If so,
   the user should share them — this avoids re-deriving things the
   organization already knows.

### 1.2 Info dump

After meta-questions, let the user brain-dump everything they know about
the topic. Do NOT interrupt with structure. Do NOT correct or organize.
Just absorb.

Prompt with: "Tell me everything you know about this topic — context,
constraints, opinions, things you're unsure about, things you think are
obvious but might not be. Don't worry about order or completeness. I'll
ask follow-up questions after."

The brain-dump is raw material. Some of it will become the document.
Some will become context that informs tone and emphasis. Some will be
discarded. That's fine — the point is to get everything out of the
author's head so nothing is forgotten once structure takes over.

### 1.3 Clarifying questions

After the brain-dump, identify gaps. Ask 5-10 questions that are
**specific to what the user said**, not generic. Bad questions ask about
things you could figure out yourself. Good questions surface things only
the author knows.

Bad questions (generic, answerable by reading):
- "Can you tell me more about the architecture?"
- "What technologies are you using?"
- "Is this important?"

Good questions (specific, gap-filling):
- "You mentioned the migration needs to be zero-downtime, but the
  current schema has a NOT NULL constraint on the old column. How are
  you handling the transition period where both old and new code run
  simultaneously?"
- "The runbook says to restart the service, but you also said the
  service takes 90 seconds to warm up. Should the runbook include a
  health check step before routing traffic back?"
- "You listed three alternatives but didn't mention why you ruled out
  the event-sourcing approach that the payments team uses. Was there a
  specific reason, or should we include it as a considered alternative?"

Ask questions one at a time using the `AskUserQuestion` tool when the
question has a clear set of possible answers. Use open-ended text when
the question requires explanation.

### Exit criterion

Stage 1 is complete when you can answer:

- Who will read this document and what they already know
- What the document should accomplish (the reader's action after reading)
- What format and sections are appropriate
- The key claims, decisions, or procedures the document will contain
- What's explicitly out of scope

If you cannot confidently answer all five, ask more questions. Do NOT
proceed to Stage 2 with gaps — they become incoherent sections later.

---

## Stage 2: Refinement & Structure

The goal is to go from raw context to a polished draft through iterative
refinement. Never write the whole document at once — build it section by
section with user feedback at each step.

### 2.1 Proposed outline

Generate a proposed outline with section headings and a 1-line summary
of what each section covers. The outline should follow the conventions
of the chosen format (from Stage 1.1).

Present the outline to the user. Ask:
- "Does this ordering make sense for your audience?"
- "Is anything missing that should be a top-level section?"
- "Is anything here that doesn't belong?"

Iterate until the outline is approved. The outline is the skeleton —
everything else hangs on it.

### 2.2 Section-by-section brainstorming

For each section in the approved outline, brainstorm 5-20 options for
key points, phrasings, framings, or approaches. This is where creative
breadth happens — before narrowing to a single draft.

**Why brainstorm before drafting:** A first draft locks in assumptions.
If you brainstorm 10 ways to frame the "Problem" section and the user
picks the framing that resonates, the resulting draft is far better than
the one you would have written from your first instinct.

What to brainstorm per section:
- **Content options**: What key points to include vs. omit
- **Framing options**: How to present the information (chronological?
  by importance? by audience concern?)
- **Phrasing options**: For critical sentences — the thesis, the
  recommendation, the key trade-off statement
- **Depth options**: How deep to go (summary vs. detailed analysis)
- **Visual options**: Would a table, diagram, timeline, or code example
  serve better than prose?

Present options to the user. Use `AskUserQuestion` for clear-cut
choices. Curate together: which options land? Which need revision? Which
should be combined?

### 2.3 Iterative drafting

Write the document section by section using the Edit tool. After each
section:

1. Let the user read it
2. Ask for specific feedback: "Does this accurately represent your
   intent? Is anything missing? Is the tone right for your audience?"
3. Revise based on feedback before moving to the next section

**Do NOT write all sections and then ask for feedback.** By the time a
user reads a 2000-word draft, they've lost the energy to give detailed
feedback on each section. Section-by-section review catches problems
early when they're cheap to fix.

### 2.4 Tone calibration

The right tone depends on the audience and goal from Stage 1:

| Audience + Goal | Tone |
|---|---|
| Engineers + technical decision | Precise, direct, evidence-based. Short sentences. Code examples. |
| Leadership + proposal | Clear, confident, outcome-focused. Quantify impact. Lead with the ask. |
| New hires + onboarding | Warm, patient, no jargon without definition. "You'll see X" not "X exists." |
| External partners + API docs | Neutral, complete, example-heavy. Assume nothing about internal context. |
| Incident reviewers + postmortem | Factual, blameless, timeline-driven. Clear separation of what happened vs. what we'll do. |

If the tone feels wrong during drafting, stop and recalibrate. Ask the
user: "This section reads as [X] — is that the right register for
[audience]? Should it be more [Y]?"

### 2.5 Cross-section coherence

After all sections are drafted, read the document end-to-end and check:

- **Terminology consistency**: Is the same concept called the same thing
  everywhere? ("service" vs. "microservice" vs. "API" — pick one)
- **Forward references**: Does any section reference something that
  hasn't been introduced yet?
- **Redundancy**: Do two sections make the same point? Consolidate.
- **Flow**: Does each section lead naturally into the next? Add
  transition sentences where the jump is jarring.
- **Scope creep**: Did any section drift beyond what's in scope? Cut it
  or move it to an appendix.

### Exit criterion

Stage 2 is complete when:

- Every section from the approved outline has been drafted and reviewed
- The user has approved each section individually
- Cross-section coherence check has passed
- The tone is calibrated for the target audience
- The document reads as a single coherent piece, not a collection of
  independently written sections

---

## Stage 3: Reader Testing

The goal is to verify that the document communicates what the author
intends. Writers are the worst judges of their own clarity — they fill
in gaps from memory that readers don't have.

### 3.1 Sub-agent approach (preferred)

Spawn a fresh Claude Code sub-agent with NO context from the writing
process. This is critical — the sub-agent must simulate a naive reader,
not a collaborator who already knows the backstory.

**Setup:**
1. Write 2-3 comprehension questions tailored to this document. These
   should test the document's KEY claims, not trivia. Examples:
   - "What is the primary risk of the proposed approach, and how does
     the document propose to mitigate it?"
   - "If you needed to execute step 4 of this runbook and the health
     check failed, what would you do?"
   - "What alternatives were considered and why were they rejected?"

2. Dispatch a foreground sub-agent with ONLY:
   - The document text (read the file path)
   - These instructions:
     ```
     You are a reader testing this document for clarity and completeness.
     You have NO prior context about this topic — only what the document
     tells you.

     1. Summarize the document in 3 sentences.
     2. List the top 3 decisions or recommendations the document makes.
     3. Identify any sections that are confusing, incomplete, or
        contradictory.
     4. Answer these comprehension questions:
        [insert your 2-3 questions here]
     5. List any terms or acronyms used without definition.
     6. Note any place where you had to re-read a sentence to understand
        it.
     ```

3. Do NOT include any context from Stage 1 or Stage 2 in the sub-agent
   prompt. No brain-dump content, no design.md, no conversation history.
   The sub-agent must work from the document alone.

**Evaluation:**
Compare the sub-agent's responses against the author's intent:

| Sub-agent result | What it means | Action |
|---|---|---|
| Summary matches intent | Core message is clear | No change needed |
| Summary misses a key point | That point is buried or unclear | Elevate it — move earlier, make it a heading, add emphasis |
| Wrong answer to comprehension question | The document is ambiguous or misleading | Rewrite the relevant section for clarity |
| "Confusing" flag on a section | The section assumes context the reader doesn't have | Add context, define terms, or restructure |
| Terms listed without definition | Jargon leak | Add definitions or a glossary |
| Re-read needed | Sentence is too complex or poorly structured | Simplify — shorter sentences, clearer antecedents |

### 3.2 Manual approach (fallback)

For environments where sub-agents are not available, simulate the reader
test yourself. This is less reliable than the sub-agent approach because
you wrote the document and cannot fully forget your context, but it
still catches obvious gaps.

1. Write the same 2-3 comprehension questions
2. Read the document from top to bottom as if encountering it for the
   first time. For each section, ask: "If I knew NOTHING except what
   this document has told me so far, would I understand this?"
3. Answer the comprehension questions using ONLY information in the
   document — do not draw on conversation context
4. Flag any section where you had to rely on knowledge from Stage 1
   that isn't in the document text

### 3.3 Revision from reader test

For each gap identified in 3.1 or 3.2:

1. Identify the root cause — is it missing context, bad structure,
   ambiguous phrasing, or assumed knowledge?
2. Propose a specific fix to the user
3. Apply the fix using the Edit tool
4. If the fix is substantial (more than a sentence), re-run the
   relevant comprehension question on the revised section

### 3.4 Final review via Orbit

After reader testing revisions are complete, present the final document
for user approval:

1. Fetch Orbit tools: `ToolSearch query: "+orbit await_review"`
2. Call `orbit_await_review` on the document file
3. Handle response:
   - **Approved**: Document is done. Record completion in plan.json.
   - **Changes requested**: Apply changes, re-run affected reader test
     questions, then re-submit.

### Exit criterion

Stage 3 is complete when:

- Reader test has been run (sub-agent or manual)
- All comprehension questions answered correctly from document alone
- All "confusing" flags resolved
- User has approved the final document

---

## Boundaries

This skill must NOT:

- **Modify code files.** This skill produces documents, not code. If the
  document references code that needs changing, flag it as a follow-up
  task — do not make the code change yourself.
- **Skip Stage 1**, even for "quick" documents. A 1-page ADR still
  needs audience, goal, and format decisions. The meta-questions take
  2 minutes and prevent rework. The only exception: if brainstorming
  already ran and produced a design.md that answers all Stage 1
  questions.
- **Generate the full document in one shot** without iterative
  refinement. No matter how clear the requirements seem, section-by-section
  drafting with user review produces better results than a single
  generation pass. The user's feedback on Section 1 changes how you
  write Section 5.
- **Hallucinate technical details.** If the document describes system
  behavior, architecture, or procedures, every claim must come from the
  user's input or from reading actual code/config. If you're unsure
  about a technical detail, ask — do not guess and present it as fact.
- **Overwrite the user's voice.** The document should sound like the
  author wrote it with expert help, not like an AI wrote it. Match the
  user's vocabulary, phrasing preferences, and level of formality. If
  the user writes "we" in their brain-dump, the document says "we." If
  they write formally, maintain that register.

---

## Principles

- **Extract, don't generate** — the best material comes from the
  author's head, not yours. Your job is to organize and clarify.
- **Structure follows content** — gather everything first, then impose
  structure. Premature structure kills ideas.
- **One section at a time** — iterative feedback beats end-of-draft
  review every time.
- **Test with fresh eyes** — if a naive reader can't understand the
  document, the document is incomplete, no matter how obvious the
  content seems to the author.
- **Tone is not decoration** — the wrong tone for the audience makes
  even correct information ineffective.
- **Explicit scope prevents bloat** — every document should state what
  it does NOT cover. This is especially true for RFCs and design docs.
