#!/usr/bin/env bash

set -e

if [ "$(whoami)" != "crypto" ]; then
    echo -e "Please run with \"\033[32msudo -u crypto $0\033[0m\""
    exit 1
fi

read -p "Please select either mainnet(M) or testnet(T) to join (M/T): " mt
case $mt in
    [Mm]* ) REMOTE_SCRIPT="https://raw.githubusercontent.com/crypto-org-chain/cronos-mainnet/main/1-click/1click-reconfig.sh";;
    [Tt]* ) REMOTE_SCRIPT="https://raw.githubusercontent.com/crypto-org-chain/cronos-testnets/main/1-click/1click-reconfig.sh";;
    * ) echo "No match"; exit 1;;
esac

bash <(curl -sSL $REMOTE_SCRIPT)