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

if rg -n '(curl[^|]*\|[[:space:]]*(ba)?sh|((ba)?sh)[[:space:]]+-c[^$]*\$\([^)]*curl)' \
    "${docs[@]}"; then
  fail 'documentation still executes curl output directly in a shell'
fi

for doc in "${docs[@]}"; do
  grep -Fq -- '--output "$omz_installer"' "$doc" || \
    fail "$doc does not download the installer to a file"
  grep -Fq 'sha256sum "$omz_installer"' "$doc" || \
    fail "$doc does not print the installer checksum"
  grep -Fq 'less "$omz_installer"' "$doc" || \
    fail "$doc does not require installer inspection"
  grep -Fq 'POWERLEVEL10K_PIN=' "$doc" || \
    fail "$doc is missing POWERLEVEL10K_PIN"
  grep -Fq 'FZF_TAB_PIN=' "$doc" || fail "$doc is missing FZF_TAB_PIN"
  grep -Fq 'REQUIRED: fill these with reviewed 40-character commits' "$doc" || \
    fail "$doc is missing the required fill-in guidance"
  grep -Fq 'The placeholder values fail closed.' "$doc" || \
    fail "$doc does not make its placeholder pins fail closed"
  grep -Fq '[[ $POWERLEVEL10K_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$doc" || \
    fail "$doc does not require a full Powerlevel10k commit SHA"
  grep -Fq '[[ $FZF_TAB_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$doc" || \
    fail "$doc does not require a full fzf-tab commit SHA"
  grep -Fq 'checkout --detach "$FZF_TAB_PIN"' "$doc" || \
    fail "$doc does not check out the pinned fzf-tab commit"
done

grep -Eq -- '--git https://github\.com/omacom-io/ttfx --rev "\$TTFX_PIN"' \
  "$install_ttfx" || fail 'install-ttfx does not pass TTFX_PIN with --rev'
grep -Fq "TTFX_PIN=\${TTFX_PIN:-'<REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_SHA>'}" \
  "$install_ttfx" || \
  fail 'install-ttfx is missing the TTFX_PIN variable'
grep -Fq 'REQUIRED: fill this with a reviewed 40-character commit' \
  "$install_ttfx" || fail 'install-ttfx is missing the required fill-in guidance'
grep -Fq 'The placeholder fails closed' "$install_ttfx" || \
  fail 'install-ttfx does not make its placeholder pin fail closed'
grep -Fq '[[ $TTFX_PIN =~ ^[0-9a-fA-F]{40}$ ]]' "$install_ttfx" || \
  fail 'install-ttfx does not require a full commit SHA'

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/rust-target"
for command_name in cargo musl-gcc; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/$command_name"
  chmod +x "$test_root/bin/$command_name"
done
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$RUST_TARGET_FIXTURE"\n' \
  >"$test_root/bin/rustc"
chmod +x "$test_root/bin/rustc"

fixture_env=(
  "HOME=$test_root/home"
  "PATH=$test_root/bin:/usr/bin"
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
