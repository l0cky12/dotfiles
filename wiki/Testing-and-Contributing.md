# Testing and contributing

## The rules

[`AGENTS.md`](../AGENTS.md) is the authoritative list. In short:

- **This Git repository is the only authoritative source.** Edit Stow package
  paths like `hypr/.config/hypr/`, never live paths under `~/.config` or
  `~/.local`, even though those are symlinks back into the repo.
- Begin non-trivial changes with read-only discovery. Present the intended files
  and the validation plan before editing.
- Preserve existing user changes. Keep patches focused. Do not delete, rename,
  stage, commit, or push unrelated work.
- **Do not run GNU Stow, reload or restart Hyprland, or restart desktop services
  without explicit approval for that specific action.**
- Anything that can mutate Hyprland or system state must provide and use a safe
  dry-run or fixture path during validation. Do not assume a live Hyprland
  session exists.
- Edit theme palettes, templates, or generators — never the generated outputs
  listed in `.gitignore`.
- Run the applicable syntax checks and fixture tests, then `git diff --check`.
  Review the whole diff and confirm every changed path before calling it done.

The dry-run requirement is not decoration. It is why nearly every mutating script
here has a `--dry-run`, a `--fixture`, or an environment override that redirects
it at a temporary directory.

## The test suite

`tests/` holds 29 shell tests and 3 Python tests. There is no runner script —
each file is self-contained, uses `set -euo pipefail`, builds its own fixture
directory under `mktemp -d`, and removes it on `EXIT`.

Run one:

```bash
tests/lmenu.test.sh
python3 tests/desktop-mode.test.py
```

Run them all:

```bash
for t in tests/*.test.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
for t in tests/*.test.py; do echo "== $t"; python3 "$t" || echo "FAILED: $t"; done
python3 -m unittest tests.test_theme_generator
```

### What is covered

| Test | Covers |
| --- | --- |
| `hyprland-lua.test.sh` | `luac -p` on every tracked Lua file, plus monitor-profile selection with mocked `hyprctl` — including the connector-renumbering regression and the rule that a partial monitor set must not select `kvm` |
| `hypr-monitor-watch.test.sh` | the socket2 watcher and its debounce |
| `test_theme_generator.py` | the generator, against `tests/fixtures/theme-generator-snapshots.json` |
| `hyprlock-theme.test.py` | generated lock-screen colours |
| `desktop-mode.test.py` | mode transitions, timers, conditions, doctor output |
| `screensaver.test.sh` | monitor spawn planning and the lock handoff |
| `arch-updates.test.sh` | update counting, including a failed mirror sync |
| `omakub-bar-layout.test.sh` | the bar still mounts the expected component set |
| `audio-panel.test.sh` | shared audio helper behavior and headless panel rendering |
| `omakub-toggles.test.sh` | the toggles menu |
| `bluetooth-control.test.sh`, `network-control.test.sh` | the Quickshell panel backends |
| `browser-native-tools.test.sh` | both native hosts, with mocked clipboard, downloader, notification, player, and OSD commands |
| `capture-screenshot-editor.test.sh`, `webcam-resize.test.sh` | capture behaviours |
| `lmenu.test.sh`, `lmenu-reminder.test.sh` | menu rendering and systemd-timer reminders |
| `windows-vm.test.sh` | the VM controller |
| `yubikey-auth.test.sh` | the guarded PAM helper |
| `eject-drive.test.sh` | drive ejection, with `--fixture` implying `--dry-run` |
| `docker-dev-env.test.sh` | the development stack |
| `hypr-wallpaper-picker.test.sh` | index, search, apply |
| `calculator.test.sh`, `emoji-picker.test.sh`, `quick-search.test.sh`, `power-menu.test.sh`, `power-profile.test.sh`, `night-light.test.sh`, `transcode.test.sh`, `window-width.test.sh`, `close-all-windows.test.sh`, `default-browser-private.test.sh` | the remaining helpers |

The browser suite uses mocked commands throughout. It never downloads media and
never touches the live clipboard.

### Writing one

Follow the existing shape:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t mything-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
```

Stub external commands into a fixture directory and make that directory the
**entire** `PATH` where you can, so a real binary on the host cannot shadow your
stub. If the script under test needs `bash` itself, symlink it into the fixture.

Prefer the script's own `--dry-run` or `--fixture` flag over mocking when one
exists — that path is guaranteed never to mutate system state.

## Other validation

```bash
# Lua syntax across the tree
find hypr -name '*.lua' -not -path '*/themes/.active/*' -exec luac -p {} +

# Bash syntax
bash -n hypr/.config/hypr/scripts/<script>

# QML, headless
QT_QPA_PLATFORM=offscreen quickshell -p quickshell/.config/quickshell/OmakubBarSmoke.qml

# Notification unit tests
python3 -m unittest discover -s quickshell/.config/quickshell/notifications/tests -p 'test_*.py'
node quickshell/.config/quickshell/notifications/tests/notification_logic.test.js

# Every theme palette
theme validate --all

# What Stow would actually link
stow --simulate --verbose <package>

# Whitespace errors in the diff
git diff --check
```

`theme set --prefix DIR` renders a theme into a scratch directory without
writing state or reloading anything, which is the safe way to inspect a palette
or template change.

## Documentation

Three layers, and they are meant to stay distinct:

| Where | For |
| --- | --- |
| `README.md` | the feature-first tour |
| `wiki/` | this wiki: task-oriented pages, cross-linked |
| `docs/` | the original reference notes |

When behaviour changes, update the page that describes it. Where the repository
does not establish a fact, say so rather than substituting a plausible upstream
default — that convention is what makes the rest of these pages trustworthy.

## Committing

Do not commit generated output. `.gitignore` lists it, but the two easiest
mistakes are:

- editing `conf/decorations.lua` directly instead of the palette or template;
- committing `monitors.lua` or `workspaces.lua` after a profile switch.

Both files are untracked for a reason — see
[Monitors and workspaces](Monitors-and-Workspaces.md#the-active-files-are-machine-state).
