#!/bin/bash
set -e

SYSCTL_FILE="/etc/sysctl.d/90-plex.conf"

wipe_old() {
  # Earlier versions appended a block to /etc/sysctl.conf.
  if grep -q "#plex-settings-start" /etc/sysctl.conf 2>/dev/null; then
    echo -n "  Removing old settings from /etc/sysctl.conf..."
    cp /etc/sysctl.conf "/etc/sysctl.conf.$(date +"%Y-%m-%d_%H-%M-%S")"
    sed -i '/[#]plex[-]settings[-]start/,/[#]plex[-]settings[-]end/ d' /etc/sysctl.conf
    echo "done."
  fi
}

write_new() {
echo -n "  Writing ${SYSCTL_FILE}..."
cat <<EOT > "$SYSCTL_FILE"
# Plex streaming over 1 Gbps to remote viewers. Only settings that differ from
# a modern kernel's defaults; the old web-server tuning (file-max, TIME_WAIT,
# backlogs, 16 MB per-socket defaults) is gone on purpose.

# BBR holds throughput on long, lossy paths better than cubic/htcp. fq paces it.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Let TCP autotuning grow buffers to 16 MB for fast long-distance streams.
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Don't drop back to slow start between video segments.
net.ipv4.tcp_slow_start_after_idle = 0

# Keep Plex and the rclone cache index in RAM.
vm.swappiness = 10

# Ignore source-routed packets and ICMP redirects.
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
EOT
echo "done."
}

echo "OS settings updating..."
wipe_old
modprobe tcp_bbr 2>/dev/null || true
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
write_new
sysctl -q --system
echo "  Congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"
MSG="OS settings updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
