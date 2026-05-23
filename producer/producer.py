import os
import time
import random
import json
from datetime import datetime, timezone
from kafka import KafkaProducer



BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:29092")
TOPIC = os.getenv("KAFKA_TOPIC", "metrics-raw")

HOSTS = [f"web-{i}" for i in range(1, 4)]
SERVICES = ["api", "auth", "payment"]

producer = KafkaProducer(
    bootstrap_servers=BOOTSTRAP,
    value_serializer=lambda v: json.dumps(v).encode(),
    api_version=(3, 6, 0),
)

def generate_metric():
    host = random.choice(HOSTS)
    service = random.choice(SERVICES)
    base_cpu = {"web-1": 55, "web-2": 70, "web-3": 40}[host]
    return {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "host": host,
        "service": service,
        "cpu_percent":    round(base_cpu + random.gauss(0, 8), 2),
        "memory_percent": round(random.uniform(30, 90), 2),
        "latency_ms":     round(abs(random.gauss(120, 40)), 2),
        "request_count":  random.randint(10, 500),
        "error": bool(random.getrandbits(1))
    }

print(f"Producer started → {BOOTSTRAP} / {TOPIC}")
try:
    while True:
        metric = generate_metric()
        producer.send(TOPIC, value=metric)
        producer.flush()
        print(f"Produced: {metric}")
        time.sleep(1)
except KeyboardInterrupt:
    print("Producer stopped.")