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

mapfile -t runtime_info < <(XDG_RUNTIME_DIR="$fixture/runtime" "$helper" create)
runtime_session=${runtime_info[0]}
boot_id=${runtime_info[1]}
mapfile -t second_info < <(XDG_RUNTIME_DIR="$fixture/runtime" "$helper" create)
second_session=${second_info[0]}
[[ "$runtime_session" == "$fixture/runtime"/screen-toolkit.* ]] || {
  printf 'FAIL: session directory is outside XDG_RUNTIME_DIR: %s\n' "$runtime_session" >&2
  exit 1
}
[[ "$runtime_session" != "$second_session" ]] || {
  printf 'FAIL: session directory name is not random\n' >&2
  exit 1
}
[[ "$boot_id" =~ ^[[:xdigit:]-]+$ ]] || {
  printf 'FAIL: session helper did not report a boot ID: %s\n' "$boot_id" >&2
  exit 1
}
[[ $(stat -c '%a' -- "$runtime_session") == 700 ]] || {
  printf 'FAIL: runtime session directory is not mode 0700\n' >&2
  exit 1
}

mapfile -t fallback_info < <(env -u XDG_RUNTIME_DIR XDG_CACHE_HOME="$fixture/cache" HOME="$fixture" "$helper" create)
fallback_session=${fallback_info[0]}
[[ "$fallback_session" == "$fixture/cache"/screen-toolkit.* ]] || {
  printf 'FAIL: fallback session directory is outside XDG_CACHE_HOME: %s\n' "$fallback_session" >&2
  exit 1
}
[[ $(stat -c '%a' -- "$fallback_session") == 700 ]] || {
  printf 'FAIL: fallback session directory is not mode 0700\n' >&2
  exit 1
}
mkdir -m 700 -- "$fixture/cache/screen-toolkit.stale"
touch -d '2 hours ago' -- "$fixture/cache/screen-toolkit.stale"
mapfile -t fallback_sweep_info < <(env -u XDG_RUNTIME_DIR XDG_CACHE_HOME="$fixture/cache" HOME="$fixture" "$helper" create)
fallback_sweep_session=${fallback_sweep_info[0]}
[[ ! -e "$fixture/cache/screen-toolkit.stale" && -d "$fallback_sweep_session" ]] || {
  printf 'FAIL: fallback startup sweep did not reap stale storage safely\n' >&2
  exit 1
}

mkdir -m 700 -- "$fixture/runtime/screen-toolkit.stale"
touch -d '2 hours ago' -- "$fixture/runtime/screen-toolkit.stale"
mapfile -t sweep_info < <(XDG_RUNTIME_DIR="$fixture/runtime" "$helper" create)
sweep_session=${sweep_info[0]}
[[ ! -e "$fixture/runtime/screen-toolkit.stale" ]] || {
  printf 'FAIL: startup sweep left a stale session directory behind\n' >&2
  exit 1
}
[[ -d "$sweep_session" ]] || {
  printf 'FAIL: startup sweep removed the current session directory\n' >&2
  exit 1
}

mkdir -m 700 -- "$fixture/outside" "$fixture/outside/screen-toolkit.attack"
if XDG_RUNTIME_DIR="$fixture/runtime" "$helper" cleanup "$fixture/outside/screen-toolkit.attack" 2>/dev/null; then
  printf 'FAIL: cleanup accepted a session-shaped directory outside its base\n' >&2
  exit 1
fi
[[ -d "$fixture/outside/screen-toolkit.attack" ]] || {
  printf 'FAIL: rejected cleanup removed an outside directory\n' >&2
  exit 1
}

if rg -n '(/tmp/|\$\{?TMPDIR\}?|StandardPaths\.TempLocation)' "$plugin"; then
  printf 'FAIL: shared temporary path API remains\n' >&2
  exit 1
fi
if rg -n --pcre2 'mktemp(?![^\n]*X{6})' "$plugin"; then
  printf 'FAIL: mktemp invocation without an explicit random template remains\n' >&2
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
printf '%s\n' '#!/usr/bin/env bash' \
  'printf partial > "${!#}"' \
  '[[ ${STUB_GRIM_FAIL:-0} != 1 ]]' \
  >"$fixture/bin/grim"
printf '%s\n' '#!/usr/bin/env bash' \
  'while (( $# )); do [[ $1 == -f ]] && { printf video > "$2"; exit; }; shift; done; exit 1' \
  >"$fixture/bin/wl-screenrec"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ ${1:-} == --list-langs ]]; then printf "List of available languages (1):\\neng\\n"; exit; fi' \
  'printf "fixture OCR text\\n"' \
  >"$fixture/bin/tesseract"
printf '%s\n' '#!/usr/bin/env bash' \
  'for arg; do [[ $arg == "%[fx:mean]" ]] && { printf "0.5"; exit; }; done' \
  'out=${!#}' \
  '[[ $out == info:* || $out == stdout ]] && { printf image; exit; }' \
  'printf image > "$out"' \
  >"$fixture/bin/magick"
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ ${1:-} == --help ]] && { printf "%s\\n" "--radius"; exit; }' \
  '[[ ${STUB_HYPRPICKER_FAIL:-0} == 1 ]] && exit 1' \
  'printf "%s\\n" "#123456"' \
  >"$fixture/bin/hyprpicker"
printf '%s\n' '#!/usr/bin/env bash' 'printf "10, 10\\n"' >"$fixture/bin/hyprctl"
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ ${STUB_WL_COPY_FAIL:-0} == 1 ]] && exit 1' \
  'cat >/dev/null' \
  >"$fixture/bin/wl-copy"
chmod +x -- "$fixture/bin"/*
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

ocr_capture="$runtime_session/ocr-fixture.png"
ocr_result=$(PATH="$fixture/bin:$PATH" "$plugin/scripts/ocr.sh" \
  0 0 100 40 eng '' 6 "$ocr_capture" "$runtime_session")
[[ "$ocr_result" == 'fixture OCR text' ]] || {
  printf 'FAIL: OCR fixture returned unexpected output: %s\n' "$ocr_result" >&2
  exit 1
}
[[ -f "$ocr_capture" ]] || {
  printf 'FAIL: successful OCR did not retain its capture\n' >&2
  exit 1
}
if compgen -G "$runtime_session/ocr.*.pnm" >/dev/null ||
   compgen -G "$runtime_session/ocr-noise.*.pnm" >/dev/null; then
  printf 'FAIL: successful OCR left processing files behind\n' >&2
  exit 1
fi

failed_ocr_capture="$runtime_session/ocr-failed.png"
if STUB_GRIM_FAIL=1 PATH="$fixture/bin:$PATH" "$plugin/scripts/ocr.sh" \
  0 0 100 40 eng '' 6 "$failed_ocr_capture" "$runtime_session"; then
  printf 'FAIL: OCR fixture accepted a failed capture\n' >&2
  exit 1
else
  ocr_status=$?
fi
[[ $ocr_status == 3 && ! -e "$failed_ocr_capture" ]] || {
  printf 'FAIL: failed OCR did not report code 3 and run its cleanup trap\n' >&2
  exit 1
}

color_capture="$runtime_session/color-fixture.png"
color_result=$(PATH="$fixture/bin:$PATH" "$plugin/scripts/color-picker.sh" "$color_capture")
[[ "$color_result" == '18 52 86' && -f "$color_capture" ]] || {
  printf 'FAIL: color picker fixture did not produce its expected result\n' >&2
  exit 1
}
failed_color_capture="$runtime_session/color-failed.png"
printf stale > "$failed_color_capture"
if STUB_HYPRPICKER_FAIL=1 PATH="$fixture/bin:$PATH" \
  "$plugin/scripts/color-picker.sh" "$failed_color_capture"; then
  printf 'FAIL: color picker fixture accepted a failed picker\n' >&2
  exit 1
fi
[[ ! -e "$failed_color_capture" ]] || {
  printf 'FAIL: failed color picker did not run its cleanup trap\n' >&2
  exit 1
}

printf base > "$runtime_session/annotate-base.png"
printf overlay > "$runtime_session/annotate-overlay.png"
annotate_result=$(PATH="$fixture/bin:$PATH" "$plugin/scripts/annotate.sh" save-overlay \
  "$runtime_session/annotate-base.png" "$runtime_session/annotate-overlay.png" \
  "$runtime_session/annotate-result.png")
[[ "$annotate_result" == "$runtime_session/annotate-result.png" &&
   -f "$runtime_session/annotate-result.png" &&
   ! -e "$runtime_session/annotate-overlay.png" ]] || {
  printf 'FAIL: annotate fixture did not produce its expected output\n' >&2
  exit 1
}
printf overlay > "$runtime_session/annotate-copy-overlay.png"
if STUB_WL_COPY_FAIL=1 PATH="$fixture/bin:$PATH" "$plugin/scripts/annotate.sh" copy \
  "$runtime_session/annotate-base.png" "$runtime_session/annotate-copy-overlay.png" \
  "$runtime_session"; then
  printf 'FAIL: annotate fixture accepted a failed clipboard write\n' >&2
  exit 1
fi
if compgen -G "$runtime_session/annotated.*.png" >/dev/null; then
  printf 'FAIL: failed annotate copy did not run its cleanup trap\n' >&2
  exit 1
fi

XDG_RUNTIME_DIR="$fixture/runtime" "$helper" cleanup "$runtime_session"
[[ ! -e "$runtime_session" ]] || {
  printf 'FAIL: explicit session cleanup left the directory behind\n' >&2
  exit 1
}
XDG_RUNTIME_DIR="$fixture/runtime" "$helper" cleanup "$second_session"
XDG_RUNTIME_DIR="$fixture/runtime" "$helper" cleanup "$sweep_session"
env -u XDG_RUNTIME_DIR XDG_CACHE_HOME="$fixture/cache" HOME="$fixture" \
  "$helper" cleanup "$fallback_session"
env -u XDG_RUNTIME_DIR XDG_CACHE_HOME="$fixture/cache" HOME="$fixture" \
  "$helper" cleanup "$fallback_sweep_session"

printf 'ok: screen toolkit temporary captures use private session storage\n'
