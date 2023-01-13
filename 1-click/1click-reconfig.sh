#!/usr/bin/env bash

set -e

download_genesis()
{
    echo_s "💾 Downloading $NETWORK genesis"
    curl -sS $NETWORK_URL/$NETWORK/genesis.json -o $CM_GENESIS
}
shopt -s globstar
download_binary()
{
    echo_s "💾 Downloading $CM_DESIRED_VERSION binary"
    sudo curl -LJ $(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".binary | .[] | select(.version==\"$CM_DESIRED_VERSION\").linux.link") -o $CM_DIR/cronosd.tar.gz
    CHECKSUM=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".binary | .[] | select(.version==\"$CM_DESIRED_VERSION\").linux.checksum")
    echo "downloaded $CHECKSUM"
    if (! echo "$CHECKSUM $CM_DIR/cronosd.tar.gz" | sha256sum -c --status --quiet - > /dev/null 2>&1) ; then
        echo_s "The checksum does not match the target downloaded file! Something wrong from download source, please try again or create an issue for it."
        exit 1
    fi
    sudo tar -xzf $CM_DIR/cronosd.tar.gz -C $CM_DIR
}
InitChain()
{
    # Config .cronos/config/config.toml
    echo_s "Replace moniker in $CM_CONFIG"
    echo_s "Moniker is display name for tendermint p2p\n"
    read -p 'moniker: ' MONIKER

    if [[ -n "$MONIKER" ]] ; then
        sudo $CM_BINARY init $MONIKER --chain-id $NETWORK --home $CM_HOME
        PERSISTENT_PEERS=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".seeds")
        sudo sed -i "s/^\(persistent_peers\s*=\s*\).*\$/\1\"$PERSISTENT_PEERS\"/" $CM_CONFIG
    else
        echo_s "moniker is not set. Try again!\n"
    fi
}
StartService()
{
    # Enable systemd service for cronosd
    sudo systemctl daemon-reload
    sudo systemctl enable cronosd.service
    echo_s "👏🏻 Restarting cronosd service\n"
    sudo systemctl restart cronosd.service
    sudo systemctl restart rsyslog
    echo_s "👀 View the log by \"\033[32mjournalctl -u cronosd.service -f\033[0m\" or find in /chain/log/cronosd/cronosd.log"
}
StopService()
{
    # Stop service
    echo_s "Stopping cronosd service"
    sudo systemctl stop cronosd.service
}

AllowGossip()
{
    # find IP
    IP=$(curl -s http://checkip.amazonaws.com)
    if [[ -z "$IP" ]] ; then
        read -p 'What is the public IP of this server?: ' IP
    fi
    echo_s "✅ Added public IP to external_address in cronosd config.toml for p2p gossip\n"
    sudo sed -i "s/^\(external_address\s*=\s*\).*\$/\1\"$IP:26656\"/" $CM_CONFIG
}
EnableStateSync()
{
    #Setting up statesync
    RPC_SERVERS=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".endpoint.rpc")
    LASTEST_HEIGHT=$(curl -s $RPC_SERVERS/block | jq -r .result.block.header.height)
    BLOCK_HEIGHT=$((LASTEST_HEIGHT - 300))
    TRUST_HASH=$(curl -s "$RPC_SERVERS/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)
    PERSISTENT_PEERS=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".persistent_peers")
    IFS=',' read -r -a array <<< "$PERSISTENT_PEERS"
    peer_size=${#array[@]}
    index1=$(($RANDOM % $peer_size))
    index2=$(($RANDOM % $peer_size))
    PERSISTENT_PEERS="${array[$index1]},${array[$index2]}"
    sudo sed -i "s/^\(seeds\s*=\s*\).*\$/\1\"\"/" $CM_CONFIG
    sudo sed -i "s/^\(persistent_peers\s*=\s*\).*\$/\1\"$PERSISTENT_PEERS\"/" $CM_CONFIG
    sudo sed -i "s/^\(trust_height\s*=\s*\).*\$/\1$BLOCK_HEIGHT/" $CM_CONFIG
    sudo sed -i "s/^\(trust_hash\s*=\s*\).*\$/\1\"$TRUST_HASH\"/" $CM_CONFIG
    sudo sed -i "s/^\(enable\s*=\s*\).*\$/\1true/" $CM_CONFIG
    sudo sed -i "s|^\(rpc_servers\s*=\s*\).*\$|\1\"$RPC_SERVERS,$RPC_SERVERS\"|" $CM_CONFIG
}
DisableStateSync()
{
    sudo sed -i "s/^\(enable\s*=\s*\).*\$/\1false/" $CM_CONFIG
}
clearDataAndBinary()
{
    #Remove old dataand binary
    echo_s "Reset cronosd and remove data if any"
    read -p '❗️ Enter (Y/N) to confirm to delete any old data: ' yn
    case $yn in
        [Yy]* ) 
            StopService;
            sudo rm -rf $CM_HOME/ 
            sudo rm -rf $CM_BINARY $CM_DIR/cronosd.tar.gz $CM_DIR/exe $CM_DIR/lib
            sudo rm -rf $CM_DIR/README.md $CM_DIR/LICENSE $CM_DIR/CHANGELOG.md
            sleep 3
            echo_s "Deletion completed";;
        * ) echo_s "continue without deleting\n";;
    esac
}
shareIP()
{
    read -p "Do you want to add the public IP of this node for p2p gossip? (Y/N): " yn
    case $yn in
        [Yy]* ) AllowGossip;;
        * )
            echo_s "WIll keep 'external_address value' empty\n";
            sudo sed -i "s/^\(external_address\s*=\s*\).*\$/\1\"\"/" $CM_CONFIG;;
    esac
}
shopt -s extglob
checkout_network()
{
    mapfile -t arr < <(curl -sS $NETWORK_JSON | jq -r 'keys[]')
    echo_s "You can select the following networks to join"
    for i in "${!arr[@]}"; do
        printf '\t%s. %s\n' "$i" "${arr[i]}"
    done

    read -p "Please choose the network to join by index (0/1/...): " index
    case $index in
        +([0-9]))
            if [[ $index -gt $((${#arr[@]} - 1)) ]]; then
                echo_s "Larger than the max index"
                exit 1
            fi
            NETWORK=${arr[index]}
            echo_s "The selected network is $NETWORK"
            read -p "Select Y to initalize the chain with the current binary. Select N if you have initialized manually before (Y/N): " yn
            case $yn in
                [Yy]* ) 
                    clearDataAndBinary
                    echo_s "Download the target version $CM_DESIRED_VERSION binary from github release."
                    CM_DESIRED_VERSION=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".binary | .[-1].version")
                    download_binary
                    InitChain
                ;;
                * ) 
                    echo_s "Continue assuming you have ran ./cronosd init by yourself"
                ;;
            esac
            read -p "Do you want to enable state-sync? (Y/N): " yn
            case $yn in
                [Yy]* ) 
                    echo_s "State-sync requires the latest version of binary to state-sync from the latest block."
                    echo_s "Be aware that the latest binary might contain extra dependencies!"
                    CM_DESIRED_VERSION=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".latest_version")
                    if [[ ! -f "$CM_BINARY" ]] || [[ $($CM_BINARY version 2>&1) != $CM_DESIRED_VERSION ]]; then
                        echo_s "The binary does not exist or the version does not match the target version. Download the target version binary from github release."
                        clearDataAndBinary
                        download_binary
                        InitChain
                    fi
                    EnableStateSync
                ;;
                * ) 
                    if [[ ! -f "$CM_BINARY" ]]; then
                       echo_s "Restart this script and select Y to init chain." 
                       exit 1
                    fi 
                    DisableStateSync
                ;;
            esac
            GENESIS_TARGET_SHA256=$(curl -sS $NETWORK_JSON | jq -r ".\"$NETWORK\".genesis_sha256sum")
            if [[ ! -f "$CM_GENESIS" ]] || (! echo "$GENESIS_TARGET_SHA256 $CM_GENESIS" | sha256sum -c --status --quiet - > /dev/null 2>&1) ; then
                echo_s "The genesis does not exist or the sha256sum does not match the target one. Download the target genesis from github."
                download_genesis
            fi
            shareIP
        ;;
        *)
            echo_s "No match"
            exit 1
        ;;
    esac
}
echo_s()
{
    echo -e $1
}

require_jq()
{
    if ! [ -x "$(command -v jq)" ]; then
            echo 'jq not installed! Installing jq' >&2
            sudo apt update
            sudo apt install jq -y
    fi
}


# Select network
NETWORK_URL="https://raw.githubusercontent.com/crypto-org-chain/cronos-mainnet/fix/update-1click-reconfig-script"
NETWORK_JSON="$NETWORK_URL/mainnet.json"
CM_DIR="/chain"
CM_HOME="/chain/.cronos"
CM_BINARY="/chain/bin/cronosd"
CM_CONFIG="$CM_HOME/config/config.toml"
CM_GENESIS="$CM_HOME/config/genesis.json"

require_jq
checkout_network
StartService