#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/windows/.local/bin/windows-vm"
compose_file="$repo_root/windows/.local/share/windows-vm/compose.yaml"
test_root=$(mktemp -d -t windows-vm-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"; }

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/runtime" "$test_root/config"
calls="$test_root/calls"
: > "$calls"

cat > "$test_root/bin/docker" <<'SH'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$WINDOWS_VM_TEST_CALLS"
if [[ "${WINDOWS_VM_TEST_VALIDATE_COMPOSE:-0}" == 1 && " $* " == *' up --detach windows '* ]]; then
  args=("$@")
  config_args=()
  for arg in "${args[@]}"; do
    if [[ "$arg" == up ]]; then
      config_args+=(config --quiet)
      break
    fi
    config_args+=("$arg")
  done
  exec /usr/bin/docker "${config_args[@]}"
fi
case "${1:-} ${2:-}" in
  'compose version') printf 'Docker Compose version fixture\n' ;;
  'info ') exit 0 ;;
  'ps --all') printf 'fixture-container\n' ;;
  'inspect --format')
    if [[ -r "${WINDOWS_VM_TEST_STATE_FILE:-}" ]]; then
      cat "$WINDOWS_VM_TEST_STATE_FILE"
    else
      printf '%s\n' "${WINDOWS_VM_TEST_CONTAINER_STATUS:-running}"
    fi
    ;;
  'compose --project-name')
    if [[ " $* " == *' up --detach windows '* && -n "${WINDOWS_VM_TEST_STATE_FILE:-}" ]]; then
      printf 'running\n' > "$WINDOWS_VM_TEST_STATE_FILE"
    fi
    case " $* " in
      *' ps -q windows '*) printf 'fixture-container\n' ;;
      *' config --quiet '*) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
esac
SH
cat > "$test_root/bin/sdl-freerdp3" <<'SH'
#!/usr/bin/env bash
printf 'rdp %s\n' "$*" >> "$WINDOWS_VM_TEST_CALLS"
cat >/dev/null || true
[[ " $* " != *' +auth-only '* ]] || exit 0
exit "${WINDOWS_VM_TEST_RDP_STATUS:-0}"
SH
cat > "$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '[{"name":"DP-1","focused":true,"scale":%s}]\n' "${WINDOWS_VM_TEST_SCALE:-1}"
SH
cat > "$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf 'notify %s\n' "$*" >> "$WINDOWS_VM_TEST_CALLS"
SH
cat > "$test_root/bin/kitty" <<'SH'
#!/usr/bin/env bash
printf 'kitty %s\n' "$*" >> "$WINDOWS_VM_TEST_CALLS"
SH
cat > "$test_root/bin/xdg-open" <<'SH'
#!/usr/bin/env bash
printf 'xdg-open %s\n' "$*" >> "$WINDOWS_VM_TEST_CALLS"
SH
cat > "$test_root/bin/df" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' \
  '/dev/fixture 2147483648 1 2147483647 1% /fixture'
SH
cat > "$test_root/bin/timeout" <<'SH'
#!/usr/bin/env bash
shift
if [[ "${1:-}" == bash ]]; then
  exit "${WINDOWS_VM_TEST_PORT_STATUS:-1}"
fi
exec "$@"
SH
chmod +x "$test_root/bin/"*

export HOME="$test_root/home"
export PATH="$test_root/bin:/usr/bin"
export WINDOWS_VM_TEST_CALLS="$calls"
export WINDOWS_VM_CONFIG_DIR="$test_root/config"
export WINDOWS_VM_DATA_DIR="$repo_root/windows/.local/share/windows-vm"
export WINDOWS_VM_RUNTIME_DIR="$test_root/runtime"
export WINDOWS_VM_STORAGE_DIR="$test_root/home/.windows"
export WINDOWS_VM_SHARE_DIR="$test_root/home/Windows"
export WINDOWS_VM_NONINTERACTIVE=1
export WINDOWS_VM_INSTALL_PASSWORD="fixture 'secret'"

# A missing setup routes the main entry point to the configured terminal.
WINDOWS_VM_DRY_RUN=1 "$helper" launch > "$test_root/missing.out" 2>&1
assert_contains "$test_root/missing.out" 'kitty'
[[ ! -e "$WINDOWS_VM_CONFIG_DIR/settings.env" ]] || fail 'dry-run launch wrote configuration'

# Install dry-run is side-effect free and reports all managed paths. The real
# dependency gate (KVM, /dev/net/tun) runs before the dry-run branch, so on
# hosts without virtualization devices this check is skipped entirely.
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm && -c /dev/net/tun ]]; then
WINDOWS_VM_DRY_RUN=1 "$helper" install > "$test_root/install-dry.out" 2>&1
assert_contains "$test_root/install-dry.out" "$WINDOWS_VM_STORAGE_DIR"
[[ ! -e "$WINDOWS_VM_CONFIG_DIR/settings.env" ]] || fail 'install dry-run wrote settings'
fi

# A fixture install writes only under the temporary HOME and starts fake Docker.
# check_install_prerequisites requires /dev/kvm and /dev/net/tun, which do not
# exist in containers or VMs without nested virtualization, so the fixture
# install section is skipped there. The dry-run checks above stay active.
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm && -c /dev/net/tun ]]; then
WINDOWS_VM_TEST_VALIDATE_COMPOSE=1 "$helper" install > "$test_root/install.out" 2>&1
[[ -d "$WINDOWS_VM_STORAGE_DIR" && -d "$WINDOWS_VM_SHARE_DIR" ]] || fail 'install did not create managed directories'
[[ $(stat -c %a "$WINDOWS_VM_CONFIG_DIR/settings.env") == 600 ]] || fail 'settings are not mode 0600'
[[ $(stat -c %a "$WINDOWS_VM_CONFIG_DIR/credentials.env") == 600 ]] || fail 'credentials are not mode 0600'
grep -Fq 'WINDOWS_PASSWORD_B64=' "$WINDOWS_VM_CONFIG_DIR/credentials.env" || fail 'password was not encoded'
grep -Fq "fixture 'secret'" "$WINDOWS_VM_CONFIG_DIR/credentials.env" && fail 'plaintext password was written'
printf 'WINDOWS_START_TIMEOUT=1\n' >> "$WINDOWS_VM_CONFIG_DIR/settings.env"
export WINDOWS_VM_TEST_PORT_STATUS=0

# Compose must expose only localhost and only the intended host paths.
runtime_env="$test_root/container.env"
printf 'USERNAME=liam\nPASSWORD=fixture\n' > "$runtime_env"
WINDOWS_VM_CONTAINER_ENV="$runtime_env" docker compose \
  --env-file "$WINDOWS_VM_CONFIG_DIR/settings.env" -f "$compose_file" config --quiet
assert_contains "$compose_file" '127.0.0.1:${WINDOWS_WEB_PORT:-8006}:8006/tcp'
assert_contains "$compose_file" '127.0.0.1:${WINDOWS_RDP_PORT:-3389}:3389/tcp'
assert_contains "$compose_file" '${WINDOWS_SHARE_DIR:?windows-vm must provide its shared directory}:/shared'
assert_contains "$compose_file" '${WINDOWS_OEM_DIR:-./oem}:/oem:ro'
assert_contains "$WINDOWS_VM_CONFIG_DIR/settings.env" "WINDOWS_OEM_DIR=$WINDOWS_VM_DATA_DIR/oem"
assert_contains "$repo_root/windows/.local/share/windows-vm/oem/install.ps1" 'Microsoft.Sysinternals'
assert_contains "$repo_root/windows/.local/share/windows-vm/oem/install.ps1" 'voidtools.Everything'
assert_contains "$repo_root/windows/.local/share/windows-vm/oem/install.ps1" 'ImputNet.Helium'
assert_contains "$repo_root/windows/.local/share/windows-vm/oem/install.ps1" 'PuTTY.PuTTY'

# Status is concise and includes the security-sensitive paths and endpoints.
"$helper" status > "$test_root/status.out"
assert_contains "$test_root/status.out" 'Installed:     yes'
assert_contains "$test_root/status.out" 'KVM:'
assert_contains "$test_root/status.out" "$WINDOWS_VM_SHARE_DIR"
assert_contains "$test_root/status.out" '127.0.0.1:3389'

# The bar needs one stable phase, not a second copy of Docker/RDP detection.
WINDOWS_VM_TEST_CONTAINER_STATUS=running WINDOWS_VM_TEST_PORT_STATUS=0 \
  "$helper" status --bar > "$test_root/bar-ready.out"
[[ $(<"$test_root/bar-ready.out") == ready ]] || fail 'bar status did not report ready RDP'
WINDOWS_VM_TEST_CONTAINER_STATUS=running WINDOWS_VM_TEST_PORT_STATUS=1 \
  "$helper" status --bar > "$test_root/bar-starting.out"
[[ $(<"$test_root/bar-starting.out") == starting ]] || fail 'bar status did not report startup progress'
WINDOWS_VM_TEST_CONTAINER_STATUS=stopped WINDOWS_VM_TEST_PORT_STATUS=0 \
  "$helper" status --bar > "$test_root/bar-off.out"
[[ $(<"$test_root/bar-off.out") == off ]] || fail 'bar status showed a stopped VM'

# Scale mapping uses only values FreeRDP supports.
for pair in '1 100' '1.4 140' '1.8 180'; do
  set -- $pair
  WINDOWS_VM_TEST_SCALE="$1" WINDOWS_VM_DRY_RUN=1 "$helper" status >/dev/null
  scale=$(WINDOWS_VM_TEST_SCALE="$1" bash -c \
    'source "$1" help >/dev/null; focused_scale' _ "$helper")
  [[ "$scale" == "$2" ]] || fail "scale $1 mapped to $scale instead of $2"
done

# Starting a stopped VM and a clean RDP exit both emit lifecycle notifications.
: > "$calls"
export WINDOWS_VM_TEST_STATE_FILE="$test_root/container-state"
printf 'stopped\n' > "$WINDOWS_VM_TEST_STATE_FILE"
WINDOWS_VM_TEST_SCALE=1.4 "$helper" launch > "$test_root/launch.out" 2>&1
assert_contains "$calls" '+dynamic-resolution +f /clipboard /sound /microphone'
assert_contains "$calls" '/scale:140'
assert_contains "$calls" ' stop windows'
assert_contains "$calls" 'Windows VM started'
assert_contains "$calls" 'Windows VM stopped'

# The explicit stop command also notifies only after Docker succeeds.
: > "$calls"
"$helper" stop > "$test_root/stop.out" 2>&1
assert_contains "$calls" ' stop windows'
assert_contains "$calls" 'Windows VM stopped'

# Keep-alive and client failure both preserve the running VM.
: > "$calls"
"$helper" launch --keep-alive > "$test_root/keep.out" 2>&1
grep -Fq ' stop windows' "$calls" && fail 'keep-alive stopped the VM'
: > "$calls"
set +e
WINDOWS_VM_TEST_RDP_STATUS=7 "$helper" launch > "$test_root/failed-rdp.out" 2>&1
rdp_status=$?
set -e
[[ "$rdp_status" == 7 ]] || fail "failed RDP returned $rdp_status instead of 7"
grep -Fq ' stop windows' "$calls" && fail 'failed RDP stopped the VM'
assert_contains "$test_root/failed-rdp.out" 'left running for troubleshooting'

# Non-destructive removal preserves all three user directories.
WINDOWS_VM_DRY_RUN=1 "$helper" remove > "$test_root/remove.out"
assert_contains "$test_root/remove.out" "$WINDOWS_VM_STORAGE_DIR"
[[ -d "$WINDOWS_VM_STORAGE_DIR" && -d "$WINDOWS_VM_SHARE_DIR" ]] || fail 'remove dry-run deleted user data'

# The real launch implementation carries the required RDP channels and lifecycle guard.
assert_contains "$helper" '/from-stdin:force'
assert_contains "$helper" '+dynamic-resolution +f'
assert_contains "$helper" '/clipboard /sound /microphone'
[[ $(grep -Fc '/cert:ignore' "$helper") == 2 ]] || fail 'RDP certificate handling is not consistently non-interactive'
grep -Fq '/cert:tofu' "$helper" && fail 'interactive TOFU certificate handling is still enabled'
assert_contains "$helper" 'if (( rdp_status != 0 ))'
assert_contains "$helper" 'compose stop windows'
assert_contains "$helper" 'flock -n 9'

set +e
"$helper" launch --unknown >/dev/null 2>&1
unknown_status=$?
set -e
[[ "$unknown_status" == 2 ]] || fail 'unknown launch option was accepted'

assert_contains "$repo_root/hypr/.config/hypr/conf/keybindings.lua" \
  'exec(mod .. " + ALT + W", "Windows VM", "$HOME/.local/bin/windows-vm launch")'
assert_contains "$repo_root/hypr/.config/hypr/conf/keybindings.lua" \
  'exec(mod .. " + CTRL + ALT + W", "stop Windows VM", "$HOME/.local/bin/windows-vm stop")'

# Purge requires exact confirmation, deletes only managed defaults, and keeps Shared.
default_config="$HOME/.config/windows"
mkdir -p "$default_config"
cp "$WINDOWS_VM_CONFIG_DIR/settings.env" "$default_config/settings.env"
cp "$WINDOWS_VM_CONFIG_DIR/credentials.env" "$default_config/credentials.env"
set +e
printf 'no\n' | env -u WINDOWS_VM_CONFIG_DIR -u WINDOWS_VM_STORAGE_DIR \
  -u WINDOWS_VM_SHARE_DIR "$helper" remove --purge-data >/dev/null 2>&1
cancel_status=$?
set -e
[[ "$cancel_status" == 1 && -d "$HOME/.windows" ]] || fail 'cancelled purge removed VM data'
printf '%s\n' "$HOME/.windows" | env -u WINDOWS_VM_CONFIG_DIR \
  -u WINDOWS_VM_STORAGE_DIR -u WINDOWS_VM_SHARE_DIR \
  "$helper" remove --purge-data >/dev/null 2>&1
[[ ! -e "$HOME/.windows" && ! -e "$default_config" ]] || fail 'confirmed purge kept managed VM data'
[[ -d "$HOME/Windows" ]] || fail 'confirmed purge deleted the shared folder'
fi

printf 'ok: windows-vm fixtures\n'
