# Power Tool

## Purpose
Collects power consumption and thermal sensor data from Redfish-enabled BMC endpoints during benchmark execution. Designed for NVIDIA BlueField-3 DPU BMCs with a plugin architecture for extensibility to other Redfish-compliant devices.

## Language
Bash — all scripts (collection, start/stop, post-processing, plugins)

## Key Files
| File | Purpose |
|------|---------|
| `power-collect` | Multi-threaded Redfish collector: polls BMC endpoints at configurable intervals |
| `power-start` | Parses CLI args (endpoints, credentials, interval, plugin), launches collection |
| `power-stop` | Stops collection, compresses output with xz |
| `power-post-process` | Converts raw data to crucible metrics (TODO) |
| `plugins/bf3-sensor.sh` | NVIDIA BlueField-3 DPU BMC Redfish plugin |
| `plugins/generic-redfish.sh` | Generic Redfish-compliant device plugin |
| `rickshaw.json` | Rickshaw integration: profiler-only deployment on remotehosts |
| `workshop.json` | Engine image build requirements |

## Configuration
- Endpoints and credentials configured via `--netrc` (secure) or `--user`/`--password` CLI params
- `--interval <seconds>` — Collection interval
- `--plugin <name>` — Redfish plugin to use (bf3-sensor or generic-redfish)
- Deployment controlled via opt-in/opt-out tags in run-file

## Tests
Unit tests in `unit-test/` directory (4 numbered tests)

## Conventions
- Primary branch is `main`
- Profiler-only tool — runs on remotehosts profiler role only, not on cluster nodes
- Plugin architecture for different Redfish implementations
