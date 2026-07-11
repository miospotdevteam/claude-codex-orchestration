#!/usr/bin/env bash

# Synchronous, fail-open Claude lifecycle bridge. Only closed labels leave this
# process; hook messages, prompts, transcript paths, and environment never do.
set +e
umask 077

main() {
  local payload event notification scope kind root pane supervisor
  payload=$(dd bs=65536 count=1 2>/dev/null) || return 0
  event=$(printf '%s' "$payload" | jq -r 'if (.hook_event_name | type) == "string" then .hook_event_name else empty end' 2>/dev/null) || return 0
  scope=main
  case $event in
    Stop) kind=completed ;;
    SubagentStop) scope=subagent; kind=completed ;;
    StopFailure) kind=failed ;;
    Notification)
      notification=$(printf '%s' "$payload" | jq -r 'if (.notification_type | type) == "string" then .notification_type else empty end' 2>/dev/null) || return 0
      case $notification in permission_prompt|idle_prompt|elicitation_dialog) kind=input-needed ;; *) return 0 ;; esac
      ;;
    *) return 0 ;;
  esac
  [[ -n ${CLAUDE_PLUGIN_ROOT:-} && -n ${CLAUDE_PROJECT_DIR:-} && -n ${TMUX_PANE:-} ]] || return 0
  [[ -d $CLAUDE_PROJECT_DIR ]] || return 0
  if [[ -L $CLAUDE_PROJECT_DIR ]]; then
    root=$(readlink "$CLAUDE_PROJECT_DIR") || return 0
    [[ $root == /* ]] || return 0
  else
    root=$CLAUDE_PROJECT_DIR
  fi
  [[ -d $root ]] || return 0
  pane=$TMUX_PANE
  case $pane in %*[!0-9]*|%|'') return 0 ;; %*) ;; *) return 0 ;; esac
  supervisor=$CLAUDE_PLUGIN_ROOT/scripts/agent-supervisor
  [[ -x $supervisor ]] || return 0
  "$supervisor" enqueue "$root" "$pane" "$scope" "$kind" </dev/null >/dev/null 2>&1 || true
  return 0
}

main "$@" >/dev/null 2>/dev/null
exit 0
