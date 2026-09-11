#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/gource-dotfiles.sh"

output=$(GOURCE_DOTFILES_DIR="$repo_root" \
  XDG_RUNTIME_DIR=/tmp/gource-dotfiles-test-runtime \
  GOURCE_DOTFILES_PLAYER=mpv \
  "$script" --dry-run)

expected="dry-run: render $repo_root 150x faster in a virtual display, play the temporary MP4 under /tmp/gource-dotfiles-test-runtime at source speed fullscreen with mpv, then delete it"
[[ "$output" == "$expected" ]] || {
  printf 'unexpected dry-run output: %s\n' "$output" >&2
  exit 1
}

grep -Fqx '"$player_bin" --force-window=immediate --fullscreen=yes "$output_file"' "$script" || {
  printf 'Gource playback does not explicitly request fullscreen\n' >&2
  exit 1
}

grep -Fqx '  xvfb-run -a -s "-screen 0 1280x720x24" gource \' "$script" || {
  printf 'Gource rendering is not isolated in a virtual display\n' >&2
  exit 1
}

grep -Fqx 'render_seconds_per_day=0.001' "$script" || {
  printf 'Gource render speed is not configured for 150x acceleration\n' >&2
  exit 1
}

grep -Fqx '    --auto-skip-seconds 0.01 \' "$script" || {
  printf 'Gource idle gaps are not configured for maximum render speed\n' >&2
  exit 1
}

for expected_line in \
  '    --no-vsync \' \
  '    --hide mouse,bloom \' \
  '    -1280x720 \' \
  '    --output-framerate 30 \' \
  '    -r 30 \' \
  '    -preset ultrafast \'
do
  grep -Fqx "$expected_line" "$script" || {
    printf 'missing fast-render option: %s\n' "$expected_line" >&2
    exit 1
  }
done

if rg -q -- '--highlight-users|--key' "$script"; then
  printf 'slow optional Gource overlays are still enabled\n' >&2
  exit 1
fi

if rg -q -- 'playback_slowdown|setpts' "$script"; then
  printf 'Gource playback is still being slowed by timestamp stretching\n' >&2
  exit 1
fi

grep -Fqx '    -fps_mode vfr \' "$script" || {
  printf 'FFmpeg does not preserve sparse render timestamps\n' >&2
  exit 1
}
