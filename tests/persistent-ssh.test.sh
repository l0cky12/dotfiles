#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repo_root/ssh/.local/bin/sshpersist"
ssh_fragment="$repo_root/ssh/.config/ssh/conf.d/autossh.conf"
tmux_config="$repo_root/tmux/.config/tmux/tmux.conf"
zsh_config="$repo_root/zsh/.zshrc"
test_root=$(mktemp -d -t persistent-ssh.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"
}

mkdir -p "$test_root/bin"
calls="$test_root/autossh.calls"

cat > "$test_root/bin/autossh" <<'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$AUTOSSH_TEST_CALLS"
SH
chmod +x "$test_root/bin/autossh"

AUTOSSH_TEST_CALLS="$calls" PATH="$test_root/bin:$PATH" \
  "$launcher" admin@example.net
mapfile -d '' -t args < "$calls"
expected=(
  -M 0 -t
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
  -o ConnectTimeout=10
  -o TCPKeepAlive=yes
  admin@example.net tmux new -A -s admin_example_net
)
[[ ${args[*]} == "${expected[*]}" ]] \
  || fail "unexpected autossh arguments: ${args[*]}"

AUTOSSH_TEST_CALLS="$calls" PATH="$test_root/bin:$PATH" \
  "$launcher" example.net maintenance
mapfile -d '' -t args < "$calls"
[[ ${args[-1]} == maintenance ]] || fail 'explicit tmux session was not preserved'

: > "$calls"
if AUTOSSH_TEST_CALLS="$calls" PATH="$test_root/bin:$PATH" \
  "$launcher" example.net 'unsafe;command' >/dev/null 2>&1; then
  fail 'an unsafe tmux session name was accepted'
fi
[[ ! -s $calls ]] || fail 'autossh ran after unsafe input'

assert_contains "$launcher" 'exec autossh -M 0'
assert_contains "$launcher" 'tmux new -A -s'
assert_contains "$zsh_config" "alias sshp='sshpersist'"
assert_contains "$ssh_fragment" 'ServerAliveInterval 15'
assert_contains "$ssh_fragment" 'ServerAliveCountMax 3'
assert_contains "$ssh_fragment" 'ConnectTimeout 10'
assert_contains "$tmux_config" 'set-option -g detach-on-destroy off'

if grep -ERiq -- '(IdentityFile|id_(rsa|dsa|ecdsa|ed25519)|/home/[^/]+/\.ssh)' \
  "$launcher" "$ssh_fragment" "$tmux_config"; then
  fail 'persistent SSH files contain a hardcoded key path'
fi

printf 'ok: persistent SSH fixtures\n'
