#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# NVIDIA BlueField-3 Sensor Plugin
# Uses BF-3 sensor-based API for power metrics

# Plugin metadata
plugin_name="BF3 Sensor API"
plugin_description="NVIDIA BlueField-3 sensor-based power API"

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

    # Test BF-3 sensor endpoint (Card1 is the standard BF-3 chassis name)
    sensor_response=$(curl --connect-timeout 5 --max-time 10 -k -s $auth_flags "https://$ip/redfish/v1/Chassis/Card1/Sensors" 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR($LINENO): Cannot query BF-3 sensor endpoint at $ip" >&2
        return 1
    fi

    # Verify we got a valid sensor collection
    sensor_count=$(echo "$sensor_response" | jq -r '.Members | length' 2>/dev/null)
    if [ -z "$sensor_count" ] || [ "$sensor_count" == "null" ] || [ "$sensor_count" -eq 0 ]; then
        echo "ERROR($LINENO): No sensors found on BF-3 device at $ip" >&2
        return 1
    fi

    # BF-3 uses "Card1" as chassis ID
    echo "Card1"
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
        echo "timestamp,date,endpoint,power_envelope,power_envelope_status,soc_power,soc_power_status,power_envelope_deviation,power_envelope_deviation_status" > "$power_file"
    fi

    # Define power sensors to collect
    local power_sensors=("power_envelope" "soc_power" "power_envelope_deviation")

    while true; do
        timestamp=$(date +%s.%N)
        date_str=$(date '+%Y-%m-%d %H:%M:%S')

        # Initialize CSV fields
        declare -A readings
        declare -A statuses

        # Query power sensors
        for sensor in "${power_sensors[@]}"; do
            sensor_data=$(curl --connect-timeout 5 --max-time 10 -k -s $auth_flags \
                "https://$ip/redfish/v1/Chassis/$chassis_id/Sensors/$sensor" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$sensor_data" ]; then
                reading=$(echo "$sensor_data" | jq -r '.Reading' 2>/dev/null)
                status=$(echo "$sensor_data" | jq -r '.Status.Health // "Unknown"' 2>/dev/null)

                # Store values (use N/A if null)
                if [ "$reading" != "null" ] && [ -n "$reading" ]; then
                    readings[$sensor]=$reading
                    statuses[$sensor]=$status
                else
                    readings[$sensor]="N/A"
                    statuses[$sensor]="N/A"
                fi
            else
                readings[$sensor]="N/A"
                statuses[$sensor]="N/A"
            fi
        done

        # Write CSV row
        echo "$timestamp,$date_str,$ip,${readings[power_envelope]},${statuses[power_envelope]},${readings[soc_power]},${statuses[soc_power]},${readings[power_envelope_deviation]},${statuses[power_envelope_deviation]}" >> "$power_file"

        sleep "$interval"
    done
}
