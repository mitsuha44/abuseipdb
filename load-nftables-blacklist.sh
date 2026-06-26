#!/bin/bash

RULESET_FILE="/etc/nftables.d/abuse-blacklist.nft"

# Wait for system to be ready
sleep 2

if [ -f "$RULESET_FILE" ]; then
    echo "Loading nftables blacklist rules from $RULESET_FILE..." | logger
    nft -f "$RULESET_FILE"
    if [ $? -eq 0 ]; then
        echo "Blacklist rules loaded successfully." | logger
    else
        echo "Failed to load blacklist rules!" | logger
        exit 1
    fi
else
    echo "Ruleset file not found at $RULESET_FILE" | logger
fi
