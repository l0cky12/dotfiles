#!/usr/bin/env bash
set -euo pipefail
umask 077

action=${1:-create}

choose_base() {
    if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
        printf '%s\n' "$XDG_RUNTIME_DIR"
    else
        local cache_base=${XDG_CACHE_HOME:-${HOME:?HOME is required when XDG_RUNTIME_DIR is unset}/.cache}
        mkdir -p -- "$cache_base"
        printf '%s\n' "$cache_base"
    fi
}

case "$action" in
create)
    base=$(choose_base)
    base=$(cd -- "$base" && pwd -P)
    session_dir=$(mktemp -d -- "$base/screen-toolkit.XXXXXX")
    chmod 700 -- "$session_dir"
    # Reap abandoned sessions once they are old enough not to be a concurrently
    # starting instance. The explicit exclusion makes the current session safe.
    find "$base" -mindepth 1 -maxdepth 1 -type d -name 'screen-toolkit.*' \
        ! -path "$session_dir" -mmin +60 -exec rm -rf -- {} +
    boot_id=$(< /proc/sys/kernel/random/boot_id)
    printf '%s\n%s\n' "$session_dir" "$boot_id"
    ;;
cleanup)
    session_dir=${2:-}
    [[ -n $session_dir && -d $session_dir ]] || exit 0
    base=$(choose_base)
    base=$(cd -- "$base" && pwd -P)
    session_parent=$(cd -- "$(dirname -- "$session_dir")" && pwd -P)
    [[ $session_parent == "$base" ]] || {
        printf 'ERROR: refusing to remove path outside session base: %s\n' "$session_dir" >&2
        exit 1
    }
    [[ $(basename -- "$session_dir") == screen-toolkit.* ]] || {
        printf 'ERROR: refusing to remove unexpected path: %s\n' "$session_dir" >&2
        exit 1
    }
    rm -rf -- "$session_dir"
    ;;
*)
    printf 'Usage: temp-session.sh [create|cleanup <session-dir>]\n' >&2
    exit 1
    ;;
esac
