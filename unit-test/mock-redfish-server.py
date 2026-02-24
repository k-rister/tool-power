#!/usr/bin/env python3
"""
Mock Redfish server for testing power-collect
Simulates a Redfish-enabled device BMC (e.g., BF-3 NIC/DPU)
"""

import sys
import json
import random
from http.server import HTTPServer, BaseHTTPRequestHandler
from base64 import b64decode
import ssl

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8443
SERVER_NAME = sys.argv[2] if len(sys.argv) > 2 else f"BMC-{PORT}"

class RedfishHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        # Check authentication
        auth_header = self.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Basic '):
            self.send_error(401, 'Unauthorized')
            return

        # Parse path
        path = self.path

        if path == '/redfish/v1/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "@odata.type": "#ServiceRoot.v1_5_0.ServiceRoot",
                "@odata.id": "/redfish/v1/",
                "Id": "RootService",
                "Name": f"Root Service {SERVER_NAME}",
                "RedfishVersion": "1.6.0",
                "Chassis": {
                    "@odata.id": "/redfish/v1/Chassis"
                }
            }
            self.wfile.write(json.dumps(response, indent=2).encode())

        elif path == '/redfish/v1/Chassis':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "@odata.type": "#ChassisCollection.ChassisCollection",
                "@odata.id": "/redfish/v1/Chassis",
                "Name": "Chassis Collection",
                "Members": [
                    {"@odata.id": "/redfish/v1/Chassis/Chassis1"}
                ],
                "Members@odata.count": 1
            }
            self.wfile.write(json.dumps(response, indent=2).encode())

        elif path == '/redfish/v1/Chassis/Chassis1/Power':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            # Generate realistic varying power values
            base_power = 150 + random.uniform(-10, 10)

            response = {
                "@odata.type": "#Power.v1_5_0.Power",
                "@odata.id": "/redfish/v1/Chassis/Chassis1/Power",
                "Id": "Power",
                "Name": "Power",
                "PowerControl": [
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Power#/PowerControl/0",
                        "MemberId": "0",
                        "Name": "System Power Control",
                        "PowerConsumedWatts": round(base_power, 2),
                        "PowerCapacityWatts": 400,
                        "PowerLimit": {
                            "LimitInWatts": 350
                        },
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    }
                ],
                "Voltages": [
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Power#/Voltages/0",
                        "MemberId": "0",
                        "Name": "12V",
                        "ReadingVolts": round(12.0 + random.uniform(-0.2, 0.2), 2),
                        "UpperThresholdCritical": 13.2,
                        "LowerThresholdCritical": 10.8,
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    },
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Power#/Voltages/1",
                        "MemberId": "1",
                        "Name": "5V",
                        "ReadingVolts": round(5.0 + random.uniform(-0.1, 0.1), 2),
                        "UpperThresholdCritical": 5.5,
                        "LowerThresholdCritical": 4.5,
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    }
                ],
                "PowerSupplies": [
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Power#/PowerSupplies/0",
                        "MemberId": "0",
                        "Name": "PSU1",
                        "PowerOutputWatts": round(base_power * 0.5, 2),
                        "PowerCapacityWatts": 750,
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    }
                ]
            }
            self.wfile.write(json.dumps(response, indent=2).encode())

        elif path == '/redfish/v1/Chassis/Chassis1/Thermal':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            # Generate realistic varying thermal values
            ambient_temp = 25 + random.uniform(-2, 3)
            cpu_temp = 55 + random.uniform(-5, 15)

            response = {
                "@odata.type": "#Thermal.v1_4_0.Thermal",
                "@odata.id": "/redfish/v1/Chassis/Chassis1/Thermal",
                "Id": "Thermal",
                "Name": "Thermal",
                "Temperatures": [
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Thermal#/Temperatures/0",
                        "MemberId": "0",
                        "Name": "Ambient Temp",
                        "ReadingCelsius": round(ambient_temp, 1),
                        "UpperThresholdCritical": 45.0,
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    },
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Thermal#/Temperatures/1",
                        "MemberId": "1",
                        "Name": "CPU Temp",
                        "ReadingCelsius": round(cpu_temp, 1),
                        "UpperThresholdCritical": 95.0,
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    },
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Thermal#/Temperatures/2",
                        "MemberId": "2",
                        "Name": "Memory Temp",
                        "ReadingCelsius": round(45 + random.uniform(-3, 8), 1),
                        "UpperThresholdCritical": 85.0,
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    }
                ],
                "Fans": [
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Thermal#/Fans/0",
                        "MemberId": "0",
                        "Name": "Fan1",
                        "Reading": round(3000 + random.uniform(-200, 500)),
                        "ReadingUnits": "RPM",
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    },
                    {
                        "@odata.id": "/redfish/v1/Chassis/Chassis1/Thermal#/Fans/1",
                        "MemberId": "1",
                        "Name": "Fan2",
                        "Reading": round(3200 + random.uniform(-200, 500)),
                        "ReadingUnits": "RPM",
                        "Status": {
                            "State": "Enabled",
                            "Health": "OK"
                        }
                    }
                ]
            }
            self.wfile.write(json.dumps(response, indent=2).encode())

        else:
            self.send_error(404, 'Not Found')

    def log_message(self, format, *args):
        # Suppress default logging
        pass

if __name__ == '__main__':
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, RedfishHandler)

    # Create self-signed SSL context
    httpd.socket = ssl.wrap_socket(httpd.socket,
                                    server_side=True,
                                    certfile='/tmp/mock-cert.pem',
                                    keyfile='/tmp/mock-key.pem',
                                    ssl_version=ssl.PROTOCOL_TLS)

    print(f"Mock Redfish server '{SERVER_NAME}' running on port {PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print(f"\nShutting down {SERVER_NAME}")
        httpd.shutdown()
