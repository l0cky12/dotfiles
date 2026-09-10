# Monitors and workspaces

Monitor configuration here is dynamic. Hyprland sources `monitors.lua` and
`workspaces.lua`, and a script rewrites both from a profile pair whenever the
connected-output set changes.

## Why it works this way

The KVM reaches the external monitors over DP-alt, and **every switch
re-enumerates the DisplayPort connectors**. The same three panels have been
`DP-5`/`DP-7`/`DP-9` and are now `DP-6`/`DP-10`/`DP-12`, with the abandoned
indices piling up as `disconnected` entries under `/sys/class/drm`.

Detection keyed on connector names failed after every switch. It fell through to
the `laptop` profile, which pins workspaces 1–15 to `eDP-1` — and with the lid
display disabled those workspaces have nowhere to go and collapse onto one
screen. Fixing the geometry by hand in `nwg-displays` did not help, because the
stale pinning lives in `workspaces.lua`, not the monitor file.

The `kvm` profile therefore matches on the EDID description, using Hyprland's
`desc:` selector, which survives renumbering:

```lua
hl.monitor({
    output = "desc:Dell Inc. DELL P2722H CTCS1M3",
    ...
})
```

Get the exact strings with:

```bash
hyprctl monitors -j | jq -r '.[].description'
```

## Profiles

Profiles live in `hypr/.config/hypr/monitor_profiles/`, as pairs of
`<name>.monitors.lua` and `<name>.workspaces.lua`.

| Profile | Detection | Arrangement |
| --- | --- | --- |
| `kvm` | all three KVM EDID descriptions present | eDP-1 off; P2214H portrait left, P2722H centre, P2725H right |
| `desktop` | DP-4 and HDMI-A-3 present | DP-4 rotated left, 2560×1080 HDMI-A-3 right, DP-1 off |
| `laptop` | fallback | eDP-1 at 2256×1504 |
| `work` | manual stub | eDP-1 at 2256×1504 until captured |
| `presentation` | manual stub | eDP-1 at 2256×1504 until captured |

`desktop` still matches on connector names. It describes different hardware whose
EDID strings are not recorded here, and it is unaffected by the KVM renumbering.

**A partial KVM set never selects `kvm`.** During a hotplug the monitors do not
all reappear at once, and acting on a partial set is exactly what collapsed the
workspaces in the first place.

## Workspace mapping

| Profile | Workspaces |
| --- | --- |
| `kvm` | 1–5 on P2722H (centre), 6–10 on P2214H (left, portrait), 11–15 on P2725H (right) |
| `desktop` | 1–5 on HDMI-A-3, 6–15 on DP-4 |
| `laptop` | 1–15 on eDP-1 |
| `work`, `presentation` | 1–15 on eDP-1 until captured |

When applying a profile, the script reloads the pair, reads Hyprland's loaded
workspace rules, and dispatches `hl.dsp.workspace.move()` for workspaces 1
through 15. It resolves each `desc:` to its current connector and skips monitors
that are not present. The desktop profile then focuses HDMI-A-3.

## Automatic reapplication

The watcher runs as the systemd user unit `hypr-monitor-watch.service`.
Hyprland's autostart starts that unit rather than the Python script directly.
It subscribes to Hyprland's `socket2` IPC and calls the applier on
`monitoradded` / `monitorremoved`. There is no polling loop.

Stowing does not enable it:

```bash
stow systemd
systemctl --user daemon-reload
systemctl --user enable --now hypr-monitor-watch.service
```

What happens on a KVM switch:

1. Events arrive in a burst; the watcher debounces them into one trigger after
   0.6 s of quiet.
2. The applier waits for the monitor set to stop changing. If any KVM monitor is
   present it waits for **all** of them, up to 10 s.
3. `flock` ensures one applier at a time; later copies exit.
4. The live layout is compared against the profile — mode, position, scale,
   transform, enabled state, plus whether the generated files still match. If
   everything agrees, it exits without touching anything.
5. Otherwise it applies the profile, verifies, and retries once.

Logs go to the journal:

```bash
journalctl -t hypr-monitor -f
```

## Changing the layout

1. Arrange the displays however you like — `nwg-displays`, or by hand.
2. Capture it into the profile:

   ```bash
   ~/.config/hypr/scripts/capture-monitor-profile.sh kvm --dry-run   # preview
   ~/.config/hypr/scripts/capture-monitor-profile.sh kvm             # write
   ```

   This rewrites `kvm.monitors.lua` from the running session, keyed by EDID
   description, after showing a diff and asking. The previous file is kept as
   `.bak`, and the generated Lua is validated with `luac`.

3. Apply it:

   ```bash
   ~/.config/hypr/scripts/auto-monitor-profile.sh --force
   ```

Workspace pinning is **not** captured by default. Workspaces that are not
currently open have no live monitor to read, so snapshotting them invents
assignments. Pass `--with-workspaces` only after deliberately rearranging
workspaces, and review the entries it reports as inferred.

If you change the physical monitors, update `KVM_DESCS` in
`auto-monitor-profile.sh` — that array is what defines the KVM setup.

## The active files are machine state

`monitors.lua`, `workspaces.lua`, `monitors.conf`, and `workspaces.conf` are
**untracked**. The applier rewrites the Lua pair on every connected-output
change, and `nwg-displays` rewrites them too.

Tracking them let the two halves drift apart: a `git restore`, or an
`nwg-displays` run that touched only `monitors.lua`, left workspace rules pinned
to outputs that were not connected. The applier now compares both active files
against the selected profile rather than trusting a cached profile name, so an
external edit to either half is reconciled on the next trigger.

A fresh clone materialises them with:

```bash
~/.config/hypr/scripts/auto-monitor-profile.sh --force
```

`monitors.conf` and `workspaces.conf` are the inactive hyprlang mirror, kept as a
rollback path. Since Hyprland loads the Lua config, anything written there has no
effect; regenerate them by hand alongside the profile if that path is ever used.
`monitors.conf.bak` is empty.

## Manual profile switching

`SUPER+ALT+P` opens the Rofi profile menu. It discovers paired profile files,
marks the active pair, and includes a `Next profile` entry. The cycle is
`desktop` → `laptop` → `work` → `presentation`; `kvm` stays directly selectable
but is not in the cycle.

The applier refuses a manual profile when none of its enabled outputs are
connected, so a docked profile cannot disable your only usable screen.

## Scale changes from the display panel

The Quickshell display panel reads outputs through `hyprctl`, adjusts DDC/CI
brightness with `ddcutil`, and offers scale presets. Persisting a scale calls
`hypr/.config/hypr/scripts/set-monitor-scale.sh`.

That script validates the output and scale, then atomically updates both the
active `monitors.lua` and `monitor_profiles/desktop.monitors.lua`. It does **not**
update the laptop or KVM profile, and it works on connector names. A scale chosen
while the KVM profile is active gets overwritten at the next apply — capture it
into the profile instead.

## Disabling the feature

```bash
# stop it for this session (a plain pkill would trip Restart=on-failure)
systemctl --user stop hypr-monitor-watch.service

# stop it starting again
systemctl --user disable --now hypr-monitor-watch.service
```

No udev rules or root files are installed by Stow. `hypr/.config/hypr/udev/`
contains an optional system rule and a root-owned dispatcher whose comments
describe the manual privileged install; it is optional because the user-space
watcher already covers hotplug. If you ever installed it, remove it too.

Disabling the service leaves `monitors.lua` and `workspaces.lua` at whatever was
last applied.

## Testing

`tests/hyprland-lua.test.sh` covers profile selection with mocked `hyprctl`,
including the connector-renumbering regression (`DP-5/7/9`, `DP-6/10/12`, and
arbitrary names must all resolve to `kvm`), geometry drift detection, and the
rule that a partial monitor set must not select `kvm`. It also `luac -p`
validates every tracked Lua file.
