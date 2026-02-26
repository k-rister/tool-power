#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# Test script for power-collect with mock Redfish servers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    pkill -f "mock-redfish-server.py.*:8443" 2>/dev/null
    pkill -f "mock-redfish-server.py.*:8444" 2>/dev/null
    pkill -f "power-collect.*127.0.0.1" 2>/dev/null
}

# Set trap to cleanup on exit or interrupt
trap cleanup EXIT INT TERM

echo "========================================="
echo "Power-Collect Test with Mock Devices"
echo "========================================="
echo ""

# Create output directory
mkdir -p generated

# Clean up any previous test files
echo "Cleaning up previous test files..."
rm -f generated/power-127.0.0.1*.csv generated/thermal-127.0.0.1*.csv
rm -f /tmp/mock-*.pem

# Generate self-signed certificate for mock servers
echo "Generating self-signed SSL certificate..."
openssl req -x509 -newkey rsa:2048 -keyout /tmp/mock-key.pem -out /tmp/mock-cert.pem \
    -days 1 -nodes -subj "/CN=localhost" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to generate SSL certificate"
    exit 1
fi

echo "✓ SSL certificate generated"
echo ""

# Start mock Redfish servers
echo "Starting mock Redfish servers..."

python3 ./mock-redfish-server.py 8443 "Device-1" &
MOCK_PID1=$!
echo "  Mock server 1 started (PID: $MOCK_PID1, port 8443)"

python3 ./mock-redfish-server.py 8444 "Device-2" &
MOCK_PID2=$!
echo "  Mock server 2 started (PID: $MOCK_PID2, port 8444)"

# Give servers time to start
sleep 2
echo ""

# Verify servers are running
if ! ps -p $MOCK_PID1 > /dev/null 2>&1; then
    echo "ERROR: Mock server 1 failed to start"
    kill $MOCK_PID2 2>/dev/null
    exit 1
fi

if ! ps -p $MOCK_PID2 > /dev/null 2>&1; then
    echo "ERROR: Mock server 2 failed to start"
    kill $MOCK_PID1 2>/dev/null
    exit 1
fi

echo "✓ Both mock servers running"
echo ""

# Run power-collect
echo "Starting power-collect (will run for 15 seconds)..."
echo "Command: cd generated && ../../power-collect 2 admin password123 127.0.0.1:8443 127.0.0.1:8444"
echo ""
echo "----------------------------------------"

(cd generated && ../../power-collect 2 admin password123 127.0.0.1:8443 127.0.0.1:8444) &
COLLECT_PID=$!

# Give power-collect time to print startup messages
sleep 2

# Let it collect data for 15 seconds
echo ""
echo "========================================"
echo "TEST: Collecting for 15 seconds..."
echo "      (Ctrl+C to force stop early)"
echo "========================================"
echo ""
sleep 13

# Stop power-collect
echo ""
echo "----------------------------------------"
echo ""
echo "Stopping power-collect..."
kill $COLLECT_PID 2>/dev/null
wait $COLLECT_PID 2>/dev/null

# Stop mock servers
echo "Stopping mock servers..."
kill $MOCK_PID1 $MOCK_PID2 2>/dev/null
wait $MOCK_PID1 $MOCK_PID2 2>/dev/null

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo ""

# Validate CSV files
validation_passed=true

for file in generated/power-127.0.0.1*.csv; do
    if [ -f "$file" ]; then
        echo "--- Validating $file ---"

        # Check if file has content
        if [ ! -s "$file" ]; then
            echo "ERROR: File is empty"
            validation_passed=false
            continue
        fi

        # Read header
        header=$(head -1 "$file")
        echo "Header: $header"

        # Validate header format
        if [[ "$header" != timestamp,date,endpoint,* ]]; then
            echo "ERROR: Invalid CSV header format"
            validation_passed=false
            continue
        fi

        # Count total lines (header + data rows)
        total_lines=$(wc -l < "$file")
        data_rows=$((total_lines - 1))

        if [ $data_rows -lt 1 ]; then
            echo "ERROR: No data rows found"
            validation_passed=false
            continue
        fi

        echo "Total samples collected: $data_rows"

        # Count fields in header
        header_fields=$(echo "$header" | tr ',' '\n' | wc -l)
        echo "CSV fields per row: $header_fields"

        # Validate all data rows have correct number of fields
        invalid_rows=0
        line_num=2  # Start after header
        while IFS= read -r line; do
            field_count=$(echo "$line" | tr ',' '\n' | wc -l)
            if [ $field_count -ne $header_fields ]; then
                echo "WARNING: Line $line_num has $field_count fields (expected $header_fields)"
                invalid_rows=$((invalid_rows + 1))
            fi
            line_num=$((line_num + 1))
        done < <(tail -n +2 "$file")

        if [ $invalid_rows -gt 0 ]; then
            echo "ERROR: Found $invalid_rows rows with incorrect field count"
            validation_passed=false
        else
            echo "✓ All data rows have correct field count"
        fi

        echo ""
        echo "First 3 data rows:"
        head -4 "$file" | tail -3
        echo ""
        echo "Last 3 data rows:"
        tail -3 "$file"
        echo ""
        echo "========================================="
        echo ""
    fi
done

if [ "$validation_passed" = true ]; then
    echo "✓ Test completed successfully!"
else
    echo "✗ Test completed with validation errors"
fi

echo ""
echo "Output files:"
ls -lh generated/power-*.csv 2>/dev/null
echo ""
echo "To view full output:"
echo "  cat generated/power-127.0.0.1:8443.csv"
echo "  cat generated/power-127.0.0.1:8444.csv"
