# plex-server
A hand full of scripts to setup your Plex Media Server and keep it running smoothly

## Getting started

1. ssh into your Plex Media Server
```
ssh -i ~/.ssh/id_rsa -L 32400:localhost:32400 root@<your.pms.public.ip>
```
1. Clone this repo
```
apt-get install -y git
cd / && git clone https://github.com/n8io/plex-server.git && cd plex-server
```
1. Initialize
```
./init.sh
```
