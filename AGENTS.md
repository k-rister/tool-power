# Tool-power

## Purpose
Crucible tool for collecting and post-processing power consumption and thermal telemetry from Redfish-enabled BMC endpoints during benchmark execution. Features a plugin architecture supporting generic Redfish endpoints and NVIDIA BlueField-3 DPU BMCs.

## Languages
- Bash: collection, start/stop, and plugins (`power-collect`, `power-start`, `power-stop`, `plugins/bf3-sensor.sh`, `plugins/generic-redfish.sh`)
- Python: post-processor (`power-post-process.py`) and mock test server (`unit-test/mock-redfish-server.py`)

## Key Files
| File | Purpose |
|------|---------|
| `power-collect` | Multi-threaded Redfish collector polling BMC endpoints at configurable intervals |
| `power-start` | Parses CLI arguments (interval, endpoints, credentials, plugin) and launches background collector |
| `power-stop` | Terminates worker and collector processes |
| `power-post-process.py` | Converts uncompressed CSV telemetry into CDM metrics (`redfish-bmc:power`) |
| `plugins/bf3-sensor.sh` | NVIDIA BlueField-3 DPU BMC Redfish plugin |
| `plugins/generic-redfish.sh` | Generic Redfish-compliant device plugin |
| `rickshaw.json` | Rickshaw integration: profiler-only deployment on remotehosts |
| `workshop.json` | Engine image build requirements (`curl`, `jq`) |
| `tool-metadata.json` | Machine-readable description and CDM-indexed status (consumed by `crucible tools list`) |
| `multiplex.json` | Parameter validation rules and `defaults` preset for multiplex (mirrors benchmark `multiplex.json`) |

## Configuration
- `--interval <seconds>` — Polling interval in seconds (default: `3`)
- `--endpoints <ip1,ip2,...>` — Comma-separated list of BMC IP addresses or hostnames
- `--plugin <name>` — Redfish plugin to use (`generic-redfish` or `bf3-sensor`, default: `generic-redfish`)
- `--username <user>` / `--password <pass>` — BMC credentials (optional, `.netrc` recommended)

## Architecture
- `power-start` — Validates inputs, spawns `power-collect` in the background, and writes PID to `power-collect-pid.txt`
- `power-collect` — Loads selected plugin, validates each endpoint with exponential retry backoff, spawns background collector per endpoint, and writes worker PIDs to `power-collect-worker-pids.txt`
- `power-stop` — Reads worker PIDs, terminates workers with SIGTERM, terminates main collector, and cleans up PID files
- `plugins/` — Plugins implement `plugin_validate_endpoint` and `plugin_collect_endpoint`, writing `power-<endpoint>.csv`
- `power-post-process.py` — Discovers all `power-*.csv` files, autodetects format (`generic-redfish` or `bf3-sensor`), parses power metrics, and emits CDM metric records under source `redfish-bmc` (type: `power`)

## Testing
- Unit tests: `cd unit-test && ./test-01-plugins.sh`
- Mock server tests: `cd unit-test && ./test-02-power-collect.sh` (requires mock server)
- Python syntax verification: `python3 -c "import py_compile; py_compile.compile('power-post-process.py', doraise=True)"`
- Integration: `crucible run <run-file.json>` with power tool configured on Redfish-accessible profiler host

## Conventions
- Primary branch is `main`
- Profiler-only tool — runs on remotehosts profiler role only, not on compute/cluster nodes
- Standard Bash and Python modelines and 4-space indentation
