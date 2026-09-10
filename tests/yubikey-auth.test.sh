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
    printf '/dev/hidraw-test: vendor=0x1050, product=0x0402 (Yubico YubiKey FIDO)\n'
    if [[ ${FIDO_FIXTURE_MULTIPLE:-0} == 1 ]]; then
      printf '/dev/hidraw-other: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO)\n'
    fi
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
  cat|cp) exec "$@" ;;
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

printf 'invalid terminal bytes\033[0m\n' > "$test_root/etc/u2f_mappings"
printf 'old sudo pam\n' > "$test_root/etc/pam.d/sudo"
printf 'old hyprlock pam\n' > "$test_root/etc/pam.d/hyprlock"

"$auth" setup --enroll-fingerprint --confirm-sudo-tested > "$test_root/setup.out"
grep -Fq 'liam:first-handle,first-public-key,es256,+verification' \
  "$test_root/etc/u2f_mappings" || fail 'setup did not install the first mapping'
cmp "$repo_root/system/pam.d/sudo" "$test_root/etc/pam.d/sudo" \
  || fail 'setup did not install the sudo PAM template'
cmp "$repo_root/system/pam.d/hyprlock" "$test_root/etc/pam.d/hyprlock" \
  || fail 'setup did not install the Hyprlock PAM template'
grep -Fq -- '-S -e /dev/hidraw-test' "$FIDO_FIXTURE_CALLS" \
  || fail 'Bio enrollment did not call the fingerprint command'
grep -Fq -- '-V' "$PAMU_FIXTURE_CALLS" \
  || fail 'Bio setup did not require user verification'
find "$test_root/etc" -maxdepth 2 -name '*.pre-yubikey.*' | grep -q . \
  || fail 'setup did not retain recovery backups'
[[ $(stat -c '%a' "$test_root/etc/u2f_mappings") == 600 ]] \
  || fail 'mapping permissions are not 0600'

"$auth" add > "$test_root/add.out"
expected='liam:first-handle,first-public-key,es256,+verification:second-handle,second-public-key,es256,+verification'
[[ $(<"$test_root/etc/u2f_mappings") == "$expected" ]] \
  || fail 'additional credential was not appended to the existing user line'
grep -Fq -- '-n ' "$PAMU_FIXTURE_CALLS" \
  || fail 'additional registration did not omit the duplicate username'
[[ $(find "$test_root/etc" -maxdepth 1 -name 'u2f_mappings.pre-yubikey.*' | wc -l) -ge 2 ]] \
  || fail 'same-second updates did not preserve distinct mapping backups'

before=$(sha256sum "$test_root/etc/u2f_mappings" "$test_root/etc/pam.d/sudo" "$test_root/etc/pam.d/hyprlock")
"$auth" setup --dry-run --enroll-fingerprint > "$test_root/dry-run.out"
after=$(sha256sum "$test_root/etc/u2f_mappings" "$test_root/etc/pam.d/sudo" "$test_root/etc/pam.d/hyprlock")
[[ $before == "$after" ]] || fail 'dry-run changed authentication state'
grep -Fq 'would enroll: fingerprint' "$test_root/dry-run.out" \
  || fail 'dry-run did not report fingerprint enrollment'

: > "$PAMU_FIXTURE_CALLS"
"$auth" add --mode pin > "$test_root/pin.out"
grep -Fq -- '-N' "$PAMU_FIXTURE_CALLS" || fail 'PIN mode did not request PIN verification'
! grep -Fq -- '-V' "$PAMU_FIXTURE_CALLS" || fail 'PIN mode also requested biometric verification'

"$auth" status > "$test_root/status.out"
grep -Fq 'mapping: valid for liam' "$test_root/status.out" \
  || fail 'status did not recognize the valid mapping'
grep -Fq 'pam: deployed' "$test_root/status.out" \
  || fail 'status did not recognize deployed PAM templates'

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
  [[ $aliases[yubi-setup] == "yubikey-auth setup --enroll-fingerprint" ]]
  [[ $aliases[yubi-add] == "yubikey-auth add --enroll-fingerprint" ]]
' _ "$zsh_integration" || fail 'Zsh shortcuts were not defined as expected'

PATH="$test_root/zsh-bin:$PATH" zsh -f -c '
  alias yubi-setup="existing setup"
  yubi-add() { print existing-add; }
  source "$1"
  [[ $aliases[yubi-setup] == "existing setup" ]]
  [[ "$(whence -w yubi-add)" == "yubi-add: function" ]]
' _ "$zsh_integration" || fail 'Zsh integration overwrote an existing name'

printf 'ok: YubiKey auth fixtures\n'
