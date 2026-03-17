#!/bin/bash

# 1. Grab only the FIRST Ethernet interface found to avoid "en0 en1" errors
eth_interface=$(networksetup -listallhardwareports | awk '/Hardware Port: .*Ethernet/{getline; print $2}' | head -n 1)

# 2. Check if Ethernet exists at all
if [ -z "$eth_interface" ]; then
    result="No Ethernet Hardware"
else
    # 3. Get status and clean up whitespace
    status=$(ifconfig "$eth_interface" 2>/dev/null | grep "status:" | awk -F ": " '{print $2}' | xargs)
    
    if [ -z "$status" ]; then
        result="Unknown"
    else
        result="$status"
    fi
fi

# 4. Return to Jamf
echo "<result>$result</result>"
