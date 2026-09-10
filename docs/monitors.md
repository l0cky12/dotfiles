# Monitors and workspaces

## Overview

Monitor configuration is dynamic. Hyprland sources:

- `hypr/.config/hypr/monitors.lua`
- `hypr/.config/hypr/workspaces.lua`

Both are generated. `hypr/.config/hypr/scripts/auto-monitor-profile.sh` picks a
profile, copies that profile's monitor/workspace files over the active files,
reloads Hyprland, and redistributes existing workspaces.

Because these paths are Stowed, profile switching also changes files inside the
Git working tree.

## Monitors are identified by EDID, not connector name

The KVM reaches the external monitors over DP-alt. **Every switch re-enumerates
the DisplayPort connectors**: the same three panels have been `DP-5`/`DP-7`/`DP-9`
and are now `DP-6`/`DP-10`/`DP-12`, and the abandoned indices accumulate as
`disconnected` entries under `/sys/class/drm`.

Detection keyed on connector names therefore failed after every switch. It fell
through to the `laptop` profile, which pins workspaces 1–15 to `eDP-1`; with the
lid display disabled those workspaces have nowhere to go and collapse onto a
single screen. Repairing the geometry by hand in `nwg-displays` did not fix it,
because the stale pinning lives in `workspaces.lua`.

The `kvm` profile matches on the EDID description instead, via Hyprland's
`desc:` selector, which is stable across renumbering:

```lua
hl.monitor({
    output = "desc:Dell Inc. DELL P2722H CTCS1M3",
    ...
})
```

Get the exact strings with `hyprctl monitors -j | jq -r '.[].description'`.

## Profile selection

Profiles live below `hypr/.config/hypr/monitor_profiles/`.

| Profile | Detection | Output arrangement |
| --- | --- | --- |
| `kvm` | all three KVM EDID descriptions present | eDP-1 disabled; P2214H portrait at left, P2722H centre, P2725H right |
| `desktop` | DP-4 and HDMI-A-3 present | DP-4 rotated at left; 2560×1080 HDMI-A-3 to its right; DP-1 disabled |
| `laptop` | fallback | eDP-1 at 2256×1504 |
| `work` | manual stub | eDP-1 at 2256×1504 until captured |
| `presentation` | manual stub | eDP-1 at 2256×1504 until captured |

`desktop` still matches on connector names: it describes different hardware whose
EDID strings are not recorded here. It is unaffected by the KVM renumbering.

A **partial** KVM set never selects `kvm`. During a hotplug the monitors do not
all reappear at once, and acting on a partial set is precisely what collapsed the
workspaces.

`SUPER+ALT+P` opens the manual profile menu. It discovers paired profile files,
marks the active pair, and includes a `Next profile` entry. The cycle is
`desktop` → `laptop` → `work` → `presentation`; `kvm` remains directly selectable.
The applier refuses a manual profile when none of its enabled outputs are
connected, so a docked profile cannot disable the only usable screen.

## Workspace mapping

| Profile | Workspaces |
| --- | --- |
| `kvm` | 1–5 on P2722H (centre); 6–10 on P2214H (left, portrait); 11–15 on P2725H (right) |
| `desktop` | 1–5 on HDMI-A-3; 6–15 on DP-4 |
| `laptop` | 1–15 on eDP-1 |
| `work` | 1–15 on eDP-1 until captured |
| `presentation` | 1–15 on eDP-1 until captured |

When applying a profile, the script reloads the pair, reads Hyprland's loaded
workspace rules, and dispatches `hl.dsp.workspace.move()` for workspaces 1
through 15. It resolves each `desc:` to its current connector and skips monitors
that are not present. The desktop profile then focuses HDMI-A-3 through
`hl.dsp.focus()`.

## Automatic reapplication

The watcher runs as the systemd user unit
`hypr-monitor-watch.service`; Hyprland's direct `exec-once` now starts that
unit instead of `hypr-monitor-watch.py` itself. It subscribes to Hyprland's
`socket2` IPC and calls the
applier when a monitor is added or removed. There is no polling loop.

This change does not enable the unit automatically. After installing the
dotfiles, run:

```sh
stow systemd
systemctl --user daemon-reload
systemctl --user enable --now hypr-monitor-watch.service
```

No udev rule is shipped in the repository. The optional system udev rule
described in [Installation](installation.md#optional-monitor-hotplug-helper) is
installed manually.

Sequence on a KVM switch:

1. `monitoradded`/`monitorremoved` arrive in a burst; the watcher debounces them
   into one trigger (0.6 s of quiet).
2. The applier waits for the monitor set to stop changing, and if any KVM monitor
   is present it waits for **all** of them, up to 10 s.
3. `flock` ensures a single applier runs at a time; later copies exit.
4. The layout is compared against the profile — the full tuple of mode, position,
   scale, transform, enabled/disabled, plus whether the generated files still
   match the profile. If everything matches, it exits without touching anything.
5. Otherwise the profile is applied, then verified, with one retry.

Logs go to the journal:

```sh
journalctl -t hypr-monitor -f
```

## Laptop lid

The internal panel (`eDP-1`) follows the lid, independent of which profile is
active. Hyprland's `switch:on:Lid Switch` / `switch:off:Lid Switch` binds run
`scripts/lid-switch.sh`, which only touches live compositor state:

- **Close** disables `eDP-1` — unless it is the only enabled monitor, in which
  case it is left alone (an undocked lid close is logind's suspend to handle).
- **Open** re-enables it with `preferred`/`auto`; the resulting `monitoradded`
  event triggers the applier, which snaps the panel to the active profile's
  exact mode and position.

The applier is lid-aware: while `/proc/acpi/button/lid/*/state` reports
`closed`, it treats `eDP-1` as desired-off regardless of the profile row, and
re-disables it after a `hyprctl reload`. A hotplug apply therefore never
re-lights a closed laptop, and the lid binds never fight the watcher.

Logs go to the journal under the `hypr-lid` tag.

## Changing the layout

1. Arrange the displays however you like — `nwg-displays`, or by hand.
2. Capture it:

   ```sh
   ~/.config/hypr/scripts/capture-monitor-profile.sh kvm --dry-run   # preview
   ~/.config/hypr/scripts/capture-monitor-profile.sh kvm             # write
   ```

   This rewrites `kvm.monitors.lua` from the running session, keyed by EDID
   description, after showing a diff and asking for confirmation. The previous
   file is kept as `.bak`.
3. Apply it: `~/.config/hypr/scripts/auto-monitor-profile.sh --force`

Workspace pinning is **not** captured by default. Workspaces that are not
currently open have no live monitor to read, so snapshotting them invents
assignments. Pass `--with-workspaces` only when you have deliberately rearranged
workspaces, and review the inferred entries it reports.

If you change the physical monitors, update `KVM_DESCS` in
`auto-monitor-profile.sh` to match — that array is what defines the KVM setup.

Do not make durable edits only to active `monitors.lua` or `workspaces.lua`; they
are replaced from the profile.

## Untracked machine state

`monitors.lua`, `workspaces.lua`, `monitors.conf` and `workspaces.conf` are
**not tracked**: the applier rewrites the first two from the profile pair on
every connected-output change, and nwg-displays rewrites them too. Tracking them
let the two halves drift apart — a `git restore` or an nwg-displays run touching
only `monitors.lua` left workspace rules pinned to outputs that were not
connected. The applier compares both active files against the selected profile
rather than trusting a cached profile name, so an external edit to either half
is reconciled on the next trigger.

A fresh clone materialises them with:

```bash
~/.config/hypr/scripts/auto-monitor-profile.sh --force
```

## Other monitor files

- `hypr/.config/hypr/monitors.lua` and `workspaces.lua` are required by the entry
  point and replaced from the selected profile at runtime.
- `monitors.conf` and `workspaces.conf` are the inactive hyprlang mirror kept as a
  rollback path. Hyprland loads the Lua config (`[cfg] Using lua config found at
  .../hyprland.lua`), so `nwg-displays` output written there has no effect;
  regenerate them by hand alongside the profile if that path is ever used.
- `hypr/.config/hypr/monitors.conf.bak` is empty.

## Display panel and scale changes

The Quickshell display panel reads outputs through `hyprctl`. It can adjust DDC/CI
brightness through `ddcutil` and offers scale presets. Scale persistence calls
`hypr/.config/hypr/scripts/set-monitor-scale.sh`.

That script validates the output and scale, then updates both the active
`monitors.lua` and `monitor_profiles/desktop.monitors.lua` atomically. It does
not update the laptop or KVM profile, and it works on connector names. A scale
chosen while the KVM profile is active is therefore overwritten at the next
apply; capture it into the profile instead.

## Disabling or uninstalling

```sh
# stop the watcher for this session (a plain pkill would trip Restart=on-failure)
systemctl --user stop hypr-monitor-watch.service

# stop it starting again:
systemctl --user disable --now hypr-monitor-watch.service
```

No udev rules or root files are shipped. Disabling the service and stopping the
process fully disables the feature; `monitors.lua` and `workspaces.lua` keep
whatever was last applied.

## Testing

`tests/hyprland-lua.test.sh` covers profile selection with mocked `hyprctl`,
including the connector-renumbering regression (`DP-5/7/9`, `DP-6/10/12` and
arbitrary names must all resolve to `kvm`), geometry drift detection, and the
rule that a partial monitor set must not select `kvm`.
