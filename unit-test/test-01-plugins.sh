#!/bin/bash
# Quick test of plugin architecture

echo "========================================="
echo "Plugin Architecture Test"
echo "========================================="
echo ""

# Test 1: List available plugins
echo "[Test 1] Testing plugin error handling..."
../power-collect 2 test test --plugin nonexistent 192.168.1.1 2>&1 | grep -A 5 "Available plugins"
echo ""

# Test 2: Load generic-redfish plugin
echo "[Test 2] Testing generic-redfish plugin loading..."
timeout 2 ./power-collect 2 test test --plugin generic-redfish 192.168.1.1 2>&1 | grep -E "Plugin loaded:|Loading plugin:" | head -5
echo ""

# Test 3: Load bf3-sensor plugin
echo "[Test 3] Testing bf3-sensor plugin loading..."
timeout 2 ./power-collect 2 test test --plugin bf3-sensor 192.168.1.1 2>&1 | grep -E "Plugin loaded:|Loading plugin:" | head -5
echo ""

# Test 4: Default plugin (no --plugin specified)
echo "[Test 4] Testing default plugin (should be generic-redfish)..."
timeout 2 ./power-collect 2 test test 192.168.1.1 2>&1 | grep -E "Plugin:|Plugin loaded:" | head -5
echo ""

echo "========================================="
echo "Plugin architecture tests complete!"
echo "========================================="
