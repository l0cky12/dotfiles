-- KVM profile -- monitors are matched by EDID description, never by connector name.
--
-- Why: this machine reaches the monitors over DP-alt through a KVM. Every switch
-- re-enumerates the DisplayPort connectors, so the same three panels have been
-- DP-5/DP-7/DP-9 and are now DP-6/DP-10/DP-12; the stale indices pile up as
-- "disconnected" entries under /sys/class/drm. Matching on connector name breaks
-- on the next switch. The `desc:` string comes from EDID and is stable.
--
-- Regenerate from the live session with:
--   ~/.config/hypr/scripts/capture-monitor-profile.sh kvm

-- The internal panel follows the lid, not the dock: scripts/lid-switch.sh
-- disables it live on lid close, and auto-monitor-profile.sh keeps it off
-- while the lid is closed.
hl.monitor({
    output = "eDP-1",
    mode = "2256x1504@60.0",
    position = "0x0",
    scale = 1.0,
})

-- left, portrait
hl.monitor({
    output = "desc:Dell Inc. DELL P2214H KW14V42L3ACB",
    mode = "1920x1080@60.0",
    position = "2256x0",
    scale = 1.0,
    transform = 1,
})

-- middle
hl.monitor({
    output = "desc:Dell Inc. DELL P2722H CTCS1M3",
    mode = "1920x1080@60.0",
    position = "3336x0",
    scale = 1.0,
    transform = 0,
})

-- right
hl.monitor({
    output = "desc:Dell Inc. DELL P2725H 21MG834",
    mode = "1920x1080@60.0",
    position = "5256x0",
    scale = 1.0,
    transform = 0,
})
