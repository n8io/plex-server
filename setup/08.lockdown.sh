#!/bin/bash
# SSH and firewall lockdown. Public: Plex on 32400 (and SSH unless told
# otherwise). Everything else, including Scan UI and Tautulli, is reachable
# only over Tailscale.
#
#   setup/08.lockdown.sh                     keys-only SSH, firewall on, SSH still public
#   SSH_TAILSCALE_ONLY=1 setup/08.lockdown.sh  also close public SSH (run only after
#                                              `ssh root@<tailscale name>` works)
#
# Lost access? OVH's rescue mode boots the box from the network so you can
# undo this (ufw disable, remove /etc/ssh/sshd_config.d/90-plex.conf).
set -e

SSHD_DROPIN="/etc/ssh/sshd_config.d/90-plex.conf"

# Never turn off passwords without a key to get back in with.
if [ ! -s /root/.ssh/authorized_keys ]; then
  echo "No keys in /root/.ssh/authorized_keys; refusing to disable password login." >&2
  exit 1
fi

if [ "${SSH_TAILSCALE_ONLY:-0}" = "1" ] && ! tailscale status >/dev/null 2>&1; then
  echo "Tailscale isn't up; refusing to close public SSH. Run setup/07.tailscale.sh first." >&2
  exit 1
fi

echo "Lockdown updating..."

echo -n "  SSH: keys only..."
cat <<'EOT' > "$SSHD_DROPIN"
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOT
sshd -t
systemctl reload ssh
echo "done."

echo -n "  Firewall..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 32400/tcp comment "Plex" >/dev/null
ufw allow 41641/udp comment "Tailscale direct connections" >/dev/null
ufw allow in on tailscale0 comment "Tailnet: SSH, Scan UI, Tautulli" >/dev/null
if [ "${SSH_TAILSCALE_ONLY:-0}" = "1" ]; then
  echo -n " SSH over Tailscale only..."
else
  ufw allow 22/tcp comment "SSH" >/dev/null
fi
ufw --force enable >/dev/null
echo "done."

ufw status verbose
echo -e "\e[32mLockdown updated successfully.\e[0m"
