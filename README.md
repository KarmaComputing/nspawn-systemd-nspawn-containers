# nspawn-systemd-nspawn-containers

Using systemd-nspawn containers with publicly routable ips (IPv6 and IPv4) via bridged mode for high density testing whilst balancing tenant isolation.

See associated [nspawn blog tutorial for background](https://blog.karmacomputing.co.uk/using-systemd-nspawn-containers-with-publicly-routable-ips-ipv6-and-ipv4-via-bridged-mode-for-high-density-testing-whilst-balancing-tenant-isolation/).

# Usage
(Read the above blog)

## Step day 0, create a Linux host with debian 11 as the base image

Setup `.env`

```
cp .env.example .env
```
Run to create a new node:
```
./new-node.sh
```

1. Set `HOST_IP` and `FLOATING_IP` in `install.sh`
2. Run `install.sh $HOST_IP $FLOATING_IP`

### Example: `IPv4`
```
./install.sh 203.0.113.1 203.0.113.2
# Follow instructions from script output at the end.
```

### Example: `IPv6`

> When doing `IPv6` pass the `IPv4` address of the host, and the `IPv6` address of the server also.

The `IPv4` address is used initially to connect to the host server and so the install,
the next available `IPv6` address is used for the container(s) IPv6 address.

```
./install.sh 203.0.113.1 ipv6 2a01:4f9:c010:9f30::1/64
```

> Note you currently have to add the bridge and edit the container network settings
manually after install:

(On the host- not the guest):
```
ip route add 2a01:4f9:c010:9f30::2/128 dev br0
ip -6 nei show proxy # will be empty
ip neigh add proxy 2a01:4f9:c010:9f30::1 dev br0
ip -6 nei show proxy
```

Then also edit: `/var/lib/machines/debian/etc/systemd/network/80-container-host0.network`
and update the `changeme` values keeping the `/` masks.


