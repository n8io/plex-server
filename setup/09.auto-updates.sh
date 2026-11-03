#!/bin/bash
# Hands-off updates: Ubuntu Pro (security fixes to 2034 + Livepatch), nightly
# unattended upgrades for Ubuntu, Plex and Tailscale, idle-only reboots, and a
# monthly rclone update.
#
#   UBUNTU_PRO_TOKEN=<token> setup/09.auto-updates.sh
#
# Get a free personal token at https://ubuntu.com/pro/dashboard. Without one,
# everything but Pro/Livepatch is still set up.
set -e
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

UNIT_DIR="/etc/systemd/system"

echo "Automatic updates updating..."

if [ -n "${UBUNTU_PRO_TOKEN:-}" ]; then
  echo -n "  Attaching Ubuntu Pro..."
  pro status --format json 2>/dev/null | grep -q '"attached": true' || pro attach "$UBUNTU_PRO_TOKEN" >/dev/null
  pro enable livepatch --assume-yes >/dev/null 2>&1 || true
  echo "done."
else
  echo "  No UBUNTU_PRO_TOKEN: skipping Ubuntu Pro and Livepatch."
fi

echo -n "  Unattended upgrades..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades >/dev/null
cat <<'EOT' > /etc/apt/apt.conf.d/51plex-unattended
Unattended-Upgrade::Origins-Pattern {
  "origin=Ubuntu,archive=${distro_codename}-security";
  "origin=UbuntuESM,archive=${distro_codename}-infra-security";
  "origin=UbuntuESMApps,archive=${distro_codename}-apps-security";
  "site=repo.plex.tv";
  "site=pkgs.tailscale.com";
};
// Reboots are handled by plex-reboot-if-needed.timer, which waits for zero streams.
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOT
cat <<'EOT' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOT
echo "done."

echo -n "  Timers for idle-only reboots and rclone..."
for u in plex-reboot-if-needed.service plex-reboot-if-needed.timer rclone-update.service rclone-update.timer; do
  sed -e "s|@PLEX_CODE_DIR@|${PLEX_CODE_DIR}|g" "${PLEX_CODE_DIR}/systemd/${u}" > "${UNIT_DIR}/${u}"
done
systemctl daemon-reload
systemctl enable --now plex-reboot-if-needed.timer rclone-update.timer >/dev/null
echo "done."

"${PLEX_CODE_DIR}/scripts/update-status.sh"
echo -e "\e[32mAutomatic updates set up successfully.\e[0m"
