#!/bin/bash

set -euo pipefail

if ! command -v docker >/dev/null; then
    # Install Docker-CE
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    # Install add-apt-repository
    sudo apt-get install -y software-properties-common
    # arm64
    # TODO support other platforms: amd64 & armhf (32bit)
    sudo add-apt-repository \
"deb [arch=arm64] https://download.docker.com/linux/debian \
$(lsb_release -cs) \
stable"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker $USER
    # https://stackoverflow.com/questions/49434650/how-to-add-a-user-to-a-group-without-logout-login-bash-script
    # skip 00raspiblitz.sh
    TMUX=1 newgrp docker
    TMUX=1 newgrp $USER
fi

xudScript="/home/admin/xud.sh" # TODO change to a more proper location in Raspiblitz
if [ ! -e "$xudScript" ]; then
    # Download xud.sh
    curl -s https://raw.githubusercontent.com/ExchangeUnion/xud-docker/master/xud.sh > "$xudScript"
fi

if [ ! -e "/mnt/hdd/xud-mainnet" ]; then
    sudo mkdir /mnt/hdd/xud-mainnet
fi

if [ ! -e "/mnt/hdd/xud-mainnet/lndbtc" ]; then
    sudo mkdir /mnt/hdd/xud-mainnet/lndbtc
fi

sudo chown -R $USER:$USER /mnt/hdd/xud-mainnet
# RaspiBlitz ~/.lnd is a link which will not be mapped in /mnt/hostfs
cp $HOME/.lnd/tls.cert /mnt/hdd/xud-mainnet/lndbtc/tls.cert
cp $HOME/.lnd/data/chain/bitcoin/mainnet/admin.macaroon /mnt/hdd/xud-mainnet/lndbtc/admin.macaroon

# TODO make sure lndbtc is properly set up
bash "$xudScript" -b pi \
--network mainnet \
--mainnet-dir /mnt/hdd/xud-mainnet \
--lndbtc.mode external \
--lndbtc.rpc-host 10.0.3.1 \
--lndbtc.rpc-port 10009 \
--lndbtc.certpath /mnt/hostfs/mnt/hdd/xud-mainnet/lndbtc/tls.cert \
--lndbtc.macaroonpath /mnt/hostfs/mnt/hdd/xud-mainnet/lndbtc/admin.macaroon \
