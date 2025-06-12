#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>
#include <time.h>

// WiFi credentials
const char* ssid = "スマホです";
const char* password = "hehe4321";

// Firebase credentials
const char* DATABASE_URL = "https://iotproject-51bbb-default-rtdb.firebaseio.com";
const char* DATABASE_SECRET = "kpw2U8YgWuVBZFGE1vKDMp3UE4A0ecfukF6DpG5n";

// Firestore
const char* FIRESTORE_PROJECT_ID = "iotproject-51bbb";
const char* FIRESTORE_API_KEY = "AIzaSyBQuvdps8lO52G7SErv5dWdjKsbXJb2_Rs";

// MQTT Broker
const char* mqtt_server = "5f2bc0b8926d4530b7d3d10646ca602c.s1.eu.hivemq.cloud";
const int mqtt_port = 8883;
const char* mqtt_user = "antoniooo";
const char* mqtt_password = "x@_!k#GRs7NV.LP";
const char* mqtt_topic = "smartflood/redirect";
const char* mqtt_status_topic = "smartflood/status";

WiFiClientSecure espClient;
PubSubClient client(espClient);

// Pins
#define TRIG_PIN_A 41
#define ECHO_PIN_A 42
#define WATERSENSOR_A 1
#define SDA_PIN 4
#define SCL_PIN 5
#define TRIG_PIN_B 17
#define ECHO_PIN_B 18
#define WATERSENSOR_B 3
#define A_IA 6
#define A_IB 7
#define B_IA 9
#define B_IB 10

const float TOLERANCE = 2.0;

// Variables
float height_A = 20.0;
float height_B = 30.0;
int waterlevel_A = 30;
int waterlevel_B = 40;
bool pumpManual = false;
String pumpStatus_A = "IDLE";
String pumpStatus_B = "IDLE";
String lastAction = "NONE";
unsigned long lastTime = 0;
unsigned long interval = 1000;
unsigned long lastLogged = 0;
const unsigned long logInterval = 60000; // 1 minute for testing

WebServer server(80);
LiquidCrystal_I2C lcd(0x27, 16, 2);

// Sensor Functions
float getDistance_A() {
  digitalWrite(TRIG_PIN_A, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN_A, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN_A, LOW);
  long duration = pulseIn(ECHO_PIN_A, HIGH);
  return duration * 0.034 / 2;
}

float getDistance_B() {
  digitalWrite(TRIG_PIN_B, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN_B, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN_B, LOW);
  long duration = pulseIn(ECHO_PIN_B, HIGH);
  return duration * 0.034 / 2;
}

int WaterSensor_A() {
  int sensorValue = analogRead(WATERSENSOR_A);
  return map(sensorValue, 0, 4095, 0, 100);
}

int WaterSensor_B() {
  int sensorValue = analogRead(WATERSENSOR_B);
  return map(sensorValue, 0, 4095, 0, 100);
}

// Motor Control
void motorForwardAtoB() {
  digitalWrite(A_IA, HIGH);
  digitalWrite(A_IB, LOW);
  pumpStatus_A = "A_TO_B";
}

void motorStopAtoB() {
  digitalWrite(A_IA, LOW);
  digitalWrite(A_IB, LOW);
  if (pumpStatus_A == "A_TO_B") pumpStatus_A = "IDLE";
}

void motorForwardBtoA() {
  digitalWrite(B_IA, HIGH);
  digitalWrite(B_IB, LOW);
  pumpStatus_B = "B_TO_A";
}

void motorStopBtoA() {
  digitalWrite(B_IA, LOW);
  digitalWrite(B_IB, LOW);
  if (pumpStatus_B == "B_TO_A") pumpStatus_B = "IDLE";
}

// Firebase Realtime DB
void sendDataToRealtimeDB() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    
    // Send data for Reservoir A
    String urlA = String(DATABASE_URL) + "/sensorData_A.json?auth=" + DATABASE_SECRET;
    http.begin(urlA);
    http.addHeader("Content-Type", "application/json");
    String payloadA = "{\"height\":" + String(height_A, 2) + 
                     ",\"waterlevel\":" + String(waterlevel_A) + 
                     ",\"pumpStatus\":\"" + pumpStatus_A + "\"}";
    http.PUT(payloadA);
    http.end();
    
    // Send data for Reservoir B
    String urlB = String(DATABASE_URL) + "/sensorData_B.json?auth=" + DATABASE_SECRET;
    http.begin(urlB);
    http.addHeader("Content-Type", "application/json");
    String payloadB = "{\"height\":" + String(height_B, 2) + 
                     ",\"waterlevel\":" + String(waterlevel_B) + 
                     ",\"pumpStatus\":\"" + pumpStatus_B + "\"}";
    http.PUT(payloadB);
    http.end();
  }
}

// Firestore Functions
String getISOTime() {
  time_t now;
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return "";
  char buf[30];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
  return String(buf);
}

void logPumpActionToFirestore(String action) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    String url = "https://firestore.googleapis.com/v1/projects/" + String(FIRESTORE_PROJECT_ID) + 
                "/databases/(default)/documents/PumpHistory?key=" + String(FIRESTORE_API_KEY);

    String payload = "{"
      "\"fields\": {"
        "\"timestamp\": {\"timestampValue\": \"" + getISOTime() + "\"},"
        "\"action\": {\"stringValue\": \"" + action + "\"},"
        "\"reservoirA_height\": {\"doubleValue\": " + String(height_A, 2) + "},"
        "\"reservoirB_height\": {\"doubleValue\": " + String(height_B, 2) + "},"
        "\"reservoirA_waterlevel\": {\"integerValue\": " + String(waterlevel_A) + "},"
        "\"reservoirB_waterlevel\": {\"integerValue\": " + String(waterlevel_B) + "},"
        "\"mode\": {\"stringValue\": \"" + (pumpManual ? "MANUAL" : "AUTO") + "\"}"
      "}"
    "}";

    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(payload);
    if (code > 0) {
      Serial.println("[Firestore] Action logged: " + action);
    } else {
      Serial.println("[Firestore] Error: " + String(code));
    }
    http.end();
  }
}

// MQTT Functions
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (int i = 0; i < length; i++) msg += (char)payload[i];
  msg.trim();
  Serial.print("[MQTT] Message: ");
  Serial.println(msg);

  if (msg == "ON_AB") {
    pumpManual = true;
    motorForwardAtoB();
    lastAction = "MANUAL_A_TO_B";
    logPumpActionToFirestore("A_TO_B");
    client.publish(mqtt_status_topic, "Manual A->B Activated");
  } else if (msg == "OFF_AB") {
    pumpManual = false;
    motorStopAtoB();
    lastAction = "MANUAL_STOP";
    logPumpActionToFirestore("MANUAL_STOP");
    client.publish(mqtt_status_topic, "Manual A->B Stopped");
  } else if (msg == "ON_BA") {
    pumpManual = true;
    motorForwardBtoA();
    lastAction = "MANUAL_B_TO_A";
    logPumpActionToFirestore("B_TO_A");
    client.publish(mqtt_status_topic, "Manual B->A Activated");
  } else if (msg == "OFF_BA") {
    pumpManual = false;
    motorStopBtoA();
    lastAction = "MANUAL_STOP";
    logPumpActionToFirestore("MANUAL_STOP");
    client.publish(mqtt_status_topic, "Manual B->A Stopped");
  } else if (msg == "AUTO") {
    pumpManual = false;
    lastAction = "AUTO_MODE";
    logPumpActionToFirestore("AUTO_MODE_ACTIVATED");
    client.publish(mqtt_status_topic, "Auto Mode Activated");
  }
}

void reconnectMQTT() {
  while (!client.connected()) {
    Serial.print("[MQTT] Connecting...");
    String clientId = "ESP32Client-" + String(random(0xffff), HEX);
    if (client.connect(clientId.c_str(), mqtt_user, mqtt_password)) {
      Serial.println("connected");
      client.subscribe(mqtt_topic);
      client.publish(mqtt_status_topic, "ESP32 Reconnected");
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" retrying...");
      delay(5000);
    }
  }
}

// Setup
void setup() {
  Serial.begin(115200);
  delay(500);

  Wire.begin(SDA_PIN, SCL_PIN);
  lcd.init(); lcd.backlight(); lcd.clear();
  lcd.setCursor(0, 0); lcd.print("Connecting WiFi");

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }
  lcd.clear(); lcd.print("WiFi Connected");

  if (!MDNS.begin("esp32")) {
    Serial.println("[mDNS] Failed");
  }

  configTime(0, 0, "pool.ntp.org");

  //Initialize pins
  pinMode(TRIG_PIN_A, OUTPUT);
  pinMode(ECHO_PIN_A, INPUT);
  pinMode(WATERSENSOR_A, INPUT);
  pinMode(A_IA, OUTPUT);
  pinMode(A_IB, OUTPUT);
  pinMode(TRIG_PIN_B, OUTPUT);
  pinMode(ECHO_PIN_B, INPUT);
  pinMode(WATERSENSOR_B, INPUT);
  pinMode(B_IA, OUTPUT);
  pinMode(B_IB, OUTPUT);

  espClient.setInsecure();
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(mqttCallback);
}

// Main Loop
void loop() {
  server.handleClient();
  if (!client.connected()) reconnectMQTT();
  client.loop();

  if (millis() - lastTime > interval) {
    lastTime = millis();

    // Read sensor values
    height_A = getDistance_A();
    height_B = getDistance_B();
    waterlevel_A = WaterSensor_A();
    waterlevel_B = WaterSensor_B();

    // Send data to Firebase
    sendDataToRealtimeDB();

    // Automatic pump control
if (!pumpManual) {
  bool floodA = (height_A < 4.0) && (waterlevel_A > 75);
  bool floodB = (height_B < 4.0) && (waterlevel_B > 75);

  if (floodA && !floodB) {
    // Pompa dari A ke B sampai distance A >= 7 cm
    if (height_A < 7.0) {
      if (pumpStatus_A != "A_TO_B") {
        lastAction = "AUTO_A_TO_B";
        logPumpActionToFirestore("AUTO_A_TO_B");
        client.publish(mqtt_status_topic, "Auto: Pump A->B Activated");
      }
      motorForwardAtoB();
      motorStopBtoA();
    } else {
      motorStopAtoB();
      lastAction = "AUTO_STOP_A_TO_B";
      client.publish(mqtt_status_topic, "Auto: Pump A->B Stopped");
    }
  } else if (floodB && !floodA) {
    // Pompa dari B ke A sampai distance B >= 7 cm
    if (height_B < 7.0) {
      if (pumpStatus_B != "B_TO_A") {
        lastAction = "AUTO_B_TO_A";
        logPumpActionToFirestore("AUTO_B_TO_A");
        client.publish(mqtt_status_topic, "Auto: Pump B->A Activated");
      }
      motorForwardBtoA();
      motorStopAtoB();
    } else {
      motorStopBtoA();
      lastAction = "AUTO_STOP_B_TO_A";
      client.publish(mqtt_status_topic, "Auto: Pump B->A Stopped");
    }
  } else {
    // Jika kedua kanal banjir atau kedua kanal tidak banjir, stop semua pompa
    if (pumpStatus_A == "A_TO_B") motorStopAtoB();
    if (pumpStatus_B == "B_TO_A") motorStopBtoA();
    lastAction = "AUTO_STOP_ALL";
    client.publish(mqtt_status_topic, "Auto: Pump Stopped");
  }
}

    // Periodic logging to Firestore
    if (millis() - lastLogged > logInterval) {
      lastLogged = millis();
      logPumpActionToFirestore("STATUS_UPDATE");
    }

    // LCD Display
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.printf("A:%.1fcm %d%%", height_A, waterlevel_A);
    lcd.setCursor(0, 1);
    lcd.printf("B:%.1fcm %d%%", height_B, waterlevel_B);
  }
}