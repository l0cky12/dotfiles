#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
auth="$repo_root/security/.local/bin/fingerprint-auth"
test_root=$(mktemp -d -t fingerprint-auth-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

contains() {
  grep -Fq -- "$2" <<<"$1" || fail "$3"
}

mkdir -p "$test_root/bin"

# --------------------------------------------------------------- fixtures ---

# A sysfs-shaped USB tree. Only idVendor/idProduct/product are read.
make_usb_tree() {
  local root=$1; shift
  rm -rf -- "$root"
  mkdir -p "$root/1-0:1.0"
  printf '1d6b\n' > "$root/1-0:1.0/idVendor"
  printf '0002\n' > "$root/1-0:1.0/idProduct"
  printf 'xHCI Host Controller\n' > "$root/1-0:1.0/product"
  if [[ ${1:-} == --with-reader ]]; then
    mkdir -p "$root/1-4"
    printf '27c6\n' > "$root/1-4/idVendor"
    printf '609c\n' > "$root/1-4/idProduct"
    printf 'Goodix USB2.0 MISC\n' > "$root/1-4/product"
  fi
}

usb_bare="$test_root/usb-bare"
usb_reader="$test_root/usb-reader"
make_usb_tree "$usb_bare"
make_usb_tree "$usb_reader" --with-reader

cat > "$test_root/bin/fprintd-list" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FPRINT_FIXTURE_CALLS"
if [[ ${FPRINT_FIXTURE_NO_DEVICE:-0} == 1 ]]; then
  printf 'Impossible to enumerate devices: No devices available\n' >&2
  exit 1
fi
if [[ ${FPRINT_FIXTURE_DBUS_ERROR:-0} == 1 ]]; then
  printf 'Failed to connect to bus\n' >&2
  exit 1
fi
if [[ -n ${FPRINT_FIXTURE_ERROR:-} ]]; then
  printf '%s\n' "$FPRINT_FIXTURE_ERROR" >&2
  exit 1
fi
printf 'found 1 devices\n'
printf 'Devices for user %s:\n' "${1:-liam}"
if [[ -s ${FPRINT_FIXTURE_ENROLLED:-/dev/null} ]]; then
  i=0
  while read -r finger; do
    printf ' - #%d: %s\n' "$i" "$finger"
    i=$((i + 1))
  done < "$FPRINT_FIXTURE_ENROLLED"
fi
SH

cat > "$test_root/bin/fprintd-enroll" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FPRINT_FIXTURE_CALLS"
[[ ${FPRINT_FIXTURE_ENROLL_FAIL:-0} == 0 ]] || exit 1
# What fprintd-enroll prints when polkit had no agent to ask for the password.
if [[ ${FPRINT_FIXTURE_ENROLL_DENIED:-0} == 1 ]]; then
  printf 'Using device /net/reactivated/Fprint/Device/0\n'
  printf 'EnrollStart failed: GDBus.Error:net.reactivated.Fprint.Error.PermissionDenied: Not Authorized: net.reactivated.fprint.device.enroll\n'
  exit 1
fi
finger=right-index-finger
while (($#)); do
  case $1 in
    -f) finger=$2; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n' "$finger" >> "$FPRINT_FIXTURE_ENROLLED"
printf 'Enroll result: enroll-completed\n'
SH

cat > "$test_root/bin/fprintd-delete" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FPRINT_FIXTURE_CALLS"
: > "$FPRINT_FIXTURE_ENROLLED"
SH

cat > "$test_root/bin/fprintd-verify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FPRINT_FIXTURE_CALLS"
printf 'Verify result: verify-match (done)\n'
SH

cat > "$test_root/bin/sudo-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FPRINT_FIXTURE_ROOT_CALLS"
if [[ ${1##*/} == pacman-fixture ]]; then exec "$@"; fi
if [[ $1 == install ]]; then
  shift
  args=()
  while (($#)); do
    case $1 in
      -o|-g) shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  [[ ${FPRINT_FIXTURE_INSTALL_FAIL:-0} == 0 ]] || exit 1
  exec install "${args[@]}"
fi
case $1 in
  cp|mktemp|mv|rm) exec "$@" ;;
  *) exit 2 ;;
esac
SH

# "Installs" fprintd by copying the fake fprintd tools to where the script
# looks for them. Like the real pacman, it needs a terminal to confirm on.
cat > "$test_root/bin/pacman-fixture" <<'SH'
#!/usr/bin/env bash
if [[ ! -t 0 ]]; then
  printf 'pacman fixture ran without a terminal\n' >&2
  exit 2
fi
if [[ $* != '-S --needed fprintd' ]]; then
  printf 'unexpected pacman arguments: %s\n' "$*" >&2
  exit 2
fi
if [[ ${FPRINT_FIXTURE_PACMAN_FAIL:-0} == 1 ]]; then
  printf 'error: failed retrieving file fprintd-1.94.5-2-x86_64.pkg.tar.zst\n' >&2
  exit 1
fi
mkdir -p "$FPRINT_FIXTURE_INSTALLED"
cp "$FPRINT_FIXTURE_TOOLS"/fprintd-* "$FPRINT_FIXTURE_INSTALLED"/
SH

chmod +x "$test_root"/bin/*

make_hyprlock_conf() {
  local path=$1
  cat > "$path" <<'CONF'
$hyprlockDir = $HOME/.config/hyprlock

auth {
    pam:enabled = true
    pam:module = hyprlock
    fingerprint:enabled = false
}
CONF
}

reset_state() {
  rm -rf -- "${test_root:?}/etc"
  mkdir -p "$test_root/etc/pam.d"
  for service in sudo doas greetd; do
    printf 'old %s pam\n' "$service" > "$test_root/etc/pam.d/$service"
  done
  : > "$test_root/calls"
  : > "$test_root/enrolled"
  : > "$test_root/root-calls"
  rm -rf -- "$test_root/installed"
  make_hyprlock_conf "$test_root/hyprlock.conf"
}

export FINGERPRINT_AUTH_ETC_ROOT="$test_root/etc"
export FINGERPRINT_AUTH_PAM_MODULE="$test_root/pam_fprintd.so"
: > "$FINGERPRINT_AUTH_PAM_MODULE"
export FPRINT_FIXTURE_CALLS="$test_root/calls"
export FPRINT_FIXTURE_ENROLLED="$test_root/enrolled"
export FPRINT_FIXTURE_ROOT_CALLS="$test_root/root-calls"
export FPRINT_FIXTURE_TOOLS="$test_root/bin"
export FPRINT_FIXTURE_INSTALLED="$test_root/installed"
export FINGERPRINT_AUTH_USER=testuser
export FINGERPRINT_AUTH_HYPRLOCK_CONF="$test_root/hyprlock.conf"
export FINGERPRINT_AUTH_SUDO="$test_root/bin/sudo-fixture"
export FINGERPRINT_AUTH_PACMAN="$test_root/bin/pacman-fixture"

with_fprintd() { PATH="$test_root/bin:$PATH" "$@" --confirm-escalation-tested; }

# Point the tool names into a directory that starts out empty, so `command -v`
# fails the same way it does on a machine where fprintd was never installed.
# The pacman fixture fills it in.
without_fprintd() {
  FINGERPRINT_AUTH_FPRINTD_ENROLL="$test_root/installed/fprintd-enroll" \
  FINGERPRINT_AUTH_FPRINTD_LIST="$test_root/installed/fprintd-list" \
  FINGERPRINT_AUTH_FPRINTD_DELETE="$test_root/installed/fprintd-delete" \
  FINGERPRINT_AUTH_FPRINTD_VERIFY="$test_root/installed/fprintd-verify" \
  "$@"
}

# Run a command on a pseudo-terminal, the way it runs when someone types it,
# whatever stdin this test itself was given. script(1) passes the exit status
# through; its output ends lines with CRLF, which the substring checks ignore.
command -v script >/dev/null 2>&1 || fail "script(1) from util-linux is needed for the fixture terminal"
with_terminal() {
  SHELL=$(command -v bash) script -qec "$(printf '%q ' "$@")" /dev/null </dev/null
}

# ------------------------------------------------------------------ tests ---

# 1. The headline requirement from the issue: no reader must produce a clear
#    message, not a crash, and must leave the machine alone.
reset_state
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_bare" without_fprintd "$auth" status 2>&1) \
  || fail "status exited non-zero on a machine with no reader"
contains "$out" 'usb reader: none detected' "status did not report a missing reader"
contains "$out" 'fprintd device: unknown' "status did not report fprintd as absent"
contains "$out" 'hyprlock fingerprint: disabled' "status misread the hyprlock config"
contains "$out" 'MISSING' "status did not flag the missing fprintd tools"

# 2. setup on a machine with no reader: fails closed, explains why, installs
#    and changes nothing.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_bare" without_fprintd "$auth" setup 2>&1); then
  fail "setup succeeded on a machine with no fingerprint reader"
fi
contains "$out" 'no fingerprint reader was detected' "setup gave no clear no-reader message"
contains "$out" 'pacman -S --needed fprintd' "setup did not name the install command"
[[ ! -s $test_root/root-calls ]] || fail "setup installed fprintd with no reader present"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "setup modified hyprlock.conf despite having no reader"
[[ ! -s $test_root/enrolled ]] || fail "setup enrolled a finger with no reader present"

# 3. Reader on USB but fprintd not installed: name the device, install fprintd
#    through the escalation command, then carry on to enroll and wire Hyprlock.
reset_state
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" without_fprintd with_terminal "$auth" setup --confirm-escalation-tested 2>&1) \
  || fail "setup did not install fprintd and carry on: $out"
contains "$out" '27c6:609c' "setup did not identify the detected reader"
contains "$out" 'fprintd is not installed' "setup did not explain that fprintd is missing"
[[ $(head -n 1 "$test_root/root-calls") == "$test_root/bin/pacman-fixture -S --needed fprintd" ]] \
  || fail "setup did not run exactly 'pacman -S --needed fprintd' as root"
contains "$out" 'Enrolled right-index-finger' "setup stopped after installing fprintd"
grep -q 'fingerprint:enabled = true' "$test_root/hyprlock.conf" \
  || fail "setup did not wire Hyprlock after installing fprintd"

# 3a. With no terminal to confirm on, setup stops before doas, sudo, or pacman
#     and prints the command to run by hand.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" without_fprintd "$auth" setup 2>&1 </dev/null); then
  fail "setup succeeded with no terminal to confirm the fprintd install"
fi
contains "$out" 'no terminal is attached' "setup did not explain why it stopped without a terminal"
contains "$out" "$test_root/bin/sudo-fixture pacman -S --needed fprintd" \
  "setup did not print the manual install command with the privilege command"
[[ ! -s $test_root/root-calls ]] || fail "setup ran the privilege command without a terminal"
[[ ! -e $test_root/installed ]] || fail "setup installed fprintd without a terminal"
[[ ! -s $test_root/enrolled ]] || fail "setup enrolled a finger without a terminal"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "setup changed hyprlock.conf without a terminal"

# 3b. A declined or failed install stops before enrolling and keeps the manual
#     command in view.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" FPRINT_FIXTURE_PACMAN_FAIL=1 \
  without_fprintd with_terminal "$auth" setup 2>&1); then
  fail "setup succeeded although pacman did not install fprintd"
fi
contains "$out" 'fprintd was not installed' "setup did not report the failed install"
contains "$out" 'pacman -Syu' "setup did not suggest a full upgrade after a failed download"
contains "$out" 'pacman -S --needed fprintd' "setup did not keep the manual install command"
[[ ! -s $test_root/enrolled ]] || fail "setup enrolled a finger after a failed install"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "setup changed hyprlock.conf after a failed install"

# 3c. Only setup installs. enroll and status point at it instead.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" without_fprintd "$auth" enroll 2>&1); then
  fail "enroll succeeded without fprintd installed"
fi
contains "$out" "Run 'fingerprint-auth setup' first" "enroll did not point at setup"
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" without_fprintd "$auth" status 2>&1) \
  || fail "status failed with a reader but no fprintd"
contains "$out" 'Next step: fingerprint-auth setup  (installs fprintd first)' \
  "status did not point at setup"
[[ ! -s $test_root/root-calls ]] || fail "enroll or status tried to install fprintd"

# 3d. fprintd refuses to enroll because no polkit agent asked for the password:
#     stop before Hyprlock and say how to start one.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" FPRINT_FIXTURE_ENROLL_DENIED=1 \
  with_fprintd "$auth" setup 2>&1); then
  fail "setup succeeded although fprintd refused to enroll"
fi
contains "$out" 'Not Authorized: net.reactivated.fprint.device.enroll' \
  "the fprintd error did not reach the user"
contains "$out" 'systemctl --user start hyprpolkitagent.service' \
  "setup did not say how to start a polkit agent"
[[ ! -s $test_root/enrolled ]] || fail "a refused enrollment was recorded"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "setup wired Hyprlock after a refused enrollment"

# 4. fprintd installed but reporting no device.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_bare" FPRINT_FIXTURE_NO_DEVICE=1 \
  with_fprintd "$auth" setup 2>&1); then
  fail "setup succeeded while fprintd reported no device"
fi
contains "$out" 'no fingerprint reader found' "setup gave no clear message for an empty fprintd"

reset_state
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_bare" FPRINT_FIXTURE_DBUS_ERROR=1 \
  with_fprintd "$auth" status 2>&1) || fail 'status failed on a D-Bus error'
contains "$out" 'fprintd device: error (Failed to connect to bus)' \
  'status reported a broken fprintd service as an available reader'
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_bare" FPRINT_FIXTURE_DBUS_ERROR=1 \
  with_fprintd "$auth" setup 2>&1); then
  fail 'setup continued after fprintd-list failed'
fi
contains "$out" 'fprintd-list failed: Failed to connect to bus' \
  'setup did not explain the fprintd service failure'
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" ||
  fail 'setup changed Hyprlock after fprintd-list failed'

# 5. Happy path: enroll and wire hyprlock.
reset_state
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" setup 2>&1) \
  || fail "setup failed on a machine with a working reader"
contains "$out" 'Enrolled right-index-finger' "setup did not report the enrollment"
grep -Fq -- '-f right-index-finger testuser' "$test_root/calls" \
  || fail "setup did not call fprintd-enroll with the finger and user"
grep -q 'fingerprint:enabled = true' "$test_root/hyprlock.conf" \
  || fail "setup did not enable fingerprint unlock in hyprlock.conf"
grep -q 'pam:module = hyprlock' "$test_root/hyprlock.conf" \
  || fail "setup damaged the rest of the hyprlock auth block"

# 6. Idempotent: a second setup re-enrolls nothing and re-writes nothing.
before=$(cat "$test_root/hyprlock.conf")
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" setup 2>&1) \
  || fail "second setup failed"
contains "$out" 'already enrolled' "second setup re-enrolled an existing finger"
contains "$out" 'already enabled' "second setup rewrote an already-enabled config"
[[ $before == $(cat "$test_root/hyprlock.conf") ]] \
  || fail "second setup changed hyprlock.conf"

# 7. status surfaces enrolled fingers.
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" status 2>&1) \
  || fail "status failed on a configured machine"
contains "$out" 'enrolled: right-index-finger' "status did not list the enrolled finger"
contains "$out" 'hyprlock fingerprint: enabled' "status did not see the enabled config"

# 8. --dry-run reports without touching prints or config.
reset_state
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" setup --dry-run 2>&1) \
  || fail "dry-run setup failed"
contains "$out" 'would enroll: right-index-finger' "dry run did not report the enrollment"
contains "$out" 'would enable' "dry run did not report the hyprlock change"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "dry run modified hyprlock.conf"
[[ ! -s $test_root/enrolled ]] || fail "dry run enrolled a finger"

# 8b. A dry run on a host that still needs fprintd reports the install and the
#     rest of the plan, and installs nothing.
reset_state
out=$(FINGERPRINT_AUTH_PAM_MODULE="$test_root/missing-pam_fprintd.so" \
  FINGERPRINT_AUTH_USB_ROOT="$usb_reader" without_fprintd "$auth" setup --dry-run 2>&1) \
  || fail "dry-run setup failed without fprintd: $out"
contains "$out" 'would install: fprintd' "dry run did not report the fprintd install"
contains "$out" 'would enroll: right-index-finger' "dry run stopped at the fprintd install"
contains "$out" 'would enable' "dry run did not report the hyprlock change"
[[ ! -s $test_root/root-calls ]] || fail "dry run ran the install"
[[ ! -e $test_root/installed ]] || fail "dry run installed fprintd"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "dry run without fprintd modified hyprlock.conf"

# 9. --no-hyprlock --no-pam enrolls only.
reset_state
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" setup --no-hyprlock --no-pam 2>&1) \
  || fail "setup --no-hyprlock failed"
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" \
  || fail "--no-hyprlock still rewrote hyprlock.conf"
[[ -s $test_root/enrolled ]] || fail "--no-hyprlock skipped enrollment too"

# 10. Bad input is rejected before any device work happens.
reset_state
if out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd \
  "$auth" setup --finger thumb 2>&1); then
  fail "setup accepted an invalid finger name"
fi
contains "$out" "invalid finger 'thumb'" "no clear message for an invalid finger"
[[ ! -s $test_root/enrolled ]] || fail "invalid finger still reached fprintd-enroll"

if out=$("$auth" --bogus 2>&1); then
  fail "the tool accepted an unknown argument"
fi
contains "$out" 'unknown argument: --bogus' "no clear message for an unknown argument"

# 11. No action prints usage and exits 2, like yubikey-auth.
set +e
"$auth" >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 2 ]] || fail "expected exit 2 with no action, got $status"

# 12. delete clears prints and leaves the lockscreen config alone.
reset_state
FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" setup >/dev/null 2>&1
out=$(FINGERPRINT_AUTH_USB_ROOT="$usb_reader" with_fprintd "$auth" delete 2>&1) \
  || fail "delete failed"
[[ ! -s $test_root/enrolled ]] || fail "delete left fingerprints enrolled"
grep -q 'fingerprint:enabled = true' "$test_root/hyprlock.conf" \
  || fail "delete unexpectedly changed hyprlock.conf"

# Errors must not turn into available devices or start enrollment/deployment.
for error in 'Failed to connect to session bus: connection refused' \
             'Impossible to get devices: daemon unavailable' \
             'ListEnrolledFingers failed: permission denied'; do
  reset_state
  out=$(FPRINT_FIXTURE_ERROR="$error" with_fprintd "$auth" status)
  contains "$out" 'fprintd device: error' 'query failure reported as a reader'
  if out=$(FPRINT_FIXTURE_ERROR="$error" with_fprintd "$auth" setup 2>&1); then
    fail 'setup accepted a failed device query'
  fi
  contains "$out" "$error" 'query diagnostic was lost'
  [[ ! -s $test_root/enrolled && ! -s $test_root/root-calls ]] || fail 'query failure mutated state'
done

# Missing, ambiguous, or unsupported Hyprlock keys fail before enrollment.
for state in missing absent duplicate invalid; do
  reset_state
  case $state in
    missing) rm "$test_root/hyprlock.conf" ;;
    absent) printf 'auth {\n}\n' > "$test_root/hyprlock.conf" ;;
    duplicate) printf 'fingerprint:enabled = false\n' >> "$test_root/hyprlock.conf" ;;
    invalid) sed -i 's/= false/= perhaps/' "$test_root/hyprlock.conf" ;;
  esac
  if out=$(with_fprintd "$auth" setup 2>&1); then fail "accepted $state config"; fi
  [[ ! -s $test_root/enrolled && ! -s $test_root/root-calls ]] || fail "$state config mutated state"
done

reset_state
out=$(with_fprintd "$auth" setup)
for service in sudo doas greetd; do
  target="$test_root/etc/pam.d/$service"
  cmp "$repo_root/system/pam.d/$service" "$target" || fail "$service template not deployed"
  backups=("$target".pre-fingerprint.*)
  [[ ${#backups[@]} == 1 ]] || fail "$service missing backup"
  [[ $(cat "${backups[0]}") == "old $service pam" ]] || fail "$service backup content lost"
  [[ $(stat -c %a "$target") == 644 ]] || fail "$service has incorrect permissions"
done
: > "$test_root/root-calls"
out=$(with_fprintd "$auth" setup)
[[ ! -s $test_root/root-calls ]] || fail 'second setup redeployed PAM'
out=$(with_fprintd "$auth" status)
contains "$out" 'pam greetd: configured' 'status lost PAM deployment state'

reset_state
out=$(with_fprintd "$auth" setup --dry-run)
contains "$out" 'would back up and deploy:' 'dry-run omitted PAM plan'
[[ ! -s $test_root/root-calls ]] || fail 'dry-run invoked privilege escalation'
for service in sudo doas greetd; do
  [[ $(cat "$test_root/etc/pam.d/$service") == "old $service pam" ]] || fail 'dry-run changed PAM'
done

reset_state
if out=$(FINGERPRINT_AUTH_PAM_MODULE="$test_root/missing.so" with_fprintd "$auth" setup 2>&1); then
  fail 'setup succeeded without PAM module'
fi
[[ ! -s $test_root/enrolled && ! -s $test_root/root-calls ]] || fail 'missing module mutated state'

reset_state
if out=$(FPRINT_FIXTURE_ENROLL_FAIL=1 with_fprintd "$auth" setup 2>&1); then
  fail 'setup accepted failed enrollment'
fi
[[ ! -s $test_root/root-calls ]] || fail 'failed enrollment deployed PAM'
grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" || fail 'failed enrollment wired Hyprlock'

# Without a terminal/checkpoint override, fail before any changes.
reset_state
if out=$(PATH="$test_root/bin:$PATH" "$auth" setup </dev/null 2>&1); then
  fail 'noninteractive setup skipped login checkpoint'
fi
[[ ! -s $test_root/enrolled && ! -s $test_root/root-calls ]] || fail 'checkpoint preflight mutated state'

# An install failure must preserve the original destination and its backup.
if (( EUID != 0 )); then
  reset_state
  if out=$(FPRINT_FIXTURE_INSTALL_FAIL=1 with_fprintd "$auth" setup 2>&1); then
    fail 'setup accepted PAM installation failure'
  fi
  [[ $(cat "$test_root/etc/pam.d/sudo") == 'old sudo pam' ]] || fail 'failed install damaged sudo'
  [[ $(cat "$test_root/etc/pam.d/greetd") == 'old greetd pam' ]] || fail 'failed install changed login'
  grep -q 'fingerprint:enabled = false' "$test_root/hyprlock.conf" || fail 'failed install wired Hyprlock'
fi

# 13. Without an override the install goes through doas when it exists and
#     sudo otherwise. The PATH here holds only the tools the script needs plus
#     fake doas and sudo, so the real ones can be neither picked nor run.
#     Root needs no escalation command at all, so skip this as root.
if (( EUID != 0 )); then
  escalation_bin="$test_root/escalation-bin"
  mkdir -p "$escalation_bin"
  for tool in bash readlink dirname grep sed cat rm mktemp tr id; do
    ln -s "$(command -v "$tool")" "$escalation_bin/$tool"
  done
  for tool in doas sudo; do
    printf '#!/bin/sh\necho "unexpected %s call" >&2\nexit 2\n' "$tool" > "$escalation_bin/$tool"
    chmod +x "$escalation_bin/$tool"
  done
  no_override() {
    without_fprintd env -u FINGERPRINT_AUTH_SUDO PATH="$escalation_bin" \
      FINGERPRINT_AUTH_USB_ROOT="$usb_reader" "$@"
  }

  reset_state
  out=$(no_override "$auth" setup --dry-run 2>&1) || fail "dry run failed with fake doas and sudo: $out"
  contains "$out" 'would install: fprintd (doas pacman -S --needed fprintd)' \
    "setup did not prefer doas over sudo"

  rm -- "$escalation_bin/doas"
  out=$(no_override "$auth" setup --dry-run 2>&1) || fail "dry run failed with only fake sudo: $out"
  contains "$out" 'would install: fprintd (sudo pacman -S --needed fprintd)' \
    "setup did not fall back to sudo without doas"

  rm -- "$escalation_bin/sudo"
  if out=$(no_override "$auth" setup 2>&1 </dev/null); then
    fail "setup succeeded with neither doas nor sudo"
  fi
  contains "$out" 'found neither doas nor sudo' "setup gave no clear message without doas or sudo"
  [[ ! -e $test_root/installed ]] || fail "setup installed fprintd without doas or sudo"
fi

printf 'PASS: fingerprint-auth\n'
