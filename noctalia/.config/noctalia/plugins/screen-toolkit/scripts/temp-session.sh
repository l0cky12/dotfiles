#!/usr/bin/env bash
set -euo pipefail
umask 077

action=${1:-create}

case "$action" in
create)
    if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
        base=$XDG_RUNTIME_DIR
    else
        base=${XDG_CACHE_HOME:-${HOME:?HOME is required when XDG_RUNTIME_DIR is unset}/.cache}
        mkdir -p -- "$base"
    fi
    session_dir=$(mktemp -d -- "$base/screen-toolkit.XXXXXX")
    chmod 700 -- "$session_dir"
    printf '%s\n' "$session_dir"
    ;;
cleanup)
    session_dir=${2:-}
    [[ -n $session_dir && -d $session_dir ]] || exit 0
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
