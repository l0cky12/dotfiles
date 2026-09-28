#!/usr/bin/env bash
# run-or-install runs installed programs directly and offers an install for
# missing ones. Every package manager, terminal and notifier here is a fake on a
# fixture PATH that holds no real pacman, sudo or AUR helper.
# The fake commands' bodies are single-quoted so they expand when they run.
# shellcheck disable=SC2016
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
wrapper="$repo_root/hypr/.config/hypr/scripts/run-or-install"
test_root=$(mktemp -d -t run-or-install-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

bin="$test_root/bin"
log="$test_root/log"
mkdir -p "$bin" "$log"
for tool in bash env mktemp grep rm date mkdir setsid cat chmod sleep; do
  ln -s "$(command -v "$tool")" "$bin/$tool"
done

fake() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$bin/$1"
  chmod +x "$bin/$1"
}

# A launched program records its arguments, one per line.
app_body='printf "%s\n" "$@" >"'"$log"'/launched-${0##*/}"'
fake installed-app "$app_body"

# pacman -F knows fixture-repo-app; a missing files database is simulated with
# FAKE_FILES_DB=missing. pacman -S "installs" by creating the program.
fake pacman '
log='"$log"'
if [[ $1 == -Fq ]]; then
  if [[ ${FAKE_FILES_DB:-} == missing ]]; then
    echo "warning: database file for '\''core'\'' does not exist (use '\''-Fy'\'' to download)" >&2
    exit 1
  fi
  [[ $3 == /usr/bin/fixture-repo-app ]] && { echo extra/fixture-repo-pkg; exit 0; }
  [[ $3 == /usr/bin/fixture-fail-app ]] && { echo extra/fixture-fail-pkg; exit 0; }
  exit 1
fi
echo "pacman $*" >>"$log/install"
[[ ${!#} == fixture-fail-pkg ]] && exit 1
printf "#!/usr/bin/env bash\n%s\n" '"'$app_body'"' >"'"$bin"'/fixture-repo-app"
chmod +x "'"$bin"'/fixture-repo-app"'
fake sudo 'echo "sudo $*" >>"'"$log"'/install"; exec "$@"'
fake yay '
echo "yay $*" >>"'"$log"'/install"
printf "#!/usr/bin/env bash\n%s\n" '"'$app_body'"' >"'"$bin"'/fixture-aur-app"
chmod +x "'"$bin"'/fixture-aur-app"'
# The terminal runs its -e command at once and answers the closing prompt.
fake kitty '
echo "kitty $*" >>"'"$log"'/terminal"
while (($#)) && [[ $1 != -e ]]; do shift; done
shift
echo | "$@"'
# Records every notification and answers with FAKE_CHOICE, like notify-send --wait.
fake notify-send '
printf "%s\n" "$*" >>"'"$log"'/notify"
[[ " $* " == *" --wait "* && -n ${FAKE_CHOICE:-} ]] && printf "%s\n" "$FAKE_CHOICE"
exit 0'

printf '# comment\nfixture-aur-app\tfixture-aur-pkg\taur\nbad-app\t-rf\trepo\n' >"$test_root/map.tsv"

# The wrapper's own output (the install transcript) goes to a log; tests that
# need stdout capture it themselves.
run() {
  env -i HOME="$test_root" PATH="$bin" XDG_STATE_HOME="$test_root/state" \
    RUN_OR_INSTALL_MAP="$test_root/map.tsv" "$@" 2>>"$log/stderr"
}

wait_for() {
  local i
  for ((i = 0; i < 50; i++)); do
    [[ -e $1 ]] && return 0
    sleep 0.1
  done
  return 1
}

# Installed: exec at once with the arguments intact and no notification.
run "$wrapper" installed-app one 'two words'
[[ $(<"$log/launched-installed-app") == $'one\ntwo words' ]] || fail 'installed program lost its arguments'
[[ ! -e $log/notify ]] || fail 'an installed program triggered a notification'

# Dry run: the lookup result and the install command, nothing else.
out=$(run "$wrapper" --dry-run installed-app)
[[ $out == $'command: installed-app\nstatus: installed' ]] || fail "dry run of an installed program: $out"
out=$(run "$wrapper" --dry-run fixture-repo-app)
[[ $out == $'command: fixture-repo-app\nstatus: missing\npackage: fixture-repo-pkg\nsource: repo\ninstall: sudo pacman -S --needed fixture-repo-pkg' ]] ||
  fail "dry run of a repo package: $out"
out=$(run "$wrapper" --dry-run fixture-aur-app)
[[ $out == *$'source: aur\ninstall: yay -S --needed fixture-aur-pkg' ]] || fail "dry run of an AUR package: $out"
out=$(run "$wrapper" --dry-run nothing-provides-this)
[[ $out == $'command: nothing-provides-this\nstatus: missing\npackage: none' ]] || fail "dry run with no package: $out"
out=$(run FAKE_FILES_DB=missing "$wrapper" --dry-run nothing-provides-this)
[[ $out == *$'package: none\nhint: sudo pacman -Fy' ]] || fail 'dry run did not suggest pacman -Fy'
out=$(run "$wrapper" --dry-run bad-app)
[[ $out == *'package: none' ]] || fail 'a map entry with an invalid package name was used'
[[ ! -e $log/notify && ! -e $log/install && ! -e $log/terminal ]] || fail 'a dry run notified or installed'

# Missing repo package, Install chosen: the terminal runs sudo pacman, then the
# program starts with its original arguments.
run FAKE_CHOICE=install "$wrapper" fixture-repo-app --flag 'x y' >>"$log/stdout" || true
grep -Fq -- '--action=install=Install --action=dismiss=Dismiss Not installed: fixture-repo-app Install fixture-repo-pkg from the Arch repositories?' "$log/notify" ||
  fail "repo notification is wrong: $(<"$log/notify")"
[[ $(<"$log/install") == $'sudo pacman -S --needed fixture-repo-pkg\npacman -S --needed fixture-repo-pkg' ]] ||
  fail "repo install command is wrong: $(<"$log/install")"
grep -Fq -- '--title Install fixture-repo-pkg -e bash -c' "$log/terminal" || fail 'the install did not run in a terminal'
wait_for "$log/launched-fixture-repo-app" || fail 'the program did not start after its install'
[[ $(<"$log/launched-fixture-repo-app") == $'--flag\nx y' ]] || fail 'the started program lost its arguments'

# Missing AUR package, Install chosen: yay, not sudo pacman.
rm -f "$log/install" "$log/notify"
run FAKE_CHOICE=install "$wrapper" fixture-aur-app >>"$log/stdout" || true
grep -Fq 'Install fixture-aur-pkg from the AUR?' "$log/notify" || fail 'AUR notification is wrong'
[[ $(<"$log/install") == 'yay -S --needed fixture-aur-pkg' ]] || fail "AUR install command is wrong: $(<"$log/install")"
wait_for "$log/launched-fixture-aur-app" || fail 'the AUR program did not start after its install'

# A failed install starts nothing.
rm -f "$log/install"
run FAKE_CHOICE=install "$wrapper" fixture-fail-app >>"$log/stdout" || true
grep -Fq 'pacman -S --needed fixture-fail-pkg' "$log/install" || fail 'the failing install did not run'
sleep 0.3
[[ ! -e $log/launched-fixture-fail-app ]] || fail 'a failed install started the program'

# Dismiss opens no terminal.
rm -f "$log/terminal" "$bin/fixture-repo-app"
rm -rf "$test_root/state"
run FAKE_CHOICE=dismiss "$wrapper" fixture-repo-app >>"$log/stdout" || true
[[ ! -e $log/terminal ]] || fail 'Dismiss opened a terminal'

# No package: a plain notification without actions, once per quiet window.
rm -f "$log/notify"
status=0
run FAKE_FILES_DB=missing "$wrapper" nothing-provides-this || status=$?
((status == 127)) || fail "a missing program did not exit 127 (got $status)"
run FAKE_FILES_DB=missing "$wrapper" nothing-provides-this || true
[[ $(grep -c . "$log/notify") == 1 ]] || fail 'a repeated press prompted again inside the quiet window'
grep -Fq "nothing-provides-this is not installed and no package provides it. Run 'sudo pacman -Fy'" "$log/notify" ||
  fail "no-package notification is wrong: $(<"$log/notify")"
grep -Fq -- '--action' "$log/notify" && fail 'the no-package notification offered an action'
run RUN_OR_INSTALL_QUIET_SECONDS=0 FAKE_FILES_DB=missing "$wrapper" nothing-provides-this || true
[[ $(grep -c . "$log/notify") == 2 ]] || fail 'the quiet window did not expire'

# An AUR package without yay or paru is named but not offered.
rm -f "$log/notify" "$bin/yay" "$bin/fixture-aur-app"
run FAKE_CHOICE=install "$wrapper" fixture-aur-app || true
grep -Fq 'Install yay or paru' "$log/notify" || fail 'a missing AUR helper was not explained'
grep -Fq -- '--action' "$log/notify" && fail 'an install was offered without an AUR helper'

# No installation terminal: explain the manual command without offering Install.
rm -f "$bin/kitty" "$log/notify" "$log/install"
run RUN_OR_INSTALL_QUIET_SECONDS=0 FAKE_CHOICE=install "$wrapper" fixture-repo-app || true
grep -Fq 'sudo pacman -S --needed fixture-repo-pkg' "$log/notify" || fail 'missing terminal has no recovery command'
grep -Fq -- '--action' "$log/notify" && fail 'an install was offered without a terminal'
[[ ! -e $log/install ]] || fail 'installation ran without a terminal'

# The shipped map parses: every entry has a valid package and source.
while IFS=$'\t' read -r name package origin rest; do
  [[ -z $name || $name == \#* ]] && continue
  [[ -z ${rest:-} && $package =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ && $origin =~ ^(repo|aur)$ ]] ||
    fail "bad install-map.tsv line for $name"
done <"$repo_root/hypr/.config/hypr/conf/install-map.tsv"

# The keybindings route plain programs through the wrapper, and keep their
# descriptions for the keybindings palette.
if command -v lua >/dev/null 2>&1; then
  binds=$(lua "$repo_root/hypr/.config/hypr/scripts/keybinds-replay.lua" \
    "$repo_root/hypr/.config/hypr/conf/keybindings.lua" "$repo_root/hypr/.config/hypr")
  for pair in 'spotify:spotify' 'obsidian:obsidian' 'hermes:hermes' 'browser:helium-browser' \
              'share with LocalSend:localsend' 'terminal:kitty'; do
    description=${pair%%:*} command=${pair#*:}
    grep -Fq "\"description\":\"$description\",\"key\"" <<<"$binds" || fail "the $description bind lost its description"
    grep -Fq "/run-or-install $command\"" <<<"$binds" || fail "the $description bind is not wrapped"
  done
fi

printf 'ok: run-or-install\n'
