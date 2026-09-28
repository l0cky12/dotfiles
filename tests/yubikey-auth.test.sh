#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
auth="$repo_root/security/.local/bin/yubikey-auth"
test_root=$(mktemp -d -t yubikey-auth-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/etc/pam.d"

cat > "$test_root/bin/fido2-token" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -L)
    printf '/dev/hidraw-test: vendor=0x1050, product=%s (Yubico YubiKey FIDO)\n' "${FIDO_FIXTURE_PRODUCT:-0x0402}"
    if [[ ${FIDO_FIXTURE_MULTIPLE:-0} == 1 ]]; then
      printf '/dev/hidraw-other: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO)\n'
    fi
    ;;
  -I)
    # Mirrors the shape of a real `fido2-token -I`. The default key has no
    # sensor, which is what the attached hardware reports.
    printf 'proto: 0x02\n'
    if [[ ${FIDO_FIXTURE_BIO:-0} == 1 ]]; then
      printf 'options: rk, up, noplat, nobioEnroll, clientPin, uv\n'
    elif [[ ${FIDO_FIXTURE_NOPIN:-0} == 1 ]]; then
      printf 'options: rk, up, noplat\n'
    else
      printf 'options: rk, up, noplat, clientPin, credentialMgmtPreview\n'
    fi
    printf 'pin retries: 8\n'
    ;;
  -S)
    printf '%s\n' "$*" >> "$FIDO_FIXTURE_CALLS"
    ;;
  *) exit 2 ;;
esac
SH

cat > "$test_root/bin/pamu2fcfg" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PAMU_FIXTURE_CALLS"
user=liam
additional=false
while (($#)); do
  case $1 in
    -u) user=$2; shift 2 ;;
    -n) additional=true; shift ;;
    *) shift ;;
  esac
done
if [[ $additional == true ]]; then
  printf 'second-handle,second-public-key,es256,+verification\n'
else
  printf '%s:first-handle,first-public-key,es256,+verification\n' "$user"
fi
SH

cat > "$test_root/bin/sudo-fixture" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  install)
    shift
    args=()
    while (($#)); do
      case $1 in
        -o|-g) shift 2 ;;
        *) args+=("$1"); shift ;;
      esac
    done
    exec install "${args[@]}"
    ;;
  cat|cp|rm) exec "$@" ;;
  *) printf 'unexpected sudo command: %s\n' "$*" >&2; exit 2 ;;
esac
SH

chmod +x "$test_root/bin/"*

export YUBIKEY_AUTH_USER=liam
export YUBIKEY_AUTH_ORIGIN=pam://Kelper
export YUBIKEY_AUTH_ETC_ROOT="$test_root/etc"
export YUBIKEY_AUTH_TEMPLATE_DIR="$repo_root/system/pam.d"
export YUBIKEY_AUTH_FIDO2_TOKEN="$test_root/bin/fido2-token"
export YUBIKEY_AUTH_PAMU2FCFG="$test_root/bin/pamu2fcfg"
export YUBIKEY_AUTH_SUDO="$test_root/bin/sudo-fixture"
export FIDO_FIXTURE_CALLS="$test_root/fido.calls"
export PAMU_FIXTURE_CALLS="$test_root/pamu.calls"

# Exercise the commands actually offered by the menu, without a terminal or
# token mutation. Both setup and add must have PIN and Bio enrollment paths.
python3 - "$repo_root/menu/.config/lmenu/menu.jsonc" "$auth" <<'PY'
import os
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

rows = json.loads(re.sub(r'^\s*//.*$', '', Path(sys.argv[1]).read_text(), flags=re.M))
actions = []
for row in rows:
    if row["id"] not in {"setup.security.yubikey." + kind + suffix
                         for kind in ("setup", "add") for suffix in ("", "-pin", "-bio")}:
        continue
    terminal = shlex.split(row["action"])
    script = terminal[terminal.index("-lc") + 1]
    command = shlex.split(script.split(";", 1)[0])
    assert command[0] == "yubikey-auth"
    actions.append(command[1:])
for action in ("setup", "add"):
    offered = [args for args in actions if args[0] == action]
    for product, mode in (("0x0407", "pin"), ("0x0402", "bio")):
        results = [subprocess.run([sys.argv[2], *args, "--dry-run"],
                   env=os.environ | {"FIDO_FIXTURE_PRODUCT": product, "FIDO_FIXTURE_BIO": "1" if mode == "bio" else "0"},
                   capture_output=True, text=True) for args in offered]
        assert any(r.returncode == 0 and f"mode: {mode}" in r.stdout
                   and (mode != "bio" or "would enroll: fingerprint" in r.stdout)
                   for r in results), f"menu cannot {action} a {mode} key"
PY

printf 'invalid terminal bytes\033[0m\n' > "$test_root/etc/u2f_mappings"
printf 'old sudo pam\n' > "$test_root/etc/pam.d/sudo"
printf 'old hyprlock pam\n' > "$test_root/etc/pam.d/hyprlock"

# A key with no fingerprint sensor must not be routed into Bio enrollment: the
# old product-ID check picked bio for product=0x0402 and libfido2 answered
# FIDO_ERR_INVALID_COMMAND on hardware that has no sensor at all.
if "$auth" setup --enroll-fingerprint --confirm-sudo-tested \
  > "$test_root/no-sensor.out" 2>&1; then
  fail 'a key without a fingerprint sensor still accepted --enroll-fingerprint'
fi
grep -Fq 'no fingerprint sensor' "$test_root/no-sensor.out" \
  || fail 'the missing-sensor failure was not actionable'
[[ ! -s $FIDO_FIXTURE_CALLS ]] \
  || fail 'a key without a sensor was still sent a fingerprint enrollment'

"$auth" setup --confirm-sudo-tested > "$test_root/setup.out"
grep -Fq 'mode: touch' "$test_root/setup.out" \
  || fail 'a key offering only presence did not resolve to touch mode'
grep -Fq 'Then touch /dev/hidraw-test when it blinks to finish registration.' "$test_root/setup.out" \
  || fail 'setup did not explain the touch after the optional PIN prompt'
grep -Fq 'liam:first-handle,first-public-key,es256,+verification' \
  "$test_root/etc/u2f_mappings" || fail 'setup did not install the first mapping'
cmp "$repo_root/system/pam.d/sudo" "$test_root/etc/pam.d/sudo" \
  || fail 'setup did not install the sudo PAM template'
cmp "$repo_root/system/pam.d/doas" "$test_root/etc/pam.d/doas" \
  || fail 'setup did not install the doas PAM template'
for service in sudo doas; do
  awk '
    $1 == "auth" || $1 == "-auth" {
      if (/\[success=2 default=ignore\].*pam_unix\.so/) password = NR
      if (/pam_fprintd\.so/) fingerprint = NR
      if (/pam_u2f\.so/) key = NR
      if (/include.*(system-auth|login)/) fallback = NR
    }
    END { exit !(password && fingerprint && key && fallback && password < fingerprint && fingerprint < key && key < fallback) }
  ' "$repo_root/system/pam.d/$service" \
    || fail "$service does not offer password before waiting for the key"
done
grep -Fq 'old hyprlock pam' "$test_root/etc/pam.d/hyprlock" \
  || fail 'setup changed the lock screen without --with-hyprlock'
! grep -Eq -- '(^| )-[NV]( |$)' "$PAMU_FIXTURE_CALLS" \
  || fail 'touch mode still registered a PIN or user-verification requirement'
find "$test_root/etc" -maxdepth 2 -name '*.pre-yubikey.*' | grep -q . \
  || fail 'setup did not retain recovery backups'
[[ $(stat -c '%a' "$test_root/etc/u2f_mappings") == 644 ]] \
  || fail 'mapping permissions are not 0644'

"$auth" add > "$test_root/add.out"
expected='liam:first-handle,first-public-key,es256,+verification:second-handle,second-public-key,es256,+verification'
[[ $(<"$test_root/etc/u2f_mappings") == "$expected" ]] \
  || fail 'additional credential was not appended to the existing user line'
grep -Fq -- '-n ' "$PAMU_FIXTURE_CALLS" \
  || fail 'additional registration did not omit the duplicate username'
[[ $(find "$test_root/etc" -maxdepth 1 -name 'u2f_mappings.pre-yubikey.*' | wc -l) -ge 2 ]] \
  || fail 'same-second updates did not preserve distinct mapping backups'

before=$(sha256sum "$test_root/etc/u2f_mappings" "$test_root/etc/pam.d/sudo" "$test_root/etc/pam.d/hyprlock")
"$auth" setup --dry-run > "$test_root/dry-run.out"
after=$(sha256sum "$test_root/etc/u2f_mappings" "$test_root/etc/pam.d/sudo" "$test_root/etc/pam.d/hyprlock")
[[ $before == "$after" ]] || fail 'dry-run changed authentication state'
grep -Fq "would leave on password: $test_root/etc/pam.d/hyprlock" "$test_root/dry-run.out" \
  || fail 'dry-run did not report that the lock screen is left alone'
"$auth" setup --with-hyprlock --dry-run > "$test_root/hyprlock-dry-run.out"
grep -Fq "would check existing mapping: $test_root/etc/u2f_mappings" "$test_root/hyprlock-dry-run.out" \
  || fail 'Hyprlock dry-run claimed it would replace the existing mapping'
FIDO_FIXTURE_BIO=1 "$auth" setup --dry-run --enroll-fingerprint --with-hyprlock \
  > "$test_root/dry-run-bio.out"
grep -Fq 'mode: bio' "$test_root/dry-run-bio.out" \
  || fail 'a key with a sensor did not resolve to bio mode'
grep -Fq 'would enroll: fingerprint' "$test_root/dry-run-bio.out" \
  || fail 'dry-run did not report fingerprint enrollment'
grep -Fq "would deploy: $test_root/etc/pam.d/hyprlock" "$test_root/dry-run-bio.out" \
  || fail '--with-hyprlock did not report the lock-screen deployment'

: > "$PAMU_FIXTURE_CALLS"
"$auth" add --mode pin > "$test_root/pin.out"
grep -Fq -- '-N' "$PAMU_FIXTURE_CALLS" || fail 'PIN mode did not request PIN verification'
! grep -Fq -- '-V' "$PAMU_FIXTURE_CALLS" || fail 'PIN mode also requested biometric verification'

if FIDO_FIXTURE_NOPIN=1 "$auth" add --mode pin --dry-run \
  > "$test_root/nopin.out" 2>&1; then
  fail 'PIN mode was accepted by a key that cannot hold a PIN'
fi
grep -Fq 'does not support a FIDO PIN' "$test_root/nopin.out" \
  || fail 'the unsupported-PIN failure was not actionable'

if "$auth" add --with-hyprlock --dry-run > "$test_root/add-hyprlock.out" 2>&1; then
  fail "add silently accepted --with-hyprlock"
fi
grep -Fq "applies to 'setup' only" "$test_root/add-hyprlock.out" \
  || fail 'the misplaced --with-hyprlock failure was not actionable'

"$auth" status > "$test_root/status.out"
grep -Fq 'mapping: valid for liam' "$test_root/status.out" \
  || fail 'status did not recognize the valid mapping'
grep -Fq 'pam: deployed' "$test_root/status.out" \
  || fail 'status did not recognize deployed PAM templates'
grep -Fq 'verification: /dev/hidraw-test can offer touch, PIN' "$test_root/status.out" \
  || fail 'status did not report what the key can actually verify with'
grep -Fq 'pam: password only' "$test_root/status.out" \
  || fail 'status did not report the lock screen as password only'

before=$(sha256sum "$test_root/etc/u2f_mappings" "$test_root/etc/pam.d/sudo" "$test_root/etc/pam.d/doas")
pamu_calls_before=$(wc -l < "$PAMU_FIXTURE_CALLS")
if "$auth" setup --with-hyprlock < /dev/null > "$test_root/hyprlock-checkpoint.out" 2>&1; then
  fail 'an existing setup skipped the Hyprlock confirmation'
fi
grep -Fq 'interactive confirmation unavailable' "$test_root/hyprlock-checkpoint.out" \
  || fail 'an existing setup did not require the Hyprlock checkpoint'
grep -Fq 'old hyprlock pam' "$test_root/etc/pam.d/hyprlock" \
  || fail 'Hyprlock changed before confirmation'
chmod 0600 "$test_root/etc/u2f_mappings"
"$auth" setup --with-hyprlock --confirm-sudo-tested > "$test_root/hyprlock.out"
[[ $(stat -c '%a' "$test_root/etc/u2f_mappings") == 644 ]] \
  || fail 'existing mapping permissions were not migrated from 0600 to 0644'
after=$(sha256sum "$test_root/etc/u2f_mappings" "$test_root/etc/pam.d/sudo" "$test_root/etc/pam.d/doas")
[[ $before == "$after" && $(wc -l < "$PAMU_FIXTURE_CALLS") == "$pamu_calls_before" ]] \
  || fail 'enabling Hyprlock re-registered the key or changed the existing setup'
cmp "$repo_root/system/pam.d/hyprlock" "$test_root/etc/pam.d/hyprlock" \
  || fail 'setup --with-hyprlock did not deploy Hyprlock with an existing mapping'

before=$(sha256sum "$test_root/etc/u2f_mappings")
YUBIKEY_AUTH_FIDO2_TOKEN=/nonexistent YUBIKEY_AUTH_PAMU2FCFG=/nonexistent \
  "$auth" remove --dry-run > "$test_root/remove-dry-run.out"
grep -Fq 'would revoke: last registered key' "$test_root/remove-dry-run.out" \
  || fail 'remove dry-run did not report the key it would revoke'
if printf 'no\n' | "$auth" remove > "$test_root/remove-cancel.out" 2>&1; then
  fail 'remove accepted the wrong confirmation'
fi
[[ $(sha256sum "$test_root/etc/u2f_mappings") == "$before" ]] \
  || fail 'remove dry-run or cancelled removal changed the mapping'
backups_before=$(find "$test_root/etc" -maxdepth 1 -name 'u2f_mappings.pre-yubikey.*' | wc -l)
printf 'REMOVE LAST KEY\n' | "$auth" remove > "$test_root/remove-one.out"
expected='liam:first-handle,first-public-key,es256,+verification:second-handle,second-public-key,es256,+verification'
[[ $(<"$test_root/etc/u2f_mappings") == "$expected" ]] \
  || fail 'remove did not revoke only the final credential'
[[ $(find "$test_root/etc" -maxdepth 1 -name 'u2f_mappings.pre-yubikey.*' | wc -l) -gt $backups_before ]] \
  || fail 'remove did not back up the mapping'
printf 'REMOVE LAST KEY\n' | "$auth" remove > "$test_root/remove-two.out"
printf 'REMOVE LAST KEY\n' | "$auth" remove > "$test_root/remove-last.out"
[[ ! -e $test_root/etc/u2f_mappings ]] \
  || fail 'remove left a mapping with no credentials'
cmp "$repo_root/system/pam.d/sudo" "$test_root/etc/pam.d/sudo" \
  || fail 'remove changed the sudo PAM fallback'

if FIDO_FIXTURE_MULTIPLE=1 "$auth" add --dry-run > "$test_root/multiple.out" 2>&1; then
  fail 'multiple-device auto-detection did not fail closed'
fi
grep -Fq 'multiple YubiKeys found' "$test_root/multiple.out" \
  || fail 'multiple-device failure was not actionable'

command -v zsh >/dev/null 2>&1 || {
  printf 'skip: zsh is not installed\n'
  exit 0
}

mkdir -p "$test_root/zsh-bin"
cp "$auth" "$test_root/zsh-bin/yubikey-auth"
zsh_integration="$repo_root/security/.config/yubikey-auth/shell.zsh"
PATH="$test_root/zsh-bin:$PATH" zsh -f -c '
  source "$1"
  [[ $aliases[yubi] == "yubikey-auth" ]]
  [[ $aliases[yubi-status] == "yubikey-auth status" ]]
  [[ $aliases[yubi-setup] == "yubikey-auth setup" ]]
  [[ $aliases[yubi-add] == "yubikey-auth add" ]]
' _ "$zsh_integration" || fail 'Zsh shortcuts were not defined as expected'

PATH="$test_root/zsh-bin:$PATH" zsh -f -c '
  alias yubi-setup="existing setup"
  yubi-add() { print existing-add; }
  source "$1"
  [[ $aliases[yubi-setup] == "existing setup" ]]
  [[ "$(whence -w yubi-add)" == "yubi-add: function" ]]
' _ "$zsh_integration" || fail 'Zsh integration overwrote an existing name'

printf 'ok: YubiKey auth fixtures\n'
