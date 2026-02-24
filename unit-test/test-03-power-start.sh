#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# Test script to demonstrate power-start with parameters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Testing power-start parameter passing"
echo "========================================="
echo ""

# Create output directory
mkdir -p generated
cd generated

# Clean up previous test files
rm -f power-start-stderrout.txt power-collect-pid.txt power-*.txt thermal-*.txt

# Create symlinks to power-collect and plugins (from generated/ directory)
ln -sf ../../power-collect ./power-collect
ln -sf ../../plugins ./plugins

# Start mock servers
echo "Generating SSL certificate..."
openssl req -x509 -newkey rsa:2048 -keyout /tmp/mock-key.pem -out /tmp/mock-cert.pem \
    -days 1 -nodes -subj "/CN=localhost" 2>/dev/null

echo "Starting mock Redfish servers..."
python3 ../mock-redfish-server.py 8443 "Device-1" &
MOCK_PID1=$!

python3 ../mock-redfish-server.py 8444 "Device-2" &
MOCK_PID2=$!

sleep 2
echo ""

# Test power-start
echo "Testing power-start with parameters:"
echo "  --interval 2"
echo "  --username admin"
echo "  --password password123"
echo "  --endpoints 127.0.0.1:8443,127.0.0.1:8444"
echo ""

../../power-start --interval 2 --username admin --password password123 --endpoints 127.0.0.1:8443,127.0.0.1:8444

if [ $? -eq 0 ]; then
    echo ""
    echo "power-start launched successfully!"
    echo ""
    echo "Contents of power-start-stderrout.txt:"
    echo "----------------------------------------"
    cat power-start-stderrout.txt
    echo "----------------------------------------"
    echo ""

    # Let it collect for 10 seconds
    echo ""
    echo "========================================"
    echo "TEST: Collecting for 10 seconds..."
    echo "      (Ctrl+C to force stop early)"
    echo "========================================"
    echo ""
    sleep 10

    # Stop collection
    echo ""
    echo "Stopping collection..."
    ../../power-stop

    # Show results
    echo ""
    echo "Stop output:"
    echo "----------------------------------------"
    cat power-stop-stderrout.txt
    echo "----------------------------------------"
    echo ""

    echo "Generated files:"
    ls -lh power-*.txt* thermal-*.txt* 2>/dev/null
else
    echo "ERROR: power-start failed!"
fi

# Cleanup
echo ""
echo "Cleaning up mock servers..."
kill $MOCK_PID1 $MOCK_PID2 2>/dev/null
wait $MOCK_PID1 $MOCK_PID2 2>/dev/null

# Remove symlinks
rm -f power-collect plugins

echo ""
echo "Test complete!"
