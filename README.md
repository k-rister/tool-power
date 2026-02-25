# tool-power

Power and thermal telemetry collection tool for Redfish-enabled devices, specifically NVIDIA BlueField-3 DPU BMCs.

## Purpose

Collects power consumption and thermal sensor data from BF-3 BMC endpoints via Redfish API for performance analysis and monitoring.

## Features

- ✅ Multi-threaded collection from multiple endpoints
- ✅ Plugin architecture for different Redfish implementations
- ✅ BF-3 sensor-based API collection via bf3-sensor plugin
- ✅ Generic Redfish Power/Thermal endpoints via generic-redfish plugin
- ✅ Parameter handling (interval, credentials, endpoint list, plugin selection)
- ✅ Timeout handling (5s connect, 10s max)
- ✅ Profiler-only deployment via rickshaw
- ✅ Opt-in/opt-out deployment modes
- ✅ Output compression with xz
- ✅ Mock server testing framework

## Usage

**REQUIRED: Use opt-in deployment to prevent duplicate collection**

Each BMC endpoint must be assigned to exactly ONE tool-power instance. Multiple instances collecting the same endpoints will produce duplicate/aggregated metrics.

### Credential Management

**Recommended: Use `.netrc` for secure credential storage**

Credentials can be provided in two ways:

1. **`.netrc` file (recommended)** - More secure, credentials not visible in process list
2. **Command-line parameters** - Backward compatible but less secure

#### Using .netrc (Recommended)

**Step 1: Create `.netrc` file on the host**

Create a `.netrc` file in the home directory of the user running tool-power (typically `/root/.netrc`):

```bash
# ~/.netrc (chmod 600)
# Note: machine entries use only IP/hostname, no port numbers
machine 192.168.1.10
login admin
password secret123

machine 192.168.1.11
login admin
password secret456
```

Set proper permissions:
```bash
chmod 600 ~/.netrc
```

**Step 2: Create `hostmount.json` file**

Since tool-power runs in a container, you need to mount the `.netrc` file into the container. Create a `hostmount.json` file:

```json
[
  {
    "src": "/root/.netrc",
    "dest": "/root/.netrc"
  }
]
```

**Step 3: Configure rickshaw with host-mounts**

Full rickshaw configuration with `.netrc` and host-mounts:

```json
{
  "endpoints": [
    {
      "type": "remotehosts",
      "remotes": [{
        "engines": [{ "role": "profiler" }],
        "config": {
          "host": "your-profiler-host.example.com",
          "settings": {
            "tool-opt-in-tags": ["power-monitoring"],
            "host-mounts": [
              {
                "src": "/root/.netrc",
                "dest": "/root/.netrc"
              }
            ]
          }
        }
      }]
    }
  ],
  "tool-params": [
    {
      "tool": "power",
      "deployment": "opt-in",
      "opt-tag": "power-monitoring",
      "params": [
        {
          "arg": "interval",
          "val": "2"
        },
        {
          "arg": "endpoints",
          "val": "192.168.1.10,192.168.1.11"
        },
        {
          "arg": "plugin",
          "val": "bf3-sensor"
        }
      ]
    }
  ]
}
```

**Note:** `username` and `password` parameters are **omitted** - when they're not provided, tool-power automatically uses `.netrc`.

**Using with Regulus or other run.sh scripts:**

If you're using command-line endpoint specification (e.g., with `reg-c2j-api.py`), reference the `hostmount.json` file:

```bash
# In your run.sh
endpoint_opt+=" --endpoint remotehosts,user:root,host:$host,profiler:1,userenv:fedora-latest,tool-opt-in-tags:[power-monitoring],host-mounts:/path/to/hostmount.json"
```

The `host-mounts` parameter should point to the `hostmount.json` file path.

#### Using Command-line Parameters (Backward Compatible)

```json
{
  "tool-params": [
    {
      "tool": "power",
      "deployment": "opt-in",
      "opt-tag": "power-monitoring",
      "params": [
        {
          "arg": "interval",
          "val": "2"
        },
        {
          "arg": "username",
          "val": "admin"
        },
        {
          "arg": "password",
          "val": "your-password"
        },
        {
          "arg": "endpoints",
          "val": "192.168.1.10,192.168.1.11"
        },
        {
          "arg": "plugin",
          "val": "bf3-sensor"
        }
      ]
    }
  ]
}
```

### Rickshaw Configuration Example

Full configuration with opt-in deployment:

```json
{
  "endpoints": [
    {
      "type": "remotehosts",
      "remotes": [{
        "engines": [{ "role": "profiler" }],
        "config": {
          "settings": {
            "tool-opt-in-tags": ["power-monitoring"]
          }
        }
      }]
    }
  ],
  "tool-params": [
    {
      "tool": "power",
      "deployment": "opt-in",
      "opt-tag": "power-monitoring",
      "params": [
        {
          "arg": "interval",
          "val": "2"
        },
        {
          "arg": "username",
          "val": ""
        },
        {
          "arg": "password",
          "val": ""
        },
        {
          "arg": "endpoints",
          "val": "192.168.1.10,192.168.1.11"
        },
        {
          "arg": "plugin",
          "val": "bf3-sensor"
        }
      ]
    }
  ]
}
```

### Plugin Selection

Specify which Redfish implementation to use:

**In rickshaw configuration:**
```json
{
  "arg": "plugin",
  "val": "bf3-sensor"
}
```

Available plugins:
- `bf3-sensor` - NVIDIA BlueField-3 DPU BMCs (sensor-based API)
- `generic-redfish` - Generic Redfish-compliant devices (Power/Thermal endpoints)

## Scripts

Name | Description
-----|------------
power-collect | Multi-threaded Redfish telemetry collector. Validates endpoints, then spawns parallel collection threads for power and thermal data.
power-start | Rickshaw start wrapper. Parses command-line arguments (--interval, --username, --password, --endpoints, --plugin) and launches power-collect in background.
power-stop | Stops power-collect process via saved PID and compresses output files with xz.
power-post-process | (TODO) Post-processing script for generating metrics and preparing data for OpenSearch indexing.

## Output

### CSV Format

Power metrics are written in CSV format for efficient storage and easy processing:

**File naming:**
- `power-<ip>.csv` - Power metrics per endpoint

**Generic Redfish CSV format** (6 fields):
```csv
timestamp,date,endpoint,power_consumed_watts,power_capacity_watts,power_limit_watts
1708534821.234567,2024-02-21 15:20:21,192.168.1.10,150.5,200.0,180.0
```

**BF-3 Sensor CSV format** (9 fields):
```csv
timestamp,date,endpoint,power_envelope,power_envelope_status,soc_power,soc_power_status,power_envelope_deviation,power_envelope_deviation_status
1708534821.234567,2024-02-21 15:20:21,192.168.1.10,45.2,OK,42.8,OK,2.4,OK
```

**Field descriptions:**
- `timestamp` - Unix timestamp with nanosecond precision
- `date` - Human-readable date/time (YYYY-MM-DD HH:MM:SS)
- `endpoint` - IP address of the BMC
- Power values vary by plugin (see Plugin Architecture section)
- Status values: OK, Warning, Critical, or N/A

**Note on compression:**
CSV files are left uncompressed for easy inspection and processing. The CSV format itself already provides ~70-75% size reduction compared to the previous verbose text format.

## Plugin Architecture

The tool supports **multiple Redfish implementations** via a plugin system:

### Available Plugins

#### 1. **bf3-sensor** (BF-3 Sensor API)
- **File**: `plugins/bf3-sensor.sh`
- **Target**: NVIDIA BlueField-3 DPU BMCs
- **API**: `/redfish/v1/Chassis/Card1/Sensors/`
- **Sensors**: `power_envelope`, `soc_power`, `power_envelope_deviation`
- **Status**: ✅ Implemented
- **CSV Fields**:
  - `power_envelope` - Total power envelope (watts)
  - `power_envelope_status` - Health status (OK/Warning/Critical)
  - `soc_power` - SoC power consumption (watts)
  - `soc_power_status` - Health status
  - `power_envelope_deviation` - Deviation from power limit (watts)
  - `power_envelope_deviation_status` - Health status

#### 2. **generic-redfish** (Standard Redfish)
- **File**: `plugins/generic-redfish.sh`
- **Target**: Generic Redfish-compliant devices
- **API**: `/redfish/v1/Chassis/{ChassisId}/Power`
- **Status**: ✅ Implemented
- **CSV Fields**:
  - `power_consumed_watts` - Current power consumption (watts)
  - `power_capacity_watts` - Maximum power capacity (watts)
  - `power_limit_watts` - Configured power limit (watts)

### Plugin Interface

Each plugin must implement:
- `plugin_validate_endpoint()` - Validate endpoint and return chassis ID
- `plugin_collect_endpoint()` - Collect telemetry data

See `plugins/bf3-sensor.sh` for reference implementation.

## Deployment

The tool is configured for **profiler-only deployment** via rickshaw.json:

```json
{
  "collector": {
    "whitelist": [
      {
        "endpoint": "remotehosts",
        "collector-types": [ "profiler" ]
      }
    ]
  }
}
```

### Why Profiler-Only?

The profiler node has network access to the BMC management network, while cluster nodes (clients/servers/masters/workers) typically don't. Power metrics are collected from BMC Redfish endpoints, so the tool must run where it can reach those endpoints.

## Source of Truth

### NVIDIA BlueField BMC Documentation

The implementation is based on NVIDIA's official BlueField BMC documentation:

- **Primary Reference**: [BMC Sensor Data - NVIDIA BlueField BMC v23.10](https://docs.nvidia.com/networking/display/bluefieldbmcv2310/bmc+sensor+data)
- **BlueField Management**: https://docs.nvidia.com/networking/display/bluefieldbmcv2501/bluefield+management
- **BMC Software Overview**: https://docs.nvidia.com/networking/display/bluefieldbmcv2404/bluefield+bmc+software+overview

### BF-3 BMC Redfish API Structure

**IMPORTANT**: BlueField-3 BMCs use a **sensor-based** Redfish API structure, different from standard Redfish Power/Thermal endpoints.

#### Actual BF-3 Redfish Endpoints

```bash
# Base sensor endpoint
/redfish/v1/Chassis/Card1/Sensors/

# Individual sensors
/redfish/v1/Chassis/Card1/Sensors/<sensor_name>
```

#### Available Sensors

**Temperature Sensors:**
- `bluefield_temp` - BlueField SoC temperature
- `p0_temp` - Port 0 temperature
- `p1_temp` - Port 1 temperature

**Voltage Sensors:**
- `1V_BMC` - BMC 1V rail
- `12V_ATX` - 12V ATX power
- `3_3V` - 3.3V rail
- `DVDD` - Digital voltage
- `VDD` - Core voltage
- And others...

**Link Status:**
- `p0_link` - Port 0 link state
- `p1_link` - Port 1 link state

#### Sensor Data Format

```json
{
  "Reading": 43.0,
  "ReadingType": "Temperature",
  "ReadingUnits": "Cel",
  "Thresholds": {
    "UpperCritical": { "Reading": 105.0 },
    "UpperCaution": { "Reading": 95.0 }
  }
}
```

#### Example Queries

**List all sensors:**
```bash
curl -k -u root:'<password>' -X GET \
  https://<bmc_ip>/redfish/v1/Chassis/Card1/Sensors
```

**Get specific sensor:**
```bash
curl -k -u root:'<password>' -X GET \
  https://<bmc_ip>/redfish/v1/Chassis/Card1/Sensors/bluefield_temp
```

## Security Considerations

**Recommended**: Use `.netrc` file for credential storage to prevent passwords from being visible in process lists.

**Supported methods**:
1. **`.netrc` file (secure)** - Credentials stored in `~/.netrc` (chmod 600), not visible in process list
2. **Command-line parameters (legacy)** - Credentials visible in process list, backward compatible

See [Credential Management](#credential-management) section for configuration details.

## Testing

The `unit-test/` directory contains automated tests using mock Redfish servers. Tests are numbered to indicate recommended execution order:

### test-01-plugins.sh
Quick plugin architecture validation (no servers needed, ~2 seconds).
- Validates plugin discovery and error handling
- Tests bf3-sensor and generic-redfish plugin loading
- Verifies default plugin behavior

```bash
cd unit-test
./test-01-plugins.sh
```

### test-02-power-collect.sh
Core power-collect functionality with mock BMC endpoints.
- Validates endpoint discovery and connection handling
- Verifies power/thermal data collection from multiple endpoints
- Tests multi-threaded collection
- Output files created in `unit-test/generated/`
- Automatic cleanup on exit or Ctrl+C

```bash
cd unit-test
./test-02-power-collect.sh
```

### test-03-power-start.sh
Integration test for the rickshaw wrapper script.
- Validates command-line argument handling (--interval, --username, --password, --endpoints, --plugin)
- Tests background process spawning
- Verifies proper handoff to power-collect
- Tests power-stop

```bash
cd unit-test
./test-03-power-start.sh
```

### test-04-netrc.sh
Tests secure credential storage using .netrc file.
- Validates .netrc authentication works correctly
- Confirms empty username/password parameters trigger .netrc usage
- Verifies no passwords exposed in process lists
- Demonstrates recommended security practice

```bash
cd unit-test
./test-04-netrc.sh
```

### local_test
Manual diagnostic tool for testing real BMC hardware (not automated).
- Tests connectivity to actual BMC endpoints
- Discovers supported Redfish API structure
- Recommends which plugin to use
- Requires real hardware and credentials

```bash
cd unit-test
./local_test <ip_address> <username> <password>
```

See `unit-test/README.md` for detailed documentation.

## References

- [DMTF Redfish Specification](https://www.dmtf.org/standards/redfish)
- [NVIDIA BlueField BMC Documentation](https://docs.nvidia.com/networking/category/bluefieldbmc)
- [Rickshaw Tool Development](https://github.com/perftool-incubator/rickshaw)
