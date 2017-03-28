#!/bin/bash
set -e
/cd /tmp
wget https://bitbucket.org/mjarends/plex-scanners/get/master.zip
unzip master.zip -d /tmp
rm master.zip
mv mjarends-plex-scanners-*/ /tmp/plex-scanners
cp -R /tmp/plex-scanners/* /home/plexmediaserver/Library/Application Support/Plex Media Server/Scanners/
rm -rf /tmp/master.zip /tmp/plex-scanners
service plexmediaserver restart
set +e
