# Unit Tests for tool-power

Automated tests using mock Redfish servers to validate power-collect functionality without requiring real hardware.

## Overview

The test suite validates different layers of the tool:
- **test-01**: Plugin architecture (no servers, quick validation)
- **test-02**: Core collection engine (direct power-collect invocation)
- **test-03**: Rickshaw integration (wrapper scripts and lifecycle management)

**Why test-02 and test-03 both use mock servers:**
- test-02 validates the **core collection functionality** works correctly
- test-03 validates the **integration layer** (parameter parsing, background process management, compression)
- Both are needed: test-02 ensures collection works, test-03 ensures rickshaw can deploy it

**Output Format:**
All tests validate **CSV format** output:
- **generic-redfish plugin**: 6-field CSV (timestamp, date, endpoint, power_consumed_watts, power_capacity_watts, power_limit_watts)
- **bf3-sensor plugin**: 9-field CSV (timestamp, date, endpoint, power_envelope, power_envelope_status, soc_power, soc_power_status, power_envelope_deviation, power_envelope_deviation_status)
- Each file starts with a header row
- Each subsequent row contains one sample
- Files remain uncompressed as `.csv` for easy inspection

## Test Files

Tests are numbered to indicate recommended execution order:

### test-01-plugins.sh - Plugin Architecture Testing

Tests the plugin architecture and plugin loading (quickest test, no servers needed).

**What it does:**

This is a quick test that doesn't use mock servers - it just tests the plugin loading logic.

1. **Test 1 - Error Handling:**
   - Tries to load a non-existent plugin: `--plugin nonexistent`
   - Expected: power-collect should display error and list available plugins
   - Validates that error handling works

2. **Test 2 - generic-redfish Plugin:**
   - Runs: `power-collect --plugin generic-redfish 192.168.1.1`
   - Uses timeout (2s) since there's no real endpoint
   - Checks for "Plugin loaded:" or "Loading plugin:" messages
   - Validates that generic-redfish plugin can be explicitly loaded

3. **Test 3 - bf3-sensor Plugin:**
   - Runs: `power-collect --plugin bf3-sensor 192.168.1.1`
   - Same timeout approach
   - Validates that bf3-sensor plugin can be loaded

4. **Test 4 - Default Plugin:**
   - Runs power-collect WITHOUT `--plugin` argument
   - Checks what plugin gets loaded by default
   - Expected: Should default to generic-redfish

**What it validates:**
- Plugin discovery mechanism works
- Plugin error messages are helpful
- Both plugins (bf3-sensor and generic-redfish) can load
- Default plugin selection works

**Usage:**
```bash
cd unit-test
./test-01-plugins.sh
```

---

### test-02-power-collect.sh - Core Collection Testing

Tests the core power-collect script with two mock BMC endpoints.

**What it does:**

1. **Setup Phase:**
   - Creates `generated/` directory for output files
   - Generates a self-signed SSL certificate (`/tmp/mock-cert.pem`, `/tmp/mock-key.pem`) for HTTPS
   - Starts two Python mock Redfish servers on ports 8443 and 8444
   - Each mock server simulates a real BMC (like a BF-3 DPU) with Redfish API endpoints

2. **Test Execution:**
   - Runs `power-collect` with:
     - Interval: 2 seconds (collect metrics every 2s)
     - Credentials: admin/password123
     - Endpoints: 127.0.0.1:8443 and 127.0.0.1:8444
   - Lets it run for 15 seconds (should collect ~7-8 samples)

3. **Validation:**
   - Checks that CSV output files were created (`power-127.0.0.1:8443.csv`, etc.)
   - **CSV format validation:**
     - Verifies header row exists with correct field names
     - Counts data rows (excluding header)
     - Validates all rows have correct number of fields (6 for generic-redfish, 9 for bf3-sensor)
     - Shows sample data (first/last 3 rows)
   - Lists output files with sizes

4. **Cleanup:**
   - Kills power-collect process
   - Kills both mock servers
   - Cleanup trap ensures this happens even on Ctrl+C

**What it validates:**
- power-collect can connect to HTTPS endpoints
- Multi-endpoint collection works in parallel
- Data is written to correct output files
- Timestamp and data format is correct
- Automatic cleanup works

**Usage:**
```bash
cd unit-test
./test-02-power-collect.sh
```

**Output files:** Created in `generated/` subdirectory

---

### test-03-power-start.sh - Wrapper Script Testing

Tests the power-start wrapper script and parameter parsing.

**What it does:**

1. **Setup Phase:**
   - Generates SSL certificate
   - Starts two mock Redfish servers (same as test-power-collect.sh)

2. **Test Execution:**
   - Calls `power-start` (the rickshaw wrapper) with command-line arguments:
     ```bash
     --interval 2
     --username admin
     --password password123
     --endpoints 127.0.0.1:8443,127.0.0.1:8444
     ```
   - power-start should:
     - Parse these arguments
     - Launch power-collect in background
     - Save PID to `power-collect-pid.txt`
     - Redirect output to `power-start-stderrout.txt`

3. **Validation:**
   - Checks power-start exit code (success/failure)
   - Displays contents of `power-start-stderrout.txt` (shows power-collect output)
   - Lets it collect for 10 seconds
   - Calls `power-stop` to stop collection
   - **CSV format validation:**
     - Verifies header row exists with correct field names
     - Counts data rows (excluding header)
     - Validates all rows have correct number of fields
     - Shows sample data (first/last 3 rows)
   - Shows output files (`.csv`)

4. **Cleanup:**
   - Kills mock servers

**What it validates:**
- power-start correctly parses `--interval`, `--username`, `--password`, `--endpoints`, `--plugin`
- power-start launches power-collect in background
- power-collect PID is saved correctly
- power-stop can find and kill the process
- Output compression works (xz)

**Usage:**
```bash
cd unit-test
./test-03-power-start.sh
```

#### Key Differences: test-02 vs test-03

| Aspect | test-02-power-collect.sh | test-03-power-start.sh |
|--------|--------------------------|------------------------|
| **Tests** | `power-collect` (core script) | `power-start` → `power-stop` (wrappers) |
| **Arguments** | Positional: `power-collect INTERVAL USER PASS IP1 IP2` | Long options: `--interval N --username U --password P --endpoints IP1,IP2` |
| **Process management** | Test script manages process directly | power-start/power-stop manage background process |
| **Output** | Raw .csv files | Raw .csv files |
| **What's validated** | Collection functionality works | Parameter parsing, start/stop lifecycle, compression |
| **Why needed** | Ensures core engine works | Ensures rickshaw integration works |

---

### test-04-netrc.sh - .netrc Credential Testing

Tests secure credential storage using .netrc file instead of command-line parameters.

**What it does:**

1. **Setup Phase:**
   - Generates SSL certificate
   - Starts two mock Redfish servers (same as test-02)
   - Creates a temporary `.netrc` file with credentials

2. **Test Execution:**
   - Calls `power-collect` with **empty username and password** parameters
   - power-collect should automatically use credentials from `.netrc` file
   - Collects data for 10 seconds

3. **Validation:**
   - Verifies "Credential source: .netrc file" message appears
   - Validates CSV output (same as other tests)
   - Confirms no credentials visible in process command line

4. **Cleanup:**
   - Removes temporary `.netrc` file
   - Kills mock servers

**What it validates:**
- `.netrc` credential loading works correctly
- Empty credentials trigger `.netrc` usage
- No passwords exposed in process list
- Backward compatibility (other tests still use explicit credentials)

**Usage:**
```bash
cd unit-test
./test-04-netrc.sh
```

**Key Security Benefit:**
Demonstrates how to avoid password exposure in process lists and logs.

**Important Note:**
This test runs power-collect directly on the host (not in a container), so it doesn't require host-mounts. For production deployments where power-collect runs in a container, you must also configure host-mounts to mount the .netrc file into the container. See the main README.md for container deployment instructions.

---

### local_test - Manual Hardware Testing Tool

A standalone diagnostic tool for testing connectivity and data collection from **real BMC hardware** (not mock servers).

**What it does:**

1. **Connectivity Testing:**
   - Tests basic HTTPS connection to BMC endpoint
   - Validates credentials
   - Checks network reachability

2. **API Discovery:**
   - Queries Redfish service root
   - Discovers available chassis
   - Tests both API structures:
     - Standard Redfish Power/Thermal endpoints (`/Chassis/{id}/Power`, `/Chassis/{id}/Thermal`)
     - BF-3 sensor-based API (`/Chassis/Card1/Sensors/`)

3. **Data Collection:**
   - Collects actual power metrics (watts, voltage, PSU status)
   - Collects thermal metrics (temperature, fan RPM)
   - Displays BF-3 sensor readings (power_envelope, soc_power, etc.)

4. **Plugin Recommendation:**
   - Analyzes which API structure the BMC uses
   - Recommends which plugin to use (generic-redfish vs bf3-sensor)

**What it validates:**
- BMC is reachable and Redfish service is running
- Credentials are correct
- Which Redfish API structure is supported
- What power/thermal data is available
- Which plugin should be used with this BMC

**Usage:**
```bash
cd unit-test
./local_test <ip_address> <username> <password>

# Example:
./local_test 192.168.1.10 admin mypassword
```

**Example output:**
```
=========================================
Redfish Power Collection Test
=========================================
Target IP: 192.168.1.10
Username: admin
Password: <redacted>

[1/5] Testing basic Redfish connectivity...
  ✓ Connection successful

[2/5] Querying Redfish service root...
  Service: BMC Redfish Service
  Redfish Version: 1.6.0

[3/5] Querying chassis list...
  Found 1 chassis
  Using Chassis ID: Card1

[4/7] Testing Standard Redfish Power endpoint...
  URL: https://192.168.1.10/redfish/v1/Chassis/Card1/Power
  ✗ Power endpoint not accessible

[5/7] Testing BF-3 Sensor-based API...
  URL: https://192.168.1.10/redfish/v1/Chassis/Card1/Sensors
  ✓ Sensor endpoint accessible - Found 47 sensors

[6/7] Collecting Power/Sensor data...
========================================

BF-3 SENSOR-BASED API DATA
--- Power Consumption ---
Sensor: power_envelope
  Type: Power
  Reading: 145.2 W

Sensor: soc_power
  Type: Power
  Reading: 89.3 W

[7/7] Recommendation
========================================
✓ This BMC supports BF-3 Sensor-based API
  Recommended plugin: bf3-sensor
```

**Use cases:**
- Testing connection to a new BMC before deploying tool-power
- Determining which plugin to use for a specific BMC model
- Debugging connection issues with real hardware
- Validating credentials before a test run
- Exploring what power/thermal data a BMC provides

**Requirements:**
- Real BMC hardware with Redfish support
- Network access to BMC management interface
- Valid BMC credentials
- `curl` and `jq` installed

---

## Mock Redfish Server

### mock-redfish-server.py - Mock BMC Simulator

Simulates a real Redfish BMC (like NVIDIA BF-3) with HTTPS endpoints.

**What it does:**
- Simulates a Redfish-compliant BMC with HTTPS support
- Responds to Redfish API queries with realistic JSON data
- Generates random power/thermal values that change on each request
- Requires HTTP Basic authentication (checks for Authorization header)

**Endpoints it simulates:**
- `/redfish/v1/` - Root service
- `/redfish/v1/Chassis` - Chassis collection
- `/redfish/v1/Chassis/Chassis1` - Chassis details
- `/redfish/v1/Chassis/Chassis1/Power` - Power metrics (watts, voltage, PSU status)
- `/redfish/v1/Chassis/Chassis1/Thermal` - Thermal metrics (temperature, fan RPM)

**Sample data returned:**

Power metrics:
```json
{
  "PowerControl": [
    {
      "Name": "System Power Control",
      "PowerConsumedWatts": 145.2,
      "PowerCapacityWatts": 400,
      "PowerLimit": {"LimitInWatts": 350}
    }
  ],
  "Voltages": [
    {"Name": "12V", "ReadingVolts": 11.9, "Status": {"State": "Enabled"}},
    {"Name": "5V", "ReadingVolts": 5.06, "Status": {"State": "Enabled"}}
  ],
  "PowerSupplies": [
    {
      "Name": "PSU1",
      "PowerOutputWatts": 72.6,
      "PowerCapacityWatts": 750,
      "Status": {"State": "Enabled"}
    }
  ]
}
```

Thermal metrics:
```json
{
  "Temperatures": [
    {"Name": "Ambient Temp", "ReadingCelsius": 25.5, "UpperThresholdCritical": 45.0},
    {"Name": "CPU Temp", "ReadingCelsius": 68.3, "UpperThresholdCritical": 95.0},
    {"Name": "Memory Temp", "ReadingCelsius": 45.3, "UpperThresholdCritical": 85.0}
  ],
  "Fans": [
    {"Name": "Fan1", "Reading": 3200, "ReadingUnits": "RPM"},
    {"Name": "Fan2", "Reading": 3450, "ReadingUnits": "RPM"}
  ]
}
```

**Why it's useful:**
- No need for real hardware during development
- Consistent, reproducible test environment
- Can run on any system without special setup
- Allows testing error conditions and edge cases

**Manual usage:**
```bash
# Start server on port 8443
python3 mock-redfish-server.py 8443 "Device-1"

# Test with curl
curl -k -u admin:password123 https://127.0.0.1:8443/redfish/v1/Chassis/Chassis1/Power
```

---

## Output Directory

All test output files are created in `unit-test/generated/` and are excluded from git via `.gitignore`.

**Generated files:**
- `power-127.0.0.1:8443.txt` - Power metrics from first endpoint
- `power-127.0.0.1:8444.txt` - Power metrics from second endpoint
- `thermal-127.0.0.1:8443.txt` - Thermal metrics from first endpoint
- `thermal-127.0.0.1:8444.txt` - Thermal metrics from second endpoint
- `power-collect-worker-pids.txt` - PIDs of collection threads

---

## Requirements

- Python 3.6+
- OpenSSL (for generating test certificates)
- Bash 4.0+

## Troubleshooting

**"Address already in use" error:**
```bash
# Kill any leftover mock servers
pkill -f mock-redfish-server.py
```

**SSL certificate errors:**
The tests use self-signed certificates, which is expected. Power-collect uses `-k` (insecure) mode with curl to accept self-signed certs.

**No output files:**
Check that `generated/` directory was created and power-collect has write permissions.
