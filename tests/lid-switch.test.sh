#!/usr/bin/env bash
# Exercises the lid handling against a stub hyprctl: lid-switch.sh must only
# toggle the internal panel when it is safe to, and auto-monitor-profile.sh
# must treat the panel as desired-off while the lid is closed so a hotplug
# apply never re-lights a closed laptop.
set -euo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || {
  printf 'skip: jq is not installed\n'
  exit 0
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hypr_root="$repo_root/hypr/.config/hypr"
lid_switch="$hypr_root/scripts/lid-switch.sh"
applier="$hypr_root/scripts/auto-monitor-profile.sh"
[[ -x "$lid_switch" ]] || fail "not executable: $lid_switch"
[[ -r "$applier" ]] || fail "missing: $applier"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

calls="$test_root/hyprctl.calls"
monitors_json="$test_root/monitors.json"

cat >"$test_root/hyprctl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$calls"
[[ "\$*" == "-j monitors" ]] && cat "$monitors_json"
exit 0
SH
chmod +x "$test_root/hyprctl"
export HYPRCTL="$test_root/hyprctl"

internal='{"name":"eDP-1","description":"BOE 0x0BCA","width":2256,"height":1504,"refreshRate":60.0,"x":0,"y":0,"scale":1.0,"transform":0}'
kvm_set='{"name":"DP-5","description":"Dell Inc. DELL P2214H KW14V42L3ACB","width":1920,"height":1080,"refreshRate":60.0,"x":2256,"y":0,"scale":1.0,"transform":1},
{"name":"DP-7","description":"Dell Inc. DELL P2722H CTCS1M3","width":1920,"height":1080,"refreshRate":60.0,"x":3336,"y":0,"scale":1.0,"transform":0},
{"name":"DP-9","description":"Dell Inc. DELL P2725H 21MG834","width":1920,"height":1080,"refreshRate":60.0,"x":5256,"y":0,"scale":1.0,"transform":0}'

run_case() { : >"$calls"; "$lid_switch" "$1" || fail "lid-switch $1 exited $?"; }

# close while docked: the panel must be disabled.
printf '[%s,%s]\n' "$internal" "$kvm_set" >"$monitors_json"
run_case close
grep -q 'disabled = true' "$calls" || fail 'docked close did not disable the panel'

# close when the panel is the only enabled monitor: leave it on.
printf '[%s]\n' "$internal" >"$monitors_json"
run_case close
! grep -q 'eval' "$calls" || fail 'lone-monitor close must not disable the panel'

# close when the panel is already disabled: nothing to do.
printf '[%s]\n' "$kvm_set" >"$monitors_json"
run_case close
! grep -q 'eval' "$calls" || fail 'close with panel already off must be a no-op'

# open while the panel is disabled: re-enable it.
run_case open
grep -q 'mode = "preferred"' "$calls" || fail 'open did not re-enable the panel'

# open while the panel is already enabled: nothing to do.
printf '[%s,%s]\n' "$internal" "$kvm_set" >"$monitors_json"
run_case open
! grep -q 'eval' "$calls" || fail 'open with panel already on must be a no-op'

# ── Applier lid override (dry-run, no compositor touched) ───────────────────
simulated="$(printf '[%s,%s]\n' "$internal" "$kvm_set")"

# Lid open: the live layout matches the kvm profile, nothing to apply.
out="$(SIMULATED_MONITORS="$simulated" HYPR_DIR="$hypr_root" \
  HYPR_LID_STATE="$test_root/no-such-lid-state" \
  bash "$applier" --dry-run 2>/dev/null)" || fail 'applier dry-run (lid open) failed'
grep -q 'profile=kvm' <<<"$out" || fail "lid open: expected kvm profile, got: $out"
grep -q 'result=already-correct' <<<"$out" ||
  fail "lid open: expected already-correct, got: $out"

# Lid closed: the same layout must now be wrong -- the panel is wanted off.
printf 'state:      closed\n' >"$test_root/lid-state"
out="$(SIMULATED_MONITORS="$simulated" HYPR_DIR="$hypr_root" \
  HYPR_LID_STATE="$test_root/lid-state" \
  bash "$applier" --dry-run 2>/dev/null)" || fail 'applier dry-run (lid closed) failed'
grep -q 'want=disabled' <<<"$out" ||
  fail "lid closed: expected the panel to be wanted off, got: $out"
grep -q 'result=would-apply' <<<"$out" ||
  fail "lid closed: expected would-apply, got: $out"

printf 'PASS: lid-switch\n'
