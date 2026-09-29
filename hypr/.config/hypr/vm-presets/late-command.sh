#!/bin/sh
# Runs inside the installed system from the preseed late_command. Rendered by
# scripts/vm-preset, which appends the preset's extra fragment, if any.
set -eu

user=@USERNAME@

if [ -f /root/vm-preset-authorized_keys ]; then
  install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
  install -m 600 -o "$user" -g "$user" /root/vm-preset-authorized_keys \
    "/home/$user/.ssh/authorized_keys"
  install -d -m 755 /etc/ssh/sshd_config.d
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
    >/etc/ssh/sshd_config.d/50-vm-preset.conf
fi

@PRESET_STEPS@
