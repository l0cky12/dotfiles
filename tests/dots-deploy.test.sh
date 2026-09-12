#!/usr/bin/env bash

set -euo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dots=$repo_root/dots/.local/bin/dots
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fixture_home="$test_root/home with quote's"
fixture_repo="$test_root/repository outside home"
fixture_state="$test_root/state with quote's/dots/last-deployed"
fixture_system_root="$test_root/system root"
stub_bin=$test_root/bin
calls=$test_root/calls
mkdir -p "$fixture_repo" "$stub_bin"

git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.name 'Dots Test'
git -C "$fixture_repo" config user.email dots@example.invalid
mkdir -p "$fixture_repo/alpha/.config/alpha" \
  "$fixture_repo/hypr/.config/hypr" "$fixture_repo/neovim/.config/nvim" \
  "$fixture_repo/wallpaper/theme" "$fixture_repo/docs" \
  "$fixture_repo/tests" "$fixture_repo/system/greetd" \
  "$fixture_repo/system/pam.d"
printf 'one\n' > "$fixture_repo/alpha/.config/alpha/config"
printf 'one\n' > "$fixture_repo/hypr/.config/hypr/config"
printf 'one\n' > "$fixture_repo/neovim/.config/nvim/init.lua"
printf 'one\n' > "$fixture_repo/wallpaper/theme/wallpaper"
printf 'docs\n' > "$fixture_repo/docs/guide"
printf 'tests\n' > "$fixture_repo/tests/example"
printf 'config\n' > "$fixture_repo/system/greetd/config.toml"
printf 'pam sudo\n' > "$fixture_repo/system/pam.d/sudo"
printf 'pam lock\n' > "$fixture_repo/system/pam.d/hyprlock"
git -C "$fixture_repo" add .
git -C "$fixture_repo" commit -qm initial
initial_sha=$(git -C "$fixture_repo" rev-parse HEAD)

run_dots() {
  HOME=$fixture_home DOTS_REPO=$fixture_repo DOTS_STATE_FILE=$fixture_state \
    DOTS_SYSTEM_ROOT=$fixture_system_root PATH="$stub_bin:/usr/bin:/bin" \
    DOTS_TEST_CALLS=$calls "$dots" deploy "$@"
}

# A first deployment plans every package, excludes non-packages, and mutates
# neither state nor the system during a dry run.
output=$(run_dots --dry-run)
[[ $output == *'Notice: no previous deployment record; deploying all packages.'* ]] ||
  fail 'first-run notice missing'
[[ $output == *'  - alpha'* && $output == *'  - hypr'* ]] ||
  fail 'first-run package plan incomplete'
[[ $output == *'neovim skipped: requires manual stow - see README.'* ]] ||
  fail 'manual-package skip notice missing'
[[ $output != *'  - neovim'* ]] || fail 'neovim was not skipped by default'
[[ $output != *'  - docs'* && $output != *'  - tests'* && $output != *'  - system'* ]] ||
  fail 'excluded directory appeared as a package'
[[ ! -e $fixture_state && ! -e $calls ]] || fail 'dry run changed fixture state'

# Even an opt-in system dry run only prints commands.
output=$(run_dots --dry-run --system --yes)
[[ $output == *'sudo install -m 0644 system/greetd/config.toml'* ]] ||
  fail 'system dry-run plan is incomplete'
[[ $output == *'hardcode host identity pam://Kelper'* ]] ||
  fail 'system identity warning missing'
[[ ! -e $fixture_state && ! -e $calls ]] || fail 'system dry run changed fixture state'

if output=$(run_dots --system 2>&1); then
  fail '--system without --yes unexpectedly succeeded'
fi
[[ $output == *'--system requires explicit confirmation with --yes'* ]] ||
  fail '--system confirmation error missing'

# Git is mandatory, and its absence fails before any plan or mutation.
mkdir -p "$test_root/no-git"
ln -s "$(command -v bash)" "$test_root/no-git/bash"
if output=$(HOME=$fixture_home DOTS_REPO=$fixture_repo DOTS_STATE_FILE=$fixture_state \
  PATH=$test_root/no-git "$dots" deploy --dry-run 2>&1); then
  fail 'missing git unexpectedly succeeded'
fi
[[ $output == *'git is required'* ]] || fail 'missing git error was not clear'

# Only a changed top-level package is selected; docs and system remain outside
# the default deployment.
mkdir -p "$(dirname "$fixture_state")"
chmod 0700 "$(dirname "$fixture_state")"
printf '%s\n' "$initial_sha" > "$fixture_state"
printf 'two\n' >> "$fixture_repo/alpha/.config/alpha/config"
printf 'more docs\n' >> "$fixture_repo/docs/guide"
printf 'new pam\n' >> "$fixture_repo/system/pam.d/sudo"
git -C "$fixture_repo" add .
git -C "$fixture_repo" commit -qm changed
changed_sha=$(git -C "$fixture_repo" rev-parse HEAD)
output=$(run_dots --dry-run)
[[ $output == *'  - alpha'* ]] || fail 'changed package missing from plan'
[[ $output != *'  - hypr'* && $output != *'  - system'* ]] ||
  fail 'unchanged or excluded package appeared in diff plan'
[[ $(<"$fixture_state") == "$initial_sha" ]] || fail 'dry run updated state'

# --all overrides the diff.
output=$(run_dots --dry-run --all)
[[ $output == *'Notice: --all selected; deploying all packages.'* ]] ||
  fail '--all notice missing'
[[ $output == *'  - alpha'* && $output == *'  - hypr'* && $output == *'  - neovim'* ]] ||
  fail '--all package plan incomplete'
[[ $output == *'stow --restow --no-folding --target'* ]] ||
  fail '--all no-folding plan missing'

cat > "$stub_bin/stow" <<'STUB'
#!/usr/bin/env bash
printf 'stow cwd=%q' "$PWD" >> "$DOTS_TEST_CALLS"
printf ' arg=%q' "$@" >> "$DOTS_TEST_CALLS"
printf '\n' >> "$DOTS_TEST_CALLS"
STUB
cat > "$stub_bin/pgrep" <<'STUB'
#!/usr/bin/env bash
exit "${DOTS_TEST_PGREP_RC:-1}"
STUB
cat > "$stub_bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf 'hyprctl arg=%q\n' "$1" >> "$DOTS_TEST_CALLS"
STUB
cat > "$stub_bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo' >> "$DOTS_TEST_CALLS"
printf ' arg=%q' "$@" >> "$DOTS_TEST_CALLS"
printf '\n' >> "$DOTS_TEST_CALLS"
"$@"
STUB
chmod +x "$stub_bin/stow" "$stub_bin/pgrep" "$stub_bin/hyprctl" "$stub_bin/sudo"

# A new state directory is created privately and receives the deployed commit.
fresh_state="$test_root/fresh state/dots/last-deployed"
: > "$calls"
HOME=$fixture_home DOTS_REPO=$fixture_repo DOTS_STATE_FILE=$fresh_state \
  PATH="$stub_bin:/usr/bin:/bin" DOTS_TEST_CALLS=$calls "$dots" deploy --all >/dev/null
[[ $(<"$fresh_state") == "$changed_sha" ]] || fail 'new state file did not record HEAD'
[[ $(stat -c '%a' "$(dirname "$fresh_state")") == 700 ]] ||
  fail 'new state directory mode is not 0700'

# A successful fixture deployment invokes the stub from the fixture repo and
# records HEAD. No real stow or Hyprland command is reachable.
: > "$calls"
run_dots >/dev/null
printf -v fixture_repo_q '%q' "$fixture_repo"
grep -F "stow cwd=$fixture_repo_q arg=--restow" "$calls" >/dev/null ||
  fail 'stow invocation was not rooted in the repository'
printf -v fixture_home_q '%q' "$fixture_home"
grep -F "arg=--target arg=$fixture_home_q arg=alpha" "$calls" >/dev/null ||
  fail 'repository outside HOME was not explicitly targeted at HOME'
[[ $(<"$fixture_state") == "$changed_sha" ]] || fail 'successful deploy did not record HEAD'

# An explicitly requested manual package uses the safe no-folding path.
: > "$calls"
run_dots --no-folding-pkg neovim >/dev/null
grep -F "arg=--restow arg=--no-folding arg=--target arg=$fixture_home_q arg=neovim" \
  "$calls" >/dev/null || fail 'explicit neovim deployment omitted --no-folding'

# A live fixture Hyprland session reloads only after hypr is deployed.
printf '%s\n' "$changed_sha" > "$fixture_state"
printf 'two\n' >> "$fixture_repo/hypr/.config/hypr/config"
git -C "$fixture_repo" add .
git -C "$fixture_repo" commit -qm hypr
: > "$calls"
DOTS_TEST_PGREP_RC=0 run_dots >/dev/null
grep -Fx 'hyprctl arg=reload' "$calls" >/dev/null || fail 'live Hyprland was not reloaded'

# --system backs up every existing target before installing mode 0644 files.
mkdir -p "$fixture_system_root/etc/greetd" "$fixture_system_root/etc/pam.d"
printf 'old greetd\n' > "$fixture_system_root/etc/greetd/config.toml"
printf 'old sudo\n' > "$fixture_system_root/etc/pam.d/sudo"
printf 'old lock\n' > "$fixture_system_root/etc/pam.d/hyprlock"
: > "$calls"
output=$(run_dots --system --yes)
grep -F 'sudo arg=install arg=-m arg=0644' "$calls" >/dev/null ||
  fail '--system did not use install mode 0644'
[[ $(grep -c '^sudo arg=install ' "$calls") == 3 ]] ||
  fail '--system did not install all templates'
[[ $(grep -c '^sudo arg=cp arg=-a arg=-- ' "$calls") == 3 ]] ||
  fail '--system did not back up all existing targets'
grep -F 'sudo arg=mkdir arg=-p arg=--' "$calls" >/dev/null ||
  fail '--system did not create the greetd directory'
[[ $output == *'Rollback instructions:'* && $output == *'.pre-dots.'* ]] ||
  fail '--system did not print backup and rollback details'
find "$fixture_system_root/etc" -type f -name '*.pre-dots.*' | grep -q . ||
  fail '--system did not retain fixture backups'

# A stow conflict fails, explains recovery, and leaves the state SHA untouched.
cat > "$stub_bin/stow" <<'STUB'
#!/usr/bin/env bash
printf 'existing target is not owned by stow\n' >&2
exit 1
STUB
printf '%s\n' "$initial_sha" > "$fixture_state"
if output=$(run_dots 2>&1); then
  fail 'stow conflict unexpectedly succeeded'
fi
[[ $output == *"stow failed for 'alpha'"* && $output == *'not adopted or overwritten'* ]] ||
  fail 'stow conflict was not reported clearly'
[[ $(<"$fixture_state") == "$initial_sha" ]] || fail 'failed deploy advanced state'

printf 'ok: dots deploy fixtures\n'
