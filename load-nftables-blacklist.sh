#!/bin/bash

RULESET_BASE="/etc/nftables.d/abuse-base.nft"
RULESET_SET1="/etc/nftables.d/abuseipdb-set.nft"
RULESET_SET2="/etc/nftables.d/skipa-set.nft"

# Wait for system to be ready
sleep 2

echo "Loading nftables blacklist rules..." | logger

# Load base rules first (creates table, sets, chain, and rules)
if [ -f "$RULESET_BASE" ]; then
    echo "Loading base rules from $RULESET_BASE..." | logger
    nft -f "$RULESET_BASE"
    if [ $? -eq 0 ]; then
        echo "Base rules loaded successfully." | logger
    else
        echo "Failed to load base rules!" | logger
        exit 1
    fi
else
    echo "Base ruleset file not found at $RULESET_BASE" | logger
    exit 1
fi

# Load abuseipdb set data
if [ -f "$RULESET_SET1" ]; then
    echo "Loading abuseipdb IP set from $RULESET_SET1..." | logger
    nft -f "$RULESET_SET1" 2>/dev/null || {
        echo "Warning: Could not load abuseipdb set - file may be empty" | logger
    }
fi

# Load skipa set data
if [ -f "$RULESET_SET2" ]; then
    echo "Loading skipa IP set from $RULESET_SET2..." | logger
    nft -f "$RULESET_SET2" 2>/dev/null || {
        echo "Warning: Could not load skipa set - file may be empty" | logger
    }
fi

echo "All blacklist rules loaded successfully." | logger
