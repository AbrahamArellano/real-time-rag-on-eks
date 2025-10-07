# generate_logs.py
import json
import random
from datetime import datetime, timedelta

# Sample data for generation
services = ["vehicle-telemetry", "diagnostic-system", "sensor-gateway", "navigation-system"]
error_codes = {
    "vehicle-telemetry": ["SENSOR_001", "SENSOR_002", "SENSOR_003"],
    "diagnostic-system": ["DIAG_001", "DIAG_002", "DIAG_003"],
    "sensor-gateway": ["CONN_001", "CONN_002", "CONN_003"],
    "navigation-system": ["GPS_001", "GPS_002", "GPS_003"]
}

error_messages = {
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

vehicle_states = [
    "MOVING", "IDLE", "STOPPED", "CHARGING", "MAINTENANCE"
]

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
        "last_maintenance": (datetime.now() - timedelta(days=random.randint(1, 365))).isoformat()
    }

def generate_error_log(timestamp):
    service = random.choice(services)
    error_code = random.choice(error_codes[service])
    vehicle_id = f"VIN-{random.randint(1000, 9999)}"
    vehicle_state = random.choice(vehicle_states)
    
    return {
        "timestamp": timestamp.isoformat() + "Z",
        "level": "ERROR",
        "service": service,
        "error_code": error_code,
        "message": error_messages[error_code],
        "vehicle_id": vehicle_id,
        "vehicle_state": vehicle_state,
        "location": {
            "latitude": round(random.uniform(35.0, 42.0), 6),
            "longitude": round(random.uniform(-120.0, -100.0), 6)
        },
        "sensor_readings": generate_sensor_readings(),
        "diagnostic_info": generate_diagnostic_info(),
        "metadata": {
            "environment": "production",
            "region": "us-west-2",
            "firmware_version": f"{random.randint(1,3)}.{random.randint(0,9)}.{random.randint(0,9)}"
        }
    }

def main():
    logs = []
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=7)
    current_time = start_time

    print("Generating IoT vehicle error logs...")
    while current_time < end_time:
        if random.random() < 0.1:  # 10% chance of error in each minute
            logs.append(generate_error_log(current_time))
        current_time += timedelta(minutes=1)

    print(f"Generated {len(logs)} error logs")
    
    with open('error_logs.json', 'w') as f:
        json.dump(logs, f, indent=2)
    print("Logs saved to error_logs.json")

if __name__ == "__main__":
    main()
