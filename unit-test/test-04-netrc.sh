#!/bin/bash
## -*- mode: bash; indent-tabs-mode: nil; perl-indent-level: 4 -*-
## vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=bash

# Test .netrc credential handling
# This test demonstrates how to use .netrc for secure credential storage
#
# NOTE: This tests power-collect's .netrc support directly (not in a container).
# For containerized deployment, you also need to mount .netrc via host-mounts.
# See README.md "Using .netrc (Recommended)" section for container setup.

echo "========================================="
echo "Testing .netrc credential handling"
echo "========================================="
echo ""

# Cleanup from previous runs
rm -rf generated
mkdir -p generated

# Generate SSL certificate for HTTPS
echo "Generating SSL certificate..."
if [ ! -f /tmp/mock-cert.pem ] || [ ! -f /tmp/mock-key.pem ]; then
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/mock-key.pem -out /tmp/mock-cert.pem -days 365 -nodes -subj "/CN=localhost" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✓ SSL certificate generated"
    else
        echo "✗ Failed to generate SSL certificate"
        exit 1
    fi
else
    echo "✓ Using existing SSL certificate"
fi

# Start mock servers
echo "Starting mock Redfish servers..."
python3 ./mock-redfish-server.py 8443 "Mock-Device-1" &
mock_server1_pid=$!
python3 ./mock-redfish-server.py 8444 "Mock-Device-2" &
mock_server2_pid=$!

# Wait for servers to start
sleep 2

if ps -p $mock_server1_pid > /dev/null && ps -p $mock_server2_pid > /dev/null; then
    echo "✓ Both mock servers running"
else
    echo "✗ Failed to start mock servers"
    kill $mock_server1_pid $mock_server2_pid 2>/dev/null
    exit 1
fi
echo ""

# Create temporary .netrc file for testing
NETRC_FILE="generated/.netrc"
echo "Creating test .netrc file: $NETRC_FILE"
cat > "$NETRC_FILE" << 'EOF'
machine 127.0.0.1
login admin
password password123
EOF

chmod 600 "$NETRC_FILE"
echo "✓ .netrc file created with correct permissions (600)"
echo ""

# Export HOME to use our test .netrc
export HOME="$(pwd)/generated"

echo "Testing power-collect with .netrc (no credentials on command line)..."
echo "Command: cd generated && ../../power-collect 2 \"\" \"\" 127.0.0.1:8443 127.0.0.1:8444"
echo ""
echo "----------------------------------------"

cd generated
../../power-collect 2 "" "" 127.0.0.1:8443 127.0.0.1:8444 &
power_collect_pid=$!
cd ..

echo "----------------------------------------"
echo ""

# Let it run for 10 seconds
echo "========================================"
echo "TEST: Collecting for 10 seconds..."
echo "      (Ctrl+C to force stop early)"
echo "========================================"
echo ""

sleep 10

# Stop power-collect
echo "Stopping power-collect..."
kill -TERM $power_collect_pid 2>/dev/null
sleep 2

# Check worker PIDs and kill them
if [ -f generated/power-collect-worker-pids.txt ]; then
    worker_pids=$(cat generated/power-collect-worker-pids.txt)
    for pid in $worker_pids; do
        kill -TERM $pid 2>/dev/null
    done
fi

# Stop mock servers
echo "Stopping mock servers..."
kill $mock_server1_pid $mock_server2_pid 2>/dev/null
wait $mock_server1_pid $mock_server2_pid 2>/dev/null

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo ""

# Validate CSV output
for csv_file in generated/power-*.csv; do
    if [ ! -f "$csv_file" ]; then
        echo "✗ No CSV files found"
        exit 1
    fi

    echo "--- Validating $(basename $csv_file) ---"

    # Check header
    header=$(head -n 1 "$csv_file")
    echo "Header: $header"

    # Count data rows (excluding header)
    data_rows=$(tail -n +2 "$csv_file" | wc -l)
    echo "Total samples collected: $data_rows"

    if [ $data_rows -lt 3 ]; then
        echo "✗ Expected at least 3 samples, got $data_rows"
        exit 1
    fi

    # Validate field count (should be 6 for generic-redfish)
    expected_fields=6
    field_count=$(head -n 2 "$csv_file" | tail -n 1 | awk -F',' '{print NF}')
    echo "CSV fields per row: $field_count"

    if [ "$field_count" -ne "$expected_fields" ]; then
        echo "✗ Expected $expected_fields fields, got $field_count"
        exit 1
    fi

    # Check all data rows have same field count
    invalid_rows=$(tail -n +2 "$csv_file" | awk -F',' -v expected=$expected_fields 'NF != expected {print}' | wc -l)
    if [ $invalid_rows -gt 0 ]; then
        echo "✗ Found $invalid_rows rows with incorrect field count"
        exit 1
    fi
    echo "✓ All data rows have correct field count"
    echo ""

    # Show sample data
    echo "First 3 data rows:"
    tail -n +2 "$csv_file" | head -n 3
    echo ""

    echo "Last 3 data rows:"
    tail -n 3 "$csv_file"
    echo ""
    echo "========================================="
    echo ""
done

echo "✓ Test completed successfully with .netrc authentication!"
echo ""
echo "Output files:"
ls -lh generated/power-*.csv
echo ""
echo "Key points demonstrated:"
echo "  1. Credentials stored securely in .netrc file"
echo "  2. No passwords visible on command line"
echo "  3. Empty username/password parameters trigger .netrc usage"
echo ""

# Cleanup
rm -f "$NETRC_FILE"
echo "Cleaning up..."
