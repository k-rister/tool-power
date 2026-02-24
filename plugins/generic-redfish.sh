#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# Generic Redfish Plugin
# Supports standard Redfish Power endpoints

# Plugin metadata
plugin_name="Generic Redfish"
plugin_description="Standard Redfish Power endpoints"

# Validate endpoint and return chassis ID
# Args: $1=ip, $2=username, $3=password
# Returns: chassis_id via stdout, exit code 0 on success
plugin_validate_endpoint() {
    local ip=$1
    local username=$2
    local password=$3

    # Test basic connectivity
    if ! curl --connect-timeout 5 --max-time 10 -k -s -u "$username:$password" "https://$ip/redfish/v1/" > /dev/null 2>&1; then
        echo "ERROR($LINENO): Cannot connect to Redfish endpoint at $ip" >&2
        return 1
    fi

    # Get chassis list (Redfish API uses "Chassis" terminology even for NICs/DPUs)
    chassis_response=$(curl --connect-timeout 5 --max-time 10 -k -s -u "$username:$password" "https://$ip/redfish/v1/Chassis" 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR($LINENO): Failed to query device from $ip" >&2
        return 1
    fi

    # Extract first chassis ID (internal Redfish identifier)
    chassis_id=$(echo "$chassis_response" | jq -r '.Members[0]."@odata.id"' 2>/dev/null | sed 's|.*/||')
    if [ -z "$chassis_id" ] || [ "$chassis_id" == "null" ]; then
        echo "ERROR($LINENO): Could not determine device identifier for $ip" >&2
        return 1
    fi

    # Validate Power endpoint
    if ! curl --connect-timeout 5 --max-time 10 -k -s -u "$username:$password" "https://$ip/redfish/v1/Chassis/$chassis_id/Power" > /dev/null 2>&1; then
        echo "ERROR($LINENO): Power endpoint not accessible for $ip" >&2
        return 1
    fi

    # Return chassis_id
    echo "$chassis_id"
    return 0
}

# Collect telemetry for a single endpoint
# Args: $1=ip, $2=chassis_id, $3=username, $4=password, $5=interval
plugin_collect_endpoint() {
    local ip=$1
    local chassis_id=$2
    local username=$3
    local password=$4
    local interval=$5

    local power_file="power-${ip}.txt"

    while true; do
        timestamp=$(date +%s.%N)
        date_str=$(date '+%Y-%m-%d %H:%M:%S')

        # Collect Power data
        power_data=$(curl --connect-timeout 5 --max-time 10 -k -s -u "$username:$password" "https://$ip/redfish/v1/Chassis/$chassis_id/Power" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$power_data" ]; then
            echo "" >> "$power_file"
            echo "TIMESTAMP: $timestamp" >> "$power_file"
            echo "DATE: $date_str" >> "$power_file"
            echo "ENDPOINT: $ip" >> "$power_file"
            echo "---" >> "$power_file"

            # Parse power consumption values
            echo "$power_data" | jq -r '
                .PowerControl[]? |
                "PowerControl: \(.Name // .MemberId // "Unknown")
  PowerConsumedWatts: \(.PowerConsumedWatts // "N/A")
  PowerCapacityWatts: \(.PowerCapacityWatts // "N/A")
  PowerLimit: \(.PowerLimit.LimitInWatts // "N/A")"
            ' >> "$power_file" 2>/dev/null
        fi

        sleep "$interval"
    done
}
