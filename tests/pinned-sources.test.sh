#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
docs=(
  "$repo_root/README.md"
  "$repo_root/docs/installation.md"
  "$repo_root/wiki/Getting-Started.md"
)
install_ttfx="$repo_root/screensaver/.local/bin/install-ttfx"
test_root=$(mktemp -d -t pinned-sources-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Follow-ups
# - Fill TTFX_PIN with a reviewed commit during the first online setup session.
# - Fill POWERLEVEL10K_PIN and FZF_TAB_PIN during that same online session.

# Join shell line continuations so direct execution cannot evade the scan by
# putting the pipe or process substitution on the following physical line.
scan_input="$test_root/docs.logical-lines"
sed ':join; /\\$/ { N; s/\\\n/ /; b join; }' "${docs[@]}" >"$scan_input"

# Reject downloader output piped to a shell, including path-qualified shells
# and sudo with flags. The wget alternatives cover its common stdout forms.
pipe_exec_pattern='(curl[^|]*|wget[^|]*(-qO-|-O[[:space:]]+-|--output-document(=|[[:space:]]+)-)[^|]*)\|[[:space:]]*(sudo[[:space:]]+[^|]*)?([^|[:space:]]*/)?(ba|z|da)?sh([[:space:]]|$)'
# Reject shells (or eval) executing downloader output via command substitution.
command_substitution_exec_pattern='(([^[:space:]]*/)?(ba|z|da)?sh[[:space:]]+-c|eval)[[:space:]]+"?\$\([[:space:]]*(curl|wget)[^)]*\)'
# Reject source/dot and shell-stdin execution via process substitution.
process_substitution_exec_pattern='((source|\.)[[:space:]]+|([^[:space:]]*/)?(ba|z|da)?sh[[:space:]]*<[[:space:]]*)<\([[:space:]]*(curl|wget)[^)]*\)'
direct_exec_pattern="$pipe_exec_pattern|$command_substitution_exec_pattern|$process_substitution_exec_pattern"
if grep -Eq -- "$direct_exec_pattern" "$scan_input"; then
  fail 'documentation still executes curl output directly in a shell'
else
  grep_status=$?
  ((grep_status == 1)) || fail "documentation source scan failed with grep status $grep_status"
fi

for doc in "${docs[@]}"; do
  doc_scan="$test_root/${doc##*/}.logical-lines"
  sed ':join; /\\$/ { N; s/\\\n/ /; b join; }' "$doc" >"$doc_scan"
  grep -Eq 'omz_installer' "$doc" || \
    fail "$doc is missing the downloaded installer variable"
  grep -Eq 'sha256sum' "$doc" || \
    fail "$doc is missing the installer checksum step"
  grep -Fq '[[ $POWERLEVEL10K_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$doc" || \
    fail "$doc does not require a full Powerlevel10k commit SHA"
  grep -Fq '[[ $FZF_TAB_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$doc" || \
    fail "$doc does not require a full fzf-tab commit SHA"
  grep -Eq 'checkout --detach[[:space:]]+"?\$POWERLEVEL10K_PIN' "$doc_scan" || \
    fail "$doc does not detach the pinned Powerlevel10k commit"
  grep -Eq 'checkout --detach[[:space:]]+"?\$FZF_TAB_PIN' "$doc_scan" || \
    fail "$doc does not detach the pinned fzf-tab commit"
done

grep -Eq -- '--git https://github\.com/omacom-io/ttfx --rev "\$TTFX_PIN"' \
  "$install_ttfx" || fail 'install-ttfx does not pass TTFX_PIN with --rev'
grep -Eq 'TTFX_PIN=.*REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA' \
  "$install_ttfx" || \
  fail 'install-ttfx is missing the TTFX_PIN variable'
grep -Fq '[[ $TTFX_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$install_ttfx" || \
  fail 'install-ttfx does not require a full commit SHA'

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/rust-target"
ln -s "$(command -v bash)" "$test_root/bin/bash"
for command_name in cargo musl-gcc; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/$command_name"
  chmod +x "$test_root/bin/$command_name"
done
for command_name in paru yay; do
  printf '#!/usr/bin/env bash\nexit 1\n' >"$test_root/bin/$command_name"
  chmod +x "$test_root/bin/$command_name"
done
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$RUST_TARGET_FIXTURE"\n' \
  >"$test_root/bin/rustc"
chmod +x "$test_root/bin/rustc"

fixture_env=(
  "HOME=$test_root/home"
  "PATH=$test_root/bin"
  "RUST_TARGET_FIXTURE=$test_root/rust-target"
)
if env -u TTFX_PIN "${fixture_env[@]}" "$install_ttfx" --dry-run \
    >"$test_root/missing-pin.out" 2>&1; then
  fail 'install-ttfx accepted its placeholder source pin'
fi

pin=0123456789abcdef0123456789abcdef01234567
env "${fixture_env[@]}" TTFX_PIN=$pin "$install_ttfx" --dry-run \
  >"$test_root/pinned.out"
grep -Fq -- "--git https://github.com/omacom-io/ttfx --rev $pin ttfx" \
  "$test_root/pinned.out" || fail 'install-ttfx dry-run omitted the pinned revision'

printf 'pinned source checks passed\n'
