# nspawn-systemd-nspawn-containers

Using systemd-nspawn containers with publicly routable ips (IPv6 and IPv4) via bridged mode for high density testing whilst balancing tenant isolation.

See associated [nspawn blog tutorial for background](https://blog.karmacomputing.co.uk/using-systemd-nspawn-containers-with-publicly-routable-ips-ipv6-and-ipv4-via-bridged-mode-for-high-density-testing-whilst-balancing-tenant-isolation/).

# Usage

1. Set `HOST_IP` and `FLOATING_IP` in `install.sh`
2. Run `install.sh $HOST_IP $FLOATING_IP`

Example:
```
./install.sh 203.0.113.1 203.0.113.2
# Follow instructions from script output at the end.
```

(Read the above blog)
