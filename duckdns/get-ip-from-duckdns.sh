#!/bin/bash
# Get the current IP address registered with DuckDNS for a given domain
# Usage: ./get-ip-from-duckdns.sh [domain-name] [--json]
# Example: ./get-ip-from-duckdns.sh iforin
#          ./get-ip-from-duckdns.sh iforin.duckdns.org
#          ./get-ip-from-duckdns.sh iforin --json

# Parse arguments
JSON_OUTPUT=false
DOMAIN=""

for arg in "$@"; do
    if [ "$arg" = "--json" ]; then
        JSON_OUTPUT=true
    else
        DOMAIN="$arg"
    fi
done

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 [domain-name] [--json]"
    echo "Example: $0 iforin"
    echo "         $0 iforin.duckdns.org"
    echo "         $0 iforin --json"
    exit 1
fi

# Normalize domain name - add .duckdns.org if not present
if [[ ! "$DOMAIN" =~ \.duckdns\.org$ ]]; then
    DOMAIN="${DOMAIN}.duckdns.org"
fi

if [ "$JSON_OUTPUT" = false ]; then
    echo "Querying DuckDNS for: $DOMAIN"
fi

# Query Google's DNS API for the IP address
RESPONSE=$(curl -s "https://dns.google/resolve?name=${DOMAIN}&type=A")

if [ -z "$RESPONSE" ]; then
    echo "Error: No response from DNS server"
    exit 1
fi

IP=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'Answer' in data and len(data['Answer']) > 0:
        print(data['Answer'][0]['data'])
    else:
        print('No IP found')
except:
    print('Error parsing response')
")

if [ "$IP" = "No IP found" ] || [ "$IP" = "Error parsing response" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{\"status\": \"error\", \"error\": \"Could not resolve IP address for $DOMAIN\", \"domain\": \"$DOMAIN\"}"
    else
        echo "Error: Could not resolve IP address for $DOMAIN"
    fi
    exit 1
fi

if [ "$JSON_OUTPUT" = true ]; then
    echo "{\"status\": \"success\", \"domain\": \"$DOMAIN\", \"ip\": \"$IP\"}"
else
    echo "IP Address: $IP"
fi
