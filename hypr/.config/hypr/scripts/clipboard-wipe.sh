#!/usr/bin/env bash
# Clear the active Wayland clipboard and wipe clipboard history while preserving
# pinned entries.
#
# Usage: clipboard-wipe.sh [pinned-id ...] | --pins JSON
# Use selective deletion so pins keep their IDs and a concurrent refresh never
# observes an empty database between wiping and restoring pins.

set -euo pipefail

if [[ ${1:-} == --pins ]]; then
  (($# == 2)) || exit 2
  # Capture the complete successful output, never partially resolved pins.
  resolved=$(python3 "${BASH_SOURCE[0]%/*}/clipboard-pins.py" resolve "$2") || exit 1
  mapfile -t pinned_ids <<< "$resolved"
else
  pinned_ids=("$@")
fi

declare -A keep=()
for id in "${pinned_ids[@]}"; do
  [[ $id =~ ^[0-9]+$ ]] && keep[$id]=1
done

# Clear the live clipboard before mutating history. If this fails, leave the
# database untouched so the UI can report the failure without losing entries.
wl-copy --clear || exit 1

if ((${#keep[@]} == 0)); then
  cliphist wipe
else
  lines=$(cliphist list) || exit 1
  while IFS= read -r line; do
    id=${line%%$'\t'*}
    [[ $id =~ ^[0-9]+$ ]] || continue
    if [[ ! -v keep[$id] ]]; then
      printf '%s\n' "$line" | cliphist delete
    fi
  done <<< "$lines"
fi
