#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# Generic Redfish Plugin
# Supports standard Redfish Power endpoints

# Plugin metadata
plugin_name="Generic Redfish"
plugin_description="Standard Redfish Power endpoints"

# Validate endpoint and return chassis ID
# Args: $1=ip
# Returns: chassis_id via stdout, exit code 0 on success
# Uses get_curl_auth_flags() for authentication (either .netrc or explicit credentials)
plugin_validate_endpoint() {
    local ip=$1
    local auth_flags=$(get_curl_auth_flags)

    # Test basic connectivity
    if ! curl --connect-timeout 5 --max-time 10 -k -s $auth_flags "https://$ip/redfish/v1/" > /dev/null 2>&1; then
        echo "ERROR($LINENO): Cannot connect to Redfish endpoint at $ip" >&2
        return 1
    fi

    # Get chassis list (Redfish API uses "Chassis" terminology even for NICs/DPUs)
    chassis_response=$(curl --connect-timeout 5 --max-time 10 -k -s $auth_flags "https://$ip/redfish/v1/Chassis" 2>&1)
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
    if ! curl --connect-timeout 5 --max-time 10 -k -s $auth_flags "https://$ip/redfish/v1/Chassis/$chassis_id/Power" > /dev/null 2>&1; then
        echo "ERROR($LINENO): Power endpoint not accessible for $ip" >&2
        return 1
    fi

    # Return chassis_id
    echo "$chassis_id"
    return 0
}

# Collect telemetry for a single endpoint
# Args: $1=ip, $2=chassis_id, $3=interval
# Uses get_curl_auth_flags() for authentication (either .netrc or explicit credentials)
plugin_collect_endpoint() {
    local ip=$1
    local chassis_id=$2
    local interval=$3
    local auth_flags=$(get_curl_auth_flags)

    local power_file="power-${ip}.csv"

    # Write CSV header on first run
    if [ ! -f "$power_file" ]; then
        echo "timestamp,date,endpoint,power_consumed_watts,power_capacity_watts,power_limit_watts" > "$power_file"
    fi

    while true; do
        timestamp=$(date +%s.%N)
        date_str=$(date '+%Y-%m-%d %H:%M:%S')

        # Collect Power data
        power_data=$(curl --connect-timeout 5 --max-time 10 -k -s $auth_flags "https://$ip/redfish/v1/Chassis/$chassis_id/Power" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$power_data" ]; then
            # Parse power consumption values
            power_consumed=$(echo "$power_data" | jq -r '.PowerControl[0].PowerConsumedWatts // "N/A"' 2>/dev/null)
            power_capacity=$(echo "$power_data" | jq -r '.PowerControl[0].PowerCapacityWatts // "N/A"' 2>/dev/null)
            power_limit=$(echo "$power_data" | jq -r '.PowerControl[0].PowerLimit.LimitInWatts // "N/A"' 2>/dev/null)

            # Write CSV row
            echo "$timestamp,$date_str,$ip,$power_consumed,$power_capacity,$power_limit" >> "$power_file"
        fi

        sleep "$interval"
    done
}
