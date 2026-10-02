#!/usr/bin/env bash
# =============================================================================
# power-profile.sh — switch powerprofilesctl profiles
#
# Fixture-testable CLI and standalone Rofi picker for power-profiles-daemon.
# Labels shown in the menu are display metadata only — they are never executed;
# each branch calls a fixed argv through powerprofilesctl.
#
# User prerequisite (not handled here):
#   pacman -S power-profiles-daemon
#   systemctl enable --now power-profiles-daemon
# =============================================================================
set -euo pipefail

PROFILES=(performance balanced power-saver)

usage() {
  cat <<'EOF'
Usage: power-profile.sh <action> [--dry-run]

Actions:
  list              list available profiles
  get|status        print the current profile and power source
  set PROFILE       set an available profile (performance|balanced|power-saver)
  cycle             cycle profiles in powerprofilesctl order
  toggle            choose a profile from AC/battery state
  menu              open the Rofi profile picker

--dry-run prints what would run and never mutates state.
EOF
}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  # A missing notification daemon must not fail an already-applied change.
  notify-send -a "Power profile" "$1" "${2:-}" || true
}

require_powerprofilesctl() {
  command -v powerprofilesctl >/dev/null 2>&1 || {
    notify "Power profiles unavailable" "Install power-profiles-daemon"
    printf 'power-profile.sh: powerprofilesctl is not installed\n' >&2
    printf 'Install and start it with:\n  pacman -S power-profiles-daemon\n  systemctl enable --now power-profiles-daemon\n' >&2
    return 1
  }
}

# Report daemon errors consistently; anything that looks like a missing/busy
# daemon points the user at the systemd unit.
daemon_error() {
  local error="$1"
  if [[ "$error" == *"daemon"*"not"*"running"* || "$error" == *"No such object"* ||
        "$error" == *"ServiceUnknown"* || "$error" == *"PowerProfiles"* ]]; then
    notify "Power profiles daemon unavailable" "systemctl enable --now power-profiles-daemon"
    printf 'power-profile.sh: the power profiles daemon is not running\n' >&2
    printf 'Start it with: systemctl enable --now power-profiles-daemon\n' >&2
  else
    notify "Power profile error" "$error"
    printf 'power-profile.sh: %s\n' "$error" >&2
  fi
  return 1
}

# Parse `powerprofilesctl list` for known profile names.
profiles() {
  local output line profile available=""
  output=$(powerprofilesctl list 2>&1) || daemon_error "$output"
  while IFS= read -r line; do
    profile=${line%%:*}
    # Real powerprofilesctl prefixes the active profile with "* " — strip
    # markers and whitespace before matching known names.
    profile=${profile//[![:alnum:]-]/}
    for known in "${PROFILES[@]}"; do
      if [[ "$profile" == "$known" ]]; then
        available+="$known"$'\n'
        break
      fi
    done
  done <<< "$output"
  printf '%s' "$available"
}

current_profile() {
  local output profile
  output=$(powerprofilesctl get 2>&1) || daemon_error "$output"
  profile=${output%%$'\n'*}
  profile=${profile##* }
  for known in "${PROFILES[@]}"; do
    [[ "$profile" == "$known" ]] && { printf '%s\n' "$profile"; return 0; }
  done
  printf 'balanced\n'
}

power_source() {
  local online
  for online in /sys/class/power_supply/A*/online; do
    [[ -e "$online" ]] || continue
    if [[ "$(cat "$online")" == 1 ]]; then
      printf '%s\n' AC
    else
      printf '%s\n' battery
    fi
    return 0
  done
  printf '%s\n' unknown
}

status_line() {
  local profile src label
  profile=$(current_profile)
  src=$(power_source)
  case "$src" in
    AC) label="on AC" ;;
    battery) label="on battery" ;;
    *) label="power source unknown" ;;
  esac
  printf '%s (%s)\n' "$profile" "$label"
}

run_set() {
  local dry_run="$1" profile="$2" available output
  available=$(profiles)
  if ! grep -Fxq "$profile" <<< "$available"; then
    notify "Unknown power profile" "$profile"
    printf 'power-profile.sh: unavailable profile: %s\n' "$profile" >&2
    return 2
  fi
  if [[ "$dry_run" == true ]]; then
    printf 'powerprofilesctl set %s\n' "$profile"
    return 0
  fi
  if output=$(powerprofilesctl set "$profile" 2>&1); then
    notify "Power profile set" "$profile"
  else
    daemon_error "$output"
  fi
}

# Set the first profile of the given list (newlines separated).
choose_from() {
  local dry_run="$1" available="$2" profile
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    if [[ "$dry_run" == true ]]; then
      printf 'powerprofilesctl set %s\n' "$profile"
    else
      run_set false "$profile"
    fi
    return 0
  done <<< "$available"
  printf 'power-profile.sh: no available profiles\n' >&2
  return 1
}

cycle() {
  local dry_run="$1" profile available previous="" fallback next
  available=$(profiles)
  [[ -n "$available" ]] || { printf 'power-profile.sh: no available profiles\n' >&2; return 1; }
  profile=$(current_profile)
  fallback=${available%%$'\n'*}
  while IFS= read -r next; do
    [[ -n "$next" ]] || continue
    if [[ -n "$previous" && "$previous" == "$profile" ]]; then
      fallback=$next
      break
    fi
    previous=$next
  done <<< "$available"
  choose_from "$dry_run" "$fallback"
}

ac_state() {
  local online state
  for online in /sys/class/power_supply/A*/online; do
    [[ -e "$online" ]] || continue
    state=$(cat "$online")
    [[ "$state" == 1 ]] && return 0
    return 1
  done
  return 2
}

toggle() {
  local dry_run="$1" available preference ac=2
  available=$(profiles)
  [[ -n "$available" ]] || { printf 'power-profile.sh: no available profiles\n' >&2; return 1; }
  ac_state || ac=$?
  case "$ac" in
    0) preference=performance ;;
    1) preference=power-saver ;;
    *) preference=balanced ;;
  esac
  grep -Fxq "$preference" <<< "$available" || preference=balanced
  grep -Fxq "$preference" <<< "$available" || preference=${available%%$'\n'*}
  [[ -n "$preference" ]] || return 1
  choose_from "$dry_run" "$preference"
}

menu() {
  local dry_run="$1" available profile active label items="" marker
  active=$(current_profile)
  available=$(profiles)
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    marker=""
    label=""
    [[ "$profile" == "$active" ]] && marker="*"
    case "$profile" in
      performance) label="󰓅  Performance $marker" ;;
      balanced) label="󰾅  Balanced $marker" ;;
      power-saver) label="󰾆  Power saver $marker" ;;
    esac
    items+="$label"$'\n'
  done <<< "$available"
  items=${items%$'\n'}
  if [[ -z "$items" ]]; then
    printf 'power-profile.sh: no available profiles\n' >&2
    return 1
  fi
  if [[ "$dry_run" == true ]]; then
    printf 'Rofi items:\n%s\n' "$items"
    return 0
  fi
  command -v rofi >/dev/null 2>&1 || {
    notify "Rofi unavailable" "power-profile menu requires rofi"
    printf 'power-profile.sh: rofi is not installed\n' >&2
    return 1
  }
  if pgrep -x rofi >/dev/null 2>&1; then
    pkill rofi
  fi
  local rofi_theme="$HOME/.config/rofi/current-theme.rasi"
  [[ -f "$rofi_theme" ]] || rofi_theme="$HOME/.config/rofi/comet-glass.rasi"
  local choice
  choice=$(printf '%s\n' "$items" | rofi -dmenu -i -p "Power profile" \
    -theme "$rofi_theme") || return 0
  [[ -n "$choice" ]] || return 0
  case "$choice" in
    *Performance*) run_set false performance ;;
    *Balanced*) run_set false balanced ;;
    *"Power saver"*) run_set false power-saver ;;
  esac
}

dry_run=false
action=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) action="$1"; shift; break ;;
  esac
done
[[ -n "$action" ]] || { usage >&2; exit 2; }
require_powerprofilesctl
profile_arg=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    *) [[ -n "$profile_arg" ]] || profile_arg="$arg" ;;
  esac
done

case "$action" in
  list)
    if [[ "$dry_run" == true ]]; then
      profiles
    else
      powerprofilesctl list
    fi
    ;;
  get|status)
    status_line
    ;;
  set)
    [[ -n "$profile_arg" && "$profile_arg" != "--dry-run" ]] || { usage >&2; exit 2; }
    run_set "$dry_run" "$profile_arg"
    ;;
  cycle) cycle "$dry_run" ;;
  toggle) toggle "$dry_run" ;;
  menu) menu "$dry_run" ;;
  *) usage >&2; exit 2 ;;
esac
