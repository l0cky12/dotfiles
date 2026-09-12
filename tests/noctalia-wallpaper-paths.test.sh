#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugin_root="$repo_root/noctalia/.config/noctalia/plugins"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v rg >/dev/null || fail 'ripgrep required'

folder_model="$plugin_root/video-wallpaper/common/FolderModel.qml"
video_thumbs="$plugin_root/video-wallpaper/main/Thumbnails.qml"
video_colors="$plugin_root/video-wallpaper/main/ColorGeneration.qml"
video_mpvpaper="$plugin_root/video-wallpaper/main/Mpvpaper.qml"
legacy_thumbs="$plugin_root/mpvpaper/main/Thumbnails.qml"
legacy_mpvpaper="$plugin_root/mpvpaper/main/Mpvpaper.qml"

for path in "$plugin_root/video-wallpaper" "$plugin_root/mpvpaper" \
    "$folder_model" "$video_thumbs" "$video_colors" "$video_mpvpaper" \
    "$legacy_thumbs" "$legacy_mpvpaper"; do
    [[ -e "$path" ]] || fail "required search path does not exist: $path"
done

assert_match() {
    local pattern=$1
    local path=$2
    local message=$3
    local status

    if rg -Uq --glob '*.qml' -- "$pattern" "$path"; then
        return
    else
        status=$?
    fi

    [[ $status -eq 1 ]] || fail "ripgrep failed for $path (exit $status)"
    fail "$message"
}

assert_no_match() {
    local pattern=$1
    local path=$2
    local message=$3
    local status

    if rg -Un --glob '*.qml' -- "$pattern" "$path"; then
        fail "$message"
    else
        status=$?
    fi

    [[ $status -eq 1 ]] || fail "ripgrep failed for $path (exit $status)"
}

# The sole remaining shell command is the unchanged, literal availability check.
# Commands containing paths or other runtime values must never cross a shell.
shell_command_count=$(rg -Uo --glob '*.qml' '"sh"\s*,\s*"-c"' \
    "$plugin_root/video-wallpaper" "$plugin_root/mpvpaper" | wc -l)
[[ $shell_command_count -eq 1 ]] || \
    fail "expected exactly one sh -c command, found $shell_command_count"
assert_match 'command\s*:\s*\[\s*"sh"\s*,\s*"-c"\s*,\s*"mpvpaper --help"\s*\]' \
    "$plugin_root/video-wallpaper" 'sole sh -c command is not the literal mpvpaper --help check'

for path in "$plugin_root/video-wallpaper" "$plugin_root/mpvpaper"; do
    assert_no_match '\[\s*"(?:sh|bash)"\s*,\s*"-c"\s*,\s*`' \
        "$path" 'wallpaper plugins interpolate a command through a shell'
    assert_no_match '\[\s*"(?:sh|bash)"\s*,\s*"-c"\s*,\s*"(?:find|ffmpeg|rm|mkdir)\b' \
        "$path" 'wallpaper plugins still pass path commands through a shell'
    assert_no_match 'rm\s+-rf|`(?:find|ffmpeg|mkdir|mpvpaper)\b' \
        "$path" 'wallpaper plugins still construct an unsafe command string'
done

assert_match 'FolderListModel\s*\{[^}]*folder\s*:\s*root\._folderUrl' \
    "$folder_model" 'video enumeration is not declaratively bound to FolderListModel'
assert_match 'function\s+forceReload\(\)\s*\{\s*internal\.ready\s*=\s*false' \
    "$folder_model" 'FolderModel forceReload does not clear readiness'
assert_match 'folderList\.folder\s*=\s*""\s*;\s*folderList\.folder\s*=\s*root\._folderUrl' \
    "$folder_model" 'FolderModel forceReload does not synchronously reset the folder'
assert_match 'if\s*\(root\.folder\s*===\s*""\)\s*\{\s*internal\.files\s*=\s*\[\]\s*;\s*internal\.ready\s*=\s*true\s*;\s*return\s*;' \
    "$folder_model" 'FolderModel does not make the empty folder unconditionally ready'
assert_no_match 'Qt\.callLater\([^)]*forceReload' "$folder_model" \
    'FolderModel forceReload is deferred'

# These source-level checks verify that every untrusted path is a distinct argv
# element. They do not execute QML or prove Quickshell runtime behavior.
assert_match 'thumbGenerationProc\.command\s*=\s*\[\s*"ffmpeg"\s*,\s*"-y"\s*,\s*"-i"\s*,\s*videoPath\s*,' \
    "$video_thumbs" 'video-wallpaper ffmpeg input is not an array operand'
assert_match 'thumbProc\.command\s*=\s*\[\s*"ffmpeg"\s*,\s*"-y"\s*,\s*"-i"\s*,\s*videoPath\s*,' \
    "$legacy_thumbs" 'mpvpaper ffmpeg input is not an array operand'
assert_match 'proc\.command\s*=\s*\[\s*"ffmpeg"\s*,\s*"-y"\s*,\s*"-i"\s*,\s*currentWallpaper\s*,' \
    "$video_colors" 'color-generation ffmpeg input is not an array operand'
assert_match 'command\s*:\s*\[\s*"mkdir"\s*,\s*"-p"\s*,\s*"--"\s*,\s*root\.thumbCacheFolderPath\s*\]' \
    "$video_thumbs" 'video-wallpaper mkdir path is not an array operand'
assert_match 'command\s*:\s*\[\s*"mkdir"\s*,\s*"-p"\s*,\s*"--"\s*,\s*root\.thumbCacheFolder\s*\]' \
    "$legacy_thumbs" 'mpvpaper mkdir path is not an array operand'
assert_match 'thumbRegenerationMkdirProc\.command\s*=\s*\[\s*"mkdir"\s*,\s*"-p"\s*,\s*"--"\s*,\s*root\.thumbCacheFolderPath\s*\]' \
    "$video_thumbs" 'video-wallpaper regeneration does not recreate its cache directory'
assert_match 'thumbRegenerationMkdirProc\.command\s*=\s*\[\s*"mkdir"\s*,\s*"-p"\s*,\s*"--"\s*,\s*root\.thumbCacheFolder\s*\]' \
    "$legacy_thumbs" 'mpvpaper regeneration does not recreate its cache directory'
assert_match 'const\s+command\s*=\s*\[\s*"rm"\s*,\s*"-f"\s*,\s*"--"\s*\]' \
    "$video_thumbs" 'video-wallpaper cache deletion is not limited to enumerated files'
assert_match 'const\s+command\s*=\s*\[\s*"rm"\s*,\s*"-f"\s*,\s*"--"\s*\]' \
    "$legacy_thumbs" 'mpvpaper cache deletion is not limited to enumerated files'
assert_match 'return\s*\[\s*"mpvpaper"\s*,\s*"-o"\s*,\s*options\.join\(" "\)\s*,\s*root\.screenName\s*,' \
    "$video_mpvpaper" 'video-wallpaper playback path is not an array operand'
assert_match 'return\s*\[\s*"mpvpaper"\s*,\s*"-o"\s*,\s*options\.join\(" "\)\s*,\s*"ALL"\s*,' \
    "$legacy_mpvpaper" 'mpvpaper playback path is not an array operand'

printf 'ok: Noctalia wallpaper paths are represented as literal process operands\n'
