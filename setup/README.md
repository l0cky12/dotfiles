# Arch post-install setup

`setup/arch-dotfiles-setup.sh` configures an Arch Linux system after archinstall. It is strict, repeatable, logs every run, makes timestamped backups before system-file changes, never handles secrets, and never reboots.

```sh
./setup/arch-dotfiles-setup.sh --user liam --group core --group hyprland
```

Groups are explicit manifests: `core`, `hyprland`, `desktop-apps`, `virtualization`, `docker`, and `optional`; repeat `--group` to add groups. Official packages are installed with `pacman`. `yay` is bootstrapped only after confirmation and runs as the target non-root user; no curl-piped installer is used. GNU Stow deploys the declared existing packages (`hypr`, `hyprlock`, `kitty`, `waybar`, `rofi`, `wofi`, `swaync`, `fastfetch`, `zsh`, `xdg`).

Sensitive/system changes are opt-in: `--ssh-hardening`, `--ufw`, `--docker-forwarding`, and `--iommu`, each with an interactive confirmation (or `--yes`). SSH keys and `authorized_keys` are untouched; sshd config is backed up and validated with `sshd -t`. UFW backs up rules and permits the active SSH port plus TCP 53317. Docker policy is explicit and limited. IOMMU detects AMD/Intel, appends only the requested kernel parameters to the existing GRUB default line, shows the change through the command log, and runs `grub-mkconfig`; it does not configure VFIO/initramfs. Direct root use requires `--user NAME`.

`--dry-run` prints commands without mutating the host (package/Stow/system operations are skipped or printed). Logs go to `/var/log/arch-dotfiles-setup`, falling back to `$TMPDIR/arch-dotfiles-setup`. Run safe tests with:

```sh
bash setup/tests/test-setup.sh
```

The test uses temporary fixtures, an isolated target home, and command mocks; it never invokes pacman, GNU Stow, or system changes on the host. ShellCheck is run when already installed and otherwise reported as unavailable; tests never install packages.
