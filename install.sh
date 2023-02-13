#!/bin/bash

HOST_IP=$1
FLOATING_IP=$2
# IPv6_MODE (optional) The plain string "ipv6". Example: ipv6
IPv6_MODE="${2:-default}"
# IPv6_HOST_ADDR An IPv6 address with mask. Example: 2a01:4f9:c010:9f30::1/64
IPv6_HOST_ADDR="${3:-default}"

scp bootstrap.sh root@"$HOST_IP":/root

if [ "$IPv6_MODE" == 'ipv6' ]; then
    ssh -t root@"$HOST_IP" ./bootstrap.sh "$HOST_IP" "$IPv6_MODE" "$IPv6_HOST_ADDR"
else
    ssh -t root@"$HOST_IP" ./bootstrap.sh "$HOST_IP" "$FLOATING_IP"
fi
