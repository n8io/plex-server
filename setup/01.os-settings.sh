#!/bin/bash
set -e

backup() {
  echo -n "  Backing up current network settings..."

  cat /etc/sysctl.conf > "/etc/sysctl.conf.$(date +"%Y-%m-%d_%H-%M-%S")"

  echo "done."
}

wipe_old() {
  echo -n "  Removing previous network settings..."

  sed -i '/[#]plex[-]settings[-]start/,/[#]plex[-]settings[-]end/ d' /etc/sysctl.conf

  echo "done."
}

write_new() {
echo -n "  Writing new network settings..."
cat <<EOT >> /etc/sysctl.conf
#plex-settings-start

# Increase system file descriptor limit
fs.file-max = 100000

# Discourage Linux from swapping idle processes to disk (default = 60)
vm.swappiness = 10

# Increase Linux autotuning TCP buffer limits
# Set max to 16MB for 1GE and 32M (33554432) or 54M (56623104) for 10GE
# Don't set tcp_mem itself! Let the kernel scale it based on RAM.
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 40960
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Make room for more TIME_WAIT sockets due to more clients,
# and allow them to be reused if we run out of sockets
# Also increase the max packet backlog
net.core.netdev_max_backlog = 50000
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10

# Disable TCP slow start on idle connections
net.ipv4.tcp_slow_start_after_idle = 0

# If your servers talk UDP, also up these limits
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Disable source routing and redirects
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0

# recommended default congestion control is htcp
net.ipv4.tcp_congestion_control=htcp

# recommended for CentOS7/Debian8 hosts
net.core.default_qdisc = fq

#plex-settings-end
EOT
echo "done."
}

echo "OS settings updating..."
backup # make a backup
wipe_old # remove previous
write_new # write new values
sysctl -p -q # apply changes
MSG="OS settings updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"