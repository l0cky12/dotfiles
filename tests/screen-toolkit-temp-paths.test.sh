#!/usr/bin/env bash
set -euo pipefail

for tool in bash chmod find mktemp rg stat; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'FAIL: required test tool is missing: %s\n' "$tool" >&2
    exit 1
  }
done

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin="$repo_root/noctalia/.config/noctalia/plugins/screen-toolkit"
helper="$plugin/scripts/temp-session.sh"
fixture=$(mktemp -d -t screen-toolkit-temp-paths.XXXXXX)
cleanup() { rm -rf -- "$fixture"; }
trap cleanup EXIT
chmod 700 -- "$fixture"
mkdir -m 700 -- "$fixture/runtime" "$fixture/cache"

runtime_session=$(XDG_RUNTIME_DIR="$fixture/runtime" "$helper" create)
second_session=$(XDG_RUNTIME_DIR="$fixture/runtime" "$helper" create)
[[ "$runtime_session" == "$fixture/runtime"/screen-toolkit.* ]] || {
  printf 'FAIL: session directory is outside XDG_RUNTIME_DIR: %s\n' "$runtime_session" >&2
  exit 1
}
[[ "$runtime_session" != "$second_session" ]] || {
  printf 'FAIL: session directory name is not random\n' >&2
  exit 1
}
[[ $(stat -c '%a' -- "$runtime_session") == 700 ]] || {
  printf 'FAIL: runtime session directory is not mode 0700\n' >&2
  exit 1
}

fallback_session=$(env -u XDG_RUNTIME_DIR XDG_CACHE_HOME="$fixture/cache" HOME="$fixture" "$helper" create)
[[ "$fallback_session" == "$fixture/cache"/screen-toolkit.* ]] || {
  printf 'FAIL: fallback session directory is outside XDG_CACHE_HOME: %s\n' "$fallback_session" >&2
  exit 1
}
[[ $(stat -c '%a' -- "$fallback_session") == 700 ]] || {
  printf 'FAIL: fallback session directory is not mode 0700\n' >&2
  exit 1
}

if rg -n '/tmp/(screen-toolkit|measure|mirror)' "$plugin"; then
  printf 'FAIL: predictable shared temporary path remains\n' >&2
  exit 1
fi

for script in annotate.sh capture.sh color-picker.sh lens-upload.sh measure.sh \
  mirror-record.sh mirror-screenshot.sh ocr.sh record.sh temp-session.sh; do
  rg -q '^umask 077$' "$plugin/scripts/$script" || {
    printf 'FAIL: %s does not enforce umask 077\n' "$script" >&2
    exit 1
  }
done

for script in annotate.sh capture.sh color-picker.sh lens-upload.sh measure.sh mirror-record.sh \
  mirror-screenshot.sh ocr.sh record.sh; do
  rg -q '^[[:space:]]*trap .* EXIT$' "$plugin/scripts/$script" || {
    printf 'FAIL: %s does not install an EXIT cleanup trap\n' "$script" >&2
    exit 1
  }
done

rg -q 'mktemp -- "\$TEMP_DIR/recording\.XXXXXX\.mp4"' "$plugin/scripts/record.sh" || {
  printf 'FAIL: recordings do not use securely randomized files\n' >&2
  exit 1
}

rg -q 'Component\.onDestruction' "$plugin/Main.qml" || {
  printf 'FAIL: QML session cleanup hook is missing\n' >&2
  exit 1
}
rg -q 'execDetached\(\[root\._scriptsDir \+ "temp-session\.sh", "cleanup", root\.tempDir\]\)' "$plugin/Main.qml" || {
  printf 'FAIL: QML does not pass its session path as a cleanup argument\n' >&2
  exit 1
}

mkdir -m 700 -- "$fixture/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf png > "${!#}"' >"$fixture/bin/grim"
printf '%s\n' '#!/usr/bin/env bash' \
  'while (( $# )); do [[ $1 == -f ]] && { printf video > "$2"; exit; }; shift; done; exit 1' \
  >"$fixture/bin/wl-screenrec"
chmod +x -- "$fixture/bin/grim" "$fixture/bin/wl-screenrec"
pin_result=$(PATH="$fixture/bin:$PATH" "$plugin/scripts/capture.sh" \
  pin '0,0 10x10' "$runtime_session")
pin_path=${pin_result%%|*}
[[ "$pin_path" == "$runtime_session"/pin.*.png ]] || {
  printf 'FAIL: pin capture did not use a random session file: %s\n' "$pin_path" >&2
  exit 1
}
[[ $(stat -c '%a' -- "$pin_path") == 600 ]] || {
  printf 'FAIL: captured file is not mode 0600\n' >&2
  exit 1
}
record_path=$(PATH="$fixture/bin:$PATH" "$plugin/scripts/record.sh" \
  start wl-screenrec '0,0 10x10' "$runtime_session" 0 0 0)
[[ "$record_path" == "$runtime_session"/recording.*.mp4 ]] || {
  printf 'FAIL: recording did not use a random session file: %s\n' "$record_path" >&2
  exit 1
}
[[ $(stat -c '%a' -- "$record_path") == 600 ]] || {
  printf 'FAIL: recording file is not mode 0600\n' >&2
  exit 1
}

"$helper" cleanup "$runtime_session"
[[ ! -e "$runtime_session" ]] || {
  printf 'FAIL: explicit session cleanup left the directory behind\n' >&2
  exit 1
}
"$helper" cleanup "$second_session"
"$helper" cleanup "$fallback_session"

printf 'ok: screen toolkit temporary captures use private session storage\n'
