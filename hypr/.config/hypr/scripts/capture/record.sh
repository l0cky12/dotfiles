#!/usr/bin/env bash
# =============================================================================
# capture/record.sh — screen recording via gpu-screen-recorder
#
# Usage:
#   record.sh toggle [options]   stop if recording, otherwise ask and start
#   record.sh start  [options]   start (refuses if already recording)
#   record.sh stop               graceful SIGINT stop
#   record.sh status             prints "recording" or "idle" (for the bar)
#   record.sh menu               audio/target chooser, then start
#   record.sh webcam-toggle      show/hide a standalone webcam overlay
#   record.sh webcam-size smaller|larger
#                                step any live webcam overlay between presets
#
# Options for start/toggle:
#   --audio=none|desktop|mic|both   (default: desktop)
#   --target=smart|region|monitor   (default: monitor)
#   --with-webcam                   floating webcam overlay while recording
#
# State lives in $XDG_RUNTIME_DIR, never the repo. The pid is re-validated
# against /proc every time, so a crashed recorder cannot wedge the toggle.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=hypr/.config/hypr/scripts/capture/select.sh
source "$_dir/select.sh"

PIDFILE="$CAPTURE_RUNTIME/record.pid"
OUTFILE_REF="$CAPTURE_RUNTIME/record.out"
WEBCAM_PIDFILE="$CAPTURE_RUNTIME/webcam.pid"
WEBCAM_SIZEFILE="$CAPTURE_RUNTIME/webcam.size"
WEBCAM_SOCKET="$CAPTURE_RUNTIME/webcam.sock"
WEBCAM_LOG="$CAPTURE_RUNTIME/webcam.log"
THUMB="$CAPTURE_RUNTIME/record-thumb.png"

RECORDER=gpu-screen-recorder
proc_root=${CAPTURE_PROC_ROOT:-/proc}

# --- state -------------------------------------------------------------------

capture_process_matches() {
  local pid=$1 executable=$2
  local -a argv=()
  [[ $pid =~ ^[1-9][0-9]*$ && -O $proc_root/$pid ]] || return 1
  mapfile -d '' -t argv <"$proc_root/$pid/cmdline" 2>/dev/null || return 1
  [[ ${argv[0]:-} == "$executable" || ${argv[0]:-} == */"$executable" ]] || return 1
  [[ $executable != mpv || " ${argv[*]} " == *' --title=capture-webcam '* ]]
}

# Prints the live recorder pid, or nothing. Clears a stale pidfile as a side
# effect so the next toggle starts cleanly instead of refusing forever.
record_pid() {
  [ -f "$PIDFILE" ] || return 1
  local pid
  pid=$(cat "$PIDFILE" 2>/dev/null || true)
  if capture_process_matches "$pid" "$RECORDER"; then
    printf '%s' "$pid"
    return 0
  fi
  rm -f "$PIDFILE"
  return 1
}

# Tell the bar's REC pill to re-read status now. It polls slowly as a backstop
# for a crashed recorder; start and stop announce themselves. Detached so a
# missing or busy shell never delays the recorder.
record_refresh_bar() {
  command -v quickshell >/dev/null 2>&1 &&
    { quickshell ipc call record refresh >/dev/null 2>&1 & }
  return 0
}

record_status() {
  if record_pid >/dev/null; then
    printf 'recording\n'
  else
    printf 'idle\n'
  fi
}

# --- audio -------------------------------------------------------------------
# Device names are resolved at runtime: the default sink here is Bluetooth and
# changes whenever headphones connect, so a hardcoded name would rot.

desktop_audio_device() {
  local sink
  sink=$(pactl get-default-sink 2>/dev/null || true)
  [ -n "$sink" ] && printf '%s.monitor' "$sink"
}

mic_audio_device() {
  pactl get-default-source 2>/dev/null || true
}

# Emits the -a arguments. Desktop+mic are merged into ONE track (gsr's "|"
# syntax) so ordinary players hear both; separate tracks confuse most of them.
audio_args() {
  local mode="$1" desktop mic
  case "$mode" in
    none) return 0 ;;
    desktop)
      desktop=$(desktop_audio_device)
      [ -n "$desktop" ] && printf '%s\n%s\n' -a "$desktop"
      ;;
    mic)
      mic=$(mic_audio_device)
      [ -n "$mic" ] && printf '%s\n%s\n' -a "$mic"
      ;;
    both)
      desktop=$(desktop_audio_device)
      mic=$(mic_audio_device)
      if [ -n "$desktop" ] && [ -n "$mic" ]; then
        printf '%s\n%s\n' -a "${desktop}|${mic}"
      elif [ -n "$desktop" ]; then
        printf '%s\n%s\n' -a "$desktop"
      elif [ -n "$mic" ]; then
        printf '%s\n%s\n' -a "$mic"
      fi
      ;;
  esac
}

# --- webcam ------------------------------------------------------------------

webcam_device() {
  if [ "$WEBCAM_DEVICE" != "auto" ]; then
    printf '%s' "$WEBCAM_DEVICE"
    return 0
  fi
  # The first device that actually reports capture formats. This box exposes
  # /dev/video0 AND /dev/video1 for one camera; only one of them captures.
  local d
  for d in /dev/video*; do
    [ -e "$d" ] || continue
    if v4l2-ctl -d "$d" --list-formats 2>/dev/null | grep -q '\[0\]'; then
      printf '%s' "$d"
      return 0
    fi
  done
  return 1
}

webcam_overlay_size() {
  case "${1:-$WEBCAM_DEFAULT_SIZE}" in
    small)  printf '320x180' ;;
    large)  printf '640x360' ;;
    *)      printf '480x270' ;;
  esac
}

webcam_live_pid() {
  [ -f "$WEBCAM_PIDFILE" ] || return 1
  local pid
  pid=$(cat "$WEBCAM_PIDFILE" 2>/dev/null || true)
  if capture_process_matches "$pid" mpv; then
    printf '%s' "$pid"
    return 0
  fi
  rm -f "$WEBCAM_PIDFILE" "$WEBCAM_SIZEFILE" "$WEBCAM_SOCKET"
  return 1
}

webcam_send_geometry() {
  local geometry="$1"

  # Tests can replace the transport without opening a live mpv socket.
  if [ -n "${WEBCAM_IPC_HELPER:-}" ]; then
    "$WEBCAM_IPC_HELPER" "$WEBCAM_SOCKET" "$geometry"
    return
  fi

  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$WEBCAM_SOCKET" "$geometry" <<'PY'
import json
import socket
import sys

socket_path, geometry = sys.argv[1:]
request = json.dumps({"command": ["set_property", "geometry", geometry]}) + "\n"

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.settimeout(1.0)
    client.connect(socket_path)
    client.sendall(request.encode())
    response = b""
    while b"\n" not in response:
        chunk = client.recv(4096)
        if not chunk:
            break
        response += chunk

result = json.loads(response.split(b"\n", 1)[0] or b"{}")
if result.get("error") != "success":
    raise SystemExit(1)
PY
}

webcam_resize_via_hyprland() {
  local pid="$1" size="$2"
  local hyprctl_command=${WEBCAM_HYPRCTL:-hyprctl}
  command -v "$hyprctl_command" >/dev/null 2>&1 || return 1
  local width=${size%x*}
  local height=${size#*x}
  "$hyprctl_command" dispatch \
    "hl.dsp.window.resize({ x = $width, y = $height, window = \"pid:$pid\" })" \
    >/dev/null
}

webcam_resize() {
  local direction="$1" current next geometry size pid
  case "$direction" in smaller|larger) ;; *) return 2 ;; esac

  if ! pid=$(webcam_live_pid); then
    webcam_toggle
    pid=$(webcam_live_pid) || return 0
  fi

  current=$(cat "$WEBCAM_SIZEFILE" 2>/dev/null || printf '%s' "$WEBCAM_DEFAULT_SIZE")
  case "$current:$direction" in
    small:smaller|large:larger) next="$current" ;;
    medium:smaller) next=small ;;
    large:smaller) next=medium ;;
    small:larger) next=medium ;;
    medium:larger) next=large ;;
    *) next=medium ;;
  esac
  [ "$next" = "$current" ] && return 0

  size=$(webcam_overlay_size "$next")
  geometry="${size}-20-60"
  if ! webcam_send_geometry "$geometry"; then
    # Covers overlays started before IPC support and mpv backends that reject
    # changing geometry at runtime. The PID selector avoids resizing any other
    # mpv window the user may have open.
    if ! webcam_resize_via_hyprland "$pid" "$size"; then
      notify_error "Could not resize the webcam overlay"
      return 0
    fi
  fi
  printf '%s\n' "$next" > "$WEBCAM_SIZEFILE"
}

webcam_start() {
  local dev size w h
  dev=$(webcam_device) || { notify "Recording" "No webcam found — recording without it"; return 0; }
  has mpv || { notify "Recording" "mpv not installed — recording without webcam"; return 0; }

  size=$(webcam_overlay_size)
  w=${size%x*}; h=${size#*x}

  # Borderless, no OSD, no audio, always on top, parked bottom-right so it does
  # not sit over what is being demonstrated.
  rm -f "$WEBCAM_SOCKET" "$WEBCAM_SIZEFILE" "$WEBCAM_LOG"
  mpv av://v4l2:"$dev" \
    --profile=low-latency --untimed \
    --no-audio --no-osc --no-osd-bar --no-border --ontop \
    --geometry="${w}x${h}-20-60" \
    --title="capture-webcam" \
    --input-ipc-server="$WEBCAM_SOCKET" \
    --demuxer-lavf-o=input_format=mjpeg,video_size="$WEBCAM_RESOLUTION" \
    >"$WEBCAM_LOG" 2>&1 &
  echo $! > "$WEBCAM_PIDFILE"
  printf '%s\n' "$WEBCAM_DEFAULT_SIZE" > "$WEBCAM_SIZEFILE"
}

webcam_stop() {
  [ -f "$WEBCAM_PIDFILE" ] || return 0
  local pid
  if pid=$(webcam_live_pid); then
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$WEBCAM_PIDFILE" "$WEBCAM_SIZEFILE" "$WEBCAM_SOCKET"
}

webcam_wait_until_ready() {
  local attempt=0 attempts=${WEBCAM_STARTUP_ATTEMPTS:-20} pid
  pid=$(<"$WEBCAM_PIDFILE")
  while [ "$attempt" -lt "$attempts" ]; do
    if capture_process_matches "$pid" mpv &&
      { [ -n "${WEBCAM_IPC_HELPER:-}" ] || [ -S "$WEBCAM_SOCKET" ]; }; then
      return 0
    fi
    sleep "${WEBCAM_STARTUP_DELAY:-0.1}"
    attempt=$((attempt + 1))
  done
  return 1
}

webcam_toggle() {
  if webcam_live_pid >/dev/null; then
    webcam_stop
    notify "Webcam" "Overlay hidden"
    return 0
  fi

  webcam_device >/dev/null || {
    notify_error "No webcam found"
    return 0
  }
  has mpv || {
    notify_error "mpv is not installed"
    return 0
  }

  webcam_start
  if webcam_wait_until_ready; then
    notify "Webcam" "Overlay shown"
  else
    webcam_stop
    notify_error "Could not open the webcam overlay — see $WEBCAM_LOG"
  fi
}

# --- start -------------------------------------------------------------------

record_start() {
  local audio="desktop" target_mode="monitor" webcam=0 arg

  for arg in "$@"; do
    case "$arg" in
      --audio=*)     audio="${arg#--audio=}" ;;
      --target=*)    target_mode="${arg#--target=}" ;;
      --with-webcam) webcam=1 ;;
    esac
  done

  if record_pid >/dev/null; then
    notify_error "A recording is already running"
    return 1
  fi

  require_cmd "$RECORDER" gpu-screen-recorder || return 1
  capture_require_writable "$SCREENRECORD_DIR" || return 1

  # --- resolve the target ---
  capture_trap_cleanup
  capture_freeze_start
  local target
  if ! target=$(capture_select "$target_mode"); then
    return 0
  fi
  capture_freeze_stop

  local -a gsr_args=()
  local width=0 height=0

  case "$target" in
    monitor:*)
      local name="${target#monitor:}"
      gsr_args+=(-w "$name")
      read -r width height < <(
        capture_monitors | awk -F'\t' -v n="$name" '$2==n {split($1,a," "); split(a[2],d,"x"); print d[1], d[2]}'
      ) || true
      # A monitor unplugged between selection and start leaves these empty, and
      # an empty string is not a number -- the downscale test below would abort.
      [ -n "$width" ]  || width=0
      [ -n "$height" ] || height=0
      ;;
    region:*)
      local geo="${target#region:}"
      local pos="${geo%% *}" dim="${geo#* }"
      width=${dim%x*}; height=${dim#*x}
      # Region recording is a newer gsr feature; check before relying on it.
      if "$RECORDER" --help 2>&1 | grep -q -- '-region'; then
        gsr_args+=(-w region -region "${dim}+${pos%%,*}+${pos#*,}")
      else
        notify_error "This gpu-screen-recorder has no region support — recording the monitor instead"
        local fallback
        fallback=$(capture_focused_monitor)
        gsr_args+=(-w "$fallback")
      fi
      ;;
  esac

  # --- downscale only if genuinely oversized ---
  local max_w=${SCREENRECORD_MAX_RESOLUTION%x*}
  local max_h=${SCREENRECORD_MAX_RESOLUTION#*x}
  if [ "$width" -gt 0 ] && { [ "$width" -gt "$max_w" ] || [ "$height" -gt "$max_h" ]; }; then
    gsr_args+=(-s "$SCREENRECORD_MAX_RESOLUTION")
  fi

  local outfile
  outfile=$(capture_outfile "$SCREENRECORD_DIR" screenrecording mp4)

  local -a aargs=()
  mapfile -t aargs < <(audio_args "$audio")

  [ "$webcam" -eq 1 ] && webcam_start

  # Prefer the GPU and let gsr choose its codec. If no supported hardware
  # encoder is available (or the capture is too large for it), fall back to the
  # CPU encoder instead of exiting immediately.
  "$RECORDER" \
    "${gsr_args[@]}" \
    -f "$SCREENRECORD_FPS" \
    -fm cfr \
    -k auto \
    -fallback-cpu-encoding yes \
    -c mp4 \
    "${aargs[@]}" \
    -o "$outfile" \
    >"$CAPTURE_RUNTIME/record.log" 2>&1 &

  local pid=$!
  echo "$pid" > "$PIDFILE"
  printf '%s' "$outfile" > "$OUTFILE_REF"

  # Give it a moment to fail loudly (bad device, no permission) rather than
  # silently reporting a recording that never started.
  sleep 0.5
  if ! [ -d "/proc/$pid" ]; then
    rm -f "$PIDFILE" "$OUTFILE_REF"
    webcam_stop
    notify_error "Recorder failed to start — see $CAPTURE_RUNTIME/record.log"
    return 1
  fi

  record_refresh_bar
  notify "Recording started" "$(basename "$outfile")"
}

# --- stop --------------------------------------------------------------------

record_stop() {
  local pid
  if ! pid=$(record_pid); then
    notify_error "No recording is running"
    return 1
  fi

  local outfile=""
  [ -f "$OUTFILE_REF" ] && outfile=$(cat "$OUTFILE_REF" 2>/dev/null || true)

  # SIGINT is what tells gsr to finalise the container. Anything harsher leaves
  # an unplayable file.
  kill -INT "$pid" 2>/dev/null || true

  local waited=0
  while capture_process_matches "$pid" "$RECORDER" && [ "$waited" -lt 50 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  local incomplete=0
  if capture_process_matches "$pid" "$RECORDER"; then
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.5
    incomplete=1
  fi

  rm -f "$PIDFILE" "$OUTFILE_REF"
  record_refresh_bar
  webcam_stop

  if [ -z "$outfile" ] || [ ! -f "$outfile" ]; then
    notify_error "Recording stopped but no output file was produced"
    return 1
  fi

  record_postprocess "$outfile"

  if [ "$incomplete" -eq 1 ]; then
    notify_error "Recorder did not stop cleanly — $(basename "$outfile") may be truncated"
    return 0
  fi

  record_notify_saved "$outfile"
}

# --- post-processing ---------------------------------------------------------
# Nothing here runs unless explicitly enabled: a stream copy is the default, so
# a recording is never re-encoded just for the sake of it.

record_postprocess() {
  local file="$1"
  has ffmpeg || return 0

  local do_trim=0 do_norm=0
  awk "BEGIN{exit !($SCREENRECORD_TRIM > 0)}" && do_trim=1
  [ "$SCREENRECORD_NORMALIZE" = "1" ] && do_norm=1
  [ "$do_trim" -eq 0 ] && [ "$do_norm" -eq 0 ] && return 0

  local tmp="${file%.mp4}-proc.mp4"
  local -a args=(-y -hide_banner -loglevel error)

  [ "$do_trim" -eq 1 ] && args+=(-ss "$SCREENRECORD_TRIM")
  args+=(-i "$file")

  if [ "$do_norm" -eq 1 ]; then
    # Audio must be re-encoded to be filtered; video is still copied.
    args+=(-c:v copy
           -af "loudnorm=I=${SCREENRECORD_LOUDNESS}:TP=${SCREENRECORD_TRUE_PEAK}:LRA=${SCREENRECORD_LRA}"
           -c:a aac -b:a 128k)
  else
    args+=(-c copy)
  fi
  args+=(-movflags +faststart "$tmp")

  if ffmpeg "${args[@]}" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$file"
  else
    rm -f "$tmp"
  fi
}

record_notify_saved() {
  local file="$1" body
  body="$(basename "$file")"

  # Mid-frame thumbnail for the notification preview.
  rm -f "$THUMB"
  if has ffprobe && has ffmpeg; then
    local dur mid
    dur=$(ffprobe -v error -show_entries format=duration \
          -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || true)
    case "$dur" in ''|N/A) dur=1 ;; esac
    mid=$(awk "BEGIN{printf \"%.2f\", $dur / 2}")
    ffmpeg -y -hide_banner -loglevel error -ss "$mid" -i "$file" \
           -frames:v 1 "$THUMB" 2>/dev/null || rm -f "$THUMB"
  fi

  # -t bounds the blocking `notify-send -A` below; see screenshot.sh.
  local -a nargs=(-a "$CAPTURE_APP" -t 12000)
  [ -f "$THUMB" ] && nargs+=(-i "$THUMB" -h "string:image-path:$THUMB")

  if has notify-send; then
    # shellcheck disable=SC2016 # Expanded in the detached notification shell.
    setsid --fork bash -c '
      file="$1"; player="$2"; body="$3"; shift 3
      choice=$(notify-send "$@" -A "open=Open" "Screen recording saved" "$body" 2>/dev/null) || exit 0
      if [ "$choice" = "open" ]; then
        if command -v "$player" >/dev/null 2>&1; then exec "$player" "$file"; fi
        command -v xdg-open >/dev/null 2>&1 && exec xdg-open "$file"
      fi
    ' _ "$file" "$SCREENRECORD_PLAYER" "$body" "${nargs[@]}" \
        >/dev/null 2>&1 </dev/null || true
  fi
}

# --- menu --------------------------------------------------------------------

record_menu() {
  local rofi_theme="$HOME/.config/rofi/current-theme.rasi"
  [ -f "$rofi_theme" ] || rofi_theme="$HOME/.config/rofi/comet-glass.rasi"

  has rofi || { record_start --audio=desktop --target=monitor; return; }

  local items="No audio
Desktop audio
Desktop + microphone"
  if webcam_device >/dev/null 2>&1; then
    items="$items
Desktop + microphone + webcam"
  fi

  local choice
  choice=$(printf '%s\n' "$items" | rofi -dmenu -i -p "Record" \
    -mesg "Screen recording" -theme "$rofi_theme") || return 0
  [ -n "$choice" ] || return 0

  case "$choice" in
    "No audio")                        record_start --audio=none    --target=smart ;;
    "Desktop audio")                   record_start --audio=desktop --target=smart ;;
    "Desktop + microphone")            record_start --audio=both    --target=smart ;;
    "Desktop + microphone + webcam")   record_start --audio=both    --target=smart --with-webcam ;;
  esac
}

# --- dispatch ----------------------------------------------------------------

ACTION="${1:-toggle}"
shift || true

case "$ACTION" in
  status)  record_status ;;
  start)   record_start "$@" ;;
  stop)    record_stop ;;
  menu)    record_menu ;;
  webcam-toggle) webcam_toggle ;;
  webcam-size)
    [ $# -eq 1 ] || { printf 'record.sh: webcam-size requires smaller or larger\n' >&2; exit 2; }
    webcam_resize "$1"
    ;;
  toggle)
    if record_pid >/dev/null; then
      record_stop
    else
      record_menu
    fi
    ;;
  *) printf 'record.sh: unknown action: %s\n' "$ACTION" >&2; exit 2 ;;
esac
