#!/usr/bin/env bash
# Install astral-pins for the current user (no root needed), optionally with
# the system-wide device-access rules (asks for sudo).
#
#   ./install.sh            user install: programs + systemd user services
#   ./install.sh --system   also install udev rules + i2c-dev autoload (sudo)
#   ./install.sh --no-tray  skip the tray icon service
set -euo pipefail
cd "$(dirname "$0")"

SYSTEM=0 TRAY=1
for a in "$@"; do
  case "$a" in
    --system) SYSTEM=1 ;;
    --no-tray) TRAY=0 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

BIN="$HOME/.local/bin"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
ok()   { printf '  \e[32m✓\e[0m %s\n' "$*"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*"; }

echo "Checking requirements"
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
ok "python3 $(python3 -c 'import sys;print(sys.version.split()[0])')"
if [ "$TRAY" = 1 ]; then
  if python3 -c 'import gi, cairo; gi.require_version("Gtk","3.0"); gi.require_version("GtkLayerShell","0.1"); gi.require_version("PangoCairo","1.0"); from gi.repository import Gtk, GtkLayerShell, PangoCairo' 2>/dev/null; then
    ok "GTK3, gtk-layer-shell, pycairo (tray)"
  else
    warn "tray needs PyGObject, GTK3, gtk-layer-shell and pycairo - skipping the tray"
    warn "  Fedora: python3-gobject gtk3 gtk-layer-shell python3-cairo"
    warn "  Debian/Ubuntu: python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-gtklayershell-0.1"
    TRAY=0
  fi
fi
command -v kdialog >/dev/null && ok "kdialog (alert dialog)" || warn "kdialog not found - alert dialogs need it (KDE Plasma)"
command -v notify-send >/dev/null && ok "notify-send" || warn "notify-send not found - no desktop notifications"

if [ "$SYSTEM" = 1 ]; then
  echo "Installing system rules (sudo)"
  sudo install -m 644 udev/70-astral-pins-i2c.rules /etc/udev/rules.d/
  ok "/etc/udev/rules.d/70-astral-pins-i2c.rules"
  echo i2c-dev | sudo tee /etc/modules-load.d/astral-pins-i2c-dev.conf >/dev/null
  sudo modprobe i2c-dev || true
  ok "i2c-dev module loaded at boot"
  rule=$(cat udev/70-wireview.rules)
  serial=$(udevadm info -q property -n /dev/wireview 2>/dev/null | sed -n 's/^ID_SERIAL_SHORT=//p' || true)
  [ -z "$serial" ] && for t in /dev/ttyACM*; do
    [ -e "$t" ] || continue
    p=$(udevadm info -q property -n "$t")
    if grep -q '^ID_VENDOR_ID=0483' <<<"$p" && grep -q '^ID_MODEL_ID=5740' <<<"$p"; then
      serial=$(sed -n 's/^ID_SERIAL_SHORT=//p' <<<"$p"); break
    fi
  done
  if [ -n "$serial" ]; then
    rule=${rule//ATTRS\{idProduct\}==\"5740\",/ATTRS\{idProduct\}==\"5740\", ATTRS\{serial\}==\"$serial\",}
    ok "WireView found (serial $serial) - rule limited to this unit"
  else
    warn "no WireView plugged in - installing the rule for any STM32 VCP (0483:5740)"
  fi
  printf '%s\n' "$rule" | sudo tee /etc/udev/rules.d/70-wireview.rules >/dev/null
  ok "/etc/udev/rules.d/70-wireview.rules"
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=i2c-dev --subsystem-match=tty
fi

echo "Installing for $USER"
install -Dm755 astral-pins "$BIN/astral-pins"
ok "$BIN/astral-pins"
install -Dm644 systemd/astral-pins.service "$UNITS/astral-pins.service"
if [ "$TRAY" = 1 ]; then
  install -Dm755 astral-pins-tray "$BIN/astral-pins-tray"
  install -Dm644 systemd/astral-pins-tray.service "$UNITS/astral-pins-tray.service"
  ok "$BIN/astral-pins-tray"
fi
systemctl --user daemon-reload
systemctl --user enable astral-pins.service >/dev/null 2>&1
systemctl --user restart astral-pins.service
ok "astral-pins.service enabled and running"
if [ "$TRAY" = 1 ]; then
  systemctl --user enable astral-pins-tray.service >/dev/null 2>&1
  systemctl --user restart astral-pins-tray.service
  ok "astral-pins-tray.service enabled and running"
fi

echo "Checking hardware access"
sleep 3
if "$BIN/astral-pins" --once >/dev/null 2>&1; then
  ok "ROG Astral sensor readable"
else
  warn "ROG Astral sensor not readable - need rw access to /dev/i2c-* (run ./install.sh --system)"
fi
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not in PATH - open a new terminal or add it";; esac
echo "Done. Logs: journalctl --user -u astral-pins -f"
