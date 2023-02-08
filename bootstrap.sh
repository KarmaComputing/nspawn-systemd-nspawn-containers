#!/bin/bash

set -xu

HOST_IP=$1
FLOATING_IP=$2

apt update
apt install -y systemd-container debootstrap bridge-utils tmux telnet traceroute vim  qemu-guest-agent
echo "set mouse=" > ~/.vimrc
echo 'kernel.unprivileged_userns_clone=1' >/etc/sysctl.d/nspawn.conf
# allow proxy_arp
echo "net.ipv4.conf.eth0.proxy_arp=1" >> /etc/sysctl.conf

# Permit ip forwarding

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf  | grep 'forward'
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -p

mkdir -p /etc/systemd/nspawn

# Create a Debian nspawn container using debootstrap

debootstrap --include=systemd,dbus,traceroute,telnet,curl stable /var/lib/machines/debian

cat >/etc/systemd/nspawn/debian.nspawn <<EOL
[Network]
Bridge=br0
EOL

cat /etc/systemd/nspawn/debian.nspawn

# Configure networking
rm /etc/network/interfaces.d/50-cloud-init
#
truncate -s0 /etc/network/interfaces

cat >/etc/network/interfaces <<EOL
# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
  address $HOST_IP
  netmask 255.255.255.255
  pointtopoint 172.31.1.1
  gateway 172.31.1.1
  dns-nameservers 185.12.64.1 185.12.64.2

#Bridge setup
auto br0
iface br0 inet static
   bridge_ports none
   bridge_stp off
   bridge_fd 1
   pre-up brctl addbr br0
   up ip route add $FLOATING_IP/32 dev br0
   down ip route del $FLOATING_IP/32 dev br0
   address $HOST_IP
   netmask 255.255.255.255
   dns-nameservers 185.12.64.1 185.12.64.2
EOL

ip link set dev eth0 up
ifup br0

# Make network configuration static
cat >/var/lib/machines/debian/etc/systemd/network/80-container-host0.network <<EOL
[Match]
Virtualization=container
Name=host0

[Network]
# Yout floating IP
Address=$FLOATING_IP/32
DHCP=no
LinkLocalAddressing=yes
LLDP=yes
EmitLLDP=customer-bridge

[Route]
# Your servers main IP
Gateway=$HOST_IP
GatewayOnLink=yes


[DHCP]
UseTimezone=yes
EOL



# Enable (but don't start) the container
systemctl enable  systemd-nspawn@debian.service


# Stop if guest already started
systemctl stop systemd-nspawn@debian.service

# Start the container
systemctl start systemd-nspawn@debian.service

set +x

echo "#####################"
echo Remaining manual steps:
echo 
echo "You'll want to ssh to the host now and perform the following:"
echo - ssh to your host: ssh root@$HOST_IP
echo - Reload systemd \& networkd to get the guest network config:
echo machinectl shell debian /bin/bash -c 'systemctl daemon-reload && systemctl restart systemd-networkd'

echo - Set password and configure /etc/securetty:
echo systemd-nspawn -D /var/lib/machines/debian -U --machine debian passwd
echo "#####################"


