#!/usr/bin/env bash
# auto-monitor-profile.sh -- pick a monitor profile and apply it, idempotently.
#
# Monitors are identified by EDID description ("desc:<make> <model> <serial>"),
# not by connector name: the KVM re-enumerates DisplayPort connectors on every
# switch, so DP-5/DP-7/DP-9 became DP-6/DP-10/DP-12 and will change again.
#
# This script is the *applier*. It is invoked once per settled hotplug by
# hypr-monitor-watch.py, and once at session start from conf/autostart.lua.
# It has no polling loop of its own.
#
#   --profile NAME  apply a named profile instead of auto-detecting one
#   --force         apply even if the live layout already matches
#   --dry-run       read monitor JSON from $SIMULATED_MONITORS or stdin and
#                   print the files that would be installed
#   --verbose       also mirror the log to stderr
#
# Logs to the journal:  journalctl -t hypr-monitor -f
set -uo pipefail

CONFIG_DIR="${HYPR_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
PROFILE_DIR="${HYPR_PROFILE_DIR:-$CONFIG_DIR/monitor_profiles}"
MONITORS_FILE="$CONFIG_DIR/monitors.lua"
WORKSPACES_FILE="$CONFIG_DIR/workspaces.lua"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="$RUNTIME/hypr-monitor-profile.lock"
HYPRCTL="${HYPRCTL:-hyprctl}"

# The built-in panel follows the lid (see scripts/lid-switch.sh): while the
# lid is closed the panel's desired state is "disabled" no matter what the
# profile row says, so a hotplug apply never re-lights a closed laptop.
INTERNAL_OUTPUT="${HYPR_INTERNAL_OUTPUT:-eDP-1}"
LID_STATE_GLOB="${HYPR_LID_STATE:-/proc/acpi/button/lid/*/state}"

# How long to wait for the display stack to finish enumerating after a hotplug.
SETTLE_TIMEOUT="${HYPR_SETTLE_TIMEOUT:-10}"
SETTLE_INTERVAL="${HYPR_SETTLE_INTERVAL:-0.4}"
# Samples the monitor set must stay identical for before we call it settled.
SETTLE_STABLE="${HYPR_SETTLE_STABLE:-2}"

FORCE=0
DRY_RUN=0
VERBOSE=0
SKIP_SETTLE="${HYPR_SKIP_SETTLE:-0}"
PROFILE=""

while (($#)); do
  case "$1" in
    --profile)
      (($# >= 2)) || { printf '%s\n' '--profile requires a name' >&2; exit 2; }
      PROFILE="$2"
      shift
      ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1; VERBOSE=1 ;;
    --verbose) VERBOSE=1 ;;
    --no-settle) SKIP_SETTLE=1 ;;
    *)
      printf 'usage: %s [--profile NAME] [--force] [--dry-run] [--verbose] [--no-settle]\n' \
        "$(basename "$0")" >&2
      exit 2
      ;;
  esac
  shift
done

[[ -z "$PROFILE" || "$PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]] || {
  printf 'invalid profile name: %s\n' "$PROFILE" >&2
  exit 2
}

log() {
  command -v logger >/dev/null 2>&1 && logger -t hypr-monitor -- "$*" 2>/dev/null
  [[ "$VERBOSE" == 1 ]] && printf '%s\n' "$*" >&2
  return 0
}

die() { log "FATAL: $*"; exit 1; }

lid_closed() {
  local f
  # Intentionally unquoted: the default is a glob over ACPI lid devices.
  for f in $LID_STATE_GLOB; do
    [[ -r "$f" ]] && grep -q closed "$f" 2>/dev/null && return 0
  done
  return 1
}

# ── The monitors that define the KVM setup, by EDID description ─────────────
# Keep in sync with monitor_profiles/kvm.monitors.lua (capture-monitor-profile.sh
# regenerates both from the live session).
KVM_DESCS=(
  "Dell Inc. DELL P2214H KW14V42L3ACB"
  "Dell Inc. DELL P2722H CTCS1M3"
  "Dell Inc. DELL P2725H 21MG834"
)

# ── Live state ──────────────────────────────────────────────────────────────
LIVE_JSON=""

# Per-refresh cache: one jq pass turns the monitor array into a single TSV
# stream (name \t description \t enabled \t actual-state) plus sorted
# desc/name lists, so the per-key lookups below are awk scans instead of a
# jq spawn each. Contents are only ever read after a successful refresh.
LIVE_CACHE=""
LIVE_DESCS=""
LIVE_NAMES=""

compute_live_cache() {
  LIVE_CACHE="$(jq -r '.[] | [
    .name,
    (.description // ""),
    (if .disabled == true then 0 else 1 end),
    ((.width|tostring) + "x" + (.height|tostring) + "@" +
     ((.refreshRate * 100 | round / 100)|tostring) + "|" +
     (.x|tostring) + "x" + (.y|tostring) + "|" +
     ((.scale * 100 | round / 100)|tostring) + "|" +
     (.transform|tostring))
  ] | @tsv' <<<"$LIVE_JSON")"
  LIVE_DESCS="$(awk -F'\t' '$2 != "" { print $2 }' <<<"$LIVE_CACHE" | sort)"
  LIVE_NAMES="$(awk -F'\t' '$1 != "" { print $1 }' <<<"$LIVE_CACHE" | sort)"
}

# `monitors all` rather than `monitors`: the latter omits disabled outputs, so
# a lid-closed eDP-1 reads as unplugged. Unplugged connectors are absent from
# both lists, which is what the presence checks below actually want to know.
refresh_live() {
  LIVE_JSON="$("$HYPRCTL" -j monitors all 2>/dev/null)"
  # A malformed payload must not be mistaken for "no monitors".
  if [[ -z "$LIVE_JSON" ]] || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$LIVE_JSON"; then
    # `all` is the correct query; losing it entirely is worse than losing sight
    # of disabled outputs, so fall back rather than give up on the layout.
    log 'warning: "hyprctl -j monitors all" unusable, falling back to "monitors"'
    LIVE_JSON="$("$HYPRCTL" -j monitors 2>/dev/null)" || { LIVE_CACHE=""; LIVE_DESCS=""; LIVE_NAMES=""; return 1; }
    [[ -n "$LIVE_JSON" ]] || { LIVE_CACHE=""; LIVE_DESCS=""; LIVE_NAMES=""; return 1; }
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$LIVE_JSON" || { LIVE_CACHE=""; LIVE_DESCS=""; LIVE_NAMES=""; return 1; }
  fi
  compute_live_cache
  return 0
}

load_simulated_live() {
  if [[ -n "${SIMULATED_MONITORS:-}" ]]; then
    LIVE_JSON="$SIMULATED_MONITORS"
  elif [[ ! -t 0 ]]; then
    LIVE_JSON="$(</dev/stdin)"
  else
    die 'dry-run requires monitor JSON in $SIMULATED_MONITORS or stdin'
  fi
  [[ -n "$LIVE_JSON" ]] || die 'simulated monitor list is empty'
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$LIVE_JSON" ||
    die 'simulated monitor list must be a JSON array'
  compute_live_cache
}

live_descs() { printf '%s\n' "$LIVE_DESCS"; }
# Is a profile key present *and* switched on? Resolution answers presence only.
is_enabled() {
  awk -F'\t' -v k="$1" '($1 == k || "desc:" $2 == k) && $3 == 1 { found = 1; exit }
    END { exit !found }' <<<"$LIVE_CACHE"
}
live_names() { printf '%s\n' "$LIVE_NAMES"; }

has_desc() {
  awk -F'\t' -v d="$1" '$2 == d { found = 1; exit } END { exit !found }' <<<"$LIVE_CACHE"
}
has_name() {
  awk -F'\t' -v n="$1" '$1 == n { found = 1; exit } END { exit !found }' <<<"$LIVE_CACHE"
}

kvm_present_count() {
  local d n=0
  for d in "${KVM_DESCS[@]}"; do has_desc "$d" && n=$((n + 1)); done
  printf '%s\n' "$n"
}

# Resolve a profile key ("eDP-1" or "desc:...") to the live connector name.
resolve_output() {
  awk -F'\t' -v k="$1" '($1 == k || "desc:" $2 == k) { print $1; exit }' <<<"$LIVE_CACHE"
}

# ── Settle ──────────────────────────────────────────────────────────────────
# A KVM switch emits a burst of add/remove events and the monitors do not all
# come back at once. Waiting a flat interval is the guess that fails: if only
# two of three panels have appeared we would select the laptop profile and
# collapse every workspace onto the internal display. So wait for the set to
# stop changing AND, if any KVM monitor is present, for all of them to arrive.
settle() {
  [[ "$SKIP_SETTLE" == 1 ]] && return 0

  local deadline=$((SECONDS + SETTLE_TIMEOUT))
  local prev="" cur stable=0 count

  while ((SECONDS < deadline)); do
    refresh_live || { sleep "$SETTLE_INTERVAL"; continue; }
    cur="$(live_descs)"

    if [[ "$cur" == "$prev" ]]; then
      stable=$((stable + 1))
    else
      stable=0
    fi
    prev="$cur"

    if ((stable >= SETTLE_STABLE)); then
      count="$(kvm_present_count)"
      # Stable but only part of the KVM set: keep waiting for the stragglers.
      if ((count > 0 && count < ${#KVM_DESCS[@]})); then
        log "settle: ${count}/${#KVM_DESCS[@]} KVM monitors present, waiting"
        stable=0
      else
        return 0
      fi
    fi
    sleep "$SETTLE_INTERVAL"
  done

  log "settle: timed out after ${SETTLE_TIMEOUT}s, proceeding with what is present"
  refresh_live || true
  return 0
}

# ── Profile selection ───────────────────────────────────────────────────────
# Returns "none" when the KVM set is only partly present. A partial set is not
# the same as an absent one: switching the KVM away disconnects all three, which
# is a genuine laptop-only session, but losing a single monitor must NOT drag
# every workspace onto the internal display. In that case we leave the session
# exactly as it is.
pick_profile() {
  local count
  count="$(kvm_present_count)"
  if ((count == ${#KVM_DESCS[@]})); then
    printf '%s\n' kvm
  elif ((count > 0)); then
    printf '%s\n' none
  elif has_name DP-4 && has_name HDMI-A-3; then
    # Unrelated machine; left on connector names deliberately -- its EDID
    # strings are not known here.
    printf '%s\n' desktop
  else
    printf '%s\n' laptop
  fi
}

# ── Desired layout, parsed out of the profile's Lua ─────────────────────────
# Emits: output|mode|position|scale|transform|disabled
# While the lid is closed the internal panel's row is forced to disabled.
lid_override() {
  if lid_closed; then
    awk -F'|' -v OFS='|' -v mon="$INTERNAL_OUTPUT" '$1 == mon { $6 = "true" } { print }'
  else
    cat
  fi
}

# $2 == "raw" skips the lid override: "is this hardware plugged in?" must not
# be answered by "the lid is shut, so we want it off".
desired_layout() {
  local file="$PROFILE_DIR/$1.monitors.lua"
  [[ -r "$file" ]] || return 1
  awk '
    function norm(v) { return sprintf("%.2f", v + 0) }
    /hl\.monitor\(\{/ { inb = 1; o = m = p = ""; s = "1.00"; t = "0"; d = "false"; next }
    inb && /output *=/     { if (match($0, /"[^"]*"/)) o = substr($0, RSTART + 1, RLENGTH - 2) }
    inb && /mode *=/       { if (match($0, /"[^"]*"/)) m = substr($0, RSTART + 1, RLENGTH - 2) }
    inb && /position *=/   { if (match($0, /"[^"]*"/)) p = substr($0, RSTART + 1, RLENGTH - 2) }
    inb && /scale *=/      { if (match($0, /[0-9]+\.?[0-9]*/)) s = norm(substr($0, RSTART, RLENGTH)) }
    inb && /transform *=/  { if (match($0, /[0-9]+/)) t = substr($0, RSTART, RLENGTH) }
    inb && /disabled *= *true/ { d = "true" }
    inb && /^\}\)/ {
      inb = 0
      if (o == "") next
      if (d == "false" && m != "") {
        # normalise "1920x1080@60.0" -> "1920x1080@60.00"
        split(m, parts, "@")
        m = parts[1] "@" norm(parts[2])
      }
      print o "|" m "|" p "|" s "|" t "|" d
    }
  ' "$file" | { [[ "${2:-}" == raw ]] && cat || lid_override; }
}

# Actual state of one profile key, in the same canonical shape.
actual_state() {
  awk -F'\t' -v k="$1" '($1 == k || "desc:" $2 == k) { print $4; exit }' <<<"$LIVE_CACHE" 2>/dev/null
}

# Renders jq's numbers the way awk's %.2f does, so the two are comparable.
canon_actual() {
  local raw="$1" mode pos scale transform res rate
  IFS='|' read -r mode pos scale transform <<<"$raw"
  res="${mode%@*}"; rate="${mode#*@}"
  printf '%s@%.2f|%s|%.2f|%s\n' "$res" "$rate" "$pos" "$scale" "$transform"
}

# ── Idempotence ─────────────────────────────────────────────────────────────
# Compares the full tuple, not merely which monitors exist: the failure being
# fixed here is monitors that are all present but arranged wrongly.
layout_matches() {
  local profile="$1" quiet="${2:-1}"
  local key mode pos scale transform disabled want got ok=0

  while IFS='|' read -r key mode pos scale transform disabled; do
    [[ -n "$key" ]] || continue

    if [[ "$disabled" == true ]]; then
      if is_enabled "$key"; then
        [[ "$quiet" == 0 ]] && printf '  %-46s want=disabled  got=enabled\n' "$key"
        ok=1
      elif [[ "$quiet" == 0 ]]; then
        printf '  %-46s ok   disabled\n' "$key"
      fi
      continue
    fi

    want="$mode|$pos|$scale|$transform"
    got="$(actual_state "$key")"
    if [[ -z "$got" ]]; then
      [[ "$quiet" == 0 ]] && printf '  %-46s want=%-28s got=ABSENT\n' "$key" "$want"
      ok=1
      continue
    fi
    got="$(canon_actual "$got")"
    if [[ "$want" != "$got" ]]; then
      [[ "$quiet" == 0 ]] && printf '  %-46s want=%-28s got=%s\n' "$key" "$want" "$got"
      ok=1
    elif [[ "$quiet" == 0 ]]; then
      printf '  %-46s ok   %s\n' "$key" "$got"
    fi
  done < <(desired_layout "$profile")

  return $ok
}

profile_missing_outputs() {
  local profile="$1" key mode pos scale transform disabled
  while IFS='|' read -r key mode pos scale transform disabled; do
    [[ -n "$key" && "$disabled" == false ]] || continue
    [[ -n "$(resolve_output "$key")" ]] || printf '%s\n' "$key"
  done < <(desired_layout "$profile" raw)
}

profile_has_connected_output() {
  local profile="$1" key mode pos scale transform disabled
  while IFS='|' read -r key mode pos scale transform disabled; do
    [[ -n "$key" && "$disabled" == false ]] || continue
    [[ -n "$(resolve_output "$key")" ]] && return 0
  done < <(desired_layout "$profile" raw)
  return 1
}

# True when the profile, after the lid override, wants every output off. That
# is a legitimate desired state (undocked with the lid shut) but it cannot be
# the *final* state of a running session, so the applier lights the panel.
layout_leaves_nothing_enabled() {
  local key rest
  while IFS='|' read -r key rest; do
    [[ -n "$key" ]] || continue
    [[ "${rest##*|}" == true ]] || return 1
  done < <(desired_layout "$1")
  return 0
}

# The generated active files must actually come from this profile. Geometry
# alone is not enough: workspaces.lua can be left over from another profile
# while monitors.lua looks correct -- that is the state that pins every
# workspace to a disabled eDP-1 and collapses them onto one screen.
files_match() {
  local profile="$1" quiet="${2:-1}" f rc=0
  for f in monitors workspaces; do
    local active="$CONFIG_DIR/$f.lua" want="$PROFILE_DIR/$profile.$f.lua"
    if ! cmp -s "$active" "$want"; then
      [[ "$quiet" == 0 ]] && printf '  %-46s stale (differs from %s)\n' "$f.lua" "$profile.$f.lua"
      rc=1
    elif [[ "$quiet" == 0 ]]; then
      printf '  %-46s ok   matches %s\n' "$f.lua" "$profile.$f.lua"
    fi
  done
  return $rc
}

# ── Workspace pinning ───────────────────────────────────────────────────────
move_existing_workspaces() {
  local rules id monitor key target
  declare -A target_by_workspace=()

  rules="$("$HYPRCTL" -j workspacerules 2>/dev/null)" || {
    log 'warning: could not read loaded workspace rules; existing workspaces were not moved'
    return 0
  }
  while IFS=$'\t' read -r id key; do
    [[ "$id" =~ ^([1-9]|1[0-5])$ && -n "$key" ]] || continue
    target_by_workspace["$id"]="$key"
  done < <(jq -r '.[] | select(.enabled and (.workspaceString | test("^([1-9]|1[0-5])$"))) | [.workspaceString, .monitor] | @tsv' <<<"$rules")

  while read -r id monitor; do
    key="${target_by_workspace[$id]:-}"
    [[ -n "$key" ]] || continue
    target="$(resolve_output "$key")"
    # Never dispatch a move to a monitor that is not present and enabled.
    [[ -n "$target" ]] || continue
    is_enabled "$target" || continue
    [[ "$monitor" != "$target" ]] || continue
    "$HYPRCTL" dispatch \
      "hl.dsp.workspace.move({ workspace = $id, monitor = \"$target\" })" >/dev/null
  done < <("$HYPRCTL" -j workspaces 2>/dev/null |
    jq -r '.[] | select(.id >= 1 and .id <= 15) | "\(.id) \(.monitor)"')
}

# ── Apply ───────────────────────────────────────────────────────────────────
install_profile_files() {
  local profile="$1" temp_dir had_monitors=0 had_workspaces=0
  temp_dir="$(mktemp -d "$CONFIG_DIR/.monitor-profile.XXXXXX")" ||
    die "could not create temporary directory in $CONFIG_DIR"

  if [[ -f "$MONITORS_FILE" ]]; then
    cp "$MONITORS_FILE" "$temp_dir/monitors.old" || {
      rmdir "$temp_dir"
      die "could not back up $MONITORS_FILE"
    }
    had_monitors=1
  fi
  if [[ -f "$WORKSPACES_FILE" ]]; then
    cp "$WORKSPACES_FILE" "$temp_dir/workspaces.old" || {
      rm -f "$temp_dir"/*; rmdir "$temp_dir"
      die "could not back up $WORKSPACES_FILE"
    }
    had_workspaces=1
  fi
  cp "$PROFILE_DIR/$profile.monitors.lua" "$temp_dir/monitors.new" || {
    rm -f "$temp_dir"/*; rmdir "$temp_dir"
    die 'could not stage monitor profile'
  }
  cp "$PROFILE_DIR/$profile.workspaces.lua" "$temp_dir/workspaces.new" || {
    rm -f "$temp_dir"/*; rmdir "$temp_dir"
    die 'could not stage workspace profile'
  }

  if ! mv "$temp_dir/monitors.new" "$MONITORS_FILE" ||
     ! mv "$temp_dir/workspaces.new" "$WORKSPACES_FILE"; then
    if ((had_monitors)); then cp "$temp_dir/monitors.old" "$MONITORS_FILE"; else rm -f "$MONITORS_FILE"; fi
    if ((had_workspaces)); then cp "$temp_dir/workspaces.old" "$WORKSPACES_FILE"; else rm -f "$WORKSPACES_FILE"; fi
    rm -f "$temp_dir"/*; rmdir "$temp_dir"
    die 'could not install both profile files; previous files restored'
  fi

  rm -f "$temp_dir"/*
  rmdir "$temp_dir"
}

apply_profile() {
  local profile="$1"

  [[ -r "$PROFILE_DIR/$profile.monitors.lua" ]] ||
    die "missing profile file: $PROFILE_DIR/$profile.monitors.lua"
  [[ -r "$PROFILE_DIR/$profile.workspaces.lua" ]] ||
    die "missing profile file: $PROFILE_DIR/$profile.workspaces.lua"
  # A monitor event can arrive while Git is replacing this Stow-linked tree.
  # Do not write profile state or ask Hyprland to reload a missing entrypoint.
  [[ -r "$CONFIG_DIR/hyprland.lua" ]] ||
    die "missing active Lua config: $CONFIG_DIR/hyprland.lua"

  install_profile_files "$profile"

  "$HYPRCTL" reload >/dev/null || log "warning: hyprctl reload reported failure"
  refresh_live || true

  # The reload just applied monitors.lua, which may have re-enabled the
  # internal panel; put it back off before workspaces are pinned to it.
  if lid_closed && [[ -n "$(resolve_output "$INTERNAL_OUTPUT")" ]]; then
    log "lid closed: disabling $INTERNAL_OUTPUT after reload"
    "$HYPRCTL" -q eval "hl.monitor({ output = \"$INTERNAL_OUTPUT\", disabled = true })" >/dev/null 2>&1
    refresh_live || true
  fi

  # Insurance against a black session: whatever the profile and the lid say,
  # a live session must have something to draw on. Undocking with the lid shut
  # used to land here with every output off.
  if ! jq -e 'any(.[]; .disabled != true)' >/dev/null 2>&1 <<<"$LIVE_JSON"; then
    log "no enabled output remains: re-enabling $INTERNAL_OUTPUT as a fallback"
    "$HYPRCTL" -q eval \
      "hl.monitor({ output = \"$INTERNAL_OUTPUT\", mode = \"preferred\", position = \"auto\", scale = 1.0 })" \
      >/dev/null 2>&1
    refresh_live || true
    "$HYPRCTL" notify -1 5000 "rgb(ebcb8b)" \
      "No external display left: $INTERNAL_OUTPUT re-enabled" >/dev/null 2>&1
  fi

  move_existing_workspaces

  if [[ "$profile" == desktop ]]; then
    "$HYPRCTL" dispatch 'hl.dsp.focus({ monitor = "HDMI-A-3" })' >/dev/null
  fi
}

main() {
  command -v jq >/dev/null 2>&1 || die "jq is required"

  if [[ "$DRY_RUN" == 1 ]]; then
    load_simulated_live
  else
    settle
    refresh_live || die "cannot read monitors from hyprctl -- is Hyprland running?"
  fi

  local profile
  profile="${PROFILE:-$(pick_profile)}"

  if [[ "$profile" == none ]]; then
    local msg
    msg="incomplete KVM set ($(kvm_present_count)/${#KVM_DESCS[@]} present), leaving layout alone"
    if [[ "$DRY_RUN" == 1 ]]; then
      printf 'profile=none\n%s\nresult=no-action\n' "$msg"
    else
      log "$msg"
    fi
    return 0
  fi

  [[ -r "$PROFILE_DIR/$profile.monitors.lua" &&
     -r "$PROFILE_DIR/$profile.workspaces.lua" ]] ||
    die "profile '$profile' does not have paired monitor and workspace files"

  local missing
  missing="$(profile_missing_outputs "$profile")"
  if ! profile_has_connected_output "$profile"; then
    local msg="profile=$profile has no connected enabled output; refusing to apply"
    if [[ "$DRY_RUN" == 1 ]]; then
      printf 'profile=%s\nwarning=%s\nresult=refused-no-connected-output\n' "$profile" "$msg"
      printf '%s\n' '=== monitors.lua ==='
      cat "$PROFILE_DIR/$profile.monitors.lua"
      printf '%s\n' '=== workspaces.lua ==='
      cat "$PROFILE_DIR/$profile.workspaces.lua"
    else
      log "$msg"
      "$HYPRCTL" notify -1 5000 "rgb(bf616a)" \
        "Monitor profile $profile refused: no requested output is connected" >/dev/null 2>&1
    fi
    return 1
  fi
  if [[ -n "$missing" ]]; then
    log "warning: profile=$profile outputs not connected: ${missing//$'\n'/, }"
    if [[ "$DRY_RUN" == 0 ]]; then
      "$HYPRCTL" notify -1 4000 "rgb(ebcb8b)" \
        "Monitor profile $profile: some requested outputs are not connected" >/dev/null 2>&1
    fi
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    printf 'profile=%s\n' "$profile"
    [[ -z "$missing" ]] || printf 'warning=outputs not connected: %s\n' "${missing//$'\n'/, }"
    layout_leaves_nothing_enabled "$profile" &&
      printf 'fallback=every output wanted off; would re-enable %s\n' "$INTERNAL_OUTPUT"
    printf '%s\n' '=== monitors.lua ==='
    cat "$PROFILE_DIR/$profile.monitors.lua"
    printf '%s\n' '=== workspaces.lua ==='
    cat "$PROFILE_DIR/$profile.workspaces.lua"
    printf 'desired vs actual:\n'
    local fok=0 lok=0
    files_match "$profile" 0 || fok=1
    layout_matches "$profile" 0 || lok=1
    if ((fok == 0 && lok == 0)); then
      printf 'result=already-correct (would do nothing)\n'
    else
      printf 'result=would-apply\n'
    fi
    return 0
  fi

  if [[ "$FORCE" == 0 ]] && files_match "$profile" && layout_matches "$profile"; then
    log "profile=$profile already applied, nothing to do"
    return 0
  fi

  log "applying profile=$profile"
  apply_profile "$profile"

  # Verify, and retry once: the compositor occasionally needs a second pass
  # when a monitor arrived while the reload was already in flight.
  refresh_live || true
  if ! { files_match "$profile" && layout_matches "$profile"; }; then
    log "verify failed after apply, retrying once"
    sleep 1
    refresh_live || true
    apply_profile "$profile"
    refresh_live || true
    if ! { files_match "$profile" && layout_matches "$profile"; }; then
      log "ERROR: layout still incorrect after retry (profile=$profile)"
      "$HYPRCTL" notify -1 5000 "rgb(bf616a)" \
        "Monitor profile $profile failed to apply" >/dev/null 2>&1
      return 1
    fi
  fi

  log "profile=$profile applied and verified"
  "$HYPRCTL" notify -1 3000 "rgb(88c0d0)" "Loaded monitor profile: $profile" >/dev/null 2>&1
  return 0
}

# ── Single-instance ─────────────────────────────────────────────────────────
# A KVM switch fires several events; the first run wins and the rest exit
# rather than queue up behind it and re-apply an already-correct layout.
if [[ "$DRY_RUN" == 0 ]] && command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" || die "cannot open lock $LOCK_FILE"
  if ! flock -n 9; then
    log "another instance holds the lock, exiting"
    exit 0
  fi
fi

main
