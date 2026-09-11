#!/usr/bin/env bash
set -euo pipefail

repo_dir="${GOURCE_DOTFILES_DIR:-$HOME/dotfiles}"
runtime_root="${XDG_RUNTIME_DIR:-/tmp}"
player_bin="${GOURCE_DOTFILES_PLAYER:-mpv}"
# Prioritize the shortest possible render and preserve that fast pace during
# playback; mpv's normal 1.00 speed is therefore the intended viewing speed.
render_seconds_per_day=0.001

usage() {
  printf 'Usage: %s [--dry-run]\n' "${0##*/}"
}

dry_run=false
case "${1:-}" in
  '') ;;
  --dry-run) dry_run=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'Gource dotfiles: not a Git work tree: %s\n' "$repo_dir" >&2
  exit 1
}

if "$dry_run"; then
  printf 'dry-run: render %s 150x faster in a virtual display, play the temporary MP4 under %s at source speed fullscreen with %s, then delete it\n' \
    "$repo_dir" "$runtime_root" "$player_bin"
  exit 0
fi

for command_name in xvfb-run gource ffmpeg "$player_bin"; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Gource dotfiles: required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
done

runtime_dir=$(mktemp -d "$runtime_root/gource-dotfiles.XXXXXX")
output_file="$runtime_dir/gource-dotfiles.mp4"
trap 'rm -rf -- "$runtime_dir"' EXIT INT TERM

(
  cd "$repo_dir"
  xvfb-run -a -s "-screen 0 1280x720x24" gource \
    --title "My Dotfiles" \
    --camera-mode overview \
    --background-colour 000000 \
    --date-format "%B %d, %Y" \
    --seconds-per-day "$render_seconds_per_day" \
    --auto-skip-seconds 0.01 \
    --file-idle-time 0 \
    --max-files 0 \
    --no-vsync \
    --hide mouse,bloom \
    --stop-at-end \
    -1280x720 \
    --output-ppm-stream - \
    --output-framerate 30 \
  | ffmpeg \
    -y \
    -r 30 \
    -f image2pipe \
    -vcodec ppm \
    -i - \
    -fps_mode vfr \
    -vcodec libx264 \
    -preset ultrafast \
    -pix_fmt yuv420p \
    -crf 18 \
    "$output_file"
)

"$player_bin" --force-window=immediate --fullscreen=yes "$output_file"
