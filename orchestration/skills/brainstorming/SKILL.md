---
name: brainstorming
description: >-
  Collaborative dialogue to turn a vague design question into a concrete proposal before any code is written. Use whenever the user is unsure how to approach something, when multiple plausible designs have non-obvious tradeoffs, when a new feature's data model is unclear, or pre-discovery when the conductor isn't sure what to explore. Trigger phrases: "how should we approach X?", "what's the best way to …?", "I'm torn between A and B", "should we …?". The skill asks one question at a time, surfaces tradeoffs honestly, offers a recommendation, and converges on a single approach before handing off to `writing-plans`. Do NOT use for implementation planning of an already-decided design, debugging (use `systematic-debugging`), refactoring of code whose target shape is clear (use `refactoring`), or pure codebase questions ("where is X defined?" — use `Explore`).
---

# brainstorming

The skill that runs before any code is written. Its job is to take a
fuzzy idea and end with a one-paragraph design summary the user has
bought into. No artifacts beyond that summary — `writing-plans` takes
it from there.

## When this fires

- The user asks "how should we approach X?" / "what's the best way
  to …?" / "should we A or B?".
- A new feature with an unclear data model.
- Multiple plausible designs, none obviously better.
- Pre-discovery: the user has a goal but no concrete idea of which
  files or systems will be involved.

It does **not** fire for:

- Implementation planning of a decided design — go straight to
  `writing-plans`.
- Debugging — `systematic-debugging`.
- Refactoring whose target shape is already clear.
- Pure codebase questions — dispatch `Explore`.

## Dialogue style

### One question at a time

The model's natural pull is to dump every consideration at once. Resist
that. The user can't usefully react to ten open questions
simultaneously. Ask one, react to the answer, ask the next.

### Multiple choice where it fits

If the question has a small set of plausible answers, offer them as
options with the tradeoffs spelled out. Use the host's structured input
control when one is available; otherwise present the choices concisely in
conversation. Open-ended questions are for genuinely open spaces.

A question like "should this be a queue or a stream?" is a multiple
choice question — present 2-4 options with their tradeoffs. A
question like "what should the API look like?" is open and benefits
from concrete sketches you propose for reaction.

### Surface tradeoffs honestly

For every option, name what it's good at AND what it costs. A
recommendation is fine — and often the user wants one — but never
present a recommended option without naming its downside.

### Offer a recommendation, accept redirection

The user will often ask "what would you do?". Answer concretely. Then
treat any redirection ("hmm, I'd rather …") as new information, not
as resistance to argue against. The user knows their system; you
know patterns. Combine, don't compete.

## The arc

A brainstorming session has a shape:

1. **Frame** — restate what the user wants in your own words. Confirm
   the framing matches. Misframing is the most common waste.
2. **Map the option space** — what are the realistic approaches?
   Three or four is usually enough. More than that and you're listing
   variations, not options.
3. **Surface constraints** — what limits the choice? Existing
   architecture, deadlines, team familiarity, dependency budget.
4. **Compare on the constraints** — score each option against the
   constraints. The winner often becomes obvious.
5. **Pick** — converge on one approach. If the user is genuinely
   torn, name what evidence would resolve it and propose a quick
   experiment.
6. **Summarize** — one paragraph: the problem, the chosen approach,
   the main tradeoff accepted. This is the handoff to
   `writing-plans`.

## What stays out

- **Code.** Brainstorming produces a design summary, not an
  implementation. If a code sketch helps illustrate an option, it's a
  pseudocode block in chat, not a file write.
- **Discovery sweeps.** If the conversation needs facts from the
  codebase ("how big is the auth module?"), dispatch a read-only
  exploration worker and feed its bounded answer back into the dialogue.
  Don't pause brainstorming to run a wide search in the host context.
- **Premature plans.** Don't draft `plan.json` here — that's
  `writing-plans`. The exit artifact is the design summary, period.

## Handoff to `writing-plans`

When the user has bought into an approach, hand off with:

> "Approach: <one paragraph summarizing the chosen design and the
> main tradeoff>. Discovery references: <files / modules / docs the
> plan will touch>. Want me to draft the plan?"

The user's confirmation is the signal for `writing-plans` to fire.

## Interaction with other skills

- `writing-plans` — the natural next step. Brainstorming's output
  paragraph becomes the Approach section of `masterPlan.md`.
- `engineering-discipline` — applies once code starts being written.
  During brainstorming, the relevant discipline is honest tradeoff
  presentation, not type safety.
- A read-only exploration worker — dispatched mid-brainstorm when the
  conversation hits a factual question about the codebase.

## Failure surface

- **Solutioning before framing.** Jumping to "let's build X" before
  confirming what the user actually wants. Always start with the
  reframe.
- **Option overload.** Listing eight approaches because they're
  technically possible. Trim to the three or four that fit the
  constraints; mention the rest only if the user asks.
- **Pretending neutrality.** "Either could work, what do you want?" is
  a cop-out when you have an opinion. Offer the recommendation, name
  the cost.
- **Drifting into implementation.** "We'd add a `Service` class, then
  a repository, then …" — that's planning, not brainstorming. Stop
  and hand off.
- **Not converging.** Brainstorming sessions that don't end with a
  picked approach are just chat. Close the loop before letting the
  user go.
