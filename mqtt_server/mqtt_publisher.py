import paho.mqtt.client as mqtt
import time
import random

# MQTT Broker (public HiveMQ broker for testing)
BROKER = "broker.hivemq.com"   # or your own broker IP
PORT = 1883
TOPIC = "distance/topic"       # must match Flutter subscription

# Create MQTT client
client = mqtt.Client()

# Connect to broker
print(f"Connecting to broker {BROKER}:{PORT} ...")
client.connect(BROKER, PORT, 60)
print("Connected ✅")

# Publish random distance values
try:
    while True:
        # Generate a fake distance (1–12 meters)
        distance = round(random.uniform(1, 12), 2)

        # Publish to topic
        client.publish(TOPIC, str(distance))
        print(f"📡 Published distance: {distance} m")

        time.sleep(1)  # send every 3 seconds

except KeyboardInterrupt:
    print("Stopped by user")
    client.disconnect()
