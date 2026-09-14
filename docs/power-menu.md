# Power menu

The power menu uses Rofi because Rofi is already installed and its palette is
already generated from `colors.toml`. The alternative, wlogout, would add a
package plus a second set of CSS, icon assets, and resolution-specific launch
logic. This route keeps the launcher and power menu on the same theme adapter.

## Design rationale

The five-column icon row follows
[adi1090x's Rofi power-menu layout](https://github.com/adi1090x/rofi/blob/master/files/powermenu/type-2/style-1.rasi),
including the split between a stable layout and
[imported colors](https://github.com/adi1090x/rofi/blob/master/files/powermenu/type-2/shared/colors.rasi).
The centered power-menu treatment also appears in this
[r/unixporn Rofi post](https://www.reddit.com/r/unixporn/comments/wp7ea0/oc_rofi_rofi_powermenus_added_to_the_repository/).

wlogout remains the main visual reference for a full-screen dim layer. In
[JaKooLit's Hyprland dots](https://github.com/JaKooLit/Hyprland-Dots/blob/main/config/wlogout/style.css),
the buttons use translucent surfaces, rounded corners, and distinct hover
states; its
[layout](https://github.com/JaKooLit/Hyprland-Dots/blob/main/config/wlogout/layout)
assigns the familiar `l/r/s/e/u/h` shortcuts. A
[recent r/unixporn setup](https://www.reddit.com/r/unixporn/comments/1lxb8jn/hyprland_i_hate_css_but_i_use_arch_btw/)
uses `wlogout -b 6` to keep those actions in one row. Here, Rofi provides the
same full-screen scrim and a responsive five-button row without adding wlogout.

Rofi's own documentation covers
[mouse and keyboard navigation](https://davatorium.github.io/rofi/current/rofi.1/)
and the
[custom dmenu return codes](https://davatorium.github.io/rofi/current/rofi-dmenu.5/)
used for the direct letter shortcuts.

## Behavior

The quickshell bar's power button opens a native popup (`PowerPopup.qml`) and
runs the chosen action with `launcher.sh ACTION`, which skips the Rofi picker.
Log out, reboot and shutdown ask for a second click in the popup.

The menu supports mouse selection, arrows plus Enter, and these direct keys:

| Key | Action |
| --- | --- |
| `L` | Lock |
| `E` | Log out |
| `U` or `H` | Suspend |
| `R` | Reboot |
| `S` | Shut down |

Logout, reboot, and shutdown require confirmation. Suspend starts Hyprlock in
the background, waits one second, and then calls `systemctl suspend`. This
ordering follows the official
[Hypridle lock-before-suspend example](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/#examples);
the delay avoids the race reported in
[HyDE issue 1536](https://github.com/HyDE-Project/HyDE/issues/1536).

## Theme pipeline

`theme set <slug>` renders
`hypr/.config/hypr/theme/templates/rofi-powermenu-theme.rasi` to
`~/.config/rofi/powermenu/theme.rasi`. The generated file supplies every color,
opacity, border width, and radius used by `layout.rasi`. It is ignored by Git in
the same way as the main generated Rofi theme.

For non-live checks, `launcher.sh --dry-run ACTION` prints the commands for one
of `lock`, `logout`, `suspend`, `reboot`, or `shutdown` without running them.

## Deployment

After reviewing the source changes:

```bash
cd /home/liam/dotfiles
stow -R hypr rofi
theme set <slug>
```

The suggested Hyprland binding is deliberately not applied by this change:

```ini
bindd = $mainMod, P, power menu, exec, bash ~/.config/rofi/powermenu/launcher.sh
```
