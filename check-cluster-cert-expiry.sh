#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================================"
echo "OpenShift Cluster Certificate Expiration Checker"
echo "======================================================"
echo ""

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' command not found. Please install the OpenShift CLI.${NC}"
    exit 1
fi

# Check if we're logged in
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into an OpenShift cluster. Please run 'oc login' first.${NC}"
    exit 1
fi

echo "Cluster: $(oc whoami --show-server)"
echo "User: $(oc whoami)"
echo ""

# Function to convert date to epoch and calculate days remaining
calculate_days_remaining() {
    local cert_date="$1"

    # Parse the date (format: "notAfter=Mar 29 12:34:56 2026 GMT")
    local formatted_date=$(echo "$cert_date" | sed 's/notAfter=//')

    # Convert to epoch time (works on both Linux and macOS)
    if date --version &>/dev/null 2>&1; then
        # GNU date (Linux)
        local cert_epoch=$(date -d "$formatted_date" +%s 2>/dev/null || echo "0")
    else
        # BSD date (macOS)
        local cert_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$formatted_date" +%s 2>/dev/null || echo "0")
    fi

    local current_epoch=$(date +%s)
    local days_remaining=$(( ($cert_epoch - $current_epoch) / 86400 ))

    echo "$days_remaining"
}

# Array to store minimum days across all nodes
declare -a all_days_remaining

echo "=== Checking Kubelet Certificates on All Nodes ==="
echo ""

nodes=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $nodes; do
    echo -e "${YELLOW}Node: $node${NC}"

    # Check kubelet client certificate
    client_cert=$(oc debug node/$node -- chroot /host sh -c 'openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -enddate 2>/dev/null' 2>/dev/null | grep -v "Starting pod" | grep -v "Removing debug pod" | grep "notAfter")

    if [ -n "$client_cert" ]; then
        echo "  Kubelet Client Cert: $client_cert"
        days=$(calculate_days_remaining "$client_cert")
        all_days_remaining+=($days)

        if [ "$days" -lt 7 ]; then
            echo -e "  ${RED}WARNING: Only $days days remaining!${NC}"
        elif [ "$days" -lt 30 ]; then
            echo -e "  ${YELLOW}Days remaining: $days${NC}"
        else
            echo -e "  ${GREEN}Days remaining: $days${NC}"
        fi
    else
        echo "  Unable to retrieve client certificate"
    fi

    # Check kubelet server certificate
    server_cert=$(oc debug node/$node -- chroot /host sh -c 'openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -enddate 2>/dev/null' 2>/dev/null | grep -v "Starting pod" | grep -v "Removing debug pod" | grep "notAfter")

    if [ -n "$server_cert" ]; then
        echo "  Kubelet Server Cert: $server_cert"
        days=$(calculate_days_remaining "$server_cert")

        if [ "$days" -lt 7 ]; then
            echo -e "  ${RED}WARNING: Only $days days remaining!${NC}"
        elif [ "$days" -lt 30 ]; then
            echo -e "  ${YELLOW}Days remaining: $days${NC}"
        else
            echo -e "  ${GREEN}Days remaining: $days${NC}"
        fi
    else
        echo "  Unable to retrieve server certificate"
    fi

    echo ""
done

echo ""
echo "======================================================"
echo "=== Summary ==="
echo "======================================================"

if [ ${#all_days_remaining[@]} -eq 0 ]; then
    echo -e "${RED}Unable to determine certificate expiration dates.${NC}"
    exit 1
fi

# Find minimum days remaining
min_days=${all_days_remaining[0]}
for days in "${all_days_remaining[@]}"; do
    if [ "$days" -lt "$min_days" ]; then
        min_days=$days
    fi
done

echo ""
echo "Minimum days until certificate expiration: $min_days days"
echo ""

# Calculate safe shutdown period (with safety margin)
safe_days=$((min_days - 2))

if [ "$safe_days" -lt 0 ]; then
    echo -e "${RED}CRITICAL: Certificates are expiring very soon!${NC}"
    echo -e "${RED}You should NOT shut down this cluster.${NC}"
    echo -e "${RED}Certificates will expire in $min_days days.${NC}"
elif [ "$safe_days" -lt 7 ]; then
    echo -e "${YELLOW}WARNING: Limited safe shutdown window.${NC}"
    echo -e "${YELLOW}Safe shutdown period: Up to $safe_days days (with 2-day safety margin)${NC}"
    echo ""
    echo "Recommendation: Keep shutdown period under $safe_days days to avoid CSR approval requirement."
elif [ "$safe_days" -lt 14 ]; then
    echo -e "${YELLOW}Safe shutdown period: Up to $safe_days days (with 2-day safety margin)${NC}"
    echo ""
    echo "Recommendation: Keep shutdown period under $safe_days days to avoid CSR approval requirement."
else
    echo -e "${GREEN}Safe shutdown period: Up to $safe_days days (with 2-day safety margin)${NC}"
    echo ""
    echo "Recommendation: Keep shutdown period under $safe_days days to avoid CSR approval requirement."
fi

echo ""
echo "NOTE: Kubelet certificates typically rotate every 30 days in OpenShift."
echo "      If certs expire during shutdown, manual CSR approval will be required on restart."
echo ""
echo "======================================================"
