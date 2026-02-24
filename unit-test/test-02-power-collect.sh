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
rm -f generated/power-127.0.0.1*.txt generated/thermal-127.0.0.1*.txt
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

# Show collected data
for file in generated/power-127.0.0.1*.txt generated/thermal-127.0.0.1*.txt; do
    if [ -f "$file" ]; then
        echo "--- $file ---"
        echo "Total samples collected: $(grep -c "^TIMESTAMP:" "$file")"
        echo ""
        echo "First sample:"
        head -30 "$file"
        echo ""
        echo "Last sample:"
        tail -25 "$file"
        echo ""
        echo "========================================="
        echo ""
    fi
done

echo "Test completed successfully!"
echo ""
echo "Output files:"
ls -lh generated/power-*.txt generated/thermal-*.txt 2>/dev/null
echo ""
echo "To view full output:"
echo "  cat generated/power-127.0.0.1:8443.txt"
echo "  cat generated/thermal-127.0.0.1:8443.txt"
echo "  cat generated/power-127.0.0.1:8444.txt"
echo "  cat generated/thermal-127.0.0.1:8444.txt"
