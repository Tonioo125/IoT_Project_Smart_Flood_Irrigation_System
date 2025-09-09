---

# smart\_water

![App Screenshot](assets/Screenshot%202025-05-18%20211850.png)
![App Data History](assets/Screenshot%202025-05-18%20211903.png)

This project is all about building a **smart flood mitigation system**. Instead of waiting for water levels to rise and flood everything, this system **monitors water in reservoirs and automatically moves it around with pumps** — all controlled by IoT + Flutter.

Think of it like a “smart irrigation system,” but for cities dealing with floods.

---

## What’s inside this repo?

* **Flutter App**
  A mobile dashboard where you can:

  * See real-time water levels
  * Check pump status
  * Manually control the pump (on/off)
  * Get alerts when water is too high/low

* **ESP32 IoT Code (Arduino/INO)**
  Runs directly on the ESP32-S3.

  * Reads data from water level/ultrasonic sensors
  * Decides when to turn the pump on/off
  * Sends data to Firebase / MQTT
  * Listens for commands from the Flutter app

---

## How it works

1. **Sensors** measure water levels in reservoirs.
2. **ESP32** collects that data and pushes it to Firebase / MQTT.
3. **Flutter app** shows everything in real-time and lets you control pumps.
4. **Pumps** move water between reservoirs so one doesn’t overflow.

Basically:

```
Reservoir → Sensor → ESP32 → Cloud → App → Pump → Reservoir
```

---

## Features

* Automatic pump activation when water gets too high
* Manual control from your phone
* Real-time monitoring (thanks to Firebase + MQTT)
* Scalable: add more reservoirs/sensors if needed
* Future-ready: notifications, graphs, dark mode

---

## Tech Stack

* **ESP32-S3** with Arduino (INO code)
* **Flutter** for the mobile app
* **Firebase** (Firestore / Realtime DB)
* **MQTT** for direct device control
* Good ol’ water pumps + sensors

---

## Getting Started

Clone the repo and open the part you need:

### Flutter app

```bash
git clone https://github.com/your-username/smart_water.git
cd smart_water
flutter pub get
flutter run
```

### ESP32 code

1. Open the `.ino` file in Arduino IDE or PlatformIO.
2. Install ESP32 board support + needed libraries (WiFi, Firebase, PubSubClient for MQTT, etc).
3. Flash it to your ESP32-S3.

---
