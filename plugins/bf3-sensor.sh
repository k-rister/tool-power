#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# NVIDIA BlueField-3 Sensor Plugin
# Uses BF-3 sensor-based API for power metrics

# Plugin metadata
plugin_name="BF3 Sensor API"
plugin_description="NVIDIA BlueField-3 sensor-based power API"

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

    # Test BF-3 sensor endpoint (Card1 is the standard BF-3 chassis name)
    sensor_response=$(curl --connect-timeout 5 --max-time 10 -k -s -u "$username:$password" "https://$ip/redfish/v1/Chassis/Card1/Sensors" 2>&1)
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
# Args: $1=ip, $2=chassis_id, $3=username, $4=password, $5=interval
plugin_collect_endpoint() {
    local ip=$1
    local chassis_id=$2
    local username=$3
    local password=$4
    local interval=$5

    local power_file="power-${ip}.txt"

    # Define power sensors to collect
    local power_sensors=("power_envelope" "soc_power" "power_envelope_deviation")

    while true; do
        timestamp=$(date +%s.%N)
        date_str=$(date '+%Y-%m-%d %H:%M:%S')

        # Collect Power sensor data
        echo "" >> "$power_file"
        echo "TIMESTAMP: $timestamp" >> "$power_file"
        echo "DATE: $date_str" >> "$power_file"
        echo "ENDPOINT: $ip" >> "$power_file"
        echo "---" >> "$power_file"

        # Query power sensors
        for sensor in "${power_sensors[@]}"; do
            sensor_data=$(curl --connect-timeout 5 --max-time 10 -k -s -u "$username:$password" \
                "https://$ip/redfish/v1/Chassis/$chassis_id/Sensors/$sensor" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$sensor_data" ]; then
                # Parse sensor data
                sensor_name=$(echo "$sensor_data" | jq -r '.Name // .Id' 2>/dev/null)
                # Replace spaces with underscores for better parsing
                sensor_name="${sensor_name// /_}"
                reading=$(echo "$sensor_data" | jq -r '.Reading' 2>/dev/null)
                units=$(echo "$sensor_data" | jq -r '.ReadingUnits // ""' 2>/dev/null)
                status=$(echo "$sensor_data" | jq -r '.Status.Health // "Unknown"' 2>/dev/null)

                # Only output if we have a valid reading (not null)
                if [ "$reading" != "null" ] && [ -n "$reading" ]; then
                    echo "Power Sensor: $sensor_name" >> "$power_file"
                    echo "  Reading: $reading $units" >> "$power_file"
                    echo "  Status: $status" >> "$power_file"
                fi
            fi
        done

        sleep "$interval"
    done
}
