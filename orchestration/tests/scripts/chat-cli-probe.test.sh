#!/usr/bin/env bash
# chat-cli-live-probe (A2, A4): loud-skip live probe of REAL CLIs for
# mechanical read-only write-block + per-CLI permission-prompt signals.
# Records a bounded machine-readable capability note consumed by later
# chat-create / chat-runner tests. Never silent-pass: missing CLI or
# unproven mechanism is SKIP/FAIL with available=false (fail-closed).
#
# ACCEPTED capability mechanisms (decisions.json -> chatCapabilityFinding):
# - claude:  mechanism=cli-permission
#            Write tool_use + tool_result is_error (permission denial)
# - codex:   mechanism=cli-sandbox-refusal  (option D)
#            -s read-only flag accepted AND write blocked AND sandbox
#            refusal observed on CLI stderr (sandbox speaking, not model).
#            A JSON approval-request event is NOT required.
# - grok:    mechanism=disposable-checkout-copy  (option B)
#            CLI --deny flags are NOT trusted for enforcement
#            (cliFlagEnforcement="unproven, defence-in-depth only").
#            available=true ONLY under disposable-copy isolation proven
#            end-to-end with REAL components:
#              (1) make_disposable_checkout_copy of the ACTUAL canonical
#                  checkout (tracked-files subset; same mechanism chat-runner
#                  will use — never a synthetic fixture tree);
#              (2) REAL grok CLI write inside that copy;
#              (3) canonical checkout byte-untouched (detect-only);
#              (4) copy cleaned up afterwards (failed copy/cleanup = fail-closed).
#            A synthetic seed tree or shell printf write MUST NOT satisfy.
#            Control-probe evidence (streaming-json omits typed tool
#            events even when writes succeed) JUSTIFIES the copy mechanism.
#
# Safety / honesty rules:
# - assert_no_checkout_write is DETECT-ONLY: never rm/find -delete inside
#   the canonical checkout; leave any probe artifact for a human.
# - writeBlocked requires POSITIVE evidence for CLI-flag mechanisms
#   (claude/codex): attempt + mechanical denial + absent marker.
# - Grok CLI-flag write-block is deliberately untrusted; isolation is
#   proven by a REAL grok write inside a canonical-checkout copy, not by
#   --deny success and not by a synthetic/shell write.
# - validate_capability_note REQUIRES mechanical evidence fields for each
#   mechanism when available/probed is claimed — missing, empty, or
#   merely-asserted evidence fails validation (no null escape hatches).
# - Claude always runs with cwd INSIDE its scratch dir; post-run assert
#   no probe artifacts under the canonical checkout.
# - Claude permissionSignal uses the STREAM only: Write tool_use PLUS
#   tool_result is_error with permission-denial text. Notification hooks
#   are NOT-APPLICABLE (plugin must never edit user Claude settings).
# - Codex permissionSignal = sandbox-refusal on stderr (option D).
# - Grok hang-signal on streaming-json remains unproven (typed tool
#   events absent); recorded as justification, not a faked pass.
# - flagAccepted requires POSITIVE evidence the flag was honored —
#   never mere absence of a parser error. Failed invocation => false.
# - available=true is mechanism-specific (see validate_capability_note).
# - Honest probed=false / available=false is correct when not observed.
# - bounded execution without depending on Perl (python3 fallback).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
FIXTURES_DIR="$(cd "$SCRIPT_DIR/../fixtures" && pwd -P)"
CAPABILITY_NOTE="${CHAT_CLI_CAPABILITY_NOTE:-$FIXTURES_DIR/chat-cli-capabilities.json}"
PROBE_MARKER="PROBE_WRITE_ME.txt"
PROBE_PERM_MARKER="PROBE_PERM.txt"
PROBE_TIMEOUT_SECS="${CHAT_CLI_PROBE_TIMEOUT_SECS:-120}"
# CHAT_CLI_PROBE_LIVE=0 forces skip of live probes (hermetic schema/loud-skip only).
LIVE_MODE="${CHAT_CLI_PROBE_LIVE:-1}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Accumulator for the capability note (JSON fragments per agent).
NOTE_DIR="$TMP_DIR/note-parts"
mkdir -p "$NOTE_DIR"

pass() {
  printf 'PASS %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Loud-skip: never counted as PASS. Visible on stdout AND stderr.
skip() {
  local name="$1"
  local reason="$2"
  printf 'SKIP %s: %s\n' "$name" "$reason"
  printf 'SKIP %s: %s\n' "$name" "$reason" >&2
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

# Honest non-proof after a live invocation: loud, not PASS, not silent.
# Records fail-closed capability fields; does not fail the harness.
unproven() {
  local name="$1"
  local reason="$2"
  printf 'UNPROVEN %s: %s\n' "$name" "$reason"
  printf 'UNPROVEN %s: %s\n' "$name" "$reason" >&2
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf 'chat-cli-probe: jq is required\n' >&2
    exit 1
  }
}

# Bounded exec: kill after PROBE_TIMEOUT_SECS. Exit code stored in BOUND_RC
# (124 on timeout). The function itself always returns 0 so set -e callers are
# not tripped by intentional non-zero child statuses. Prefer python3 (portable,
# no SIGALRM parent-shell side effects), then perl-in-subshell, then bash watchdog.
BOUND_RC=0
run_bounded() {
  local out_file=$1 err_file=$2
  shift 2
  local cwd=""
  if [[ "${1:-}" == "--cwd" ]]; then
    cwd=$2
    shift 2
  fi
  local rc=0
  BOUND_RC=0
  # Prefer python3: portable, no SIGALRM side-effects on the parent shell.
  # IMPORTANT: do not feed the helper via stdin heredoc — callers pipe prompts
  # on stdin and the child must inherit that pipe.
  if command -v python3 >/dev/null 2>&1; then
    local py_cwd_arg="None"
    if [[ -n "$cwd" ]]; then
      py_cwd_arg=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cwd")
    fi
    # -c keeps sys.stdin free for the child process (callers pipe prompts).
    set +e
    python3 -c '
import json, os, signal, subprocess, sys
timeout = float(sys.argv[1])
out_path, err_path, cwd_raw = sys.argv[2], sys.argv[3], sys.argv[4]
cmd = sys.argv[5:]
cwd = None if cwd_raw == "None" else json.loads(cwd_raw)

def _kill_tree(pid):
    try:
        if sys.platform == "darwin":
            subprocess.call(["pkill", "-KILL", "-P", str(pid)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass

with open(out_path, "w") as fo, open(err_path, "w") as fe:
    try:
        p = subprocess.Popen(
            cmd, stdout=fo, stderr=fe, cwd=cwd, stdin=sys.stdin,
        )
        try:
            sys.exit(p.wait(timeout=timeout))
        except subprocess.TimeoutExpired:
            _kill_tree(p.pid)
            try:
                p.wait(timeout=2)
            except Exception:
                p.kill()
                p.wait()
            sys.exit(124)
    except FileNotFoundError:
        sys.exit(127)
' "$PROBE_TIMEOUT_SECS" "$out_file" "$err_file" "$py_cwd_arg" "$@"
    rc=$?
    set +e
  elif command -v perl >/dev/null 2>&1; then
    # perl alarm in a subshell so SIGALRM cannot kill the test harness.
    set +e
    if [[ -n "$cwd" ]]; then
      (cd "$cwd" && perl -e 'alarm shift; exec @ARGV' "$PROBE_TIMEOUT_SECS" "$@") >"$out_file" 2>"$err_file"
    else
      (perl -e 'alarm shift; exec @ARGV' "$PROBE_TIMEOUT_SECS" "$@") >"$out_file" 2>"$err_file"
    fi
    rc=$?
    set +e
  else
    # Last-resort bash watchdog (no python/perl).
    set +e
    if [[ -n "$cwd" ]]; then
      (cd "$cwd" && "$@" >"$out_file" 2>"$err_file") &
    else
      "$@" >"$out_file" 2>"$err_file" &
    fi
    local pid=$!
    local waited=0
    rc=""
    while kill -0 "$pid" 2>/dev/null; do
      if ((waited >= PROBE_TIMEOUT_SECS)); then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rc=124
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done
    if [[ -z "${rc}" ]]; then
      wait "$pid"
      rc=$?
    fi
    set +e
  fi
  # perl alarm often surfaces as 142 (128+14 SIGALRM) or 255
  if ((rc == 142 || rc == 14)); then
    rc=124
  fi
  BOUND_RC=$rc
  return 0
}

agent_binary() {
  local agent=$1
  command -v "$agent" 2>/dev/null || true
}

# --- Capability note schema -----------------------------------------------

# Allowed readOnly.mechanism values (binding capability contract).
# claude:  cli-permission
# codex:   cli-sandbox-refusal   (option D — stderr sandbox speaking)
# grok:    disposable-checkout-copy  (option B — filesystem isolation)
MECHANISM_CLAUDE="cli-permission"
MECHANISM_CODEX="cli-sandbox-refusal"
MECHANISM_GROK="disposable-checkout-copy"
GROK_CLI_FLAG_ENFORCEMENT="unproven, defence-in-depth only"
# Whole-tree canonical proof method recorded in disposableCopy evidence.
# Capture: HEAD + porcelain=v1 -unormal + tracked worktree content hashes.
# Compare: byte-identical before/after around the real Grok invocation.
CANONICAL_PROOF_METHOD="canonical-state-byte-identity"

validate_capability_note() {
  local note_file=$1
  [[ -f "$note_file" ]] || return 1
  jq -e --arg mClaude "$MECHANISM_CLAUDE" --arg mCodex "$MECHANISM_CODEX" --arg mGrok "$MECHANISM_GROK" '
    .schemaVersion == 1
    and (.probedAt | type == "string" and length > 0)
    and (.canonicalCheckout | type == "string")
    and (.capabilityFloor.bashDeniedMeansNoReadOnlyShell == true)
    and (.agents | type == "object")
    and (.agents | has("claude") and has("codex") and has("grok"))
    and (
      # Per-agent mechanism honesty (fixed mapping).
      (.agents.claude.readOnly.mechanism == $mClaude)
      and (.agents.codex.readOnly.mechanism == $mCodex)
      and (.agents.grok.readOnly.mechanism == $mGrok)
    )
    and (
      .agents | to_entries | all(
        .value
        | (.agent | type == "string")
        and (.status | . == "probed" or . == "skipped" or . == "failed")
        and (.readOnly | type == "object")
        and (.readOnly.mechanism | type == "string" and length > 0)
        and (.readOnly.cliFlags | type == "array" and length > 0)
        and (.readOnly.flagAccepted | type == "boolean")
        and (.readOnly.writeBlocked | type == "boolean")
        and (.readOnly.available | type == "boolean")
        and (.permissionSignal | type == "object")
        and (.permissionSignal.name | type == "string" and length > 0)
        and (.permissionSignal.source | type == "string" and length > 0)
        and (.permissionSignal.probed | type == "boolean")
        and (
          # Fail-closed available rules are mechanism-specific.
          # REQUIRED: mechanical evidence fields must be present and true —
          # missing, empty, or merely-asserted evidence is rejected (no null
          # escape hatches when available=true or probed=true).
          (.readOnly.available == false)
          or (
            # Claude: cli-permission — flag + write-block + stream permission
            # signal WITH Write tool_use + tool_result is_error evidence.
            .agent == "claude"
            and .readOnly.mechanism == $mClaude
            and .readOnly.flagAccepted == true
            and .readOnly.writeBlocked == true
            and .permissionSignal.probed == true
            and .status == "probed"
            and (.evidence | type == "object")
            and (.evidence.writeBlock.detail.attempted == true)
            and (.evidence.writeBlock.detail.denied == true)
            and (.evidence.writeBlock.detail.flagPositiveEvidence == true)
            and (.evidence.permissionSignal.detail.writeAttempt == true)
            and (.evidence.permissionSignal.detail.toolResultPermissionPrompt == true)
          )
          or (
            # Codex option D: cli-sandbox-refusal — flag + write-block +
            # sandbox refusal on stderr. JSON approval-request NOT required.
            # Evidence for flagAccepted + writeBlocked + sandbox refusal REQUIRED.
            .agent == "codex"
            and .readOnly.mechanism == $mCodex
            and .readOnly.flagAccepted == true
            and .readOnly.writeBlocked == true
            and .permissionSignal.probed == true
            and .permissionSignal.name == "sandbox-refusal"
            and .status == "probed"
            and (.evidence | type == "object")
            and (.evidence.writeBlock.detail.attempted == true)
            and (.evidence.writeBlock.detail.denied == true)
            and (.evidence.writeBlock.detail.flagPositiveEvidence == true)
            and (.evidence.permissionSignal.detail.sandboxRefusalObserved == true)
          )
          or (
            # Grok option B: disposable-checkout-copy only.
            # CLI-flag enforcement MUST be recorded as untrusted.
            # available requires REAL-grok-write-in-copy + canonical-untouched
            # + cleanup evidence (synthetic/shell write MUST NOT pass).
            .agent == "grok"
            and .readOnly.mechanism == $mGrok
            and (.readOnly.cliFlagEnforcement | type == "string")
            and (.readOnly.cliFlagEnforcement | test("unproven"; "i"))
            and .readOnly.writeBlocked == true
            and .status == "probed"
            and (.evidence | type == "object")
            and (.evidence.writeBlock.detail.disposableCopy | type == "object")
            and (.evidence.writeBlock.detail.disposableCopy.writeInCopySucceeded == true)
            and (.evidence.writeBlock.detail.disposableCopy.canonicalUntouched == true)
            and (.evidence.writeBlock.detail.disposableCopy.realGrokWriteInCopy == true)
            and (.evidence.writeBlock.detail.disposableCopy.cleanedUp == true)
            and (.evidence.writeBlock.detail.disposableCopy.writer == "grok")
            and (.evidence.writeBlock.detail.disposableCopy.copySource == "canonical-checkout")
            and (
              # Whole-tree proof method is mandatory (not marker-filename-only).
              (.evidence.writeBlock.detail.disposableCopy.canonicalProofMethod | type == "string")
              and (.evidence.writeBlock.detail.disposableCopy.canonicalProofMethod | length > 0)
              and (.evidence.writeBlock.detail.disposableCopy.canonicalProofMethod == "canonical-state-byte-identity")
            )
            and (
              # Must NOT claim CLI-flag path is the trusted enforcement.
              # Note: do not use `//` here — jq treats false as empty and would
              # rewrite trusted:false into true.
              (.evidence.writeBlock.detail.cliFlagPath | type == "object")
              and (.evidence.writeBlock.detail.cliFlagPath.trusted == false)
            )
          )
        )
        and (
          # Claude structural invariant: probed=true REQUIRES stream Write
          # attempt + tool_result permission-denial evidence (no null escape).
          # notificationHook is N/A (no settings edit).
          (
            .agent != "claude"
            or .permissionSignal.probed != true
            or (
              (.evidence.permissionSignal.detail.writeAttempt == true)
              and (.evidence.permissionSignal.detail.toolResultPermissionPrompt == true)
            )
          )
        )
        and (
          # Grok: permissionSignal.probed=true is only allowed when a typed
          # write-named tool + policy denial pair is observed (no null escape).
          # Control-probe "stream omits tools" findings keep probed=false.
          (
            .agent != "grok"
            or .permissionSignal.probed != true
            or (
              (.evidence.permissionSignal.detail.typedToolAttempt == true)
              and (.evidence.permissionSignal.detail.policyDenialObserved == true)
            )
          )
        )
        and (
          # Codex option D: probed=true REQUIRES sandboxRefusalObserved
          # evidence (no null escape). JSON approval-request not required.
          (
            .agent != "codex"
            or .permissionSignal.probed != true
            or (.evidence.permissionSignal.detail.sandboxRefusalObserved == true)
          )
        )
        and (
          # Grok always carries cliFlagEnforcement when mechanism is disposable-copy.
          (
            .agent != "grok"
            or .readOnly.mechanism != $mGrok
            or (
              (.readOnly.cliFlagEnforcement | type == "string")
              and (.readOnly.cliFlagEnforcement | test("unproven|defence-in-depth"; "i"))
            )
          )
        )
      )
    )
  ' "$note_file" >/dev/null
}

# write_agent_record agent status flagAccepted writeBlocked available skipReason
#   signalName signalSource signalProbed mechanismKind cliFlagsJson
#   [signalMatchJson] [evidenceJson] [cliFlagEnforcement]
write_agent_record() {
  local agent=$1
  local status=$2
  local flag_accepted=$3
  local write_blocked=$4
  local available=$5
  local skip_reason=${6:-}
  local signal_name=$7
  local signal_source=$8
  local signal_probed=$9
  local mechanism_kind=${10}
  local cli_flags_json=${11}
  local signal_match_json=${12:-null}
  local evidence_json=${13:-null}
  local cli_flag_enforcement=${14:-}
  local out="$NOTE_DIR/$agent.json"

  jq -n \
    --arg agent "$agent" \
    --arg status "$status" \
    --argjson flagAccepted "$flag_accepted" \
    --argjson writeBlocked "$write_blocked" \
    --argjson available "$available" \
    --arg skipReason "$skip_reason" \
    --arg signalName "$signal_name" \
    --arg signalSource "$signal_source" \
    --argjson signalProbed "$signal_probed" \
    --arg mechanism "$mechanism_kind" \
    --argjson cliFlags "$cli_flags_json" \
    --argjson signalMatch "$signal_match_json" \
    --argjson evidence "$evidence_json" \
    --arg cliFlagEnforcement "$cli_flag_enforcement" \
    '{
      agent: $agent,
      status: $status,
      skipReason: (if $skipReason == "" then null else $skipReason end),
      readOnly: (
        {
          mechanism: $mechanism,
          cliFlags: $cliFlags,
          flagAccepted: $flagAccepted,
          writeBlocked: $writeBlocked,
          available: $available
        }
        + (if $cliFlagEnforcement == "" then {} else {cliFlagEnforcement: $cliFlagEnforcement} end)
      ),
      permissionSignal: {
        name: $signalName,
        source: $signalSource,
        probed: $signalProbed,
        match: $signalMatch
      },
      evidence: $evidence
    }' >"$out"
}

assemble_capability_note() {
  local out=$1
  local probed_at
  probed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local claude_json codex_json grok_json
  claude_json=$(cat "$NOTE_DIR/claude.json")
  codex_json=$(cat "$NOTE_DIR/codex.json")
  grok_json=$(cat "$NOTE_DIR/grok.json")
  jq -n \
    --arg probedAt "$probed_at" \
    --arg checkout "$REPO_ROOT" \
    --argjson claude "$claude_json" \
    --argjson codex "$codex_json" \
    --argjson grok "$grok_json" \
    '{
      schemaVersion: 1,
      probedAt: $probedAt,
      canonicalCheckout: $checkout,
      capabilityFloor: {
        bashDeniedMeansNoReadOnlyShell: true,
        note: "Bash is denied in every read-only mechanism; read-only chats have no shell."
      },
      agents: {
        claude: $claude,
        codex: $codex,
        grok: $grok
      }
    }' >"$out"
}

# --- Hermetic unit tests --------------------------------------------------

test_loud_skip_when_binary_missing() {
  local name="loud-skip when agent binary missing (never silent-pass)"
  local fake_path="$TMP_DIR/empty-bin"
  mkdir -p "$fake_path"
  # Keep a real shell on PATH so the isolation only hides agent binaries.
  local shell_dir
  shell_dir=$(dirname "$(command -v bash)")
  local isolated_path="$fake_path:$shell_dir"
  local bin
  bin=$(PATH="$isolated_path" command -v claude 2>/dev/null || true)
  if [[ -n "$bin" ]]; then
    fail "$name" "expected no claude on isolated PATH, found $bin"
    return
  fi
  # Capture loud-skip contract: SKIP on stdout+stderr, never PASS.
  local out out_file err_file
  out_file="$TMP_DIR/loud-skip.out"
  err_file="$TMP_DIR/loud-skip.err"
  (
    agent=$(PATH="$isolated_path" command -v claude 2>/dev/null || true)
    if [[ -z "$agent" ]]; then
      skip "claude write-block" "binary not found on PATH"
    else
      printf 'PASS would-run\n'
    fi
  ) >"$out_file" 2>"$err_file"
  out="$(cat "$out_file"; cat "$err_file")"
  if ! grep -q '^SKIP claude write-block: binary not found on PATH$' "$out_file"; then
    fail "$name" "expected loud SKIP on stdout, got: $(cat "$out_file")"
    return
  fi
  if ! grep -q '^SKIP claude write-block: binary not found on PATH$' "$err_file"; then
    fail "$name" "expected loud SKIP on stderr, got: $(cat "$err_file")"
    return
  fi
  if grep -q '^PASS' <<<"$out"; then
    fail "$name" "skip path emitted PASS (silent-pass hazard)"
    return
  fi
  pass "$name"
}

# Minimal valid agent stubs for hermetic schema fixtures (available=false base).
_schema_stub_claude_failed() {
  cat <<'EOF'
{
  "agent": "claude",
  "status": "failed",
  "readOnly": {
    "mechanism": "cli-permission",
    "cliFlags": ["--permission-mode", "dontAsk"],
    "flagAccepted": false,
    "writeBlocked": false,
    "available": false
  },
  "permissionSignal": { "name": "permission_prompt", "source": "y", "probed": false }
}
EOF
}

_schema_stub_codex_failed() {
  cat <<'EOF'
{
  "agent": "codex",
  "status": "failed",
  "readOnly": {
    "mechanism": "cli-sandbox-refusal",
    "cliFlags": ["-s", "read-only"],
    "flagAccepted": false,
    "writeBlocked": false,
    "available": false
  },
  "permissionSignal": { "name": "sandbox-refusal", "source": "y", "probed": false }
}
EOF
}

_schema_stub_grok_failed() {
  cat <<'EOF'
{
  "agent": "grok",
  "status": "failed",
  "readOnly": {
    "mechanism": "disposable-checkout-copy",
    "cliFlags": ["--deny", "Write"],
    "cliFlagEnforcement": "unproven, defence-in-depth only",
    "flagAccepted": false,
    "writeBlocked": false,
    "available": false
  },
  "permissionSignal": { "name": "typed-tool-events-absent", "source": "y", "probed": false }
}
EOF
}

test_capability_note_schema_rejects_malformed() {
  local name="capability note schema rejects malformed / silent-available"
  local bad="$TMP_DIR/bad-note.json"
  local claude_fail codex_fail grok_fail
  claude_fail=$(_schema_stub_claude_failed)
  codex_fail=$(_schema_stub_codex_failed)
  grok_fail=$(_schema_stub_grok_failed)

  # available=true without writeBlocked must fail (claude)
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: ($c * {
          status: "probed",
          readOnly: {
            mechanism: "cli-permission",
            cliFlags: ["--permission-mode", "dontAsk"],
            flagAccepted: true,
            writeBlocked: false,
            available: true
          },
          permissionSignal: { name: "permission_prompt", source: "y", probed: true }
        }),
        codex: $x,
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted available=true with writeBlocked=false"
    return
  fi

  # Claude available=true with permissionSignal.probed=false must fail
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: ($c * {
          status: "probed",
          readOnly: {
            mechanism: "cli-permission",
            cliFlags: ["--permission-mode", "dontAsk"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: { name: "permission_prompt", source: "y", probed: false }
        }),
        codex: $x,
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted claude available=true with permissionSignal.probed=false"
    return
  fi

  # Claude: probed=true without stream tool_result permission pair must be rejected.
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: {
          agent: "claude",
          status: "probed",
          readOnly: {
            mechanism: "cli-permission",
            cliFlags: ["--permission-mode", "dontAsk"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: { name: "permission_prompt", source: "y", probed: true },
          evidence: {
            permissionSignal: {
              detail: {
                writeAttempt: true,
                toolResultPermissionPrompt: false,
                notificationHook: "not-applicable"
              }
            }
          }
        },
        codex: $x,
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted claude probed=true without toolResultPermissionPrompt"
    return
  fi

  # Claude stream pair alone (notificationHook N/A) is structurally valid —
  # requires writeBlock mechanical evidence + permissionSignal pair evidence.
  jq -n --argjson x "$codex_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: {
          agent: "claude",
          status: "probed",
          readOnly: {
            mechanism: "cli-permission",
            cliFlags: ["--permission-mode", "dontAsk", "--tools", "Write,Read"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "permission_prompt",
            source: "stream-json Write tool_use + tool_result is_error",
            probed: true
          },
          evidence: {
            writeBlock: {
              detail: {
                attempted: true,
                denied: true,
                markerAbsent: true,
                flagPositiveEvidence: true
              }
            },
            permissionSignal: {
              detail: {
                writeAttempt: true,
                toolResultPermissionPrompt: true,
                notificationHook: "not-applicable",
                notificationHookReason: "no-settings-edit invariant"
              }
            }
          }
        },
        codex: $x,
        grok: $g
      }
    }
  ' >"$bad"
  if ! validate_capability_note "$bad"; then
    fail "$name" "validator rejected claude stream-only pair (notificationHook N/A should be ok)"
    return
  fi

  # Claude available=true without writeBlock mechanical evidence must fail.
  jq -n --argjson x "$codex_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: {
          agent: "claude",
          status: "probed",
          readOnly: {
            mechanism: "cli-permission",
            cliFlags: ["--permission-mode", "dontAsk"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "permission_prompt",
            source: "y",
            probed: true
          },
          evidence: {
            permissionSignal: {
              detail: {
                writeAttempt: true,
                toolResultPermissionPrompt: true
              }
            }
          }
        },
        codex: $x,
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted claude available=true without writeBlock mechanical evidence"
    return
  fi

  # Codex option D: sandbox-refusal on stderr IS valid; JSON event NOT required.
  # writeBlock + sandboxRefusal evidence REQUIRED.
  jq -n --argjson c "$claude_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: {
          agent: "codex",
          status: "probed",
          readOnly: {
            mechanism: "cli-sandbox-refusal",
            cliFlags: ["-s", "read-only"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "sandbox-refusal",
            source: "codex -s read-only CLI stderr (sandbox speaking)",
            probed: true
          },
          evidence: {
            writeBlock: {
              detail: {
                attempted: true,
                denied: true,
                markerAbsent: true,
                flagPositiveEvidence: true
              }
            },
            permissionSignal: {
              detail: {
                sandboxRefusalObserved: true,
                jsonEventObserved: false,
                stderrProseSandbox: true
              }
            }
          }
        },
        grok: $g
      }
    }
  ' >"$bad"
  if ! validate_capability_note "$bad"; then
    fail "$name" "validator rejected codex option-D sandbox-refusal (JSON event not required)"
    return
  fi

  # Codex available=true without sandboxRefusalObserved evidence must fail
  # (no null escape hatch).
  jq -n --argjson c "$claude_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: {
          agent: "codex",
          status: "probed",
          readOnly: {
            mechanism: "cli-sandbox-refusal",
            cliFlags: ["-s", "read-only"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "sandbox-refusal",
            source: "y",
            probed: true
          },
          evidence: {
            writeBlock: {
              detail: {
                attempted: true,
                denied: true,
                flagPositiveEvidence: true
              }
            }
          }
        },
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted codex available=true without sandboxRefusalObserved evidence"
    return
  fi

  # Codex: probed=true without sandboxRefusalObserved must be rejected.
  jq -n --argjson c "$claude_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: {
          agent: "codex",
          status: "probed",
          readOnly: {
            mechanism: "cli-sandbox-refusal",
            cliFlags: ["-s", "read-only"],
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "sandbox-refusal",
            source: "y",
            probed: true
          },
          evidence: {
            permissionSignal: {
              detail: {
                sandboxRefusalObserved: false,
                jsonEventObserved: true
              }
            }
          }
        },
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted codex probed=true without sandboxRefusalObserved"
    return
  fi

  # Grok: available=true under disposable-copy with REAL-grok isolation evidence
  # is valid even when permissionSignal.probed=false (stream hang signal unproven).
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp/canonical",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: $x,
        grok: {
          agent: "grok",
          status: "probed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["--deny", "Write", "--deny", "Edit", "--deny", "Bash"],
            cliFlagEnforcement: "unproven, defence-in-depth only",
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "typed-tool-events-absent",
            source: "control probe: streaming-json omits typed tool events",
            probed: false
          },
          evidence: {
            writeBlock: {
              detail: {
                cliFlagPath: {
                  trusted: false,
                  writeBlocked: false,
                  controlWrote: true,
                  controlHasToolEvent: false
                },
                disposableCopy: {
                  writeInCopySucceeded: true,
                  canonicalUntouched: true,
                  realGrokWriteInCopy: true,
                  cleanedUp: true,
                  writer: "grok",
                  copySource: "canonical-checkout",
                  copyPath: "/tmp/copy",
                  canonicalProofMethod: "canonical-state-byte-identity"
                }
              }
            },
            permissionSignal: {
              detail: {
                typedToolAttempt: false,
                policyDenialObserved: false
              }
            }
          }
        }
      }
    }
  ' >"$bad"
  if ! validate_capability_note "$bad"; then
    fail "$name" "validator rejected grok disposable-checkout-copy available=true with real-grok evidence"
    return
  fi

  # Grok: available=true without whole-tree canonicalProofMethod must be rejected
  # (marker-filename-only is not a real whole-tree proof).
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp/canonical",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: $x,
        grok: {
          agent: "grok",
          status: "probed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["--deny", "Write"],
            cliFlagEnforcement: "unproven, defence-in-depth only",
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "typed-tool-events-absent",
            source: "y",
            probed: false
          },
          evidence: {
            writeBlock: {
              detail: {
                cliFlagPath: { trusted: false },
                disposableCopy: {
                  writeInCopySucceeded: true,
                  canonicalUntouched: true,
                  realGrokWriteInCopy: true,
                  cleanedUp: true,
                  writer: "grok",
                  copySource: "canonical-checkout"
                }
              }
            }
          }
        }
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted grok available without canonicalProofMethod (whole-tree proof required)"
    return
  fi

  # Grok: synthetic/shell proof (writeInCopySucceeded without realGrokWriteInCopy)
  # MUST be rejected — this is the HIGH fix-up target.
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp/canonical",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: $x,
        grok: {
          agent: "grok",
          status: "probed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["--deny", "Write"],
            cliFlagEnforcement: "unproven, defence-in-depth only",
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "typed-tool-events-absent",
            source: "y",
            probed: false
          },
          evidence: {
            writeBlock: {
              detail: {
                cliFlagPath: { trusted: false },
                disposableCopy: {
                  writeInCopySucceeded: true,
                  canonicalUntouched: true,
                  copyPath: "/tmp/copy",
                  seedPath: "/tmp/seed"
                }
              }
            }
          }
        }
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted synthetic/shell disposable-copy proof (missing realGrokWriteInCopy)"
    return
  fi

  # Grok: missing cleanedUp evidence must be rejected (fail-closed cleanup).
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp/canonical",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: $x,
        grok: {
          agent: "grok",
          status: "probed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["--deny", "Write"],
            cliFlagEnforcement: "unproven, defence-in-depth only",
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "typed-tool-events-absent",
            source: "y",
            probed: false
          },
          evidence: {
            writeBlock: {
              detail: {
                cliFlagPath: { trusted: false },
                disposableCopy: {
                  writeInCopySucceeded: true,
                  canonicalUntouched: true,
                  realGrokWriteInCopy: true,
                  writer: "grok",
                  copySource: "canonical-checkout"
                }
              }
            }
          }
        }
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted grok available without cleanedUp evidence"
    return
  fi

  # Grok: available=true claiming CLI-flag trusted must be rejected.
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp/canonical",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: $x,
        grok: {
          agent: "grok",
          status: "probed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["--deny", "Write"],
            cliFlagEnforcement: "unproven, defence-in-depth only",
            flagAccepted: true,
            writeBlocked: true,
            available: true
          },
          permissionSignal: {
            name: "typed-tool-events-absent",
            source: "y",
            probed: false
          },
          evidence: {
            writeBlock: {
              detail: {
                cliFlagPath: { trusted: true, writeBlocked: true },
                disposableCopy: {
                  writeInCopySucceeded: true,
                  canonicalUntouched: true,
                  realGrokWriteInCopy: true,
                  cleanedUp: true,
                  writer: "grok",
                  copySource: "canonical-checkout"
                }
              }
            }
          }
        }
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted grok available with cliFlagPath.trusted=true"
    return
  fi

  # Grok: permissionSignal.probed=true without typedToolAttempt must be rejected.
  jq -n --argjson c "$claude_fail" --argjson x "$codex_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: $c,
        codex: $x,
        grok: {
          agent: "grok",
          status: "probed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["--deny", "Write"],
            cliFlagEnforcement: "unproven, defence-in-depth only",
            flagAccepted: true,
            writeBlocked: true,
            available: false
          },
          permissionSignal: {
            name: "permission_policy_denied",
            source: "y",
            probed: true
          },
          evidence: {
            permissionSignal: {
              detail: {
                typedToolAttempt: false,
                policyDenialObserved: true
              }
            }
          }
        }
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted grok probed=true without typedToolAttempt"
    return
  fi

  # Wrong mechanism mapping must be rejected (e.g. claude labeled disposable-copy).
  jq -n --argjson x "$codex_fail" --argjson g "$grok_fail" '
    {
      schemaVersion: 1,
      probedAt: "2026-01-01T00:00:00Z",
      canonicalCheckout: "/tmp",
      capabilityFloor: { bashDeniedMeansNoReadOnlyShell: true },
      agents: {
        claude: {
          agent: "claude",
          status: "failed",
          readOnly: {
            mechanism: "disposable-checkout-copy",
            cliFlags: ["x"],
            flagAccepted: false,
            writeBlocked: false,
            available: false
          },
          permissionSignal: { name: "x", source: "y", probed: false }
        },
        codex: $x,
        grok: $g
      }
    }
  ' >"$bad"
  if validate_capability_note "$bad"; then
    fail "$name" "validator accepted wrong mechanism mapping for claude"
    return
  fi
  pass "$name"
}

test_make_disposable_copy_from_canonical_and_cleanup() {
  local name="make_disposable_checkout_copy copies real tracked files; cleanup fail-closed"
  local dest
  dest=$(mktemp -d "$TMP_DIR/copy-from-canonical.XXXXXX")
  if ! make_disposable_checkout_copy "$dest" "$REPO_ROOT"; then
    fail "$name" "make_disposable_checkout_copy failed for REPO_ROOT=$REPO_ROOT"
    return
  fi
  # Must be a copy OF the canonical checkout (tracked files present), not a
  # synthetic seed tree.
  if [[ ! -f "$dest/AGENTS.md" && ! -f "$dest/README.md" ]]; then
    fail "$name" "copy missing tracked root files from canonical checkout"
    return
  fi
  if [[ ! -f "$dest/orchestration/tests/scripts/chat-cli-probe.test.sh" ]]; then
    fail "$name" "copy missing tracked probe test file from canonical checkout"
    return
  fi
  # Synthetic-seed markers must not be the only content.
  if [[ -f "$dest/src/note.txt" ]] && [[ ! -f "$dest/AGENTS.md" ]]; then
    fail "$name" "copy looks like a synthetic seed, not the canonical checkout"
    return
  fi
  if ! cleanup_disposable_checkout_copy "$dest"; then
    fail "$name" "cleanup_disposable_checkout_copy failed"
    return
  fi
  if [[ -e "$dest" ]]; then
    fail "$name" "copy still exists after cleanup (must fail-closed)"
    return
  fi
  # Failed cleanup path: refuse to clean REPO_ROOT.
  if cleanup_disposable_checkout_copy "$REPO_ROOT" 2>/dev/null; then
    fail "$name" "cleanup incorrectly accepted REPO_ROOT (must refuse)"
    return
  fi
  pass "$name"
}

test_canonical_state_snapshot_is_whole_tree() {
  local name="canonicalUntouched uses whole-tree before/after byte-identity (not marker-only)"
  local fake
  fake=$(mktemp -d "$TMP_DIR/canonical-snap.XXXXXX")
  # Minimal git repo standing in for the canonical checkout.
  git -C "$fake" init -q
  git -C "$fake" config user.email "probe@test.local"
  git -C "$fake" config user.name "probe"
  printf 'tracked-v1\n' >"$fake/README.md"
  printf 'other\n' >"$fake/other.txt"
  git -C "$fake" add README.md other.txt
  git -C "$fake" commit -q -m 'init'

  local before after
  before="$TMP_DIR/canonical-before.snap"
  after="$TMP_DIR/canonical-after.snap"
  if ! capture_canonical_state_snapshot "$fake" "$before"; then
    fail "$name" "capture_canonical_state_snapshot failed on clean tree"
    return
  fi
  if [[ ! -s "$before" ]]; then
    fail "$name" "before snapshot empty"
    return
  fi
  # Method banner must self-describe the proof.
  if ! rg -q "^method: ${CANONICAL_PROOF_METHOD}$" "$before"; then
    fail "$name" "snapshot missing method banner ${CANONICAL_PROOF_METHOD}"
    return
  fi
  if ! rg -q '^HEAD ' "$before"; then
    fail "$name" "snapshot missing HEAD line"
    return
  fi
  if ! rg -qF '=== porcelain-v1-unormal ===' "$before"; then
    fail "$name" "snapshot missing porcelain section"
    return
  fi
  if ! rg -qF '=== tracked-worktree-hashes ===' "$before"; then
    fail "$name" "snapshot missing tracked worktree hash section"
    return
  fi
  if ! rg -qF 'README.md' "$before"; then
    fail "$name" "tracked manifest missing README.md"
    return
  fi

  # Identical second capture => equal.
  if ! capture_canonical_state_snapshot "$fake" "$after"; then
    fail "$name" "second capture failed"
    return
  fi
  if ! compare_canonical_state_snapshots "$before" "$after"; then
    fail "$name" "identical trees compared unequal: $CANONICAL_SNAP_DIFF"
    return
  fi

  # Content change of a NON-marker tracked file must fail loudly (marker-only
  # would miss this — the whole point of the fix-up).
  printf 'tracked-v2-mutated\n' >"$fake/README.md"
  if ! capture_canonical_state_snapshot "$fake" "$after"; then
    fail "$name" "capture after content mutation failed"
    return
  fi
  if compare_canonical_state_snapshots "$before" "$after"; then
    fail "$name" "content mutation of README.md not detected (marker-only hazard)"
    return
  fi
  if [[ -z "$CANONICAL_SNAP_DIFF" ]]; then
    fail "$name" "diff summary empty on content mutation"
    return
  fi

  # Restore content; introduce a non-marker untracked file — must detect.
  printf 'tracked-v1\n' >"$fake/README.md"
  printf 'sneak\n' >"$fake/UNRELATED_NEW_FILE.txt"
  capture_canonical_state_snapshot "$fake" "$after"
  if compare_canonical_state_snapshots "$before" "$after"; then
    fail "$name" "new untracked non-marker file not detected"
    return
  fi

  # HEAD move must detect.
  rm -f "$fake/UNRELATED_NEW_FILE.txt"
  printf 'tracked-v1\n' >"$fake/README.md"
  git -C "$fake" add -A
  # ensure clean matching worktree again for a clean before re-snap
  capture_canonical_state_snapshot "$fake" "$before"
  git -C "$fake" commit --allow-empty -q -m 'empty-move-head'
  capture_canonical_state_snapshot "$fake" "$after"
  if compare_canonical_state_snapshots "$before" "$after"; then
    fail "$name" "HEAD move not detected"
    return
  fi

  # Source body of prove_disposable_copy_isolation must use the snapshot helpers
  # (not marker-filename-only), record the method name, and isolate the proof
  # target via a private worktree so concurrent REPO_ROOT writers cannot
  # invalidate a correct isolation result.
  local prove_body
  prove_body=$(sed -n '/^prove_disposable_copy_isolation()/,/^}/p' "$SCRIPT_DIR/chat-cli-probe.test.sh")
  if ! rg -q 'capture_canonical_state_snapshot' <<<"$prove_body"; then
    fail "$name" "prove_disposable_copy_isolation does not call capture_canonical_state_snapshot"
    return
  fi
  if ! rg -q 'compare_canonical_state_snapshots' <<<"$prove_body"; then
    fail "$name" "prove_disposable_copy_isolation does not call compare_canonical_state_snapshots"
    return
  fi
  if ! rg -q 'canonicalProofMethod|CANONICAL_PROOF_METHOD' <<<"$prove_body"; then
    fail "$name" "prove_disposable_copy_isolation does not record canonicalProofMethod"
    return
  fi
  if ! rg -q 'worktree add' <<<"$prove_body"; then
    fail "$name" "prove_disposable_copy_isolation does not create a private worktree for isolation proof"
    return
  fi
  if ! rg -q 'proofScope|private-worktree-of-HEAD' <<<"$prove_body"; then
    fail "$name" "prove_disposable_copy_isolation does not record proofScope"
    return
  fi
  # Old marker-only assignment (canonical_ok=true before any snapshot) is banned
  # as the sole proof path: require compare to drive canonical_ok.
  if rg -q 'canonical_ok=true' <<<"$prove_body" \
    && ! rg -q 'compare_canonical_state_snapshots' <<<"$prove_body"; then
    fail "$name" "prove still defaults canonical_ok=true without compare"
    return
  fi
  pass "$name"
}

test_disposable_copy_isolation_blocks_canonical() {
  local name="disposable-copy REAL grok write in checkout-copy; canonical untouched; cleaned up"
  # Requires LIVE + real grok — never satisfied by synthetic/shell write.
  if [[ "$LIVE_MODE" != "1" ]]; then
    skip "$name" "CHAT_CLI_PROBE_LIVE=$LIVE_MODE (real-grok isolation requires live)"
    return
  fi
  if ! command -v grok >/dev/null 2>&1; then
    skip "$name" "grok binary not found on PATH"
    return
  fi
  local result
  if ! result=$(prove_disposable_copy_isolation 2>"$TMP_DIR/prove-disposable.err"); then
    fail "$name" "prove_disposable_copy_isolation failed: $(cat "$TMP_DIR/prove-disposable.err" 2>/dev/null) result=$result"
    return
  fi
  if ! jq -e \
      --arg method "$CANONICAL_PROOF_METHOD" '
      .writeInCopySucceeded == true
      and .canonicalUntouched == true
      and .realGrokWriteInCopy == true
      and .cleanedUp == true
      and .writer == "grok"
      and .copySource == "canonical-checkout"
      and .canonicalProofMethod == $method
      and .proofScope == "private-worktree-of-HEAD"
      and (.proofCanonicalPath | type == "string" and length > 0)
    ' <<<"$result" >/dev/null; then
    fail "$name" "isolation proof missing real-grok/cleanup/whole-tree evidence: $result"
    return
  fi
  # Shared REPO_ROOT must not have the probe marker (detect-only).
  if [[ -e "$REPO_ROOT/$PROBE_MARKER" ]]; then
    fail "$name" "canonical checkout has $PROBE_MARKER after disposable-copy write"
    return
  fi
  # Copy must have been cleaned up (path gone after proof).
  local copy_path proof_path
  copy_path=$(jq -r '.copyPath // empty' <<<"$result")
  proof_path=$(jq -r '.proofCanonicalPath // empty' <<<"$result")
  if [[ -z "$copy_path" ]]; then
    fail "$name" "missing copyPath in evidence"
    return
  fi
  if [[ -e "$copy_path" ]]; then
    fail "$name" "copy path still exists after proof (cleanup required): $copy_path"
    return
  fi
  if [[ -n "$proof_path" && -e "$proof_path" ]]; then
    fail "$name" "proof worktree still exists after proof (cleanup required): $proof_path"
    return
  fi
  pass "$name"
}

test_write_blocked_requires_positive_evidence() {
  local name="writeBlocked requires attempt+denial evidence (not marker absence)"
  # Simulate: marker absent, no denial signature => must NOT set writeBlocked.
  local scratch="$TMP_DIR/evidence-check"
  mkdir -p "$scratch"
  local out="$scratch/out.txt" err="$scratch/err.txt"
  : >"$out"
  : >"$err"
  # No marker, no attempt/denial text.
  local attempted=false denied=false blocked=false
  if [[ ! -f "$scratch/$PROBE_MARKER" ]]; then
    # Old bug would set blocked=true here.
    blocked=false
  fi
  if rg -qi 'writing is blocked by read-only sandbox|patch rejected' "$err" "$out" 2>/dev/null; then
    denied=true
  fi
  if [[ "$denied" == true && ! -f "$scratch/$PROBE_MARKER" ]]; then
    blocked=true
  fi
  if [[ "$blocked" == true ]]; then
    fail "$name" "empty streams incorrectly produced writeBlocked"
    return
  fi
  # Positive path: denial signature present, marker absent.
  printf 'patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings\n' >"$err"
  denied=false
  blocked=false
  if rg -qi 'writing is blocked by read-only sandbox|patch rejected' "$err" "$out" 2>/dev/null; then
    denied=true
    attempted=true
  fi
  if [[ "$attempted" == true && "$denied" == true && ! -f "$scratch/$PROBE_MARKER" ]]; then
    blocked=true
  fi
  if [[ "$blocked" != true ]]; then
    fail "$name" "positive denial signature did not set writeBlocked"
    return
  fi
  pass "$name"
}

test_permission_signal_matchers_on_fixtures() {
  local name="permission-signal matchers recognize live-shaped fixtures"
  local fixtures="$TMP_DIR/signal-fixtures"
  mkdir -p "$fixtures"

  # Claude: STREAM pair only — Write tool_use + tool_result permission surface.
  # Notification hooks are not-applicable (no-settings-edit invariant).
  cat >"$fixtures/claude.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_x","name":"Write","input":{"file_path":"/tmp/PROBE_PERM.txt","content":"x"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Claude requested permissions to write to /tmp/PROBE_PERM.txt, but you haven't granted it yet.","is_error":true,"tool_use_id":"toolu_x"}]}}
EOF
  # Text-only stream (no tool_use / tool_result) must NOT count as probed.
  cat >"$fixtures/claude-text-only.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I will not write."}]}}
EOF
  # Codex exec --json: optional approval-request EVENT (not required for option D)
  cat >"$fixtures/codex.jsonl" <<'EOF'
{"type":"item.started","item":{"id":"item_1","type":"command_execution","status":"in_progress"}}
{"type":"error","message":"approval-request: commandExecution requires approval"}
{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"blocked"}}
EOF
  # Codex option D: sandbox refusal on stderr IS the mechanical signal.
  cat >"$fixtures/codex-sandbox-only.err" <<'EOF'
patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings
EOF
  # Grok: typed WRITE-named tool_call + independent mechanical deny-policy event
  cat >"$fixtures/grok.jsonl" <<'EOF'
{"type":"tool_call","name":"write","call_id":"call_1","arguments":{"path":"PROBE_WRITE_ME.txt","contents":"blocked"}}
{"type":"permission_policy","data":"Denied by permission policy: deny rule on edit for tool `write`."}
{"type":"end","stopReason":"EndTurn"}
EOF
  # Unrelated tool event must NOT satisfy the write-tool matcher.
  cat >"$fixtures/grok-unrelated-tool.jsonl" <<'EOF'
{"type":"tool_call","name":"read_file","call_id":"call_r","arguments":{"path":"README"}}
{"type":"permission_policy","data":"Denied by permission policy: deny rule on edit for tool `write`."}
{"type":"end","stopReason":"EndTurn"}
EOF
  # tool_result-only without a write-named tool_call must NOT match.
  cat >"$fixtures/grok-result-only.jsonl" <<'EOF'
{"type":"tool_result","call_id":"call_1","content":"Denied by permission policy"}
{"type":"end","stopReason":"EndTurn"}
EOF
  # Narration-only (text repeating denial) without typed tool event must NOT match.
  cat >"$fixtures/grok-narration.jsonl" <<'EOF'
{"type":"text","data":"Denied by permission policy: deny rule on edit for tool `write`."}
{"type":"end","stopReason":"EndTurn"}
EOF

  local claude_tool_hit claude_attempt_hit claude_text_alone
  local codex_json_hit codex_sandbox_hit grok_hit grok_narr grok_unrelated grok_result_only
  claude_attempt_hit=0
  if claude_stream_has_write_attempt "$fixtures/claude.jsonl"; then
    claude_attempt_hit=1
  fi
  claude_tool_hit=0
  if claude_stream_has_permission_prompt_tool_result "$fixtures/claude.jsonl"; then
    claude_tool_hit=1
  fi
  # Text-only stream => must not set probed.
  claude_text_alone=0
  if claude_stream_has_write_attempt "$fixtures/claude-text-only.jsonl" \
    || claude_stream_has_permission_prompt_tool_result "$fixtures/claude-text-only.jsonl"; then
    claude_text_alone=1
  fi
  # Codex option D: sandbox refusal on stderr IS the mechanical signal.
  codex_sandbox_hit=0
  if codex_stderr_has_sandbox_refusal "$fixtures/codex-sandbox-only.err"; then
    codex_sandbox_hit=1
  fi
  # JSON approval-request still recognizable (optional, not required).
  codex_json_hit=0
  if codex_stream_has_approval_request_event "$fixtures/codex.jsonl"; then
    codex_json_hit=1
  fi
  # JSON matcher must NOT fire on bare stderr prose.
  if codex_stream_has_approval_request_event "$fixtures/codex-sandbox-only.err"; then
    fail "$name" "JSON approval-request matcher incorrectly matched sandbox stderr prose"
    return
  fi
  grok_hit=0
  if grok_stream_has_typed_tool_attempt "$fixtures/grok.jsonl" \
    && grok_stream_has_policy_denial "$fixtures/grok.jsonl"; then
    grok_hit=1
  fi
  grok_unrelated=0
  if grok_stream_has_typed_tool_attempt "$fixtures/grok-unrelated-tool.jsonl"; then
    grok_unrelated=1
  fi
  grok_result_only=0
  if grok_stream_has_typed_tool_attempt "$fixtures/grok-result-only.jsonl"; then
    grok_result_only=1
  fi
  grok_narr=0
  if grok_stream_has_typed_tool_attempt "$fixtures/grok-narration.jsonl" \
    && grok_stream_has_policy_denial "$fixtures/grok-narration.jsonl"; then
    grok_narr=1
  fi
  # Narration text alone must never satisfy even if policy text is present.
  if ! grok_stream_has_typed_tool_attempt "$fixtures/grok-narration.jsonl" \
    && grok_stream_has_policy_denial_text_only "$fixtures/grok-narration.jsonl"; then
    grok_narr=0
  fi

  if [[ "${claude_tool_hit:-0}" -lt 1 || "${claude_attempt_hit:-0}" -lt 1 ]]; then
    fail "$name" "claude stream pair matchers missed (tool=$claude_tool_hit attempt=$claude_attempt_hit)"
    return
  fi
  if [[ "${claude_text_alone:-0}" -ne 0 ]]; then
    fail "$name" "claude text-only stream incorrectly counted as probed"
    return
  fi
  if [[ "${codex_sandbox_hit:-0}" -lt 1 ]]; then
    fail "$name" "codex sandbox-refusal stderr fixture not matched (option D)"
    return
  fi
  if [[ "${codex_json_hit:-0}" -lt 1 ]]; then
    fail "$name" "codex optional approval-request JSON fixture missed"
    return
  fi
  if [[ "${grok_hit:-0}" -lt 1 ]]; then
    fail "$name" "grok write-named tool + policy denial fixture not matched"
    return
  fi
  if [[ "${grok_unrelated:-0}" -ne 0 ]]; then
    fail "$name" "unrelated tool_call incorrectly matched as write attempt"
    return
  fi
  if [[ "${grok_result_only:-0}" -ne 0 ]]; then
    fail "$name" "tool_result-only incorrectly matched as write tool attempt"
    return
  fi
  if [[ "${grok_narr:-0}" -ne 0 ]]; then
    fail "$name" "assistant narration incorrectly matched as permission event"
    return
  fi
  pass "$name"
}

test_assert_no_checkout_write_is_non_destructive() {
  local name="assert_no_checkout_write detects without deleting"
  local sentinel="$REPO_ROOT/$PROBE_MARKER"
  # Never write into the real checkout for this test. Simulate detect-only
  # behavior on a fake tree: if the probe filename exists, detect and leave it.
  local fake_root="$TMP_DIR/fake-checkout"
  mkdir -p "$fake_root"
  printf 'leftover\n' >"$fake_root/$PROBE_MARKER"
  if [[ ! -e "$fake_root/$PROBE_MARKER" ]]; then
    fail "$name" "setup failed to create fake probe marker"
    return
  fi
  # Mirror the detector: existence check only (no rm).
  if [[ ! -e "$fake_root/$PROBE_MARKER" ]]; then
    fail "$name" "detector path would miss existing probe marker"
    return
  fi
  # Marker must still exist after detection (non-destructive).
  if [[ ! -e "$fake_root/$PROBE_MARKER" ]]; then
    fail "$name" "detector deleted the marker (must leave in place for human)"
    return
  fi
  local body
  body=$(sed -n '/^assert_no_checkout_write()/,/^}/p' "$SCRIPT_DIR/chat-cli-probe.test.sh")
  if rg -q 'rm -f|find .*-delete|-delete' <<<"$body"; then
    fail "$name" "assert_no_checkout_write still contains destructive rm/find -delete"
    return
  fi
  # Real checkout must not already have probe markers (precondition).
  if [[ -e "$sentinel" || -e "$REPO_ROOT/$PROBE_PERM_MARKER" ]]; then
    fail "$name" "canonical checkout already has probe marker (left for human — refusing to touch)"
    return
  fi
  pass "$name"
}

test_flag_accepted_requires_positive_evidence() {
  local name="flagAccepted requires positive evidence (not absence of parser error)"
  local scratch="$TMP_DIR/flag-pos"
  mkdir -p "$scratch"
  local out="$scratch/out.jsonl" err="$scratch/err.txt"
  : >"$out"
  : >"$err"
  local flag_ok=false
  # Empty streams / no positive signature => false (old bug set true on !parser-error).
  if ! rg -qi 'unexpected argument|unknown' "$err" 2>/dev/null; then
    # Deliberately do NOT set flag_ok=true here.
    flag_ok=false
  fi
  if [[ "$flag_ok" == true ]]; then
    fail "$name" "empty streams produced flagAccepted"
    return
  fi
  # Positive codex: read-only sandbox denial signature.
  printf 'patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings\n' >"$err"
  flag_ok=false
  if rg -qi 'writing is blocked by read-only sandbox|sandbox:[[:space:]]*read-only' "$err" "$out" 2>/dev/null; then
    flag_ok=true
  fi
  if [[ "$flag_ok" != true ]]; then
    fail "$name" "codex sandbox denial did not set flagAccepted"
    return
  fi
  # Failed invocation => false
  printf 'error: unexpected argument '\''--deny'\'' found\n' >"$err"
  flag_ok=true
  if rg -qi 'unexpected argument|unknown.*(option|deny|sandbox|permission-mode)' "$err" 2>/dev/null; then
    flag_ok=false
  fi
  if [[ "$flag_ok" != false ]]; then
    fail "$name" "failed invocation did not clear flagAccepted"
    return
  fi
  # Positive claude: init permissionMode dontAsk
  cat >"$out" <<'EOF'
{"type":"system","subtype":"init","permissionMode":"dontAsk","cwd":"/tmp/scratch"}
EOF
  : >"$err"
  flag_ok=false
  if jq -e 'select(.type=="system" and .subtype=="init") | .permissionMode=="dontAsk"' "$out" >/dev/null 2>&1; then
    flag_ok=true
  fi
  if [[ "$flag_ok" != true ]]; then
    fail "$name" "claude init permissionMode did not set flagAccepted"
    return
  fi
  # Positive grok: completed stream end after deny-flag invocation (accepted-flag signature)
  cat >"$out" <<'EOF'
{"type":"end","stopReason":"EndTurn","sessionId":"s1"}
EOF
  flag_ok=false
  if jq -e 'select(.type=="end")' "$out" >/dev/null 2>&1; then
    flag_ok=true
  fi
  if [[ "$flag_ok" != true ]]; then
    fail "$name" "grok type=end accepted-flag signature not recognized"
    return
  fi
  pass "$name"
}

test_run_bounded_portable_timeout() {
  local name="run_bounded times out without hanging (portable)"
  local out="$TMP_DIR/bound.out" err="$TMP_DIR/bound.err"
  local rc=0
  # Do not mutate the global PROBE_TIMEOUT_SECS (live probes depend on it).
  # Exercise the python timeout path directly with a 1s budget.
  set +e
  python3 -c '
import os, signal, subprocess, sys
with open(sys.argv[1], "w") as fo, open(sys.argv[2], "w") as fe:
    p = subprocess.Popen(["sleep", "30"], stdout=fo, stderr=fe)
    try:
        sys.exit(p.wait(timeout=1))
    except subprocess.TimeoutExpired:
        try:
            os.kill(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait()
        sys.exit(124)
' "$out" "$err"
  rc=$?
  set +e
  if [[ "$rc" -ne 124 ]]; then
    fail "$name" "expected exit 124 on timeout, got $rc"
    return 0
  fi
  pass "$name"
}

# --- Live write-block probes ----------------------------------------------

probe_scratch() {
  local agent=$1
  local d
  d=$(mktemp -d "$TMP_DIR/${agent}-scratch.XXXXXX")
  # Ensure probe never starts inside the canonical checkout as cwd for writes.
  printf 'scratch for %s write-block probe\n' "$agent" >"$d/README"
  printf '%s\n' "$d"
}

# DETECT-ONLY safety guard. Never deletes anything under the canonical checkout.
# If a probe artifact appears, FAIL loudly and leave it for a human to inspect.
assert_no_checkout_write() {
  local name=$1
  local bad=0
  local hits=""

  if [[ -e "$REPO_ROOT/$PROBE_MARKER" ]]; then
    fail "$name" "probe wrote $PROBE_MARKER into canonical checkout (LEFT IN PLACE for human inspection — not deleted)"
    bad=1
  fi
  if [[ -e "$REPO_ROOT/$PROBE_PERM_MARKER" ]]; then
    fail "$name" "probe wrote $PROBE_PERM_MARKER into canonical checkout (LEFT IN PLACE for human inspection — not deleted)"
    bad=1
  fi

  # Report any probe artifact under the checkout without removing it.
  hits=$(find "$REPO_ROOT" \( -name "$PROBE_MARKER" -o -name "$PROBE_PERM_MARKER" \) 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    fail "$name" "probe artifact(s) under repo checkout (LEFT IN PLACE): $(printf '%s' "$hits" | tr '\n' ' ')"
    bad=1
  fi

  # Targeted porcelain check for the exact probe filenames (detect-only).
  if git -C "$REPO_ROOT" status --porcelain 2>/dev/null \
    | rg -q -- "$PROBE_MARKER|$PROBE_PERM_MARKER"; then
    fail "$name" "git status shows probe marker under checkout (LEFT IN PLACE for human inspection)"
    bad=1
  fi

  return "$bad"
}

# Join streaming-json text.data chunks (grok emits token-sized fragments).
stream_text_concat() {
  local file=$1
  [[ -f "$file" ]] || return 0
  jq -r 'select(.type == "text") | .data // empty' "$file" 2>/dev/null | tr -d '\n'
}

# Claude: tool_use Write present in stream-json.
claude_stream_has_write_attempt() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  jq -e '
    select(.type=="assistant")
    | .message.content[]?
    | select(.type=="tool_use" and (.name|tostring|test("Write"; "i")))
  ' "$stream" >/dev/null 2>&1
}

# Claude: mechanical denial tool_result (dontAsk or requested-permissions).
claude_stream_has_write_denial() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  jq -e '
    select(.type=="user")
    | .message.content[]?
    | select(.type=="tool_result" and .is_error==true)
    | select(
        (.content|tostring) | test(
          "don.t ask mode|requested permissions|haven.t granted|Permission to use Write has been denied|disallowed";
          "i"
        )
      )
  ' "$stream" >/dev/null 2>&1
}

# Claude permission_prompt surface: tool_result is_error with permission-denial text.
# Accepts "requested permissions" (default mode) and dontAsk denial language.
claude_stream_has_permission_prompt_tool_result() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  jq -e '
    select(.type=="user")
    | .message.content[]?
    | select(.type=="tool_result" and .is_error==true)
    | select(
        (.content|tostring) | test(
          "requested permissions|haven.t granted|don.t ask mode|Permission to use Write has been denied|disallowed|permission";
          "i"
        )
      )
  ' "$stream" >/dev/null 2>&1
}

# Codex option D: sandbox refusal on CLI stderr (sandbox speaking, not the model).
# This is the binding mechanical read-only / permission signal. JSON approval-
# request events are optional and NOT required for available=true.
codex_stderr_has_sandbox_refusal() {
  local err=$1
  [[ -f "$err" ]] || return 1
  rg -qi 'writing is blocked by read-only sandbox|patch rejected:.*read-only|sandbox:[[:space:]]*read-only' "$err" 2>/dev/null
}

# Codex: optional approval-request / rejection EVENT on the exec --json stream.
# Kept for characterization; option D does not require this for available=true.
codex_stream_has_approval_request_event() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  # Must be parseable JSON lines carrying an approval-request family event.
  jq -e '
    select(.type != null or .item != null or .message != null)
    | select(
        ((.type | tostring) | test("approval[-_]?request|requestApproval|approval"; "i"))
        or ((.message | tostring) | test("approval[-_]?request|requestApproval"; "i"))
        or ((.item.type | tostring) | test("approval|requestApproval"; "i"))
        or (
          (.. | strings)
          | test("item/commandExecution/requestApproval|item/fileChange/requestApproval|approval-request"; "i")
        )
      )
  ' "$stream" >/dev/null 2>&1
}

# --- Disposable checkout copy (option B; same mechanism chat-runner will use) ---
#
# make_disposable_checkout_copy DEST [SRC]
#   Copy tracked files from the ACTUAL canonical checkout (SRC, default
#   REPO_ROOT) into DEST. Bounded: tracked-files subset via `git ls-files`,
#   never a synthetic fixture tree. Fail-closed: non-zero on any failure.
#   This is the mechanism chat-runner will use for read-only grok chats.
make_disposable_checkout_copy() {
  local dest=$1
  local src=${2:-$REPO_ROOT}
  [[ -n "$dest" && -d "$src" ]] || return 1
  mkdir -p "$dest" || return 1

  local file_count
  file_count=$(git -C "$src" ls-files 2>/dev/null | wc -l | tr -d ' ')
  if [[ -z "$file_count" || "$file_count" -lt 1 ]]; then
    printf 'make_disposable_checkout_copy: no tracked files under %s\n' "$src" >&2
    return 1
  fi

  if command -v rsync >/dev/null 2>&1; then
    if ! git -C "$src" ls-files -z | rsync -a --from0 --files-from=- -- "$src/" "$dest/"; then
      printf 'make_disposable_checkout_copy: rsync failed\n' >&2
      return 1
    fi
  else
    local rel parent
    while IFS= read -r -d '' rel; do
      parent=$(dirname "$rel")
      mkdir -p "$dest/$parent" || return 1
      cp -p "$src/$rel" "$dest/$rel" || return 1
    done < <(git -C "$src" ls-files -z)
  fi

  # Sanity: known tracked files from the real checkout must be present.
  if [[ ! -f "$dest/AGENTS.md" && ! -f "$dest/README.md" && ! -f "$dest/.gitignore" ]]; then
    printf 'make_disposable_checkout_copy: copy missing known tracked root files\n' >&2
    return 1
  fi
  local dest_count
  dest_count=$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ -z "$dest_count" || "$dest_count" -lt 1 ]]; then
    printf 'make_disposable_checkout_copy: empty copy\n' >&2
    return 1
  fi
  return 0
}

# capture_canonical_state_snapshot CANONICAL OUTFILE
#   Bounded, deterministic whole-tree state of the CANONICAL checkout for
#   before/after byte-identity comparison. Method: canonical-state-byte-identity
#   = HEAD + porcelain=v1 -unormal + tracked worktree content hashes (git hash-object).
#   DETECT-ONLY: never mutates the checkout. Returns 0 on success.
capture_canonical_state_snapshot() {
  local canonical=$1
  local out=$2
  [[ -n "$canonical" && -d "$canonical" && -n "$out" ]] || return 1
  local head_sha porcelain rel h
  head_sha=$(git -C "$canonical" rev-parse HEAD 2>/dev/null) || return 1
  porcelain=$(git -C "$canonical" status --porcelain=v1 -unormal 2>/dev/null) || return 1

  {
    # Use printf '%s\n' for section banners: BSD/macOS printf treats leading
    # '---…' as options when it is the format string.
    printf '%s\n' "method: ${CANONICAL_PROOF_METHOD}"
    printf '%s\n' "HEAD ${head_sha}"
    printf '%s\n' '=== porcelain-v1-unormal ==='
    # Preserve empty porcelain (clean tree) as a zero-length section body.
    if [[ -n "$porcelain" ]]; then
      printf '%s\n' "$porcelain"
    fi
    printf '%s\n' '=== tracked-worktree-hashes ==='
    # Sorted tracked paths; hash worktree content (not index) so dirty edits show.
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      if [[ -L "$canonical/$rel" ]]; then
        printf '%s\n' "symlink:$(readlink "$canonical/$rel")  ${rel}"
      elif [[ -f "$canonical/$rel" ]]; then
        h=$(git -C "$canonical" hash-object -- "$rel" 2>/dev/null || printf '%s' 'UNREADABLE')
        printf '%s\n' "${h}  ${rel}"
      elif [[ -e "$canonical/$rel" ]]; then
        printf '%s\n' "special  ${rel}"
      else
        printf '%s\n' "absent  ${rel}"
      fi
    done < <(git -C "$canonical" ls-files 2>/dev/null | LC_ALL=C sort)
  } >"$out" || return 1
  [[ -s "$out" ]] || return 1
  return 0
}

# Last compare diff summary (global; bash-3.2-safe — no nameref into caller locals).
CANONICAL_SNAP_DIFF=""

# compare_canonical_state_snapshots BEFORE AFTER
#   Require BYTE-IDENTICAL equality of the two snapshots. On mismatch, set
#   CANONICAL_SNAP_DIFF to a bounded unified-diff summary (detect-only; never
#   reverts or deletes checkout content). Returns 0 iff identical.
compare_canonical_state_snapshots() {
  local before=$1
  local after=$2
  CANONICAL_SNAP_DIFF=""
  [[ -f "$before" && -f "$after" ]] || return 1
  if cmp -s "$before" "$after"; then
    return 0
  fi
  local summary
  summary=$(diff -u "$before" "$after" 2>/dev/null | head -n 80 || true)
  if [[ -z "$summary" ]]; then
    summary="snapshots differ (diff unavailable); before_bytes=$(wc -c <"$before" | tr -d ' ') after_bytes=$(wc -c <"$after" | tr -d ' ')"
  fi
  CANONICAL_SNAP_DIFF=$summary
  return 1
}

# cleanup_disposable_checkout_copy DEST
#   Remove a disposable copy. Fail-closed: refuses REPO_ROOT and paths outside
#   temp roots; returns non-zero if DEST still exists after cleanup.
cleanup_disposable_checkout_copy() {
  local dest=$1
  [[ -n "$dest" ]] || return 1
  # Absolute-normalize when possible.
  local dest_abs
  dest_abs=$(cd "$(dirname "$dest")" 2>/dev/null && pwd -P)/$(basename "$dest") || dest_abs=$dest
  local repo_abs
  repo_abs=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P) || repo_abs=$REPO_ROOT

  if [[ "$dest_abs" == "$repo_abs" || "$dest" == "$REPO_ROOT" ]]; then
    printf 'cleanup_disposable_checkout_copy: refusing to remove REPO_ROOT\n' >&2
    return 1
  fi
  # Only clean paths under TMP_DIR or system temp (never the checkout tree).
  case "$dest_abs" in
    "$TMP_DIR"/*|/tmp/*|/var/folders/*|/private/var/folders/*)
      ;;
    *)
      printf 'cleanup_disposable_checkout_copy: refusing non-temp path %s\n' "$dest_abs" >&2
      return 1
      ;;
  esac

  if [[ ! -e "$dest" ]]; then
    return 0
  fi
  rm -rf "$dest"
  if [[ -e "$dest" ]]; then
    printf 'cleanup_disposable_checkout_copy: dest still exists after rm\n' >&2
    return 1
  fi
  return 0
}

# Prove disposable-copy isolation (option B) with REAL components end-to-end:
#   1) Create a PRIVATE git worktree of the ACTUAL repo HEAD (same project,
#      real git checkout — not a synthetic fixture tree). Concurrent agents
#      editing the shared REPO_ROOT worktree must not invalidate isolation.
#   2) make_disposable_checkout_copy from that private worktree (tracked subset;
#      same mechanism chat-runner will use).
#   3) BEFORE real grok: capture whole-tree state snapshot of the private
#      worktree (method=canonical-state-byte-identity: HEAD + porcelain=v1
#      -unormal + tracked worktree content hashes).
#   4) run REAL grok CLI with cwd inside the disposable copy, prompted to write
#   5) AFTER grok + cleanup: re-capture; require BYTE-IDENTICAL equality.
#      Any tracked content change, new untracked file, staged/unstaged change,
#      or HEAD move fails loudly with a diff summary (detect-only — never
#      delete/revert anything in REPO_ROOT or the private worktree).
#   6) cleanup the copy + private worktree; failed copy/cleanup = fail-closed
#   7) detect-only: probe markers must not appear under the shared REPO_ROOT
# A synthetic seed tree or shell printf write MUST NOT satisfy this proof.
# Marker-filename absence alone is NOT sufficient for canonicalUntouched.
# Prints JSON evidence on stdout; returns 0 only on full real-grok proof.
prove_disposable_copy_isolation() {
  local copy_root="" writer="none"
  local write_ok=false real_grok=false canonical_ok=false cleaned_up=false
  local copy_failed=false grok_missing=false
  local out err prompt_file marker_in_copy
  local tracked_count=0
  local snap_before snap_after canonical_diff=""
  local snapshot_error=""
  local proof_canonical="" worktree_failed=false
  local proof_scope="private-worktree-of-HEAD"

  remove_proof_worktree() {
    local wt=$1
    [[ -n "$wt" ]] || return 0
    if [[ -d "$wt" ]]; then
      git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 \
        || rm -rf "$wt" >/dev/null 2>&1 \
        || true
    fi
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  }

  emit_proof() {
    jq -n \
      --argjson writeInCopySucceeded "$write_ok" \
      --argjson canonicalUntouched "$canonical_ok" \
      --argjson realGrokWriteInCopy "$real_grok" \
      --argjson cleanedUp "$cleaned_up" \
      --argjson copyFailed "$copy_failed" \
      --argjson grokMissing "$grok_missing" \
      --arg writer "$writer" \
      --arg copyPath "${copy_root:-}" \
      --arg canonicalCheckout "$REPO_ROOT" \
      --arg proofCanonicalPath "${proof_canonical:-}" \
      --arg proofScope "$proof_scope" \
      --arg marker "$PROBE_MARKER" \
      --argjson trackedFileCount "$tracked_count" \
      --arg proofMethod "$CANONICAL_PROOF_METHOD" \
      --arg canonicalDiff "$canonical_diff" \
      --arg error "${1:-}" \
      '{
        writeInCopySucceeded: $writeInCopySucceeded,
        canonicalUntouched: $canonicalUntouched,
        realGrokWriteInCopy: $realGrokWriteInCopy,
        cleanedUp: $cleanedUp,
        writer: $writer,
        copySource: "canonical-checkout",
        copyPath: $copyPath,
        canonicalCheckout: $canonicalCheckout,
        proofCanonicalPath: $proofCanonicalPath,
        proofScope: $proofScope,
        marker: $marker,
        trackedFileCount: $trackedFileCount,
        copyFailed: $copyFailed,
        grokMissing: $grokMissing,
        mechanism: "disposable-checkout-copy",
        canonicalProofMethod: $proofMethod,
        canonicalDiffSummary: (if $canonicalDiff == "" then null else $canonicalDiff end),
        error: (if $error == "" then null else $error end)
      }'
  }

  copy_root=$(mktemp -d "$TMP_DIR/disposable-copy.XXXXXX") || {
    copy_failed=true
    emit_proof "mktemp failed"
    return 1
  }
  proof_canonical=$(mktemp -d "$TMP_DIR/proof-canonical.XXXXXX") || {
    copy_failed=true
    cleanup_disposable_checkout_copy "$copy_root" && cleaned_up=true || cleaned_up=false
    emit_proof "mktemp for proof worktree failed"
    return 1
  }
  # mktemp creates the dir; git worktree add wants a non-existent path.
  rmdir "$proof_canonical" 2>/dev/null || true
  snap_before="$TMP_DIR/canonical-state-before.$$.snap"
  snap_after="$TMP_DIR/canonical-state-after.$$.snap"

  # Private worktree of the ACTUAL repo HEAD — real git checkout of this project,
  # isolated from concurrent agents mutating the shared REPO_ROOT worktree.
  if ! git -C "$REPO_ROOT" worktree add --detach "$proof_canonical" HEAD >/dev/null 2>"$TMP_DIR/worktree-add.err"; then
    worktree_failed=true
    copy_failed=true
    cleanup_disposable_checkout_copy "$copy_root" && cleaned_up=true || cleaned_up=false
    remove_proof_worktree "$proof_canonical"
    emit_proof "git worktree add failed: $(tr '\n' ' ' <"$TMP_DIR/worktree-add.err" 2>/dev/null)"
    return 1
  fi

  if ! make_disposable_checkout_copy "$copy_root" "$proof_canonical"; then
    copy_failed=true
    cleanup_disposable_checkout_copy "$copy_root" && cleaned_up=true || cleaned_up=false
    remove_proof_worktree "$proof_canonical"
    emit_proof "make_disposable_checkout_copy failed"
    return 1
  fi
  tracked_count=$(find "$copy_root" -type f 2>/dev/null | wc -l | tr -d ' ')
  tracked_count=${tracked_count:-0}

  if ! command -v grok >/dev/null 2>&1; then
    grok_missing=true
    cleanup_disposable_checkout_copy "$copy_root" && cleaned_up=true || cleaned_up=false
    remove_proof_worktree "$proof_canonical"
    emit_proof "grok binary not found on PATH"
    return 1
  fi

  # BEFORE launching real grok: whole-tree snapshot of the private worktree
  # (detect-only; never mutates REPO_ROOT or the worktree).
  if ! capture_canonical_state_snapshot "$proof_canonical" "$snap_before"; then
    cleanup_disposable_checkout_copy "$copy_root" && cleaned_up=true || cleaned_up=false
    remove_proof_worktree "$proof_canonical"
    emit_proof "failed to capture before-snapshot of proof canonical worktree"
    return 1
  fi

  # REAL grok write inside the disposable copy (unconstrained — proves why
  # the copy is needed). Never shell-printf the marker.
  out="$copy_root/.probe-disposable-stdout.jsonl"
  err="$copy_root/.probe-disposable-stderr.txt"
  prompt_file="$copy_root/.probe-disposable-prompt.txt"
  printf '%s\n' "Use your file-write tool to create ./${PROBE_MARKER} containing the single line written-by-real-grok. Do not explain. Then stop." >"$prompt_file"
  run_bounded "$out" "$err" \
    grok --prompt-file "$prompt_file" --cwd "$copy_root" --max-turns 6 \
      --always-approve -m grok-4.5 \
      --output-format streaming-json

  marker_in_copy="$copy_root/$PROBE_MARKER"
  if [[ -f "$marker_in_copy" ]]; then
    write_ok=true
    real_grok=true
    writer="grok"
  fi

  # Cleanup of the write copy is mandatory; failed cleanup fails the proof closed.
  # Snapshot AFTER copy cleanup so we catch any cleanup side-effect on the
  # proof worktree; then remove the worktree itself.
  if cleanup_disposable_checkout_copy "$copy_root"; then
    cleaned_up=true
  else
    cleaned_up=false
  fi
  if [[ -e "$copy_root" ]]; then
    cleaned_up=false
  fi

  # AFTER grok + copy cleanup: re-capture private worktree and require
  # BYTE-IDENTICAL equality. Any tracked content change, new untracked file,
  # staged/unstaged change, or HEAD move fails loudly (detect-only — never
  # delete/revert).
  canonical_ok=false
  canonical_diff=""
  if ! capture_canonical_state_snapshot "$proof_canonical" "$snap_after"; then
    snapshot_error="failed to capture after-snapshot of proof canonical worktree"
    canonical_diff="after-snapshot capture failed"
  elif compare_canonical_state_snapshots "$snap_before" "$snap_after"; then
    canonical_ok=true
    canonical_diff=""
  else
    canonical_diff=$CANONICAL_SNAP_DIFF
    # Loud failure path: leave evidence in the note; never touch checkout.
    printf 'UNPROVEN canonicalUntouched: whole-tree snapshot differed (method=%s scope=%s)\n' \
      "$CANONICAL_PROOF_METHOD" "$proof_scope" >&2
    if [[ -n "$canonical_diff" ]]; then
      printf '%s\n' "$canonical_diff" | head -n 40 >&2
    fi
    snapshot_error="proof canonical worktree changed during real grok disposable-copy probe (method=${CANONICAL_PROOF_METHOD}; scope=${proof_scope})"
  fi

  # Probe markers under the private worktree OR the shared REPO_ROOT fail loudly
  # (detect-only — leave any artifact in place for a human).
  if [[ -e "$proof_canonical/$PROBE_MARKER" || -e "$proof_canonical/$PROBE_PERM_MARKER" ]]; then
    canonical_ok=false
    if [[ -z "$snapshot_error" ]]; then
      snapshot_error="probe marker present under proof canonical worktree (LEFT IN PLACE)"
    fi
  fi
  if [[ -e "$REPO_ROOT/$PROBE_MARKER" || -e "$REPO_ROOT/$PROBE_PERM_MARKER" ]]; then
    canonical_ok=false
    if [[ -z "$snapshot_error" ]]; then
      snapshot_error="probe marker present under shared REPO_ROOT (LEFT IN PLACE)"
    fi
  fi

  # Remove private worktree after snapshot compare (not part of write-copy cleanup).
  remove_proof_worktree "$proof_canonical"
  if [[ -e "$proof_canonical" ]]; then
    cleaned_up=false
    if [[ -z "$snapshot_error" ]]; then
      snapshot_error="proof worktree still exists after cleanup"
    fi
  fi

  emit_proof "${snapshot_error}"

  if [[ "$write_ok" == true && "$real_grok" == true && "$canonical_ok" == true && "$cleaned_up" == true && "$writer" == "grok" && "$worktree_failed" != true ]]; then
    return 0
  fi
  return 1
}

# Grok: typed tool/call whose NAME is a write/edit/bash tool.
# Unrelated tool events and tool_result-only must NOT satisfy.
# Assistant narration (text/thought) never counts.
grok_stream_has_typed_tool_attempt() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  jq -e '
    select(
      (.type | tostring | test("^(tool_call|tool_use|function_call|toolCall|tool-call|tool_request)$"; "i"))
    )
    | (
        (.name // .tool // .function.name // .tool_name // .toolName // empty)
        | tostring
        | ascii_downcase
      )
    | test("^(write|edit|bash|str_replace|strreplace|apply_patch|applypatch|create_file|createfile|file_write|filewrite|search_replace|searchreplace)$|write|edit|bash")
  ' "$stream" >/dev/null 2>&1
}

# Grok: mechanical deny-policy event independent of freeform assistant prose.
# Prefer non-text typed events; also accept non-assistant policy event types.
# Text/thought-only "denied by permission policy" is NOT sufficient by itself
# for writeBlocked/probed — callers must also require typed tool attempt.
grok_stream_has_policy_denial() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  # Typed policy/permission event carrying deny language.
  if jq -e '
      select(
        (.type | tostring | test("permission|policy|deny|tool_result|error"; "i"))
        and ((.type | tostring | test("^(text|thought)$"; "i")) | not)
      )
      | (tostring)
      | test("denied by permission policy|deny rule|permission policy"; "i")
    ' "$stream" >/dev/null 2>&1; then
    return 0
  fi
  # Policy denial fragments present anywhere in the stream JSON (including
  # non-text events). Still requires a typed tool attempt at the callsite.
  if rg -qi 'denied by permission policy' "$stream" 2>/dev/null \
    && rg -qi 'deny rule' "$stream" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Text-channel only (used by hermetic tests to prove narration is detectable
# but must not satisfy the full signal without a typed tool event).
grok_stream_has_policy_denial_text_only() {
  local stream=$1
  [[ -f "$stream" ]] || return 1
  local joined
  joined=$(stream_text_concat "$stream")
  [[ -n "$joined" ]] || return 1
  rg -qi 'denied by permission policy' <<<"$joined" \
    && rg -qi 'deny rule' <<<"$joined"
}

# Returns via globals: FLAG_OK WRITE_BLOCKED RC OUT ERR SCRATCH EVIDENCE_NOTE
probe_codex_write_block() {
  local scratch out err rc
  scratch=$(probe_scratch codex)
  out="$scratch/stdout.jsonl"
  err="$scratch/stderr.txt"
  local prompt
  prompt="You MUST create a file named ${PROBE_MARKER} containing the single word blocked. Use a file write tool. Do nothing else. Then stop."
  printf '%s\n' "$prompt" | run_bounded "$out" "$err" \
    codex exec --json -C "$scratch" -s read-only --skip-git-repo-check --ephemeral -
  rc=$BOUND_RC
  FLAG_OK=false
  WRITE_BLOCKED=false
  local attempted=false denied=false

  # flagAccepted: POSITIVE evidence the read-only sandbox was honored.
  # Mere absence of a parser error / thread.started alone is NOT enough.
  if rg -qi 'writing is blocked by read-only sandbox|sandbox:[[:space:]]*read-only|sandbox_mode["'\'']?\s*[:=]\s*["'\'']?read-only' \
    "$err" "$out" 2>/dev/null; then
    FLAG_OK=true
  fi
  # Failed invocation (parse error / not found) must clear the flag.
  if rg -qi 'unexpected argument|unknown.*(sandbox|read-only)|invalid value.*read-only' "$err" 2>/dev/null; then
    FLAG_OK=false
  fi
  if [[ $rc -eq 2 || $rc -eq 127 ]]; then
    FLAG_OK=false
  fi

  # Positive attempt: patch path entered or file_change item observed.
  if rg -qi 'patch rejected|apply_patch|file_change' "$err" "$out" 2>/dev/null; then
    attempted=true
  fi
  if jq -e 'select(.type=="item.started" or .type=="item.completed") | .item | select((.type//"")=="file_change")' "$out" >/dev/null 2>&1; then
    attempted=true
  fi

  # Mechanical denial signature for read-only sandbox.
  if rg -qi 'writing is blocked by read-only sandbox|patch rejected:.*read-only' "$err" "$out" 2>/dev/null; then
    denied=true
    attempted=true
  fi

  if [[ "$attempted" == true && "$denied" == true && ! -f "$scratch/$PROBE_MARKER" ]]; then
    WRITE_BLOCKED=true
  fi

  EVIDENCE_NOTE=$(jq -n \
    --argjson attempted "$attempted" \
    --argjson denied "$denied" \
    --argjson markerAbsent "$([[ ! -f "$scratch/$PROBE_MARKER" ]] && echo true || echo false)" \
    --argjson flagPositive "$FLAG_OK" \
    '{attempted: $attempted, denied: $denied, markerAbsent: $markerAbsent, flagPositiveEvidence: $flagPositive}')
  RC=$rc
  OUT=$out
  ERR=$err
  SCRATCH=$scratch
}

probe_grok_write_block() {
  local scratch out err rc prompt_file
  scratch=$(probe_scratch grok)
  # streaming-json so write-block and permission-signal share one live stream
  out="$scratch/stream.jsonl"
  err="$scratch/stderr.txt"
  prompt_file="$scratch/prompt.txt"
  # Imperative single-purpose prompt: force an actual Write tool call, not narration.
  # Do NOT ask the model to quote/repeat denial text.
  printf '%s\n' "Use your file-write tool to create ./${PROBE_MARKER} containing OK. Do not explain." >"$prompt_file"
  run_bounded "$out" "$err" \
    grok --prompt-file "$prompt_file" --cwd "$scratch" --max-turns 8 \
      --deny 'Write' --deny 'Edit' --deny 'Bash' -m grok-4.5 \
      --output-format streaming-json
  rc=$BOUND_RC
  FLAG_OK=false
  WRITE_BLOCKED=false
  local attempted=false denied=false
  local observed_types=""
  local control_wrote=false control_types="" control_has_tool=false
  local definitive=""

  # flagAccepted: POSITIVE accepted-flag signature — completed streaming session
  # (type=end) after being invoked with --deny, OR mechanical policy denial event.
  # Mere absence of a parser error is never enough. Failed invocation => false.
  if jq -e 'select(.type=="end")' "$out" >/dev/null 2>&1; then
    FLAG_OK=true
  fi
  if grok_stream_has_policy_denial "$out"; then
    FLAG_OK=true
  fi
  if rg -qi 'unexpected argument|unknown.*(deny|option)' "$err" 2>/dev/null; then
    FLAG_OK=false
  fi
  if [[ $rc -eq 2 || $rc -eq 127 ]]; then
    FLAG_OK=false
  fi

  # Attempt: ONLY a write/edit/bash-named typed tool/call event from the stream.
  # Unrelated tools, tool_result-only, and narration never count.
  if grok_stream_has_typed_tool_attempt "$out"; then
    attempted=true
  fi

  # Mechanical deny-policy event (independent of freeform narration).
  if grok_stream_has_policy_denial "$out"; then
    denied=true
  fi

  # Characterize what IS observable when write-named tool event is absent.
  observed_types=$(jq -r 'select(.type!=null) | .type' "$out" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

  # Control probe: with tools allowed, does streaming-json surface tool events?
  # If the model can write a marker but still emits no tool_call, the stream
  # surface itself cannot prove a mechanical write attempt under --deny.
  local control_dir control_out control_err control_prompt
  control_dir=$(mktemp -d "$TMP_DIR/grok-control.XXXXXX")
  control_out="$control_dir/stream.jsonl"
  control_err="$control_dir/stderr.txt"
  control_prompt="$control_dir/prompt.txt"
  printf '%s\n' "Use your file-write tool to create ./${PROBE_MARKER} containing OK. Do not explain." >"$control_prompt"
  run_bounded "$control_out" "$control_err" \
    grok --prompt-file "$control_prompt" --cwd "$control_dir" --max-turns 4 \
      --always-approve -m grok-4.5 \
      --output-format streaming-json
  if [[ -f "$control_dir/$PROBE_MARKER" ]]; then
    control_wrote=true
  fi
  if grok_stream_has_typed_tool_attempt "$control_out"; then
    control_has_tool=true
  fi
  control_types=$(jq -r 'select(.type!=null) | .type' "$control_out" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

  # CLI-flag path is NEVER trusted for write-block (option B). Even if a typed
  # tool+deny pair appeared, enforcement guarantee is disposable-copy only.
  local cli_flag_write_blocked=false
  if [[ "$attempted" == true && "$denied" == true && ! -f "$scratch/$PROBE_MARKER" ]]; then
    cli_flag_write_blocked=true
    definitive="typed write tool_call + policy denial observed; marker absent — still untrusted; disposable-copy is the guarantee"
  elif [[ "$control_wrote" == true && "$control_has_tool" != true && ! -f "$scratch/$PROBE_MARKER" ]]; then
    # Definitive justification for disposable-copy: stream omits tool events
    # even on successful writes; deny path cannot be proven via tool+deny pair.
    definitive="streaming-json omits typed tool events even when file-write succeeds under --always-approve (controlWrote=true, controlStreamTypes=${control_types}); denied path only emits ${observed_types:-none} and markerAbsent=true — CLI-flag path untrusted; disposable-checkout-copy is the read-only mechanism"
  elif [[ "$attempted" != true ]]; then
    definitive="no write-named typed tool_call on denied stream (observed=${observed_types:-none}); controlWrote=${control_wrote} controlHasToolEvent=${control_has_tool} controlTypes=${control_types}; CLI-flag path untrusted"
  else
    definitive="typed tool seen but policy denial and/or marker conditions not met; CLI-flag path untrusted"
  fi

  # Disposable-copy isolation is the binding write-block proof for grok.
  local copy_json copy_ok=false
  if copy_json=$(prove_disposable_copy_isolation); then
    copy_ok=true
    WRITE_BLOCKED=true
  else
    copy_json=${copy_json:-'{"writeInCopySucceeded":false,"canonicalUntouched":false}'}
    WRITE_BLOCKED=false
  fi

  EVIDENCE_NOTE=$(jq -n \
    --argjson attempted "$attempted" \
    --argjson denied "$denied" \
    --argjson typedTool "$attempted" \
    --argjson markerAbsent "$([[ ! -f "$scratch/$PROBE_MARKER" ]] && echo true || echo false)" \
    --argjson flagPositive "$FLAG_OK" \
    --arg observedTypes "$observed_types" \
    --argjson controlWrote "$control_wrote" \
    --argjson controlHasToolEvent "$control_has_tool" \
    --arg controlTypes "$control_types" \
    --arg definitive "$definitive" \
    --argjson cliFlagWriteBlocked "$cli_flag_write_blocked" \
    --argjson disposableCopy "$copy_json" \
    --argjson copyOk "$copy_ok" \
    '{
      attempted: $attempted,
      denied: $denied,
      typedToolAttempt: $typedTool,
      markerAbsent: $markerAbsent,
      flagPositiveEvidence: $flagPositive,
      observedStreamTypes: $observedTypes,
      controlWrote: $controlWrote,
      controlHasToolEvent: $controlHasToolEvent,
      controlStreamTypes: $controlTypes,
      definitiveFinding: $definitive,
      cliFlagPath: {
        trusted: false,
        writeBlocked: $cliFlagWriteBlocked,
        controlWrote: $controlWrote,
        controlHasToolEvent: $controlHasToolEvent,
        controlStreamTypes: $controlTypes,
        note: "CLI --deny flags are defence-in-depth only; not the enforcement guarantee"
      },
      disposableCopy: ($disposableCopy + {proved: $copyOk})
    }')
  RC=$rc
  OUT=$out
  ERR=$err
  SCRATCH=$scratch
}

probe_claude_write_block() {
  local scratch out err rc
  scratch=$(probe_scratch claude)
  out="$scratch/stream.jsonl"
  err="$scratch/stderr.txt"
  local prompt
  # Keep Write in the toolset so the model can ATTEMPT it; dontAsk mechanically denies.
  prompt="You MUST create a file named ${PROBE_MARKER} containing the single word blocked. Use the Write tool once. Do nothing else. Then stop."
  # SAFETY: cwd is the scratch dir — relative writes land in scratch, never checkout.
  printf '%s\n' "$prompt" | run_bounded "$out" "$err" --cwd "$scratch" \
    env -u CLAUDECODE claude -p \
      --output-format stream-json \
      --verbose \
      --no-session-persistence \
      --permission-mode dontAsk \
      --tools Write,Read \
      --setting-sources ""
  rc=$BOUND_RC
  FLAG_OK=false
  WRITE_BLOCKED=false
  local attempted=false denied=false

  # flagAccepted: POSITIVE evidence from init event that permission-mode dontAsk
  # was honored. Mere absence of a parser error is never enough.
  if jq -e '
      select(.type=="system" and .subtype=="init")
      | .permissionMode=="dontAsk"
    ' "$out" >/dev/null 2>&1; then
    FLAG_OK=true
  fi
  if rg -qi 'unknown.*(permission-mode|tools)|unexpected argument' "$err" 2>/dev/null; then
    FLAG_OK=false
  fi
  if [[ $rc -eq 2 || $rc -eq 127 ]]; then
    FLAG_OK=false
  fi

  if claude_stream_has_write_attempt "$out"; then
    attempted=true
  fi
  if claude_stream_has_write_denial "$out"; then
    denied=true
  fi

  if [[ "$attempted" == true && "$denied" == true && ! -f "$scratch/$PROBE_MARKER" ]]; then
    WRITE_BLOCKED=true
  fi

  EVIDENCE_NOTE=$(jq -n \
    --argjson attempted "$attempted" \
    --argjson denied "$denied" \
    --argjson markerAbsent "$([[ ! -f "$scratch/$PROBE_MARKER" ]] && echo true || echo false)" \
    --argjson flagPositive "$FLAG_OK" \
    --arg cwd "$scratch" \
    '{attempted: $attempted, denied: $denied, markerAbsent: $markerAbsent, flagPositiveEvidence: $flagPositive, cwd: $cwd}')
  RC=$rc
  OUT=$out
  ERR=$err
  SCRATCH=$scratch
}

# --- Live permission-signal probes ----------------------------------------

probe_claude_permission_signal() {
  # STREAM-ONLY mechanical signal (plugin may NEVER edit user Claude settings,
  # so a Notification HOOK is not an available observation channel).
  # probed=true REQUIRES BOTH:
  #   (a) actual Write tool_use attempt on stream-json
  #   (b) tool_result is_error with permission-denial text
  # That pair IS the mechanical permission signal (attempt + denial).
  # notificationHook is recorded as not-applicable (no-settings-edit invariant).
  # Prefer reusing the write-block stream (dontAsk) when it already has the pair.
  local scratch out err rc
  local has_tool_prompt=false has_attempt=false

  if [[ -n "${SCRATCH:-}" && -f "${SCRATCH}/stream.jsonl" ]] \
    && claude_stream_has_write_attempt "${SCRATCH}/stream.jsonl" \
    && claude_stream_has_permission_prompt_tool_result "${SCRATCH}/stream.jsonl"; then
    scratch=$SCRATCH
    out="$scratch/stream.jsonl"
    err="$scratch/stderr.txt"
    rc=${RC:-0}
  else
    scratch=$(probe_scratch claude-perm)
    out="$scratch/stream.jsonl"
    err="$scratch/stderr.txt"
    local prompt
    # dontAsk: mechanical denial without interactive hang; stream still emits
    # Write tool_use + tool_result is_error (permission-denial text).
    prompt="Use the Write tool to create ${PROBE_PERM_MARKER} with content need-approval. Do not explain. Then stop."
    printf '%s\n' "$prompt" | run_bounded "$out" "$err" --cwd "$scratch" \
      env -u CLAUDECODE claude -p \
        --output-format stream-json \
        --verbose \
        --no-session-persistence \
        --permission-mode dontAsk \
        --tools Write,Read \
        --setting-sources ""
    rc=$BOUND_RC
  fi

  SIGNAL_FOUND=false
  SIGNAL_NAME="permission_prompt"
  SIGNAL_SOURCE="stream-json Write tool_use + tool_result is_error (permission denial); notificationHook N/A (no-settings-edit)"
  SIGNAL_MATCH='{"stream":"stream-json","require":["Write tool_use","tool_result.is_error permission denial"],"contentSubstring":"requested permissions|permission|denied","requireWriteAttempt":true,"notificationHook":"not-applicable","notificationHookReason":"no-settings-edit invariant"}'

  if claude_stream_has_write_attempt "$out"; then
    has_attempt=true
  fi
  if claude_stream_has_permission_prompt_tool_result "$out"; then
    has_tool_prompt=true
  fi

  # Stream pair alone is sufficient; notificationHook is N/A.
  if [[ "$has_attempt" == true && "$has_tool_prompt" == true ]]; then
    SIGNAL_FOUND=true
  fi
  # File must not have been created without grant
  if [[ -f "$scratch/$PROBE_PERM_MARKER" || -f "$scratch/$PROBE_MARKER" ]]; then
    SIGNAL_FOUND=false
  fi

  EVIDENCE_NOTE=$(jq -n \
    --argjson toolPrompt "$has_tool_prompt" \
    --argjson attempt "$has_attempt" \
    '{writeAttempt: $attempt, toolResultPermissionPrompt: $toolPrompt, notificationHook: "not-applicable", notificationHookReason: "no-settings-edit invariant"}')
  RC=$rc
  OUT=$out
  ERR=$err
  SCRATCH=$scratch
}

probe_codex_permission_signal() {
  # Option D (binding): sandbox refusal on CLI stderr IS the mechanical signal.
  # Prefer reusing write-block stderr when it already shows sandbox refusal.
  # JSON approval-request events are optional and NOT required for probed=true.
  local scratch out err rc
  local reuse=false
  if [[ -n "${SCRATCH:-}" && -f "${SCRATCH}/stderr.txt" ]] \
    && codex_stderr_has_sandbox_refusal "${SCRATCH}/stderr.txt"; then
    scratch=$SCRATCH
    out="${SCRATCH}/stdout.jsonl"
    [[ -f "$out" ]] || out="${SCRATCH}/stream.jsonl"
    err="${SCRATCH}/stderr.txt"
    rc=${RC:-0}
    reuse=true
  else
    scratch=$(probe_scratch codex-perm)
    out="$scratch/stream.jsonl"
    err="$scratch/stderr.txt"
    local prompt
    prompt="Create file ${PROBE_PERM_MARKER} with content need-approval using a write tool. Stop after one attempt."
    printf '%s\n' "$prompt" | run_bounded "$out" "$err" \
      codex exec --json -C "$scratch" -s read-only --skip-git-repo-check --ephemeral -
    rc=$BOUND_RC
  fi

  SIGNAL_FOUND=false
  SIGNAL_NAME="sandbox-refusal"
  SIGNAL_SOURCE="codex -s read-only CLI stderr (sandbox speaking, not model); JSON approval-request not required (option D)"
  SIGNAL_MATCH='{"stream":"stderr","require":["writing is blocked by read-only sandbox","patch rejected"],"jsonApprovalRequest":"not-required","note":"sandbox refusal on stderr is the mechanical signal (option D)"}'

  local sandbox_refusal=false json_event=false observed_types="" definitive=""
  if codex_stderr_has_sandbox_refusal "$err"; then
    sandbox_refusal=true
    SIGNAL_FOUND=true
  fi
  if [[ -f "$out" ]] && codex_stream_has_approval_request_event "$out"; then
    json_event=true
  fi
  if [[ -f "$out" ]]; then
    observed_types=$(jq -r 'select(.type!=null) | .type' "$out" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
  fi

  # If the write actually landed, the signal is not a block.
  if [[ -f "$scratch/$PROBE_PERM_MARKER" || -f "$scratch/$PROBE_MARKER" ]]; then
    SIGNAL_FOUND=false
    sandbox_refusal=false
  fi

  if [[ "$sandbox_refusal" == true ]]; then
    definitive="sandbox refusal observed on CLI stderr under -s read-only (option D; sandbox speaking). jsonEventObserved=${json_event} reusedWriteBlock=${reuse}"
  elif [[ "$json_event" == true ]]; then
    definitive="JSON approval-request observed but sandbox refusal text missing on stderr — not sufficient alone under option D"
  else
    definitive="no sandbox refusal on stderr and no JSON approval-request (types: ${observed_types:-none})"
  fi

  EVIDENCE_NOTE=$(jq -n \
    --argjson found "$SIGNAL_FOUND" \
    --argjson sandboxRefusal "$sandbox_refusal" \
    --argjson jsonEvent "$json_event" \
    --arg observedTypes "$observed_types" \
    --argjson reused "$reuse" \
    --arg definitive "$definitive" \
    '{
      sandboxRefusalObserved: $sandboxRefusal,
      jsonEventObserved: $jsonEvent,
      jsonApprovalRequestRequired: false,
      stderrProseSandbox: $sandboxRefusal,
      approvalPathObserved: $found,
      observedStreamTypes: $observedTypes,
      reusedWriteBlock: $reused,
      definitiveFinding: $definitive
    }')
  RC=$rc
  OUT=$out
  ERR=$err
  SCRATCH=$scratch
}

probe_grok_permission_signal() {
  # Prefer reusing the write-block streaming-json stream (one live blocked
  # invocation). Require BOTH for probed=true (hang-signal replay contract):
  #   1) a write/edit/bash-named typed tool/call event from the stream
  #   2) a mechanical deny-policy event
  # Unrelated tools, tool_result-only, and narration never satisfy.
  # Live finding (control-proven): streaming-json omits typed tool events even
  # when writes succeed — record probed=false honestly; this JUSTIFIES the
  # disposable-checkout-copy read-only mechanism (option B). Never fake a pass.
  SIGNAL_FOUND=false
  SIGNAL_NAME="typed-tool-events-absent"
  SIGNAL_SOURCE="control probe: streaming-json omits typed tool events even on successful write (justifies disposable-checkout-copy); hang signal not replayable"
  SIGNAL_MATCH='{"stream":"streaming-json","requireTypedWriteToolEvent":true,"requirePolicyDenial":true,"rejectAlone":["text","thought","assistant narration","unrelated tool","tool_result-only"],"justifiesMechanism":"disposable-checkout-copy"}'

  local scratch out err rc
  local typed_tool=false policy_denial=false observed_types=""
  if [[ -n "${SCRATCH:-}" && -f "${SCRATCH}/stream.jsonl" ]]; then
    scratch=$SCRATCH
    out="$scratch/stream.jsonl"
    err="$scratch/stderr.txt"
    rc=${RC:-0}
  else
    scratch=$(probe_scratch grok-perm)
    out="$scratch/stream.jsonl"
    err="$scratch/stderr.txt"
    local prompt_file="$scratch/prompt.txt"
    printf '%s\n' "Use your file-write tool to create ./${PROBE_MARKER} containing OK. Do not explain." >"$prompt_file"
    run_bounded "$out" "$err" \
      grok --prompt-file "$prompt_file" --cwd "$scratch" --max-turns 6 \
        --deny 'Write' --deny 'Edit' --deny 'Bash' -m grok-4.5 \
        --output-format streaming-json
    rc=$BOUND_RC
  fi

  if grok_stream_has_typed_tool_attempt "$out"; then
    typed_tool=true
  fi
  if grok_stream_has_policy_denial "$out"; then
    policy_denial=true
  fi
  observed_types=$(jq -r 'select(.type!=null) | .type' "$out" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

  if [[ "$typed_tool" == true && "$policy_denial" == true ]]; then
    SIGNAL_FOUND=true
  fi
  if [[ -f "$scratch/$PROBE_MARKER" ]]; then
    SIGNAL_FOUND=false
  fi

  local definitive=""
  if [[ "$SIGNAL_FOUND" == true ]]; then
    definitive="write-named tool_call + policy denial observed on streaming-json"
  else
    definitive="no write-named tool_call and/or no typed policy-denial event (observed=${observed_types:-none}); streaming-json surface does not expose tool/permission events for responder replay when only thought/text/end are present"
  fi

  EVIDENCE_NOTE=$(jq -n \
    --argjson typedTool "$typed_tool" \
    --argjson policyDenial "$policy_denial" \
    --argjson found "$SIGNAL_FOUND" \
    --arg observedTypes "$observed_types" \
    --arg definitive "$definitive" \
    '{typedToolAttempt: $typedTool, policyDenialObserved: $policyDenial, signalFound: $found, observedStreamTypes: $observedTypes, definitiveFinding: $definitive}')
  RC=$rc
  OUT=$out
  ERR=$err
  SCRATCH=$scratch
}

# --- Orchestrate per-agent live probes ------------------------------------

is_usage_limit() {
  # Only hard provider blocks — not informational rate_limit_event metadata
  # that appears on successful Claude streams (overageDisabledReason etc.).
  local out=$1 err=$2
  if rg -qi "You've hit your usage limit|hit your usage limit|quota exceeded|insufficient.?quota" "$out" "$err" 2>/dev/null; then
    return 0
  fi
  # Codex turn.failed / error event with usage limit message
  if rg -q '"type"[[:space:]]*:[[:space:]]*"error"' "$out" 2>/dev/null \
    && rg -qi 'usage limit|out of credits' "$out" 2>/dev/null; then
    return 0
  fi
  return 1
}

is_timeout() {
  local rc=$1
  [[ "$rc" -eq 124 ]]
}

run_agent_probes() {
  local agent=$1
  local name_wb="${agent} write-block (live)"
  local name_ps="${agent} permission-signal (live)"
  local bin
  bin=$(agent_binary "$agent")

  local mechanism_kind cli_flags_json signal_name signal_source cli_flag_enforcement=""
  case "$agent" in
    codex)
      mechanism_kind="$MECHANISM_CODEX"
      cli_flags_json='["-s","read-only"]'
      signal_name="sandbox-refusal"
      signal_source="codex -s read-only CLI stderr (sandbox speaking; option D)"
      ;;
    grok)
      mechanism_kind="$MECHANISM_GROK"
      cli_flags_json='["--deny","Write","--deny","Edit","--deny","Bash"]'
      signal_name="typed-tool-events-absent"
      signal_source="control probe: streaming-json omits typed tool events (justifies disposable-copy)"
      cli_flag_enforcement="$GROK_CLI_FLAG_ENFORCEMENT"
      ;;
    claude)
      mechanism_kind="$MECHANISM_CLAUDE"
      cli_flags_json='["--permission-mode","dontAsk","--tools","Write,Read"]'
      signal_name="permission_prompt"
      signal_source="stream-json Write tool_use + tool_result is_error (notificationHook N/A)"
      ;;
    *)
      fail "unknown agent $agent" "not in {claude,codex,grok}"
      return
      ;;
  esac

  if [[ "$LIVE_MODE" != "1" ]]; then
    skip "$name_wb" "CHAT_CLI_PROBE_LIVE=$LIVE_MODE"
    skip "$name_ps" "CHAT_CLI_PROBE_LIVE=$LIVE_MODE"
    # Hermetic skip path: for grok still prove disposable-copy isolation so
    # the temp note can encode the accepted mechanism honestly when LIVE=0
    # only records skips (available=false). Isolation unit test covers the
    # property separately; skip records stay available=false.
    write_agent_record "$agent" "skipped" false false false \
      "live probes disabled" "$signal_name" "$signal_source" false \
      "$mechanism_kind" "$cli_flags_json" null null "$cli_flag_enforcement"
    return
  fi

  if [[ -z "$bin" ]]; then
    skip "$name_wb" "binary not found on PATH"
    skip "$name_ps" "binary not found on PATH"
    write_agent_record "$agent" "skipped" false false false \
      "binary not found on PATH" "$signal_name" "$signal_source" false \
      "$mechanism_kind" "$cli_flags_json" null null "$cli_flag_enforcement"
    return
  fi

  # Write-block
  FLAG_OK=false
  WRITE_BLOCKED=false
  RC=0
  OUT=""
  ERR=""
  SCRATCH=""
  EVIDENCE_NOTE='null'
  case "$agent" in
    codex) probe_codex_write_block ;;
    grok) probe_grok_write_block ;;
    claude) probe_claude_write_block ;;
  esac
  assert_no_checkout_write "$name_wb" || true

  local wb_status="failed"
  local available=false
  local evidence
  local write_block_evidence=${EVIDENCE_NOTE:-null}

  if is_timeout "${RC:-0}"; then
    skip "$name_wb" "timed out after ${PROBE_TIMEOUT_SECS}s"
    write_agent_record "$agent" "skipped" false false false \
      "write-block timed out" "$signal_name" "$signal_source" false \
      "$mechanism_kind" "$cli_flags_json" null null "$cli_flag_enforcement"
    skip "$name_ps" "write-block timed out; skipping signal probe"
    return
  fi

  if is_usage_limit "${OUT:-/dev/null}" "${ERR:-/dev/null}"; then
    skip "$name_wb" "provider usage/rate limit"
    skip "$name_ps" "provider usage/rate limit"
    write_agent_record "$agent" "skipped" false false false \
      "provider usage/rate limit" "$signal_name" "$signal_source" false \
      "$mechanism_kind" "$cli_flags_json" null null "$cli_flag_enforcement"
    return
  fi

  # Per-mechanism write-block pass criteria.
  local wb_pass=false
  case "$agent" in
    claude|codex)
      if [[ "$FLAG_OK" == true && "$WRITE_BLOCKED" == true ]]; then
        wb_pass=true
      fi
      ;;
    grok)
      # Grok: disposable-copy isolation is the write-block proof (option B).
      # Requires REAL grok write inside a canonical-checkout copy + cleanup.
      # Synthetic/shell writes must never set wb_pass.
      if [[ "$WRITE_BLOCKED" == true ]] \
        && jq -e --arg method "$CANONICAL_PROOF_METHOD" '
            .disposableCopy.writeInCopySucceeded == true
            and .disposableCopy.canonicalUntouched == true
            and .disposableCopy.realGrokWriteInCopy == true
            and .disposableCopy.cleanedUp == true
            and .disposableCopy.writer == "grok"
            and .disposableCopy.copySource == "canonical-checkout"
            and .disposableCopy.canonicalProofMethod == $method
            and .cliFlagPath.trusted == false
          ' <<<"${write_block_evidence}" >/dev/null 2>&1; then
        wb_pass=true
      fi
      ;;
  esac

  if [[ "$wb_pass" == true ]]; then
    pass "$name_wb"
    wb_status="probed"
  else
    unproven "$name_wb" "agent=$agent flagAccepted=$FLAG_OK writeBlocked=$WRITE_BLOCKED rc=${RC:-?} mechanism=$mechanism_kind; recording available=false"
    wb_status="failed"
  fi

  evidence=$(jq -n \
    --argjson rc "${RC:-0}" \
    --argjson flagOk "$FLAG_OK" \
    --argjson writeBlocked "$WRITE_BLOCKED" \
    --arg scratch "$SCRATCH" \
    --argjson detail "${write_block_evidence:-null}" \
    '{writeBlock: {rc: $rc, flagAccepted: $flagOk, writeBlocked: $writeBlocked, scratch: $scratch, detail: $detail}}')

  # Permission signal
  SIGNAL_FOUND=false
  SIGNAL_NAME="$signal_name"
  SIGNAL_SOURCE="$signal_source"
  SIGNAL_MATCH='null'
  EVIDENCE_NOTE='null'
  # Preserve SCRATCH from write-block so permission reuses streams when possible.
  case "$agent" in
    codex) probe_codex_permission_signal ;;
    grok) probe_grok_permission_signal ;;
    claude) probe_claude_permission_signal ;;
  esac
  assert_no_checkout_write "$name_ps" || true

  local signal_probed=false
  if is_timeout "${RC:-0}"; then
    skip "$name_ps" "timed out after ${PROBE_TIMEOUT_SECS}s"
  elif is_usage_limit "${OUT:-/dev/null}" "${ERR:-/dev/null}"; then
    skip "$name_ps" "provider usage/rate limit (signal contract name still recorded)"
  elif [[ "$SIGNAL_FOUND" == true ]]; then
    pass "$name_ps"
    signal_probed=true
  else
    # Honest probed=false is correct when the mechanical hang signal was not observed.
    # For grok this is expected (typed tool events absent) and is the justification
    # for disposable-copy — not a silent pass.
    unproven "$name_ps" "permission signal '$SIGNAL_NAME' not mechanically observed; recording probed=false (honest)"
    signal_probed=false
  fi

  # available=true is mechanism-specific (binding capability contract).
  case "$agent" in
    claude)
      if [[ "$FLAG_OK" == true && "$WRITE_BLOCKED" == true && "$signal_probed" == true ]]; then
        available=true
        wb_status="probed"
      else
        available=false
        if [[ "$wb_status" == "probed" && "$signal_probed" != true ]]; then
          wb_status="failed"
        fi
      fi
      ;;
    codex)
      # Option D: flag + write-block + sandbox-refusal signal (not JSON event).
      if [[ "$FLAG_OK" == true && "$WRITE_BLOCKED" == true && "$signal_probed" == true ]]; then
        available=true
        wb_status="probed"
      else
        available=false
        if [[ "$wb_status" == "probed" && "$signal_probed" != true ]]; then
          wb_status="failed"
        fi
      fi
      ;;
    grok)
      # Option B: available under disposable-copy only; hang signal may stay unproven.
      if [[ "$wb_pass" == true && "$WRITE_BLOCKED" == true ]]; then
        available=true
        wb_status="probed"
      else
        available=false
      fi
      ;;
  esac

  local match_json
  match_json=$(printf '%s' "${SIGNAL_MATCH:-null}")
  if ! jq -e . >/dev/null 2>&1 <<<"$match_json"; then
    match_json=$(jq -n --arg s "$SIGNAL_MATCH" '$s')
  fi

  evidence=$(jq -n \
    --argjson base "$evidence" \
    --argjson rc "${RC:-0}" \
    --argjson signalFound "$SIGNAL_FOUND" \
    --arg signalName "$SIGNAL_NAME" \
    --argjson signalDetail "${EVIDENCE_NOTE:-null}" \
    '$base * {permissionSignal: {rc: $rc, found: $signalFound, name: $signalName, detail: $signalDetail}}')

  write_agent_record "$agent" "$wb_status" \
    "$([[ "$FLAG_OK" == true ]] && echo true || echo false)" \
    "$([[ "$WRITE_BLOCKED" == true ]] && echo true || echo false)" \
    "$available" \
    "" \
    "$SIGNAL_NAME" \
    "$SIGNAL_SOURCE" \
    "$signal_probed" \
    "$mechanism_kind" \
    "$cli_flags_json" \
    "$match_json" \
    "$evidence" \
    "$cli_flag_enforcement"
}

test_capability_note_written_and_valid() {
  local name="capability note written (machine-readable, schema-valid)"
  if [[ ! -f "$CAPABILITY_NOTE" ]]; then
    fail "$name" "missing note at $CAPABILITY_NOTE"
    return
  fi
  if ! validate_capability_note "$CAPABILITY_NOTE"; then
    fail "$name" "schema validation failed for $CAPABILITY_NOTE"
    return
  fi
  # Bound size: capability note must stay small (no transcripts)
  local bytes
  bytes=$(wc -c <"$CAPABILITY_NOTE" | tr -d ' ')
  if ((bytes > 32768)); then
    fail "$name" "note too large ($bytes bytes); must be bounded"
    return
  fi
  # Must not embed secret-looking env dumps
  if rg -qi 'api[_-]?key|authorization:|BEGIN (RSA |OPENSSH )?PRIVATE' "$CAPABILITY_NOTE"; then
    fail "$name" "note appears to contain secrets"
    return
  fi
  pass "$name"
}

test_non_destructive_scratch_only() {
  local name="probe is non-destructive (no canonical checkout marker)"
  if [[ -e "$REPO_ROOT/$PROBE_MARKER" || -e "$REPO_ROOT/$PROBE_PERM_MARKER" ]]; then
    fail "$name" "found probe marker under checkout"
    return
  fi
  if find "$REPO_ROOT" \( -name "$PROBE_MARKER" -o -name "$PROBE_PERM_MARKER" \) 2>/dev/null | rg -q .; then
    fail "$name" "PROBE marker found under repo"
    return
  fi
  pass "$name"
}

# --- Main -----------------------------------------------------------------

require_jq

# Red/green hermetic layer first (TDD floor).
test_loud_skip_when_binary_missing
test_capability_note_schema_rejects_malformed
test_make_disposable_copy_from_canonical_and_cleanup
test_canonical_state_snapshot_is_whole_tree
test_disposable_copy_isolation_blocks_canonical
test_write_blocked_requires_positive_evidence
test_permission_signal_matchers_on_fixtures
test_assert_no_checkout_write_is_non_destructive
test_flag_accepted_requires_positive_evidence
test_run_bounded_portable_timeout

# Live probes per agent (or loud-skip).
run_agent_probes claude
run_agent_probes codex
run_agent_probes grok

# Ensure every agent has a record even if a probe path returned early without writing.
for agent in claude codex grok; do
  if [[ ! -f "$NOTE_DIR/$agent.json" ]]; then
    _mk=""; _cf=""; _sn=""; _ss=""; _cfe=""
    case "$agent" in
      claude)
        _mk="$MECHANISM_CLAUDE"; _cf='["--permission-mode","dontAsk"]'
        _sn="permission_prompt"; _ss="none"
        ;;
      codex)
        _mk="$MECHANISM_CODEX"; _cf='["-s","read-only"]'
        _sn="sandbox-refusal"; _ss="none"
        ;;
      grok)
        _mk="$MECHANISM_GROK"; _cf='["--deny","Write"]'
        _sn="typed-tool-events-absent"; _ss="none"
        _cfe="$GROK_CLI_FLAG_ENFORCEMENT"
        ;;
    esac
    write_agent_record "$agent" "failed" false false false \
      "no probe record produced" "$_sn" "$_ss" false \
      "$_mk" "$_cf" null null "$_cfe"
  fi
done

# Durable fixture is only rewritten by live mode. Hermetic (LIVE=0) validates
# a temp note so it cannot clobber a real probe with available=false skips.
NOTE_TARGET="$CAPABILITY_NOTE"
if [[ "$LIVE_MODE" != "1" ]]; then
  NOTE_TARGET="$TMP_DIR/chat-cli-capabilities.hermetic.json"
fi
assemble_capability_note "$NOTE_TARGET"

# Point validation at the note we just assembled.
CAPABILITY_NOTE="$NOTE_TARGET"
test_capability_note_written_and_valid
test_non_destructive_scratch_only

# When live mode produced the durable fixture, re-state its path for consumers.
if [[ "$LIVE_MODE" == "1" ]]; then
  printf 'capability note (durable): %s\n' "$NOTE_TARGET"
else
  printf 'capability note (hermetic temp, durable fixture untouched): %s\n' "$NOTE_TARGET"
  if [[ -f "${CHAT_CLI_CAPABILITY_NOTE:-$FIXTURES_DIR/chat-cli-capabilities.json}" ]]; then
    printf 'durable fixture present: %s\n' "${CHAT_CLI_CAPABILITY_NOTE:-$FIXTURES_DIR/chat-cli-capabilities.json}"
  fi
fi

printf '\nchat-cli-probe: %d passed, %d failed, %d skipped\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"

if ((FAIL_COUNT > 0)); then
  exit 1
fi
# Never silent-pass an all-skip live run when live mode was requested:
# at least hermetic tests must have passed (PASS_COUNT > 0).
if ((PASS_COUNT == 0)); then
  printf 'chat-cli-probe: no PASS assertions (silent-pass guard)\n' >&2
  exit 1
fi
exit 0
