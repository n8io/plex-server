#!/bin/bash
set -e
SCANNERS_DIR="/home/plexmediaserver/Library/Application Support/Plex Media Server/Scanners"
cd /tmp
wget https://bitbucket.org/mjarends/plex-scanners/get/master.zip
unzip master.zip -d /tmp
mv mjarends-plex-scanners-*/ /tmp/plex-scanners
mkdir -p "$SCANNERS_DIR"
cp -R /tmp/plex-scanners/* "$SCANNERS_DIR"
rm -rf /tmp/master.zip /tmp/plex-scanners
set +e
