#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly ROOT
readonly LAUNCHER="$ROOT/rofi/.config/rofi/powermenu/launcher.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ $haystack == *"$needle"* ]] || fail "missing output: $needle"
}

fixture_dir="$(mktemp -d)"
trap 'rm -rf -- "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"
export HOME="$fixture_dir/home"
export POWER_MENU_LOCK_COMMAND="$fixture_dir/bin/screensaver-lock"
cat >"$POWER_MENU_LOCK_COMMAND" <<'EOF'
#!/usr/bin/env bash
printf 'screensaver-lock\n' >>"$POWER_MENU_FIXTURE_LOG"
EOF
chmod +x "$POWER_MENU_LOCK_COMMAND"

for action in lock logout suspend reboot shutdown; do
  output="$($LAUNCHER --dry-run "$action")"
  assert_contains "$output" 'DRY-RUN:'
done

suspend_output="$($LAUNCHER --dry-run suspend)"
assert_contains "$suspend_output" 'screensaver-lock'
assert_contains "$suspend_output" 'sleep 1'
assert_contains "$suspend_output" 'systemctl suspend'

cat >"$fixture_dir/bin/rofi" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s' "${FAKE_ROFI_OUTPUT:-0}"
exit "${FAKE_ROFI_STATUS:-0}"
EOF

cat >"$fixture_dir/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

for command_name in hyprlock hyprctl systemctl sleep; do
  cat >"$fixture_dir/bin/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$POWER_MENU_FIXTURE_LOG"
EOF
  chmod +x "$fixture_dir/bin/$command_name"
done
chmod +x "$fixture_dir/bin/rofi" "$fixture_dir/bin/pgrep"

fixture_log="$fixture_dir/actions.log"
: >"$fixture_log"
PATH="$fixture_dir/bin:$PATH" \
POWER_MENU_FIXTURE_LOG="$fixture_log" \
FAKE_ROFI_STATUS=12 \
  "$LAUNCHER"

fixture_actions="$(<"$fixture_log")"
assert_contains "$fixture_actions" 'screensaver-lock'
assert_contains "$fixture_actions" 'sleep 1'
assert_contains "$fixture_actions" 'systemctl suspend'

: >"$fixture_log"
PATH="$fixture_dir/bin:$PATH" POWER_MENU_FIXTURE_LOG="$fixture_log" "$LAUNCHER" lock
assert_contains "$(<"$fixture_log")" 'screensaver-lock'

# A rofi-only installation retains the direct Hyprlock fallback.
POWER_MENU_LOCK_COMMAND="$fixture_dir/missing" "$LAUNCHER" --dry-run lock \
  >"$fixture_dir/fallback.out"
assert_contains "$(<"$fixture_dir/fallback.out")" 'hyprlock --config'

printf 'ok: power menu dry-run and fixture actions\n'
