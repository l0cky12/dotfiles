#!/usr/bin/env bash
#
# Reload the desktop in place after a config change: Hyprland re-reads its
# config, then Quickshell is stopped and relaunched detached.
#
# Quickshell picks up most QML edits on its own, but a panel that changed
# shape — new files, new singleton properties — needs a fresh process.

set -euo pipefail

program=${0##*/}

note() { printf '%s: %s\n' "$program" "$*"; }
fail() {
  printf '%s: error: %s\n' "$program" "$*" >&2
  exit 1
}

command -v quickshell >/dev/null 2>&1 || fail "quickshell is not installed"

if pgrep -x Hyprland >/dev/null 2>&1; then
  command -v hyprctl >/dev/null 2>&1 || fail "Hyprland is live but hyprctl is unavailable"
  note 'reloading Hyprland'
  hyprctl reload >/dev/null || fail "hyprctl reload failed"
else
  note 'no live Hyprland session; skipping the compositor reload'
fi

if pgrep -x quickshell >/dev/null 2>&1; then
  note 'stopping Quickshell'
  pkill -x quickshell || true

  # Give the instance a moment to unmap its layer surfaces. A survivor
  # would hold the bar's namespace and the relaunched process would sit
  # behind it, so escalate rather than racing.
  for _ in {1..30}; do
    pgrep -x quickshell >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -x quickshell >/dev/null 2>&1; then
    note 'Quickshell did not exit; sending SIGKILL'
    pkill -KILL -x quickshell || true
    sleep 0.2
  fi
fi

note 'starting Quickshell'
quickshell --daemonize || fail "quickshell failed to start"

note 'desktop reloaded'
