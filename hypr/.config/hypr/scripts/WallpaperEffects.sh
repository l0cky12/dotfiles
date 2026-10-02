#!/usr/bin/env bash

set -euo pipefail

ipc=(qs -c noctalia-shell ipc call)
cache_dir="$HOME/.cache/wallpaper-effects"
rofi_theme="$HOME/.config/rofi/current-theme.rasi"

notify() {
  local title="$1"
  local message="$2"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" || true
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '%s not found\n' "$cmd" >&2
    exit 1
  fi
}

require_cmd magick
require_cmd rofi
require_cmd jq
require_cmd hyprctl

focused_monitor="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')"
if [ -z "$focused_monitor" ]; then
  notify "Wallpaper Effects" "Could not detect focused monitor"
  exit 1
fi

original_file="$cache_dir/original-$focused_monitor"
mkdir -p "$cache_dir"

current="$("${ipc[@]}" wallpaper get "$focused_monitor")"

if [ -z "$current" ] || [ ! -f "$current" ]; then
  notify "Wallpaper Effects" "No wallpaper found for $focused_monitor"
  exit 1
fi

if [[ "$current" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
  notify "Wallpaper Effects" "Current wallpaper is a video; effects only work on images"
  exit 1
fi

# Remember the untouched wallpaper so effects never stack
if [[ "$current" != "$cache_dir"/* ]]; then
  printf '%s\n' "$current" >"$original_file"
fi

if [ ! -f "$original_file" ]; then
  notify "Wallpaper Effects" "Original wallpaper for $focused_monitor is unknown"
  exit 1
fi

original="$(cat "$original_file")"
if [ ! -f "$original" ]; then
  notify "Wallpaper Effects" "Original wallpaper no longer exists: $original"
  exit 1
fi

effects=(
  "No Effect"
  "Black & White"
  "Blurred"
  "Charcoal"
  "Edge Detect"
  "Negate"
  "Oil Paint"
  "Polaroid"
  "Posterize"
  "Sepia"
  "Solarize"
  "Vignette"
)

if pgrep -x rofi >/dev/null 2>&1; then
  pkill rofi
fi

rofi_cmd=(rofi -i -dmenu -p "Wallpaper Effect" -mesg "Monitor: $focused_monitor")
if [ -f "$rofi_theme" ]; then
  rofi_cmd+=(-theme "$rofi_theme")
fi

selection="$(printf '%s\n' "${effects[@]}" | "${rofi_cmd[@]}")" || exit 0
[ -z "$selection" ] && exit 0

if [ "$selection" = "No Effect" ]; then
  "${ipc[@]}" wallpaper set "$original" "$focused_monitor"
  rm -f "$cache_dir/wp-$focused_monitor-"*.jpg
  notify "Wallpaper Effects" "Restored original wallpaper"
  exit 0
fi

slug="$(printf '%s' "$selection" | tr '[:upper:] &' '[:lower:]--' | tr -s '-')"
out="$cache_dir/wp-$focused_monitor-$slug.jpg"

notify "Wallpaper Effects" "Applying $selection..."

case "$selection" in
  "Black & White") magick "$original" -colorspace Gray -sigmoidal-contrast 10,40% "$out" ;;
  "Blurred")       magick "$original" -blur 0x12 "$out" ;;
  "Charcoal")      magick "$original" -charcoal 3 "$out" ;;
  "Edge Detect")   magick "$original" -colorspace Gray -edge 2 -negate "$out" ;;
  "Negate")        magick "$original" -negate "$out" ;;
  "Oil Paint")     magick "$original" -paint 6 "$out" ;;
  "Polaroid")      magick "$original" -bordercolor White -background '#101019' -polaroid 4 -background '#101019' -flatten "$out" ;;
  "Posterize")     magick "$original" -posterize 4 "$out" ;;
  "Sepia")         magick "$original" -sepia-tone 65% "$out" ;;
  "Solarize")      magick "$original" -solarize 80% "$out" ;;
  "Vignette")      magick "$original" -background black -vignette 0x100+10+10 "$out" ;;
  *)
    notify "Wallpaper Effects" "Effect not recognized: $selection"
    exit 1
    ;;
esac

if [ ! -s "$out" ]; then
  notify "Wallpaper Effects" "Failed to render $selection"
  exit 1
fi

# Drop older renders for this monitor, keep the one we just made
find "$cache_dir/" -maxdepth 1 -type f -name "wp-$focused_monitor-*.jpg" ! -name "${out##*/}" -delete

"${ipc[@]}" wallpaper set "$out" "$focused_monitor"
notify "Wallpaper Effects" "Applied $selection"
