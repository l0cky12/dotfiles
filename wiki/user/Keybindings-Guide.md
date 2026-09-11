# Keybindings, in plain English

This is the friendly companion to the full [Keybindings](../Keybindings.md)
reference. The reference tells you what each binding runs; this page tells you
what you would actually press and why. Every binding here comes from the live
config file, `hypr/.config/hypr/conf/keybindings.lua`.

## Two things to know first

**Super** is the Windows key. Almost every binding on this page starts with it,
usually combined with one or two of `Shift`, `Ctrl`, and `Alt`. So
`Super+Shift+S` means: hold Super and Shift, then press S.

**`Super+K` shows every binding, live.** Press it any time and a searchable
palette appears listing every binding the compositor actually loaded, with a
plain description of each. Type to filter, pick one to see what it does. When
you forget any binding on this page, `Super+K` is the answer.

## How the modifiers work together

- `Super` alone does the gentle thing: move focus, switch workspace, open an app.
- Adding **Shift** usually means "act on the window" — swap it, move it to
  another workspace, make it fullscreen.
- Adding **Ctrl** usually means "more precise or quieter" — resize, move a
  window without changing workspace, move without following it.
- Adding **Alt** usually means "a variant of the same thing" — a second copy of
  a key, a private window, a finer resize.

## Everyday launching

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+Return` | Opens a terminal. | Any time you need a command line. |
| `Super+A` | Opens the app launcher — type to search every installed app. | The fast way to start anything. |
| `Super+Shift+A` | Opens **lmenu**, the big settings-and-actions menu. | When you would rather browse than remember a key — nearly everything else is in there. |
| `Super+W` | Opens the web browser. | Browsing. |
| `Super+Shift+Alt+W` | Opens a private browser window. | Looking something up without it landing in history. |
| `Super+E` (also `Super+Shift+E`) | Opens the file manager. | Finding files visually. |
| `Super+Shift+Alt+F` | Opens the file manager at the terminal's current folder. | You `cd`'d somewhere in a terminal and now want to see it. |
| `Super+S` | Opens Spotify. | Music. |
| `Super+O` | Opens Obsidian. | Notes. |
| `Super+Shift+H` | Opens Hermes. | Talking to your agent. |
| `Super+R` | Toggles voice dictation. | Typing hands-free. |
| `Super+Ctrl+S` | Opens LocalSend to share files with a nearby device. | Sending a file to your phone. |
| `Super+Alt+W` / `Super+Ctrl+Alt+W` | Starts / stops the Windows VM. | The occasional Windows-only app. |
| `Super+Shift+G` | Starts the Gaming VM and connects to it. | Gaming through Looking Glass. |
| `Super+I` | Launches the coding agent. | Delegating a coding task. |
| `Super+Ctrl+T` | Opens a floating activity monitor (`btop`). | "Why is everything slow?" |
| `Super+Alt+A` | Opens the web-app manager. | Turning a website into an app window. |
| `Super+Shift+D` | Opens the disk utility. | Checking what is using the disk. |
| `Super+U` | Ejects removable drives safely. | Before unplugging a USB stick. |
| `Super+Alt+T` | Runs a network speed test overlay. | "Is the internet slow, or is it just me?" |

## Panels: the little pop-ups on the bar

Each of these toggles a pop-up panel. Press again to close.

| Keys | What it shows |
|---|---|
| `Super+Ctrl+D` | Display settings (also has a theme launcher row). |
| `Super+Ctrl+I` | Network status. |
| `Super+Ctrl+W` | Network management — Wi-Fi, DNS, IPv4, a QR code for sharing Wi-Fi. |
| `Super+Ctrl+A` | Audio volume and devices. |
| `Super+Ctrl+B` | Bluetooth. |
| `Super+Ctrl+M` | What is currently playing. |
| `Super+Ctrl+V` | Clipboard history — everything you have copied recently. |
| `Super+Alt+V` | A little audio visualiser. |
| `Super+Ctrl+Shift+Space` | The theme picker. |
| `Super+Shift+B` | Power profile menu (battery saver, balanced, performance). |

## Workspaces

A workspace is a virtual desktop — think of them as ten (plus five extra)
separate desks you can spread your work across.

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+1` … `Super+0` | Jump to workspace 1–10. | Your main switch. |
| `Super+Alt+1` … `Super+Alt+5` | Jump to workspace 11–15. | The overflow desks. |
| `Super+Tab` / `Super+Shift+Tab` | Next / previous workspace. | Stepping through them in order. |
| `Super+Ctrl+Tab` | Back to the workspace you just left. | The "oops, take me back" key. |
| `Super+mouse wheel` | Scroll through workspaces. | Without leaving the mouse. |
| `Super+Shift+1` … `Super+Shift+0` | Move this window to workspace 1–10 and follow it. | Tidying up, then going with it. |
| `Super+Ctrl+1` … `Super+Ctrl+0` | Move this window to workspace 1–10 but stay here. | Stashing a window out of sight. |
| `Super+Shift+Alt+1` … `+4` | The same, silently, for workspaces 1–4. | Quick stashing. |
| `Super+Shift+[` / `Super+Shift+]` | Move this window to the previous / next workspace, following it. | Neighbour desks. |
| `Super+Ctrl+[` / `Super+Ctrl+]` | Same, but you stay put. | Same, without moving yourself. |

## Windows: focus, move, swap, resize

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+arrows` | Move focus to the window in that direction. | The most-used keys on this page, probably. |
| `Super+Shift+arrows` | Swap this window with its neighbour. | Reordering your tiles. |
| `Super+Ctrl+arrows` | Drag this window in that direction. | Rearranging the layout. |
| `Super+Shift+Alt+arrows` | Move the entire workspace to the monitor in that direction. | Multi-monitor shuffling. |
| `Super+Q` | Close the focused window. | Done with it. |
| `Super+Shift+F` | True fullscreen — the window takes everything, bar included. | Watching a video, reading one thing. |
| `Super+Ctrl+F` | Maximize but keep the bar and gaps. | Big window without losing the clock. |
| `Super+T` | Toggle the window between floating and tiled. | Pop it out of the grid or snap it back. |
| `Super+J` | The next window you open will appear to the right. | Shaping where the next window lands (one-shot). |
| `Super+Shift+V` | The next window you open will appear below. | Same, vertically (one-shot). |
| `Super+minus` / `Super+equal` | Shrink / widen the window, 100 px at a time. | Everyday nudging. |
| `Super+Shift+minus` / `Super+Shift+equal` | Same but vertically. | Resizing the other dimension. |
| `Super+Alt+minus` / `Super+Alt+equal` | Fine horizontal resize, 10 px. | Pixel-perfect fits. |
| `Super+Ctrl+minus` / `Super+Ctrl+equal` | Coarse horizontal resize, 300 px. | Big moves fast. |
| `Super+Alt+Home` / `Super+Home` | Save / restore this window's width. | Keep a terminal at exactly the width you like. |
| `Super+left drag` / `Super+Shift+right drag` | Move / resize with the mouse. | When dragging just feels right. |

Note: `Ctrl+Alt+Delete` closes **all** windows at once — it is there for
emergencies, and it asks nothing first. Use it deliberately or not at all.

## Copy, paste, and little helpers

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+C` / `Super+X` / `Super+V` | Copy / cut / paste, working correctly in both terminals and normal apps. | One habit everywhere; no more "which clipboard shortcut is it here?" |
| `Super+Ctrl+V` | Clipboard history. | "I copied that ten minutes ago…" |
| `Super+Alt+E` | Emoji picker — search, pick, it is copied. | 🙂 |
| `Super+Ctrl+Q` (also `Super+Shift+C`) | Calculator — type an expression, Enter copies the answer. | Quick maths without opening anything. |
| `Super+Ctrl+.` | Media transcode menu over your Pictures and Videos. | Converting a video's format. |

## Screenshots, recording, and capture

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+Shift+S` | Smart screenshot: drag a region, or click a window to grab it. | The everyday screenshot. |
| `Super+Alt+S` | Screenshot the whole current monitor. | Full-screen grabs. |
| `Super+Alt+Ctrl+S` / `Super+Ctrl+Shift+S` | Same, after a 5 / 10 second delay. | Capturing something you need to set up first. |
| `Super+Shift+R` | Toggle screen recording. | Recording a how-to. |
| `Super+Shift+P` | Colour picker — grab any pixel's colour. | Matching a colour from the screen. |
| `Super+Shift+T` | Copy text from the screen (OCR the selection). | Text inside an image or video. |
| `Super+Ctrl+C` | Capture mode chooser menu. | When you forget which screenshot key is which. |
| `Super+Alt+C` | Toggle the webcam overlay. | Being on camera while sharing the screen. |
| `Super+Alt+[` / `Super+Alt+]` | Make the webcam overlay smaller / larger. | Sizing it just so. |

## Notifications

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+,` | Dismiss the newest notification. | Clearing the corner. |
| `Super+Shift+,` | Dismiss all visible notifications. | Full sweep. |
| `Super+D` | Toggle do-not-disturb. | Focus time. |
| `Super+Ctrl+,` | Toggle do-not-disturb through the desktop-modes system (can be scheduled). | The same, with a timer if you want one. |
| `Super+Alt+,` | Trigger the newest notification's default action. | Reply to a message without finding the window. |
| `Super+Shift+Alt+,` | Reopen notification history. | "What was that notification?" |

## Modes, reminders, and screensaver

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+Alt+M` | Desktop modes menu. | Choosing a whole-desk behaviour in one place. |
| `Super+Shift+I` | Toggle selective stay-awake. | Long download, lid closed, still awake. |
| `Super+Ctrl+O` | The toggles menu (night light, DND, stay-awake, and friends). | One menu for all the switches. |
| `Super+Ctrl+N` | Toggle night light. | Evening screen warmth. |
| `Super+Backspace` | Toggle window transparency everywhere. | Briefly seeing what is behind your windows. |
| `Super+Shift+Backspace` | Toggle gaps and borders everywhere. | A denser or airier layout, one keypress. |
| `Super+Ctrl+Escape` | Start the ASCII screensaver now. | Fun on an idle screen. |
| `Super+Ctrl+Shift+Escape` | Toggle the automatic screensaver. | Turn it off before a presentation. |
| `Super+Ctrl+R` | Set a reminder. | "In 20 minutes, move the laundry." |
| `Super+Ctrl+Alt+R` | List pending reminders. | Checking what you promised yourself. |
| `Super+Ctrl+Shift+R` | Clear all reminders. | Fresh start. |

## Appearance

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+Ctrl+Shift+Space` | Theme picker. | Trying on a new look. |
| `Super+Shift+W` | Wallpaper picker with Wallhaven search. | Fresh background. |
| `Super+Alt+P` | Monitor profiles menu. | Switching monitor layouts. |
| `Super+Alt+wheel` | Desktop zoom in / out; `Super+Alt+Shift+wheel` resets. | Reading tiny text on a demo screen. |

## Lock, power, and session

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+L` | Lock the screen. | Stepping away. |
| `Super+P` | Power menu — lock, suspend, reboot, shutdown. | End of day. |
| `Super+K` | The searchable keybindings palette. | Forgetting everything else on this page. |
| `Super+Shift+Return` | A drop-down terminal that slides in over everything. | A quick command without disturbing your layout. |
| `Super+Shift+G` | Start the Gaming VM. | Game time. |
| `Super+Alt+M` (also above) | Desktop modes. | Also lives here conceptually. |

## Volume, music, brightness, and other keys

These use the media keys at the top of the keyboard — no Super needed:

| Key | What it does |
|---|---|
| Volume up / down (media keys) | Louder / quieter, 5% at a time, capped at 100%. |
| Mute (media key) | Toggle mute. |
| Play / pause, next / previous, stop (media keys) | Control the current player. |
| Brightness up / down (media keys) | Screen brightness, 5% at a time. |

Two more bindings that live outside Hyprland (they belong to the browser
extension, so `Super+K` will not list them): `Alt+Shift+L` copies the current
tab's URL, and `Alt+Shift+D` sends the current page to yt-dlp.

## Session and misc

| Keys | What it does | When would I use this |
|---|---|---|
| `Super+Shift+Return` | A drop-down terminal that slides in over everything. | A quick command without disturbing your layout. |
| `Super+Alt+P` | Monitor profiles menu. | Covered above; also useful mid-session. |

## A keyboard-first workflow

The pieces chain together nicely:

1. **Launch anything** with `Super+A` (apps) or `Super+Return` (terminal).
2. **Everything else** lives in **lmenu** (`Super+Shift+A`) — settings, toggles,
   installs, power. If you cannot remember a binding, lmenu has a menu item for it.
3. **Forgot a binding?** `Super+K` shows the live, searchable list of all of them.
4. **Between windows and desks**, it is all Super: arrows to move focus,
   numbers to jump workspaces, Shift to drag things around, Ctrl for the
   quiet/precise versions.
5. **When in doubt**, `Super+Ctrl+O` (toggles) or `Super+Alt+M` (modes) will
   get you to a menu that explains itself.

## The technical reference

This page is the friendly tour. The complete technical table — every binding
with its dispatcher or command, grouped exactly as the config file is — lives
in [Keybindings](../Keybindings.md).
