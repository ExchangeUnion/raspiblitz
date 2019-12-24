#!/bin/bash

# https://github.com/janoside/btc-rpc-explorer
# ~/.config/btc-rpc-explorer.env
# https://github.com/janoside/btc-rpc-explorer/blob/master/.env-sample

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch BTC-RPC-explorer on or off"
 echo "bonus.btc-rcp-explorer.sh [status|on|off]"
 exit 1
fi

# add default value to raspi config if needed
source /mnt/hdd/raspiblitz.conf
if [ ${#BTCRPCexplorer} -eq 0 ]; then
  echo "BTCRPCexplorer=off" >> /mnt/hdd/raspiblitz.conf
  source /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${BTCRPCexplorer}" = "on" ]; then
    echo "configured=1"

    # check indexing
    source <(sudo /home/admin/config.scripts/network.txindex.sh status)
    echo "isIndexed=${isIndexed}"
    echo "indexInfo='${indexInfo}'"

  else
    echo "configured=0"
  fi
  exit 0
fi

# determine nodeJS DISTRO
isARM=$(uname -m | grep -c 'arm')   
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')
# get checksums from -> https://nodejs.org/dist/vx.y.z/SHASUMS256.txt
if [ ${isARM} -eq 1 ] ; then
DISTRO="linux-armv7l"
fi
if [ ${isAARCH64} -eq 1 ] ; then
DISTRO="linux-arm64"
fi
if [ ${isX86_64} -eq 1 ] ; then
DISTRO="linux-x64"
fi
if [ ${isX86_32} -eq 1 ] ; then
echo "FAIL: No X86 32bit build available - will abort setup"
exit 1
fi
if [ ${#DISTRO} -eq 0 ]; then
echo "FAIL: Was not able to determine architecture"
exit 1
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop btc-rpc-explorer 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL BTC-RPC-EXPLORER ***"

  isInstalled=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ ${isInstalled} -eq 0 ]; then

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh

    # make sure that txindex of blockchain is switched on
    /home/admin/config.scripts/network.txindex.sh on

    npm install -g btc-rpc-explorer@1.1.3

    # prepare .env file
    echo "getting RPC credentials from the ${network}.conf"

    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    sudo -u bitcoin mkdir /home/bitcoin/.config/ 2>/dev/null
    touch /home/admin/btc-rpc-explorer.env
    chmod 600 /home/admin/btc-rpc-explorer.env || exit 1 
    cat > /home/admin/btc-rpc-explorer.env <<EOF
# Host/Port to bind to
# Defaults: shown
BTCEXP_HOST=0.0.0.0
#BTCEXP_PORT=3002
# Bitcoin RPC Credentials (URI -OR- HOST/PORT/USER/PASS)
# Defaults:
#   - [host/port]: 127.0.0.1:8332
#   - [username/password]: none
#   - cookie: '~/.bitcoin/.cookie'
#   - timeout: 5000 (ms)
BTCEXP_BITCOIND_URI=$network://$RPC_USER:$PASSWORD_B@127.0.0.1:8332?timeout=10000
#BTCEXP_BITCOIND_HOST=127.0.0.1
#BTCEXP_BITCOIND_PORT=8332
BTCEXP_BITCOIND_USER=$RPC_USER
BTCEXP_BITCOIND_PASS=$PASSWORD_B
#BTCEXP_BITCOIND_COOKIE=/path/to/bitcoind/.cookie
BTCEXP_BITCOIND_RPC_TIMEOUT=5000
# Password protection for site via basic auth (enter any username, only the password is checked)
# Default: none
BTCEXP_BASIC_AUTH_PASSWORD=$PASSWORD_B
# Select optional "address API" to display address tx lists and balances
# Options: electrumx, blockchain.com, blockchair.com, blockcypher.com
# If electrumx set, the BTCEXP_ELECTRUMX_SERVERS variable must also be
# set.
# Default: none
BTCEXP_ADDRESS_API=none
BTCEXP_ELECTRUMX_SERVERS=tcp://127.0.0.1:50001
EOF
    sudo mv /home/admin/btc-rpc-explorer.env /home/bitcoin/.config/btc-rpc-explorer.env
    sudo chown bitcoin:bitcoin /home/bitcoin/.config/btc-rpc-explorer.env

    # open firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow 3002 comment 'btc-rpc-explorer'
    sudo ufw --force enable
    echo ""

    # install service
    echo "*** Install btc-rpc-explorer systemd ***"
    cat > /home/admin/btc-rpc-explorer.service <<EOF
# systemd unit for BTC RPC Explorer

[Unit]
Description=btc-rpc-explorer
Wants=${network}d.service
After=${network}d.service

[Service]
ExecStart=/usr/local/lib/nodejs/node-$(node -v)-$DISTRO/bin/btc-rpc-explorer
User=bitcoin
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /home/admin/btc-rpc-explorer.service /etc/systemd/system/btc-rpc-explorer.service 
    sudo systemctl enable btc-rpc-explorer
    echo "OK - the BTC-RPC-explorer service is now enabled"

  else 
    echo "BTC-RPC-explorer already installed."
  fi

  # start service
  echo "Starting service"
  sudo systemctl start btc-rpc-explorer 2>/dev/null

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCRPCexplorer=.*/BTCRPCexplorer=on/g" /mnt/hdd/raspiblitz.conf
  
  echo "needs to finish creating txindex to be functional"
  echo "monitor with: sudo tail -n 20 -f /mnt/hdd/bitcoin/debug.log"

  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  /home/admin/config.scripts/bonus.electrsexplorer.sh

  # Hidden Service for BTC-RPC-explorer if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # correct old Hidden Service with port
    sudo sed -i "s/^HiddenServicePort 3002 127.0.0.1:3002/HiddenServicePort 80 127.0.0.1:3002/g" /etc/tor/torrc
    /home/admin/config.scripts/internet.hiddenservice.sh btc-rpc-explorer 80 3002
    
    TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/btc-rpc-explorer/hostname)
    if [ -z "$TOR_ADDRESS" ]; then
      echo "Waiting for the Hidden Service"
      sleep 10
      TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/btc-rpc-explorer/hostname)
      if [ -z "$TOR_ADDRESS" ]; then
        echo " FAIL - The Hidden Service address could not be found - Tor error?"
        exit 1
      fi
    fi    
    echo ""
    echo "***"
    echo "The Tor Hidden Service address for btc-rpc-explorer is:"
    echo "$TOR_ADDRESS"
    echo "***"
    echo "" 
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCRPCexplorer=.*/BTCRPCexplorer=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING BTC-RPC-explorer ***"
    sudo systemctl stop btc-rpc-explorer
    sudo systemctl disable btc-rpc-explorer
    sudo rm /etc/systemd/system/btc-rpc-explorer.service
    sudo rm -r /usr/local/lib/nodejs/node-$(node -v)-$DISTRO/bin/btc-rpc-explorer
    echo "OK BTC-RPC-explorer removed."
  else 
    echo "BTC-RPC-explorer is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1