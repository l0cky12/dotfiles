#!/usr/bin/env bash
# =============================================================================
# eject-drive.sh — safely unmount and power off removable drives (Super+U)
#
# Shows mounted removable drives in Rofi, asks for confirmation, then uses
# udisksctl to unmount every mounted filesystem on the drive and power off
# the disk. The visible label is display metadata only and is mapped back to
# a device with glob `case`; it is never eval'd.
#
# --dry-run prints the planned actions and touches nothing. --fixture reads
# an lsblk-style JSON file instead of probing real drives and implies
# --dry-run, so the fixture path can never mutate system state.
# =============================================================================
set -euo pipefail

DRY_RUN=false
FIXTURE=""
JSON_INPUT=""
JSON_TEMP=""

usage() {
  echo "Usage: $0 [--dry-run] [--fixture <lsblk-json-file>]" >&2
}

notify_status() {
  # User-initiated confirmations must surface under Do Not Disturb, matching
  # the swaync-bypass convention in dnd.sh and capture/common.sh.
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Eject drives" -h boolean:swaync-bypass-dnd:true "Eject drives" "$1" || true
  else
    printf 'Eject drives: %s\n' "$1" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { notify_status "$1 is not installed"; return 1; }
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --fixture)
      (($# >= 2)) || { usage; exit 1; }
      FIXTURE=$2
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

# The fixture path exists so tests can run without real drives; never let it
# reach the mutating udisksctl calls.
[[ -z "$FIXTURE" ]] || DRY_RUN=true

require_cmd jq || exit 1

if [[ -n "$FIXTURE" ]]; then
  [[ -r "$FIXTURE" ]] || { echo "Fixture is not readable: $FIXTURE" >&2; exit 1; }
  JSON_INPUT=$FIXTURE
else
  require_cmd lsblk || exit 1
  JSON_TEMP=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/eject-drive.XXXXXX")
  trap '[[ -z "$JSON_TEMP" ]] || rm -f -- "$JSON_TEMP"' EXIT
  # MOUNTPOINTS is the array column: a drive mounted at more than one path is
  # fully covered on eject. SIZE disambiguates two sticks sharing a label.
  lsblk -o NAME,RM,MOUNTPOINTS,LABEL,SIZE,TRAN -J > "$JSON_TEMP"
  JSON_INPUT=$JSON_TEMP
fi

# Collect every mounted filesystem that belongs to a removable drive. RM
# arrives as a boolean on util-linux >= 2.38 and as "1"/"0" strings on older
# builds; the transport lives on the parent disk, not on partitions, so the
# whole top-level disk is selected and all of its mounted descendants are
# gathered (partitions, LUKS holders, etc.).
DRIVES=$(jq -c '
  def rmflag: .rm == true or .rm == 1 or .rm == "1";
  [.blockdevices[]
   | select(rmflag or (.tran? == "usb"))
   | . as $disk
   | {
       name: $disk.name,
       label: ($disk.label // ""),
       size: ($disk.size // ""),
       nodes: ([ ($disk | .. | objects)
                 | . as $node
                 | ((($node.mountpoints? // [])[]?),
                    ($node.mountpoint? // empty))
                 | select(. != null and . != "")
                 | {name: $node.name, mountpoint: .} ]
               | unique_by(.name + .mountpoint))
     }
   | select(.nodes | length > 0)]
' "$JSON_INPUT")

# jq always emits an array here, so test for `[]` rather than emptiness.
if [[ -z "$DRIVES" || "$DRIVES" == "[]" ]]; then
  if $DRY_RUN; then
    echo "No mounted removable drives."
  else
    notify_status "No mounted removable drives."
  fi
  exit 0
fi

get_nodes() {
  # All mounted nodes of the selected drive.
  jq -r --arg sel "$SELECTED" '.[] | select(.name == $sel) | .nodes[]
    | [.name, .mountpoint] | @tsv' <<<"$DRIVES" | sort
}

if $DRY_RUN; then
  jq -r '.[] | . as $d
    | ($d.nodes[] | "Would unmount \(.name) at \(.mountpoint)"),
      ("Would power off \($d.name)")' <<<"$DRIVES"
  exit 0
fi

require_cmd rofi || exit 1
require_cmd udisksctl || exit 1

if pgrep -x rofi >/dev/null 2>&1; then
  pkill rofi
fi

ROFI_THEME="$HOME/.config/rofi/current-theme.rasi"
[[ -r "$ROFI_THEME" ]] || ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"

# One menu entry per top-level removable disk.
MENU=$(jq -r '.[]
  | "\(.label | if . == "" then .name else . end)  [\(.name)\(.size | if . == "" then "" else ", " + . end)]"' \
  <<<"$DRIVES")
CHOICE=$(printf '%s\n' "$MENU" | rofi -dmenu -i -p "Eject" \
  -mesg "Mounted removable drives" -theme "$ROFI_THEME") || exit 0
[[ -n "$CHOICE" ]] || exit 0

SELECTED=""
DRIVE_LABEL=""
while IFS=$'\t' read -r name label; do
  case "$CHOICE" in
    *" [$name]"*)
      SELECTED=$name
      DRIVE_LABEL=$label
      break
      ;;
  esac
done < <(jq -r '.[]
  | [.name, (.label | if . == "" then .name else . end)] | @tsv' <<<"$DRIVES")

[[ -n "$SELECTED" ]] || exit 0

CONFIRM=$(printf '%s\n' "󰇦  Eject — unmount + power off" "Cancel" |
  rofi -dmenu -i -p "Eject $DRIVE_LABEL? " -theme "$ROFI_THEME") || exit 0

case "$CONFIRM" in
  *"Eject — unmount + power off") ;;
  *) exit 0 ;;
esac

FAILED=0
while IFS=$'\t' read -r node _mountpoint; do
  # Device-mapper descendants (LUKS) live under /dev/mapper, everything else
  # under /dev.
  case "$node" in
    dm-*|luks-*|mapper/*) NODE_PATH="/dev/mapper/$node" ;;
    *)                    NODE_PATH="/dev/$node" ;;
  esac
  if ! udisksctl unmount -b "$NODE_PATH"; then
    notify_status "Failed to unmount $node on $DRIVE_LABEL ($SELECTED)."
    FAILED=1
  fi
done < <(get_nodes)

if ((FAILED)); then
  exit 1
fi

if ! udisksctl power-off -b "/dev/$SELECTED"; then
  notify_status "Unmounted $DRIVE_LABEL, but failed to power off $SELECTED."
  exit 1
fi

notify_status "Safely ejected $DRIVE_LABEL ($SELECTED)."
