import json
import random
import os
import boto3
from datetime import datetime, timedelta

# Configuration from environment variables
KINESIS_STREAM_NAME = os.environ['KINESIS_STREAM_NAME']
LOGS_PER_INVOCATION = int(os.environ.get('LOGS_PER_INVOCATION', '10'))
AWS_REGION = os.environ.get('AWS_REGION', 'us-west-2')

# Initialize Kinesis client
kinesis_client = boto3.client('kinesis', region_name=AWS_REGION)

# IoT Vehicle Error Data
SERVICES = ["vehicle-telemetry", "diagnostic-system", "sensor-gateway", "navigation-system"]
ERROR_CODES = {
    "vehicle-telemetry": ["SENSOR_001", "SENSOR_002", "SENSOR_003"],
    "diagnostic-system": ["DIAG_001", "DIAG_002", "DIAG_003"],
    "sensor-gateway": ["CONN_001", "CONN_002", "CONN_003"],
    "navigation-system": ["GPS_001", "GPS_002", "GPS_003"]
}

ERROR_MESSAGES = {
    "SENSOR_001": "Engine temperature sensor reading critical: value exceeds 110°C. Potential coolant system failure or sensor malfunction. Immediate inspection required.",
    "SENSOR_002": "Battery voltage dropped below 11.5V. Possible alternator failure or battery degradation. Check charging system and battery health.",
    "SENSOR_003": "Fuel pressure sensor indicating abnormal readings: fluctuating between 30-70 PSI. Risk of engine misfire or stalling. Fuel system diagnostic needed.",
    "DIAG_001": "OBD communication error: ECU not responding to query commands. Unable to retrieve diagnostic trouble codes. Check wiring and OBD port integrity.",
    "DIAG_002": "CAN bus data corruption detected. Multiple ECUs reporting inconsistent vehicle state. Possible electrical interference or bus wiring issue.",
    "DIAG_003": "ECU response timeout during critical parameter request. Potential processor overload or communication bus saturation. Verify ECU firmware and network load.",
    "CONN_001": "Telematics gateway connection lost. Vehicle offline for over 30 minutes. Check cellular module and antenna. Possible impact on remote diagnostics and emergency services.",
    "CONN_002": "Data transmission timeout: Vehicle health packet not received by cloud server. Retry attempts exhausted. Investigate local data buffer and transmission queue.",
    "CONN_003": "Message queue overflow in telematics unit. High-priority alerts may be delayed. Memory allocation issue suspected. Remote reset recommended.",
    "GPS_001": "GPS signal lost for over 15 minutes in open sky conditions. Potential hardware failure in GPS module. Navigation system reliability compromised.",
    "GPS_002": "Geofence violation detected: Vehicle entered restricted zone. Possible theft or driver compliance issue. Alerting fleet management and security team.",
    "GPS_003": "Significant route deviation identified. Vehicle off planned course by more than 5 miles. Check for traffic incidents or unauthorized trip changes."
}

VEHICLE_STATES = ["MOVING", "IDLE", "STOPPED", "CHARGING", "MAINTENANCE"]

def generate_sensor_readings():
    return {
        "engine_temp": round(random.uniform(70, 120), 2),
        "battery_voltage": round(random.uniform(11.5, 14.8), 2),
        "fuel_pressure": round(random.uniform(35, 65), 2),
        "speed": round(random.uniform(0, 120), 2),
        "battery_level": round(random.uniform(20, 100), 2)
    }

def generate_diagnostic_info():
    return {
        "dtc_codes": [f"P{random.randint(1000, 9999)}" for _ in range(random.randint(0, 3))],
        "system_status": random.choice(["OK", "WARNING", "ERROR"]),
        "last_maintenance": (datetime.utcnow() - timedelta(days=random.randint(1, 365))).isoformat()
    }

def generate_vehicle_log():
    """Generate a single IoT vehicle error log"""
    service = random.choice(SERVICES)
    error_code = random.choice(ERROR_CODES[service])

    return {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "level": "ERROR",
        "service": service,
        "error_code": error_code,
        "message": ERROR_MESSAGES[error_code],
        "vehicle_id": f"VIN-{random.randint(1000, 9999)}",
        "vehicle_state": random.choice(VEHICLE_STATES),
        "location": {
            "latitude": round(random.uniform(35.0, 42.0), 6),
            "longitude": round(random.uniform(-120.0, -100.0), 6)
        },
        "sensor_readings": generate_sensor_readings(),
        "diagnostic_info": generate_diagnostic_info(),
        "metadata": {
            "environment": "production",
            "region": AWS_REGION,
            "firmware_version": f"{random.randint(1,3)}.{random.randint(0,9)}.{random.randint(0,9)}"
        }
    }

def lambda_handler(event, context):
    """Lambda handler to generate and publish vehicle error logs to Kinesis"""

    print(f"Starting log generation - Target: {LOGS_PER_INVOCATION} logs")
    print(f"Kinesis stream: {KINESIS_STREAM_NAME}")
    print(f"Region: {AWS_REGION}")

    # Generate logs
    records = []
    for i in range(LOGS_PER_INVOCATION):
        log = generate_vehicle_log()
        records.append({
            'Data': json.dumps(log),
            'PartitionKey': log['service']  # Use service for ordering per service
        })

    # Send to Kinesis in batches (max 500 per put_records call)
    batch_size = 100
    sent_count = 0
    failed_count = 0

    for i in range(0, len(records), batch_size):
        batch = records[i:i + batch_size]
        try:
            response = kinesis_client.put_records(
                StreamName=KINESIS_STREAM_NAME,
                Records=batch
            )

            # Check for partial failures
            if response['FailedRecordCount'] > 0:
                failed_count += response['FailedRecordCount']
                print(f"⚠️ Batch {i//batch_size + 1}: {response['FailedRecordCount']} records failed")

            sent_count += len(batch) - response['FailedRecordCount']

            print(f"✅ Batch {i//batch_size + 1}: Sent {len(batch) - response['FailedRecordCount']}/{len(batch)} records")

        except Exception as e:
            failed_count += len(batch)
            print(f"❌ Error sending batch {i//batch_size + 1}: {e}")

    print(f"\n📊 Completed: {sent_count} sent, {failed_count} failed")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'logs_sent': sent_count,
            'logs_failed': failed_count,
            'stream': KINESIS_STREAM_NAME
        })
    }
