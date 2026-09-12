#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */
# Wallpaper picker for Hyprland:
# - images -> hyprpaper
# - videos -> mpvpaper
# Autostart file: ~/.config/hypr/conf/autostart.lua

set -euo pipefail

terminal=kitty
wallDIR="$HOME/Pictures/wallpapers"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
wallpaper_current="$HOME/.config/hypr/wallpaper_effects/.wallpaper_current"
autostart_config="${HYPR_AUTOSTART_CONFIG:-$HOME/.config/hypr/conf/autostart.lua}"
hyprpaper_conf="$HOME/.config/hypr/hyprpaper.conf"

# Directory for swaync
iDIR="$HOME/.config/swaync/images"

# Rofi
rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi"

# Hyprpaper fit mode: cover | contain | tile | fill
fit_mode="cover"

notify_error() {
  notify-send -i "$iDIR/error.png" "E-R-R-O-R" "$1"
}

require_cmd() {
  local cmd="$1"
  local msg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    notify_error "$msg"
    exit 1
  fi
}

is_video_file() {
  [[ "$1" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]
}

get_focused_monitor() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'
  else
    hyprctl monitors | awk '/^Monitor/{name=$2} /focused: yes/{print name}'
  fi
}

get_monitor_scale() {
  local mon="$1"
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r --arg mon "$mon" '.[] | select(.name == $mon) | .scale'
  else
    hyprctl monitors | awk -v mon="$mon" '
      $1=="Monitor" && $2==mon {found=1}
      found && $1=="scale:" {print $2; exit}
    '
  fi
}

get_monitor_height() {
  local mon="$1"
  if command -v jq >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r --arg mon "$mon" '.[] | select(.name == $mon) | .height'
  else
    hyprctl monitors | awk -v mon="$mon" '
      $1=="Monitor" && $2==mon {found=1}
      found && $1=="height:" {print $2; exit}
    '
  fi
}

trim_line() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

modify_autostart_config() {
  local selected_file="$1"
  local command begin_marker end_marker tmp
  begin_marker="-- >>> legacy-wallpaper-picker >>>"
  end_marker="-- <<< legacy-wallpaper-picker <<<"

  mkdir -p "$(dirname "$autostart_config")"
  touch "$autostart_config"

  if is_video_file "$selected_file"; then
    command=$(printf 'mpvpaper "*" -o "load-scripts=no no-audio --loop" "%s"' "$selected_file" | jq -Rs .)
    echo "Configured autostart for live wallpaper (video)."
  else
    command='"hyprpaper"'
    echo "Configured autostart for static wallpaper (image)."
  fi

  tmp=$(mktemp "${autostart_config}.XXXXXX")
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$autostart_config" >"$tmp"
  printf '\n%s\nhl.on("hyprland.start", function()\n    hl.exec_cmd(%s)\nend)\n%s\n' \
    "$begin_marker" "$command" "$end_marker" >>"$tmp"
  chmod --reference="$autostart_config" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$autostart_config"
}

escape_for_hyprlang() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

update_hyprpaper_conf() {
  local mon="$1"
  local image_path="$2"
  local escaped_path
  local begin_marker="# >>> wallpaper-picker:${mon} >>>"
  local end_marker="# <<< wallpaper-picker:${mon} <<<"
  local tmp

  escaped_path="$(escape_for_hyprlang "$image_path")"

  mkdir -p "$(dirname "$hyprpaper_conf")"
  touch "$hyprpaper_conf"

  # Ensure IPC is enabled
  if grep -qE '^[[:space:]]*ipc[[:space:]]*=' "$hyprpaper_conf"; then
    sed -i -E 's/^[[:space:]]*ipc[[:space:]]*=.*/ipc = true/' "$hyprpaper_conf"
  else
    printf '\nipc = true\n' >> "$hyprpaper_conf"
  fi

  # Remove any previous managed block for this monitor
  tmp="$(mktemp)"
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin {skip=1; next}
    $0 == end   {skip=0; next}
    !skip       {print}
  ' "$hyprpaper_conf" > "$tmp"
  mv "$tmp" "$hyprpaper_conf"

  # Append new managed block for this monitor
  {
    printf '\n%s\n' "$begin_marker"
    printf 'wallpaper {\n'
    printf '    monitor = %s\n' "$mon"
    printf '    path = "%s"\n' "$escaped_path"
    printf '    fit_mode = %s\n' "$fit_mode"
    printf '}\n'
    printf '%s\n' "$end_marker"
  } >> "$hyprpaper_conf"
}

ensure_hyprpaper_running() {
  if ! pgrep -x hyprpaper >/dev/null 2>&1; then
    hyprpaper >/dev/null 2>&1 &
    disown || true
    sleep 0.7
  fi
}

kill_wallpaper_for_video() {
  pkill -x mpvpaper 2>/dev/null || true
  pkill -x swaybg 2>/dev/null || true
  pkill -x hyprpaper 2>/dev/null || true
  pkill -x swww-daemon 2>/dev/null || true
}

kill_wallpaper_for_image() {
  pkill -x mpvpaper 2>/dev/null || true
  pkill -x swaybg 2>/dev/null || true
  pkill -x swww-daemon 2>/dev/null || true
}

# Offer SDDM Simple Wallpaper Option (only for non-video wallpapers)
set_sddm_wallpaper() {
  sleep 1

  local sddm_themes_dir=""
  if [ -d "/usr/share/sddm/themes" ]; then
    sddm_themes_dir="/usr/share/sddm/themes"
  elif [ -d "/run/current-system/sw/share/sddm/themes" ]; then
    sddm_themes_dir="/run/current-system/sw/share/sddm/themes"
  fi

  [ -z "$sddm_themes_dir" ] && return 0

  local sddm_simple="$sddm_themes_dir/simple_sddm_2"

  if [ -d "$sddm_simple" ] && [ -w "$sddm_simple/Backgrounds" ]; then
    if pidof yad >/dev/null 2>&1; then
      killall yad
    fi

    if yad --info \
      --text="Set current wallpaper as SDDM background?\n\nNOTE: This only applies to SIMPLE SDDM v2 Theme" \
      --text-align=left \
      --title="SDDM Background" \
      --timeout=5 \
      --timeout-indicator=right \
      --button="yes:0" \
      --button="no:1"; then

      if ! command -v "$terminal" >/dev/null 2>&1; then
        notify-send -i "$iDIR/error.png" "Missing $terminal" "Install $terminal to enable setting of wallpaper background"
        exit 1
      fi

      "$SCRIPTSDIR/sddm_wallpaper.sh" --normal
    fi
  fi
}

apply_image_wallpaper() {
  local image_path="$1"

  require_cmd hyprpaper "hyprpaper not found"
  require_cmd hyprctl "hyprctl not found"

  kill_wallpaper_for_image
  ensure_hyprpaper_running
  update_hyprpaper_conf "$focused_monitor" "$image_path"

  # Newer hyprpaper IPC
  if ! hyprctl hyprpaper wallpaper "${focused_monitor},${image_path},${fit_mode}" >/dev/null 2>&1; then
    # Fallback for older releases that still support reload syntax
    hyprctl hyprpaper reload "${focused_monitor},${image_path}" >/dev/null 2>&1 || {
      notify_error "Failed to set wallpaper with hyprpaper"
      return 1
    }
  fi

  mkdir -p "$(dirname "$wallpaper_current")"
  cp -f "$image_path" "$wallpaper_current" 2>/dev/null || true

  # Keep your existing theming pipeline
  "$SCRIPTSDIR/WallustSwww.sh" "$image_path" || true
  sleep 1
  "$SCRIPTSDIR/Refresh.sh" || true

  set_sddm_wallpaper
}

apply_video_wallpaper() {
  local video_path="$1"

  if ! command -v mpvpaper >/dev/null 2>&1; then
    notify_error "mpvpaper not found"
    return 1
  fi

  kill_wallpaper_for_video
  mpvpaper '*' -o "load-scripts=no no-audio --loop" "$video_path" &
}

# Retrieve wallpapers (images + videos)
mapfile -d '' PICS < <(
  find -L "${wallDIR}" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
    -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o \
    -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \
  \) -print0
)

if [[ ${#PICS[@]} -eq 0 ]]; then
  notify_error "No wallpapers found in $wallDIR"
  exit 1
fi

RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
RANDOM_PIC_NAME=". random"

menu() {
  IFS=$'\n' sorted_options=($(sort <<<"${PICS[*]}"))

  printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC"

  for pic_path in "${sorted_options[@]}"; do
    pic_name="$(basename "$pic_path")"

    if [[ "$pic_name" =~ \.gif$ ]]; then
      cache_gif_image="$HOME/.cache/gif_preview/${pic_name}.png"
      if [[ ! -f "$cache_gif_image" ]]; then
        mkdir -p "$HOME/.cache/gif_preview"
        magick "$pic_path[0]" -resize 1920x1080 "$cache_gif_image"
      fi
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$cache_gif_image"
    elif is_video_file "$pic_name"; then
      cache_preview_image="$HOME/.cache/video_preview/${pic_name}.png"
      if [[ ! -f "$cache_preview_image" ]]; then
        mkdir -p "$HOME/.cache/video_preview"
        ffmpeg -v error -y -i "$pic_path" -ss 00:00:01.000 -vframes 1 "$cache_preview_image"
      fi
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$cache_preview_image"
    else
      printf "%s\x00icon\x1f%s\n" "$(basename "$pic_path" | sed 's/\.[^.]*$//')" "$pic_path"
    fi
  done
}

main() {
  local -a rofi_args

  require_cmd rofi "rofi not found"
  require_cmd hyprctl "hyprctl not found"
  require_cmd bc "Install package bc first"

  focused_monitor="$(get_focused_monitor)"
  if [[ -z "$focused_monitor" ]]; then
    notify_error "Could not detect focused monitor"
    exit 1
  fi

  scale_factor="$(get_monitor_scale "$focused_monitor")"
  monitor_height="$(get_monitor_height "$focused_monitor")"

  icon_size="$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc)"
  adjusted_icon_size="$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')"
  rofi_override="element-icon{size:${adjusted_icon_size}%;}"
  rofi_args=(-i -show -dmenu -config "$rofi_theme" -theme-str "$rofi_override")

  choice="$(menu | rofi "${rofi_args[@]}")"
  choice="$(trim_line "$choice")"
  RANDOM_PIC_NAME="$(trim_line "$RANDOM_PIC_NAME")"

  if [[ -z "$choice" ]]; then
    exit 0
  fi

  if [[ "$choice" == "$RANDOM_PIC_NAME" ]]; then
    choice="$(basename "$RANDOM_PIC")"
  fi

  choice_basename="$(basename "$choice" | sed 's/\(.*\)\.[^.]*$/\1/')"
  selected_file="$(find "$wallDIR" -iname "$choice_basename.*" -print -quit)"

  if [[ -z "$selected_file" ]]; then
    notify_error "File not found for selection: $choice"
    exit 1
  fi

  modify_autostart_config "$selected_file"

  if is_video_file "$selected_file"; then
    apply_video_wallpaper "$selected_file"
  else
    apply_image_wallpaper "$selected_file"
  fi
}

if pidof rofi >/dev/null 2>&1; then
  pkill rofi
fi

main
