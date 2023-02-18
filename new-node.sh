#!/bin/bash


git clone https://github.com/KarmaComputing/high-availability-web-services.git
cd  high-availability-web-services || exit

# Reference root .env settings by creating
# a symlink to .env file
ln -s ../.env .env

git checkout 8-storage

./hetzner/hetzner-create-n-servers.sh 1 cx11 debian-11

# Delete null from servers.txt TODO fix.
#sed -i '1d' servers.txt

NEW_SERVER_IPv4=$(cat ./servers.txt)
rm ./servers.txt

cd .. || exit


# Get new server IPv6 address
echo Waiting 30 secs until we get the IPv6 address whilst server boots
sleep 30
NEW_SERVER_IPv6=$(ssh root@$NEW_SERVER_IPv4 curl http://169.254.169.254/hetzner/v1/metadata | grep ' address:' | cut -d ' ' -f 7)

echo "New server IPv4 is: $NEW_SERVER_IPv4"
echo "New server IPv6 address is: $NEW_SERVER_IPv6"
