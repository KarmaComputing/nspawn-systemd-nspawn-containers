#!/bin/bash

set -xu

HOST_IP=$1
FLOATING_IP=$2

apt update
apt install -y systemd-container debootstrap bridge-utils tmux telnet traceroute vim python3 python3-venv qemu-guest-agent
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

# Start the guest container
systemctl start systemd-nspawn@debian.service

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
echo ssh access from your host $HOST_IP to your guest has
echo "already been setup (see above)."
echo
echo "#####################"


