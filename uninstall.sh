#!/usr/bin/env bash
# Remove astral-pins for the current user.
#   ./uninstall.sh           remove programs, services and tray settings
#   ./uninstall.sh --system  also remove the udev rules / i2c-dev autoload (sudo)
set -euo pipefail
BIN="$HOME/.local/bin"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

for s in astral-pins-tray astral-pins; do
  systemctl --user disable --now "$s.service" 2>/dev/null || true
  rm -f "$UNITS/$s.service" "$BIN/$s"
done
systemctl --user daemon-reload
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/astral-pins"
rm -f "${XDG_RUNTIME_DIR:-/tmp}"/astral-pins.json "${XDG_RUNTIME_DIR:-/tmp}"/wireview.json \
      "${XDG_RUNTIME_DIR:-/tmp}"/wireview.cmd
echo "User install removed."

if [ "${1:-}" = "--system" ]; then
  sudo rm -f /etc/udev/rules.d/70-astral-pins-i2c.rules /etc/udev/rules.d/70-wireview.rules \
             /etc/modules-load.d/astral-pins-i2c-dev.conf
  sudo udevadm control --reload
  echo "System rules removed."
fi
