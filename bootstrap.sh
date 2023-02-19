#!/bin/bash

set -xu

HOST_IP=$1
FLOATING_IP=$2
# IPv6_MODE (optional) The plain string "ipv6". Example: ipv6
IPv6_MODE="${2:-default}"
# IPv6_HOST_ADDR An IPv6 address with mask. Example: 2a01:4f9:c010:9f30::1/64
IPv6_HOST_ADDR="${3:-default}"
# Remove /64 mask from IPv6_HOST_ADDR
# See https://www.shellcheck.net/wiki/SC2001
IPv6_HOST_ADDR_WITHOUT_MASK=$(echo "${IPv6_HOST_ADDR/\/64/}")

echo The IPv6_HOST_ADDR_WITHOUT_MASK is $IPv6_HOST_ADDR_WITHOUT_MASK
apt update
apt install -y python3

# Determin seccond (n) IPv6 address, and without mask
IPv6_HOST_ADDR_2=$(echo -e "from ipaddress import ip_address, IPv6Network\nimport itertools\nip = IPv6Network('$IPv6_HOST_ADDR', strict=False)\nseccondAddress = next(itertools.islice(ip, 2, None))\nprint(seccondAddress)" | python3)

echo The determind IPv6_HOST_ADDR_2 is: $IPv6_HOST_ADDR_2

apt install -y systemd-container debootstrap bridge-utils tmux telnet traceroute vim python3 tcpdump python3-venv qemu-guest-agent
echo "set mouse=" > ~/.vimrc
echo 'kernel.unprivileged_userns_clone=1' >/etc/sysctl.d/nspawn.conf
# allow proxy_arp
echo "net.ipv4.conf.eth0.proxy_arp=1" >> /etc/sysctl.conf

# Permit IPv4 forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf  | grep 'forward'
echo 1 > /proc/sys/net/ipv4/ip_forward


# Permit IPv6 forwarding
sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf

echo net.ipv6.conf.all.proxy_ndp = 1 >> /etc/sysctl.conf

# Reload sysctl
sysctl -p

mkdir -p /etc/systemd/nspawn

# Create a Debian nspawn container using debootstrap

debootstrap --include=systemd,dbus,traceroute,telnet,curl,python3 stable /var/lib/machines/debian

cat >/etc/systemd/nspawn/debian.nspawn <<EOL
[Network]
Bridge=br0

#If you want ephemeral containers,
# Uncomment below:
#[Exec]
#LinkJournal=no
#Ephemeral=yes
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
EOL


if [ "$IPv6_MODE" == 'ipv6' ]; then

cat >>/etc/network/interfaces <<EOL
#Bridge setup
auto br0
iface br0 inet static
   bridge_ports none
   bridge_stp off
   bridge_fd 1
   pre-up brctl addbr br0
   address $HOST_IP
   netmask 255.255.255.255
   dns-nameservers 185.12.64.1 185.12.64.2
EOL

else

cat >>/etc/network/interfaces <<EOL
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

fi

# Configure IPv6 host interface
if [ "$IPv6_MODE" == 'ipv6' ]; then

cat >>/etc/network/interfaces <<EOL
iface eth0 inet6 static
   address $IPv6_HOST_ADDR
   dns-nameservers 2a01:4ff:ff00::add:1 2a01:4ff:ff00::add:2
   gateway fe80::1
EOL

fi


ip link set dev eth0 up
ifup br0

# Make network configuration static
if [ "$IPv6_MODE" == 'ipv6' ]; then
cat >/var/lib/machines/debian/etc/systemd/network/80-container-host0.network <<EOL
[Match]
Virtualization=container
Name=host0

[Network]
# Yout floating IP
Address=$IPv6_HOST_ADDR_2/128
DHCP=no


[Route]
Destination=$IPv6_HOST_ADDR_WITHOUT_MASK/128

[Route]
Gateway=$IPv6_HOST_ADDR_WITHOUT_MASK
Destination=::/0
EOL

else
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

fi




# Enable (but don't start) the container
systemctl enable  systemd-nspawn@debian.service


# Stop if guest already started
systemctl stop systemd-nspawn@debian.service

# Start the guest container
systemctl start systemd-nspawn@debian.service

# Add route on host to nspawn IPv6 host TODO use systemd-networkd on host
ip route add $IPv6_HOST_ADDR_2/128 dev br0

# Add IPv6 proxy for NDP (like roxy_arp but for IPv6)
echo Initially show proxy will be empy
ip -6 nei show proxy
ip nei add proxy $IPv6_HOST_ADDR_WITHOUT_MASK dev br0
ip -6 nei show proxy

machinectl list
echo 'debug'

# Enable networkd in the container
sleep 15 # Give guest some time to boot
machinectl shell debian /bin/bash -c 'systemctl enable systemd-networkd && systemctl start systemd-networkd'

# Setup bootstrap ssh TODO lean on ephemeral instead
machinectl shell debian /bin/bash -c 'apt install -y openssh-server && mkdir -p /root/.ssh && touch /root/.ssh/authorized_keys'

# Generate host ssh key
ssh-keygen -t ecdsa -f /root/.ssh/id_ecdsa -q -N ""
HOST_PUBLIC_KEY=$(cat /root/.ssh/id_ecdsa.pub)
# Add public key to guest authorized_keys
echo -e "$HOST_PUBLIC_KEY" >> /var/lib/machines/debian/root/.ssh/authorized_keys

# Build an ansible inventory for setting guests password
# to overcome Authentication token manipulation errors. TODO work out so
# can drop ansible.
python3 -m venv venv
. venv/bin/activate
pip install ansible
echo "$FLOATING_IP ansible_user=root" > inventory

# Write a playbook
PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 15 ; echo '')

cat >change_password.yml <<EOL
---
- name: set guest ssh password
  hosts: all
  become: true
  vars:
    username: "root"
    password: "$PASSWORD"
  tasks:
    - name: change password
      ansible.builtin.user:
        name: "{{ username }}"
        state: present
        password: "{{ password | password_hash('sha512') }}"
EOL

# Set guest password
ansible-playbook -i inventory change_password.yml


set +x

echo "#####################"
echo Setup complete!
echo
echo You may want to:
echo - Verify you can ping your guest from your localhost:
echo
echo ping -c 3 "$FLOATING_IP"
echo
echo - ssh to your host:
echo ssh root@"$HOST_IP"
echo
echo "- ssh from your host ($HOST_IP) to your guest:"
echo   ssh root@"$FLOATING_IP"
echo
echo - Or directly since your on the host anyway
echo   machinectl login debian
echo   "# The guest root password is $PASSWORD"
echo
echo - You can start stop guests like this:
echo
echo systemctl stop systemd-nspawn@debian.service
echo systemctl start systemd-nspawn@debian.service
echo
echo Note: You must use ssh key based authentication to
echo access your guest remotely over ssh.
echo "If you want to do that, then you'll have to add your"
echo localhost\'s public ssh key to the authorized_keys file
echo on your guest.
echo ssh access from your host "$HOST_IP" to your guest has
echo "already been setup (see above)."
echo
echo Your IPv6 host address is: $IPv6_HOST_ADDR_WITHOUT_MASK
echo Your first IPv6 nspawn container address is: $IPv6_HOST_ADDR_2
echo "#####################"


