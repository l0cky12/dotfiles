#!/usr/bin/env bash
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/spotify-art"
mkdir -p "$CACHE_DIR"

playerctl --player=spotify metadata --follow \
  --format '{{artist}}|{{title}}|{{album}}|{{mpris:artUrl}}' |
while IFS='|' read -r artist title album arturl; do
  [ -z "${title:-}" ] && continue

  icon=""
  tmpfile="$CACHE_DIR/current.jpg"

  case "${arturl:-}" in
    file://*)
      icon="${arturl#file://}"
      ;;
    http://*|https://*)
      if curl --fail --location --silent --show-error \
        --proto '=http,https' --proto-redir '=http,https' \
        --connect-timeout 3 --max-time 5 "$arturl" -o "$tmpfile"; then
        icon="$tmpfile"
      fi
      ;;
  esac

  body="$artist"
  [ -n "${album:-}" ] && body="$artist — $album"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    notify-send \
      -a "Spotify" \
      -r 991049 \
      -i "$icon" \
      "Now Playing" \
      "$title"$'\n'"$body"
  else
    notify-send \
      -a "Spotify" \
      -r 991049 \
      "Now Playing" \
      "$title"$'\n'"$body"
  fi
done
