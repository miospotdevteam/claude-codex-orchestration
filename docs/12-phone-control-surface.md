# 12 — Phone-from-anywhere control surface

> **Historical design input — not the current product contract.** This PWA/SSE
> proposal predates the Mini-resident workflow registry, mirror journal, APNs
> notification backend, and the user's explicit native-app decision. Do not
> implement or ship a web app from this document. The resumed T3/mobile plan
> must replace it with a native iOS client over the guarded workflow-ID API,
> while preserving the security and single-writer invariants worth carrying
> forward.

This document specifies a **private, installable phone web app that lets one
operator drive the same guarded Mac Mini agent sessions from anywhere**, over a
private network, without opening any new authority. It re-exposes the agent
verbs that are already host-independent, keeps the two ownership-changing verbs
on the operator's laptop, and gates the one genuinely new capability — starting
a fresh Mini session from the phone — behind an explicit, single-use
**cession** the operator arms in advance.

The surface adds no new protocol, no bearer tokens, no public exposure, and no
polling. It is a thin re-caller of authorities that already exist. Everything
below assumes a reader who has never seen the rest of this repository; the
concepts it depends on are defined inline, and cross-references (e.g.
`docs/05-skills-catalog.md`) are pointers, not required reading.

## The system this extends

Two machines cooperate:

- A **Mac Mini** hosts long-running coding-agent sessions. Six sessions are
  addressable: the two projects `miospot` and `orchestration`, each crossed
  with the three agent harnesses `claude`, `codex`, and `grok`. The Mini runs
  a session/lifecycle adapter and a synchronization authority.
- A **MacBook** holds the canonical Git checkout of each project. It is the
  machine from which work is normally launched and to which finished work is
  reclaimed.

Ownership of a project's working tree is a **single-writer lease**: at any
moment either the MacBook owns it (writer `none` — the local checkout is
authoritative) or the Mini owns it (writer `live`). A guarded host-side helper,
`remote-agent.sh`, is the only sanctioned way to move that lease. It exposes a
closed set of verbs — `status`, `start`, `inspect`, `continue`, `send`,
`interrupt`, `kill`, `wait`, `reveal`, `reclaim` — over exactly the two
projects and three harnesses. Prompt text always travels through a private file,
never on a command line. The protocol never infers that a session has stopped
mattering from a PID, a heartbeat, a closed terminal, or a timeout; only an
explicit guarded transition (a verified `kill` then `reclaim`) clears a lease.
`docs/05-skills-catalog.md` describes this helper and its natural-language skill
in full.

### Concepts this document assumes

| Term | Meaning here |
|---|---|
| **Tailnet** | A private WireGuard mesh network (Tailscale). Only enrolled devices can reach each other; there is no public exposure. |
| **Tailscale Serve** | A tailnet-only reverse proxy that terminates HTTPS on a device's private MagicDNS name and injects the caller's verified tailnet identity as a request header. Distinct from Funnel (public exposure), which stays **off**. |
| **Writer / lease** | Who owns a project's working tree. `none` = MacBook owns it; `provisional`/`live` = Mini owns it; `quiescent` = a Mini session was killed but the lease is not yet released. |
| **Generation** | A monotonic counter bumped on each ownership transition; used for compare-and-set (CAS) so a stale actor cannot win a race. |
| **Universe digest** | A content hash of a project's transfer universe — tracked files plus ordinary untracked regular files — with `.git` and symlinks refused, and the branch and HEAD tokens folded in. Two trees with the same digest are byte-identical in everything the protocol moves, *and* on the same branch and commit. |
| **Mutex** | A per-project on-disk lock. The multi-step ownership transitions (CAS, lease writes) are only safe while it is held. |
| **Cession** | A single-use, MacBook-issued token that says "the phone may start a Mini session on this exact baseline." Defined in full below. |
| **Bridge** | A worker on the MacBook that pulls queued ownership jobs over SSH and executes them locally. It never listens for inbound connections. |

## What this surface adds — and deliberately does not

Seven of the ten verbs (`status`, `inspect`, `continue`, `send`, `interrupt`,
`kill`, `wait`, plus the Mini-local `reveal`) already run entirely against Mini
state and need no canonical checkout. The phone surface re-exposes those as a
closed web API. The two verbs that touch the canonical checkout — a
MacBook-content `start` and `reclaim` — stay on the MacBook and are reached by a
pull bridge. The one new capability is a **Mini-content `start` from the
phone**, which is safe only behind the cession gate.

Out of scope, and refused by construction:

- Any public exposure: Funnel, port forwarding, public DNS, bearer/token APIs,
  OAuth, third-party relays, or push-notification vendors.
- Arbitrary projects, harnesses, hosts, shell commands, tmux/SSH/rsync
  controls, file browsers, selectable paths, or ignored-path approvals from the
  phone. The route matrix is closed to the two projects and three harnesses.
- Persisting prompts, captures, transcripts, terminal output, or screenshots
  anywhere in the new surface — Mini, bridge, service worker, or browser cache.
- New hook events, screenshot or lifecycle polling, or treating a wake hint as
  proof of quiescence.
- New `remote-agent.sh` verbs or flags beyond the cession pair (`cede` /
  `uncede`) described here; lease forcing, divergence/CAS/recovery bypasses, or
  automatic Git object transport outside the bundle sidecar.
- Prompted queued starts. A queued start carries no prompt; the first
  instruction arrives afterward through the phone's `continue`.
- Multi-user tenancy, RBAC, WebAuthn, native apps, app-store distribution, full
  terminal streaming, or Computer Use from the phone.

## Architecture

Five components, four of which are new:

1. **`agent-control` (new; Mini; bash).** The single Mini-local guarded-verb
   authority. It exposes the host-independent session verbs plus a
   cession-gated Mini-content `start` and a private labels-only bridge queue, by
   exec-ing the existing Mini adapter and synchronization authority with fixed
   arguments. It never reimplements the protocol; it re-calls it. The guarded
   mutex/quiescence ordering lives in this one place, and `remote-agent.sh`
   delegates its early verbs to it over SSH so the ordering is not duplicated.
2. **A read-only `peek` verb (new) on the synchronization authority.** It emits
   bounded writer / lease / generation / recovery / mutex-owner / cession JSON
   **without** requiring a caller digest and mutating nothing, so aggregate
   status and cession visibility cost no state change. It is also how a human
   diagnoses a wedged Mini (see the recovery runbook) without inferring anything
   from PIDs or heartbeats.
3. **`phone-control-gateway` (new; Mini; Python 3 standard library, single
   file).** An HTTP + Server-Sent-Events daemon bound to `127.0.0.1` only, run
   as a user LaunchAgent inside the Mini's GUI session (so `reveal` can open
   Terminal). It serves the static app and a closed JSON API; every handler
   exec-s `agent-control` with validated fixed atoms. It is Python because a
   hand-rolled shell HTTP/SSE parser is a security liability; it uses zero
   third-party dependencies and asserts its interpreter at startup.
4. **Tailscale Serve (existing infrastructure).** The sole TLS terminator, on
   the Mini's private MagicDNS name. Its valid certificate satisfies the PWA
   install requirement. Funnel is off; the gateway binds loopback only, so the
   Serve proxy is the *only* network path in. Serve injects the caller's
   `Tailscale-User-Login` identity header.
5. **`phone-control-bridge` (new; MacBook; bash).** A launchd-`KeepAlive` worker
   that holds one blocking SSH long-poll against the Mini's bridge queue. When a
   job appears it executes the literal, unmodified `remote-agent.sh start` or
   `remote-agent.sh reclaim` locally, so every existing guard applies verbatim,
   then reports a bounded outcome and a heartbeat. It has **no inbound listener**
   and adds no second HTTP auth class: it pulls over the already-trusted SSH
   path.

The read/session path and the ownership path are distinct:

```text
Session & read verbs:
  phone PWA ──HTTPS(tailnet)──▶ Tailscale Serve ──loopback──▶ gateway
            ──▶ agent-control ──▶ Mini adapter / synchronization authority

Ownership changes (MacBook-content start, reclaim):
  gateway enqueues a labels-only job ──▶ bridge SSH long-poll claims it
          ──▶ canonical MacBook checkout ──▶ remote-agent.sh ──▶ Mini protocol
```

Why this shape: the seven host-independent verbs become a thin local re-caller
of Mini authorities, not a new protocol; the two checkout-bound verbs stay where
the canonical checkout lives; and a sleeping MacBook cannot listen, so its work
must **queue**, never fail. Rejected alternatives were SSH-from-phone (no closed
surface), a public token API (forbidden), a MacBook-hosted bridge listener
(unreachable exactly when the laptop sleeps), and moving `start`/`reclaim`
authority onto the Mini (which would break the single-writer model).

## The offline boundary

"Asleep" means the **MacBook (and its bridge) is unreachable while the Mini and
the tailnet remain reachable** — the common case of a laptop lid closed in a bag.
The app shows a persistent "MacBook: reachable / last seen HH:MM" chip driven by
the bridge heartbeat. Actions that need the MacBook carry a laptop badge and, when
it is asleep, render an explicit queued state — never a faked completion.

| # | Capability | MacBook awake | MacBook asleep | Mechanism |
|---|---|---|---|---|
| 1 | See all six sessions | Works | **Works** | Gateway aggregates the six session statuses + read-only `peek` + queue state + heartbeat, via `agent-control status` |
| 2 | Inspect bounded state | Works | **Works** | Existing capped capture (≤ 40 lines / 4096 bytes), returned ephemerally, never stored or cached |
| 3a | Start on Mini content | Works | **Works when a valid cession exists** | `agent-control start` consumes an armed cession under the mutex, then CAS → lease-provisional → supervisor start → lease-commit (see the cession gate) |
| 3b | Start on MacBook content | Works (bridged) | **Queued, cancellable until claimed** | Labels-only job; the bridge runs the literal `remote-agent.sh start` on wake; the tile shows "Queued — MacBook required" |
| 4 | Send / continue | Works | **Works** | `agent-control continue` (capture-before-send by default; bare `send` is a labelled advanced action); prompt body → `0600` temp file → stdin, never a command-line argument |
| 5 | Event-driven wait | Works | **Works** | SSE backed by a blocking wait with restart-aware `EPOCH:NUMBER` cursors; reconnect resumes from the last cursor; no polling; wakes are hints, never quiescence proof |
| 6 | Interrupt | Works | **Works** | Mutex-guarded supervisor interrupt via `agent-control` |
| 7 | Kill | Works | **Works** | Mutex-guarded kill; `quiescent` is recorded only through the guarded protocol path |
| 8 | Reclaim | Works (bridged) | **Queued, never executed asleep** | Always a bridge job: the relation proof needs the MacBook's digest and the inbound transfer needs the canonical checkout; the UI shows the queued state and reason |

`reveal` ships as a Mini-local advanced action ("Reveal on Mini's Terminal") — a
closed verb with zero new surface, useful when the operator is physically near
the Mini.

## New-session semantics: the cession gate

Starting a *fresh* Mini session is the only phone action that can create a new
writer, so it gets the most scrutiny. There are two modes.

### Why digest equality alone is not enough

A naive rule would let the phone start a Mini session whenever writer is `none`
and the Mini's recorded baseline still matches the Mini's actual tree. That rule
is unsafe. Writer `none` means *the MacBook owns the tree*, and digest equality
proves only the last **synchronized** state — it says nothing about **unrecorded
local edits on a sleeping MacBook**. Silently starting a Mini writer on top of a
laptop that may have diverged since the last sync would create two writers, which
is exactly what the single-writer model forbids.

The fix is to require an explicit, MacBook-issued **cession**: a promise, made
while the MacBook holds the mutex and can prove it is clean and equal, that the
phone may take the tree from a named baseline. Without a cession, the phone
`start` route offers only the queued bridge start — never a silent
digest-equality fallback.

### The cession record

One `0600` record per project lives in the Mini's protocol state directory, so
it survives MacBook sleep. It is labels-only — no prompts, no paths, no free
text:

```json
{
  "issuerHost": "macbook",
  "generation": 42,
  "universeDigest": "sha256:9f1c…",
  "branch": "main",
  "head": "0af33ce…",
  "issuedAt": "2026-07-11T14:32:02Z",
  "state": "armed"
}
```

`state` is `armed` (created, not yet used) or `consumed` (a phone start took it;
it can never be reused). The digest binds the branch and HEAD and the manifest
options, not just file bytes — this matters for staleness, below.

### The state machine

The phone surface reads two coupled variables — the **writer** (`none`,
`provisional`, `live`, `quiescent`) and the **cession** (`none`, `armed`,
`consumed`) — plus the monotonic generation, the mutex, and an orthogonal
`recovery-required` fault flag. The transitions it depends on:

```text
        remote-agent.sh cede (MacBook, mutex held)
        writer=none, relation=equal, no recovery-required
  none/──────────────────────────────────────────────▶  none/armed
  none                                                   (MacBook ownership
    ▲                                                     relinquished under
    │  remote-agent.sh uncede (MacBook, mutex held,       the protocol)
    │  local digest == baseline)                            │
    └───────────────────────────────────────────────────── ┘
                                                             │ phone start consume
                                                             │ (Mini, mutex held,
                                                             │  cession valid)
                                                             ▼
                                                        live/consumed  ── phone kill ──▶ quiescent/consumed
                                                             │                                   │
                                                             └────────── reclaim (MacBook) ──────┘
                                                                          ▼
                                                                       none/none
```

Transitions, precisely:

| Transition | Runs on | Guard | Effect |
|---|---|---|---|
| `cede` | MacBook, mutex held | writer `none`; relation equal (Mini clean and byte-equal); no `recovery-required`; no existing cession | Writes an `armed` cession bound to the current generation and universe digest; relinquishes MacBook-local ownership under the protocol (CAS/generation-bound) |
| `uncede` | MacBook, mutex held | cession `armed` and unconsumed; local digest still equals the baseline | Clears the cession (release-last preserved) |
| Phone `start` consume | Mini, mutex held | cession valid (see the sequence below) | Atomic single-shot consume → `consumed`; a phone writer is committed |
| Provisional abort | Mini, mutex held | a start failed before lease-commit | Restores the cession to `armed`, rebound to the post-CAS generation with the digest re-verified; the restored cession stays consumable; writer returns to `none` |
| Phone `kill` | Mini | writer `live` | writer `quiescent`; the cession stays `consumed` |
| `reclaim` | MacBook (bridged or local) | verified quiescence / relation proof | Pulls Mini-only work, then clears the writer to `none` and clears any cession |
| MacBook-content `start` over an armed cession | MacBook, mutex held | local digest **equals** the cession baseline | Cancels the cession via CAS under the mutex, then proceeds with the content push; on a mismatch it **refuses** — no cancel-and-proceed with changed content |

`uncede`, a guarded MacBook-content `start` whose current digest matches the
baseline, and `reclaim` are the **only** transitions that clear a cession. While
a cession is armed or a phone writer is active, every incompatible guarded
mutation — a content-push start with changed content, a second `cede`, a
`stage`/`apply` — refuses with a distinct bounded reason.

### The honest cession contract (its human-edit limitation)

A cession is a **promise the operator makes**: "I will not touch this working
tree until I reclaim it." The protocol enforces that promise **fail-closed at
the next guarded operation**, not in real time — it cannot watch the filesystem.

Concretely: if the operator edits the MacBook working tree *after* ceding
(whether the laptop is awake or asleep), those edits are unrecorded and the
cession baseline no longer matches local content. This is **the same
single-writer violation as editing files during a live Mini lease** — the
protocol has no way to prevent it as it happens. What it guarantees instead is
detection: the **next guarded mutating MacBook operation** (`start`, `reclaim`,
`cede`, `uncede`) compares the current local digest against the active cession's
baseline and **fails closed** with a bounded refusal naming the post-cession
change. Read-only `status` reports the staleness as a bounded field but never
refuses on it.

The phone start itself stays airtight — it re-verifies the *actual Mini tree*
against the baseline — so a broken cede promise cannot corrupt the Mini. But it
can produce a MacBook that has silently diverged from the Mini the phone just
started. That divergence surfaces as a fail-closed refusal on the MacBook's next
guarded operation and as a non-fast-forward refusal at reclaim; nothing is lost
silently, but the operator has created a wedge only they can resolve. Ceding is
therefore a deliberate hand-off, not a background convenience.

### Strict-digest staleness (why benign commits also fail closed)

The universe digest binds the **branch and HEAD and the manifest options**, not
just file bytes. That makes staleness detection fail-safe rather than clever: a
*benign* local commit after ceding — one that changes nothing about the intended
work — still changes HEAD, so it still fails the baseline comparison and still
refuses. So does invoking a guarded operation with different manifest flags
(for example a different ignored-path selection) than the cede used. This is by
design: the protocol refuses anything it cannot prove is identical rather than
guessing which differences are safe. Operators should expect that *any* local
change after a cede — even a trivially safe one — does **not** revoke the armed
cession: the phone start validates only the Mini-side baseline, so it remains
possible. What the local change does is knock the *MacBook* out of alignment:
every subsequent guarded mutating MacBook operation (`cede`, `uncede`,
`reclaim`, a bridge-executed start) fails closed on the changed local digest.
The way out is to resolve the local change so the working copy is
baseline-equal again (typically by reverting it), after which `uncede` — or a
fresh MacBook start — proceeds normally; if a phone start consumed the cession
in the meantime, the situation is the diverged-MacBook wedge described above.

### The one-start-per-cession limit

A cession is single-use. It is consumed at the moment a phone start commits, and
nothing recreates it silently. This produces a limit worth stating plainly:

> **After a phone start followed by a phone kill while the MacBook sleeps, the
> project cannot be started from the phone again until the MacBook wakes,
> reclaims, and issues a fresh cede.**

The chain is: a phone `kill` leaves the writer `quiescent` and the cession
`consumed`. Clearing `quiescent` back to `none` requires `reclaim`, which needs
the canonical checkout — the MacBook. Arming a new phone start requires a fresh
`cede`, which also requires the MacBook and a clean/equal relation. So while the
laptop is asleep, the phone can still inspect, continue, interrupt, and kill,
but a **restart is only available as a queued bridge job** that drains when the
laptop wakes. The UI states this on the tile: one cession permits exactly one
start.

### Mode 1 — Mini-content start (works asleep, cession-gated)

The entire transaction runs under the project mutex, acquired with an owner
record and released last via a trap. The sequence:

1. Acquire the mutex (record the owner).
2. Verify the cession is valid: its generation equals the current generation;
   its digest equals both the recorded `remote` and `common` baselines **and**
   the actual Mini working-tree universe digest recomputed with the shared
   manifest rules; the Mini's Git is clean and attached; the tmux session is
   absent; writer is `none`; no `recovery-required`.
3. CAS-bump the generation.
4. Atomically consume the cession (single-shot; it accepts the just-incremented
   in-transaction generation, so the mainline consume never refuses its own
   transaction).
5. Write a provisional lease with an explicit writer record
   `host=<mini> origin=phone operation=start cessionRef=<id>`.
6. Start the supervisor session.
7. Commit the lease (writer `live`).

If any step before commit fails, the provisional lease is aborted and the
cession is **restored to `armed`** within the same mutex-held transaction,
rebound to the post-CAS generation with the digest re-verified — so ownership is
never transferred and the restored cession remains consumable by a later start.
After lease-commit the cession is `consumed` and never reappears without a fresh
MacBook `cede`.

Each precondition miss is a distinct bounded refusal: `no-cession`,
`stale-generation`, `digest-mismatch`, `dirty-tree`, `writer-present`,
`mutex-held`, `recovery-required`, `first-contact`. The Mini never adopts its own
drifted content as a new baseline, so the MacBook's divergence refusal keeps its
meaning: a later MacBook `start`/`reclaim` sees `writer=live` and refuses exactly
as it would for any Mini-owned tree.

### Mode 2 — MacBook-content start (queued, promptless)

When the operator wants to start from *laptop* content, the gateway enqueues a
labels-only job:

```json
{
  "requestId": "req-7c2a…",
  "verb": "start",
  "project": "orchestration",
  "agent": "claude",
  "state": "queued",
  "queuedAt": "2026-07-11T14:40:00Z"
}
```

The job carries **no prompt** — the first instruction flows later through the
phone's `continue` once the session is running, keeping the queue strictly
labels-only. There is one outstanding job per project × agent; it is cancellable
until claimed; claims use a durable generation CAS so duplicate delivery cannot
execute twice. On wake the bridge runs the literal `remote-agent.sh start`. If
state changed since queueing, the existing preflight refuses and the bounded
refusal reaches the tile. A bridge crash before execution leaves a re-claimable
job; after execution begins, the protocol's own `recovery-required`/refusal
states answer — success is never assumed. `reclaim` uses the same queue with
identical semantics.

### The one-winner race

A phone consume and a bridge-executed MacBook-content start can be attempted
concurrently. Both run under the same project mutex and the same generation CAS,
so there is **exactly one winner**: whichever acquires the mutex and wins the CAS
proceeds, and the loser refuses without mutating state. The cession is consumed
at most once, and it is never silently recreated.

### Transfer fidelity: the `reset --mixed` caveat

The bridged operations (a MacBook-content start's outbound push and a
`reclaim`'s inbound pull) reproduce the source working tree via a Git bundle
sidecar followed by `git reset --mixed <head>`. This makes the destination
tree's **content and paths** content-identical to the source, and a *clean*
handoff ends `git status`-clean at the exact transferred branch and HEAD. Dirty
source content is reproduced, never silently discarded.

One fidelity limit is deliberate and worth documenting so nobody is surprised:
`git reset --mixed` unstages everything, so the **staged/unstaged split is not
preserved**. If the operator had carefully staged a subset of changes on the
source before a transfer, after the transfer the *same file contents* are
present but **nothing is staged** — every change shows as unstaged in
`git status`. Transfers are content-faithful, not index-faithful. Alignment
never runs on a refusal path, and any alignment failure restores the prior refs
through the journal, so a failed transfer leaves the destination coherent rather
than half-applied.

## Security model

**Transport.** WireGuard tailnet end to end; HTTPS via Tailscale Serve with
Funnel off, no public DNS, and no port forwarding. The gateway binds loopback
only, so the Serve proxy is the single network path in.

**Identity.** The gateway `403`s any request missing the exact
`Tailscale-User-Login` header, or whose login is not in a one-line `0600`
allowlist file (the operator's tailnet login) under the gateway's state
directory. Ambiguous or duplicated forwarded identity headers are rejected. The
pinned Tailscale version's header names are validated at install time.

**Authorization.** A closed route matrix only: the phone verbs over exactly the
two projects × three harnesses, plus enqueue/cancel/status for the two bridge
jobs. **No route accepts a command, hostname, path, SSH destination, tmux
target, or ignored-path selection.** Mutations require a strict same-origin
check (Origin/Host); API responses and captures are `Cache-Control: no-store`; a
Content-Security-Policy and a no-referrer policy are set. A manual tailnet ACL
restricts the Mini's `:443` to the phone and MacBook nodes, and the phone's
device key is given a short expiry. The bridge authenticates over existing SSH
keys — there are **no bridge HTTP routes at all**.

**Why no bearer tokens.** A token is a phishable, replayable secret that outlives
the device and leaks into logs and clipboards. Tailnet identity is bound to a
per-device WireGuard key that never transits the app layer, is centrally
revocable in seconds, and expires. That is strictly better than a token for a
single-operator surface, so no token is issued anywhere.

**Stolen-phone blast radius.** An unlocked, still-enrolled phone can drive only
the closed verbs on the six sessions: read ≤ 4096-byte captures, send prompts
into running sessions, interrupt/kill, start on Mini content **only when a
cession is already armed**, and queue a start or reclaim (which still run under
every MacBook-side guard). It **cannot** open shells, touch arbitrary
files/paths, claim bridge jobs, reach the MacBook directly, alter the tailnet, or
bypass the lease/CAS/divergence/recovery rules. The response is Tailscale device
revocation (immediate), device lock, the short key expiry, and a labels-only
audit log for triage. Steering a running agent by prompt is the largest real
exposure and is accepted and documented.

**Residual risks (accepted, documented).** A local process on the Mini could
spoof identity headers on loopback; this is accepted on a single-user Mini given
the loopback-only bind, the closed verb set, and the audit log, and revisited if
Serve gains unix-socket backends. Tailscale Serve's identity-header behavior
varies by version, so the tested version is pinned and headers are validated at
install; the tailnet ACL remains the primary boundary.

**State hygiene.** Gateway and queue state is `0700`/`0600` and contains only
request ids, closed atoms, timestamps, cursors, and bounded reason enums — never
prompts, captures, transcripts, or terminal text.

## The closed API

Every route exec-s `agent-control` with validated fixed atoms. `project` is
`miospot` or `orchestration`; `agent` is `claude`, `codex`, or `grok`; nothing
else is accepted as a routable value.

| Route | Verb | Notes |
|---|---|---|
| `GET  /api/v1/status` | `agent-control status` | Aggregates the six session statuses + `peek` (writer/lease/generation/recovery/mutex/cession) + queue state + heartbeat |
| `GET  /api/v1/inspect?project&agent` | `agent-control inspect` | Bounded capture, returned ephemerally |
| `POST /api/v1/continue` | `agent-control continue` | Prompt in the request body → `0600` temp file → stdin; capture-before-send |
| `POST /api/v1/send` | `agent-control send` | Advanced action; prompt via body only |
| `POST /api/v1/interrupt` | `agent-control interrupt` | Mutex-guarded |
| `POST /api/v1/kill` | `agent-control kill` | Mutex-guarded; records `quiescent` via the protocol |
| `POST /api/v1/reveal` | `agent-control reveal` | Mini-local; opens Terminal, sends nothing |
| `POST /api/v1/start` | `agent-control start` **or** enqueue | Mini mode consumes a cession; without a valid cession it returns the bounded `no-cession` refusal and offers only queueing — there is no silent fallback |
| `POST /api/v1/reclaim` | enqueue | Always a bridge job |
| `POST /api/v1/request-cancel` | `agent-control request-cancel` | Cancels a queued job until it is claimed |
| `GET  /api/v1/events` | blocking `agent-control wait` (multiplexed) | SSE; see below |

The static app is served from an explicit whitelist of the app-shell assets;
anything else under the templates directory — including the LaunchAgent plists —
is never servable and returns `404`. Prompt text never appears in a route's
argument vector or in any log. A refusal is a bounded envelope:

```json
{ "ok": false, "reason": "digest-mismatch", "project": "orchestration", "agent": "claude" }
```

`reason` is drawn from a fixed enum (`no-cession`, `stale-generation`,
`digest-mismatch`, `dirty-tree`, `writer-present`, `mutex-held`,
`recovery-required`, `first-contact`, `diverged`, `writer-live`,
`worktree-gate`, …); the bridge classifies `remote-agent.sh` outcomes into this
enum so protocol free-text never enters the queue or the UI.

## Events without polling

Lifecycle updates are event-driven end to end — there is no timer and no polling
loop anywhere. `GET /api/v1/events` opens an SSE stream. For each *existing*
session the gateway holds one blocking `agent-control wait` (bounded, e.g.
≤ 300 s), resumed with the restart-aware `EPOCH:NUMBER` cursor the wait returns,
and forwards each wake envelope, queue-state change, and heartbeat change as an
SSE event. A session with no supervisor state gets **no** wait worker until a
start or queue event creates it, so an absent session cannot degenerate into an
instant-fail retry storm. Client disconnect reaps the workers.

A wake is only a **hint** to look, never proof the writer lease is quiescent —
only a guarded kill/reclaim transition proves that. When a mobile browser
suspends the stream in the background, the client reconnects with the stored
`EPOCH:NUMBER` cursor and does one status refresh on foreground; it never infers
completion or quiescence from a disconnect. Web push is intentionally excluded.

## Install, operation, and recovery

The plugin ships the code and templates; it never installs itself, edits user
Claude settings, or touches Tailscale policy. The sensitive system changes are
human-only, and an install validator checks them read-only.

### Where each component runs

- **Mini:** `agent-control`, `phone-control-gateway`, and
  `phone-control-install-check` on `PATH` beside the existing Mini authorities;
  the app-shell assets and the two LaunchAgent plist templates under
  `templates/phone-control/`; the gateway loaded as a **GUI-session** user
  LaunchAgent (so `reveal` works).
- **MacBook:** `phone-control-bridge` loaded as a launchd-`KeepAlive` agent; the
  updated `remote-agent.sh` with the `cede`/`uncede` verbs.

### Prerequisites (human-only, nothing automated)

- Install and device-approve Tailscale on the Mini and the phone. Configure
  **tailnet-only** Serve with Funnel and router port-forwarding off, and write
  the exact phone-to-Mini ACL grant. Give the phone's device key a short expiry.
- Harden SSH to key-only, **proving key auth in a second concurrent connection
  before** disabling password/keyboard-interactive auth. Create a separate
  restricted bridge key with a forced closed wrapper and port/agent/X11
  forwarding disabled where practical.
- Enable the application firewall and stealth mode, then re-test Tailscale and
  SSH access.
- Write the one-line `0600` identity allowlist (the operator's tailnet login).

`phone-control-install-check` verifies — read-only, changing no system setting —
that the gateway binds loopback only, that state modes are `0700`/`0600`, that
script paths are absolute and validated, that the allowlist is present, that no
Funnel or public listener exists, and, where programmatically visible, that the
hardening prerequisites above hold. It exits non-zero on any failure and never
edits anything.

### Routine operation

To arm a phone start before leaving the laptop, the operator runs the guarded
cede verb on the MacBook:

```text
remote-agent.sh cede PROJECT
```

This is reached through the same natural-language skill as the other verbs
("arm a phone start for orchestration"). It succeeds only when the tree is clean
and equal and there is no writer, and it prints the armed cession so `status`
and the phone both show "ready for phone start — single use." `remote-agent.sh
uncede PROJECT` cancels an unconsumed cession. From then on the phone drives the
matrix above: inspect and continue any running session; start on Mini content
while a cession is armed, or queue a MacBook-content start or reclaim that drains
on wake.

### Runbook: recovering a wedged Mini-start transaction

A hard crash **in the middle of a Mini-start transaction** (power loss between
the CAS and the lease-commit) can leave a specific, diagnosable fingerprint:

- the on-disk **mutex is held** (with its owner record),
- the **cession is `consumed`**,
- the **generation is bumped**, and
- **no lease/writer record exists** (the commit never happened).

The protocol will not resolve this automatically, and that is deliberate: a held
mutex with no lease is exactly the ambiguity it refuses to guess about, because
guessing would mean inferring process death from a PID or a heartbeat — which the
single-writer model never does. Recovery is therefore a **human-executed,
Mini-local procedure**, and never an automated bypass or a "force" flag:

1. On the Mini, run `peek` for the project. It reports the mutex owner record and
   the consumed-cession marker as plain facts, so the wedged fingerprint above is
   visible without any staleness inference.
2. Confirm out of band that the owning process is genuinely gone (the crash is
   real, not a slow transaction still in flight). The mutex owner record names
   what to check.
3. Only then, release the stale mutex through the Mini-local guarded recovery
   affordance. Because no lease was ever committed and the cession is already
   consumed, the project returns to writer `none` with no cession — the correct
   resting state. The generation stays bumped, which is harmless (it only ever
   moves forward).

This recovery **cannot** manufacture a lease or a cession; it only releases a
mutex whose owner is provably gone, and it preserves every other guard. The phone
start opportunity is spent — a fresh `cede` from the MacBook is required to arm
another. Do not hand-edit protocol state, and do not retry into a held mutex.

### Revocation (stolen or lost phone)

Revoke the phone's Tailscale device (access is removed in seconds), lock the
device, and rely on the short device-key expiry as a backstop. The labels-only
audit log supports triage. No secret needs rotation because none was ever issued
to the phone.

### Rollback and uninstall

Unload the two LaunchAgents and remove the phone-control scripts and templates.
This leaves all protocol state — the lease, generation, restore journal,
recovery evidence, and any cession — **untouched**, because the phone surface
never owned that state; it only re-called the authorities that do. If the Mini
authorities themselves are rolled back, keep `agent-control` matched to the
authority version it was built against, exactly as the Mini adapter and
synchronization authority are retained and restored as a matched pair
(`docs/08-plugin-layout.md`).

### Reliability limits (FileVault, reboot, keep-awake, UPS)

The Mini's availability has hard physical limits that the surface cannot paper
over:

- **FileVault requires a local unlock after any reboot or power loss.** Until
  someone unlocks the Mini at its own keyboard, the user LaunchAgents (gateway,
  supervisor sessions), Tailscale, and SSH do **not** come back. A reboot while
  the operator is away therefore takes the phone surface offline until physical
  access is possible — this is a security property, not a bug, and it is not
  worked around.
- **Keep-awake must be supervised, on AC, display-sleep-only.** A bare
  unsupervised keep-awake process is not sufficient; use a supervised keep-awake
  that only prevents system sleep while on power and still lets the display
  sleep.
- **A UPS is expected** so that brief power interruptions do not force the
  FileVault-locked reboot path.

The surface provides one lease-based ownership handoff, not continuous sync,
secret copying, chat persistence, backend bootstrap, or reboot survival.

## Residual risks (accepted)

- **A stolen unlocked phone can steer running agents until revoked.** Mitigated
  by device lock, the short key expiry, destructive-action confirmations in the
  UI, the labels-only audit log, and the tested revocation runbook above.
- **Loopback header spoofing by a local Mini process.** Accepted on a
  single-user Mini; revisited if Serve gains unix-socket backends.
- **A broken cede promise wedges the MacBook (never the Mini).** Detected
  fail-closed on the MacBook's next guarded operation and as a non-fast-forward
  refusal at reclaim; nothing is lost silently, but the operator must resolve the
  divergence.
- **A crash mid Mini-start transaction requires the manual recovery runbook.**
  Bounded by the durable claim CAS, one outstanding job per project, the protocol
  mutex/CAS as the final authority, and `recovery-required` instead of a blind
  retry once execution has begun.
- **Codex and Grok sessions lack hook-labelled lifecycle events.** Their exit and
  timeout wakes plus bounded inspection remain exactly as for any session; the
  surface adds no new hooks (`docs/07-hooks.md`).

For where each new artifact lives and which doc informs it, see
`docs/08-plugin-layout.md`; for the natural-language skill that routes the
`cede`/`uncede` intents and the phone-originated writer records, see
`docs/05-skills-catalog.md`.
