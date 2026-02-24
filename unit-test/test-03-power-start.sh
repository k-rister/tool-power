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
rm -f power-start-stderrout.txt power-collect-pid.txt power-*.csv thermal-*.csv

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

    echo "========================================="
    echo "Validating CSV Output"
    echo "========================================="
    echo ""

    # Validate CSV files
    validation_passed=true

    for file in power-127.0.0.1*.csv; do
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
        echo "✓ CSV validation passed!"
    else
        echo "✗ CSV validation failed"
    fi

    echo ""
    echo "Generated files:"
    ls -lh power-*.csv 2>/dev/null
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
