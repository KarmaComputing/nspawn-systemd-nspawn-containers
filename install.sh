#!/bin/bash

HOST_IP=$1
FLOATING_IP=$2

scp bootstrap.sh root@$HOST_IP:/root

ssh -t root@$HOST_IP ./bootstrap.sh $HOST_IP $FLOATING_IP
