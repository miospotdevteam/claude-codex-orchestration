# Merchant Copilot — core

Implement the core of a merchant assistant that receives commands from paired
devices, executes tiered "tool" actions with a confirm-before-commit safety
model, and keeps an audit log with single-step undo. This is a **self-contained
in-memory implementation** — no network, no database, no third-party services.

## Deliverable

Create a single file **`copilot.py`** exposing a class **`Copilot`**.

## Runtime

Python 3, standard library only. No third-party packages. No I/O, no logging,
no wall-clock reads, no global mutable state. Nothing printed on import. All time
is supplied by the caller as a `now` argument (a number of seconds); identical
call sequences must produce identical results.

## Constants

- `PAIRING_TTL = 300` — a pairing code is valid for 300 seconds after issue.
- `CONFIRM_TTL = 120` — a pending confirmation is valid for 120 seconds.

A code/confirmation is expired when `now >= issued_or_created_time + TTL`
(i.e. exactly at the TTL boundary it is already expired).

## Tool registry (fixed)

The assistant exposes exactly these tools. Each has a **tier** and, for writes,
whether it is **undoable**:

| tool | tier | effect | undoable |
|---|---|---|---|
| `set_setting` | AUTO | write: `settings[key] = value` | yes |
| `bump_counter` | AUTO | write: `counter += 1` | **no** |
| `view_report` | AUTO | read: returns current settings + item count | n/a (read) |
| `add_item` | CONFIRM | write: append `name` to `items` | yes |
| `delete_all_items` | CONFIRM | write: empties `items` | yes |
| `open_billing` | DEEPLINK | returns a link; never executes | n/a |

`bump_counter` is an audited write but is **not undoable** — `undo` skips it and
targets the most recent undoable action instead.

Any other tool name is unknown.

## Merchant state

Each merchant has independent state, initially
`{"settings": {}, "items": [], "counter": 0}`. `settings` is a string→value map;
`items` is a list of names (strings); `counter` is an integer. Merchants never
see each other's state or audit log.

## API

All methods take/return plain dicts/lists/strings/numbers as described. On any
error, return the exact `error` string given (do not raise).

### Pairing

- `issue_pairing_code(merchant_id, now) -> str`
  Returns a fresh **opaque** pairing code string bound to `merchant_id`, valid
  until `now + PAIRING_TTL`. Each call returns a distinct code. A code is
  **single-use**.

- `pair(sender_id, code, now) -> dict`
  Binds `sender_id` to the code's merchant. A sender is bound to exactly one
  merchant; pairing again rebinds it. Returns `{"ok": True, "merchantId": <m>}`
  on success (and consumes the code). Errors (return `{"ok": False, "error": e}`):
  - `"invalid_code"` — no such code.
  - `"code_used"` — the code was already consumed.
  - `"code_expired"` — `now >=` the code's expiry.

- `revoke(sender_id, now) -> dict`
  Unbinds `sender_id`. `{"ok": True}` on success, else `{"ok": False, "error":
  "not_paired"}`.

### Dispatch & confirm

- `dispatch(sender_id, tool, args, now) -> dict`
  - If `sender_id` is not paired: `{"status": "guest"}` — nothing executes.
  - If `tool` is unknown: `{"status": "error", "error": "unknown_tool"}`.
  - **DEEPLINK** tool: `{"status": "deeplink", "url": <non-empty string>}` —
    nothing executes, nothing is audited.
  - **AUTO** tool: execute immediately. For a write, append an audit entry (see
    Audit). Return `{"status": "done", "result": <result>}`.
  - **CONFIRM** tool: do **not** execute. Create a pending confirmation valid
    until `now + CONFIRM_TTL` and return
    `{"status": "pending", "confirmationId": <opaque string>, "preview":
    {"tool": tool, "args": args}}`.

- `confirm(sender_id, confirmation_id, now) -> dict`
  Commits a pending confirmation. On success execute the tool, append an audit
  entry (it is a write), and return `{"status": "done", "result": <result>}`.
  A confirmation is **single-use**. Errors (`{"status": "error", "error": e}`):
  - `"unknown_confirmation"` — no such id.
  - `"already_confirmed"` — it was already committed.
  - `"wrong_sender"` — `sender_id` is not the sender that created it.
  - `"confirmation_expired"` — `now >=` its expiry.

  (When more than one error applies, check them in the order listed above.)

### Tool results

The `result` returned by `dispatch`/`confirm` for each tool:

- `set_setting` (args `{"key", "value"}`): `{"key": key, "value": value}`.
- `bump_counter` (args `{}`): `{"counter": <new counter value>}`.
- `add_item` (args `{"name"}`): `{"added": name, "count": <new length of items>}`.
- `delete_all_items` (args `{}`): `{"deleted": <number removed>}`.
- `view_report` (args `{}`): `{"settings": <copy of settings>, "itemCount": <len(items)>}`.

### Audit & undo

- `audit_log(merchant_id) -> list`
  Returns that merchant's audit entries in ascending `seq` order. Each entry:
  `{"seq": <int>, "tool": <str>, "args": <dict>, "result": <result>, "at": <now
  at commit>, "undoable": <bool>, "undone": <bool>, "kind": <"action"|"compensation">}`.
  `seq` is a positive integer that strictly increases in the order entries are
  committed across the whole `Copilot`. Only **executed writes** are audited
  (AUTO writes and confirmed CONFIRM writes); reads, DEEPLINKs, guest calls, and
  un-confirmed pendings are never audited. Audited write entries have
  `kind == "action"`.

- `undo(sender_id, now) -> dict`
  Reverses the single most recent **undoable, not-yet-undone** action of the
  sender's merchant (LIFO). Reversal restores the exact prior state:
  - `set_setting`: restore the key's previous value, or remove the key if it did
    not exist before.
  - `add_item`: remove the item that was added.
  - `delete_all_items`: restore the exact prior item list (order included).

  On success: mark that action `undone`, append a **compensation** audit entry
  (`tool == "undo"`, `kind == "compensation"`, `args == {"seq": <undone seq>}`,
  `undoable == False`), and return `{"status": "undone", "undidSeq": <seq>}`.
  A subsequent `undo` targets the next-most-recent still-undoable action.
  Errors (`{"status": "error", "error": e}`):
  - `"not_paired"` — `sender_id` is not paired.
  - `"nothing_to_undo"` — no undoable, not-yet-undone action for the merchant.

- `get_state(merchant_id) -> dict`
  Returns `{"settings": <copy>, "items": <copy>, "counter": <int>}` — provided so
  callers can inspect effects. Returns the empty initial state for an unknown
  merchant.

## Notes

- Return **copies** where a copy is specified so callers cannot mutate internal
  state through the returned value.
- `args` may be assumed well-formed for the given tool (the required keys are
  present).
