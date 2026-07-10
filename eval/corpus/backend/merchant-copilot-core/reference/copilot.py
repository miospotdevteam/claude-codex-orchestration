"""Reference implementation of the Merchant Copilot core.

Gold solution — hidden from models under test. Kept alongside the task so the
hidden test suite can be validated against a known-correct implementation.
"""

PAIRING_TTL = 300
CONFIRM_TTL = 120

# tool -> (tier, is_write, undoable)
TOOLS = {
    "set_setting": ("AUTO", True, True),
    "bump_counter": ("AUTO", True, False),
    "view_report": ("AUTO", False, False),
    "add_item": ("CONFIRM", True, True),
    "delete_all_items": ("CONFIRM", True, True),
    "open_billing": ("DEEPLINK", False, False),
}


class Copilot:
    def __init__(self):
        self._codes = {}          # code -> {merchant, expires, used}
        self._pairs = {}          # sender -> merchant
        self._state = {}          # merchant -> {"settings": {}, "items": []}
        self._pending = {}        # confirmation_id -> {sender, merchant, tool, args, expires, used}
        self._audit = []          # list of entries (global, ordered by seq)
        self._seq = 0
        self._code_n = 0
        self._conf_n = 0

    # --- internal helpers ---
    def _merchant_state(self, merchant):
        if merchant not in self._state:
            self._state[merchant] = {"settings": {}, "items": [], "counter": 0}
        return self._state[merchant]

    def _next_code(self, merchant):
        self._code_n += 1
        return "code-%s-%d" % (merchant, self._code_n)

    def _next_conf(self):
        self._conf_n += 1
        return "conf-%d" % self._conf_n

    def _execute(self, merchant, tool, args):
        """Apply a write tool's effect; return (result, undo_data)."""
        st = self._merchant_state(merchant)
        if tool == "set_setting":
            key = args["key"]
            had = key in st["settings"]
            prev = st["settings"].get(key)
            st["settings"][key] = args["value"]
            return ({"key": key, "value": args["value"]}, {"key": key, "had": had, "prev": prev})
        if tool == "add_item":
            name = args["name"]
            st["items"].append(name)
            return ({"added": name, "count": len(st["items"])}, {"name": name})
        if tool == "delete_all_items":
            prev = list(st["items"])
            st["items"] = []
            return ({"deleted": len(prev)}, {"prev": prev})
        if tool == "bump_counter":
            st["counter"] += 1
            return ({"counter": st["counter"]}, None)
        if tool == "view_report":
            return ({"settings": dict(st["settings"]), "itemCount": len(st["items"])}, None)
        raise KeyError(tool)

    def _apply_undo(self, merchant, tool, undo_data):
        st = self._merchant_state(merchant)
        if tool == "set_setting":
            if undo_data["had"]:
                st["settings"][undo_data["key"]] = undo_data["prev"]
            else:
                st["settings"].pop(undo_data["key"], None)
        elif tool == "add_item":
            # remove the specific item that was added (last matching occurrence)
            name = undo_data["name"]
            for i in range(len(st["items"]) - 1, -1, -1):
                if st["items"][i] == name:
                    del st["items"][i]
                    break
        elif tool == "delete_all_items":
            st["items"] = list(undo_data["prev"])

    def _audit_write(self, merchant, sender, tool, args, result, undo_data, now):
        self._seq += 1
        entry = {
            "seq": self._seq,
            "merchant": merchant,
            "sender": sender,
            "tool": tool,
            "args": dict(args),
            "result": result,
            "at": now,
            "undoable": TOOLS[tool][2],
            "undone": False,
            "_undo_data": undo_data,
            "kind": "action",
        }
        self._audit.append(entry)
        return entry

    # --- pairing ---
    def issue_pairing_code(self, merchant_id, now):
        code = self._next_code(merchant_id)
        self._codes[code] = {"merchant": merchant_id, "expires": now + PAIRING_TTL, "used": False}
        return code

    def pair(self, sender_id, code, now):
        rec = self._codes.get(code)
        if rec is None:
            return {"ok": False, "error": "invalid_code"}
        if rec["used"]:
            return {"ok": False, "error": "code_used"}
        if now >= rec["expires"]:
            return {"ok": False, "error": "code_expired"}
        rec["used"] = True
        self._pairs[sender_id] = rec["merchant"]
        return {"ok": True, "merchantId": rec["merchant"]}

    def revoke(self, sender_id, now=None):
        if sender_id not in self._pairs:
            return {"ok": False, "error": "not_paired"}
        del self._pairs[sender_id]
        return {"ok": True}

    # --- dispatch / confirm ---
    def dispatch(self, sender_id, tool, args, now):
        merchant = self._pairs.get(sender_id)
        if merchant is None:
            return {"status": "guest"}
        if tool not in TOOLS:
            return {"status": "error", "error": "unknown_tool"}
        tier, is_write, _ = TOOLS[tool]
        if tier == "DEEPLINK":
            return {"status": "deeplink", "url": "https://app.example/%s" % tool}
        if tier == "AUTO":
            result, undo_data = self._execute(merchant, tool, args)
            if is_write:
                self._audit_write(merchant, sender_id, tool, args, result, undo_data, now)
            return {"status": "done", "result": result}
        # CONFIRM
        conf = self._next_conf()
        self._pending[conf] = {
            "sender": sender_id,
            "merchant": merchant,
            "tool": tool,
            "args": dict(args),
            "expires": now + CONFIRM_TTL,
            "used": False,
        }
        return {"status": "pending", "confirmationId": conf, "preview": {"tool": tool, "args": dict(args)}}

    def confirm(self, sender_id, confirmation_id, now):
        p = self._pending.get(confirmation_id)
        if p is None:
            return {"status": "error", "error": "unknown_confirmation"}
        if p["used"]:
            return {"status": "error", "error": "already_confirmed"}
        if p["sender"] != sender_id:
            return {"status": "error", "error": "wrong_sender"}
        if now >= p["expires"]:
            return {"status": "error", "error": "confirmation_expired"}
        p["used"] = True
        result, undo_data = self._execute(p["merchant"], p["tool"], p["args"])
        if TOOLS[p["tool"]][1]:
            self._audit_write(p["merchant"], sender_id, p["tool"], p["args"], result, undo_data, now)
        return {"status": "done", "result": result}

    # --- audit / undo / state ---
    def audit_log(self, merchant_id):
        out = []
        for e in self._audit:
            if e["merchant"] != merchant_id:
                continue
            out.append({
                "seq": e["seq"],
                "tool": e["tool"],
                "args": e["args"],
                "result": e["result"],
                "at": e["at"],
                "undoable": e["undoable"],
                "undone": e["undone"],
                "kind": e["kind"],
            })
        return out

    def undo(self, sender_id, now):
        merchant = self._pairs.get(sender_id)
        if merchant is None:
            return {"status": "error", "error": "not_paired"}
        target = None
        for e in reversed(self._audit):
            if e["merchant"] != merchant:
                continue
            if e["kind"] != "action":
                continue
            if not e["undoable"] or e["undone"]:
                continue
            target = e
            break
        if target is None:
            return {"status": "error", "error": "nothing_to_undo"}
        self._apply_undo(merchant, target["tool"], target["_undo_data"])
        target["undone"] = True
        self._seq += 1
        self._audit.append({
            "seq": self._seq,
            "merchant": merchant,
            "sender": sender_id,
            "tool": "undo",
            "args": {"seq": target["seq"]},
            "result": {"undidSeq": target["seq"]},
            "at": now,
            "undoable": False,
            "undone": False,
            "_undo_data": None,
            "kind": "compensation",
        })
        return {"status": "undone", "undidSeq": target["seq"]}

    def get_state(self, merchant_id):
        st = self._merchant_state(merchant_id)
        return {"settings": dict(st["settings"]), "items": list(st["items"]), "counter": st["counter"]}
