/*
  GridWatch - ESP32 DevKit monitoring node
  ----------------------------------------
  Sensor stack: MAX6675 + DHT11 + IR tamper + IR fan rotation + FSR + OLED.
  Transport: ESP-NOW broadcast to the ESP8266 gateway.

  The fan driver is deliberately optional. With FAN_DRIVER_ENABLED=0 (the
  current hardware state), GPIO16 is held LOW and thermal events are classified
  as THERMAL_WARNING without falsely claiming an active fan test.
*/

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClient.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <DHT.h>
#include <LittleFS.h>
#include <vector>
#include "max6675.h"

#define NODE_ID 1

// =========================================================================
// Architecture: Set USE_DIRECT_WIFI to 1 to remove the ESP8266 gateway!
// 1 = Direct Wi-Fi from ESP32 to Spring Boot Backend (No ESP8266 required)
// 0 = Dual-tier mode via ESP-NOW to ESP8266 gateway
// =========================================================================
#define USE_DIRECT_WIFI 1

#define WIFI_SSID "Your SSID"
#define WIFI_PASSWORD "Your Password"
#define BACKEND_HOST "Your IP"
#define BACKEND_PORT 8080
#define BACKEND_PATH "/api/readings"

#define GATEWAY_SSID "Sain"
#define FAN_DRIVER_ENABLED 0
#define OUTAGE_FAIL_THRESHOLD 1
#define BUFFER_MAX_RECORDS 128
#define SAMPLE_NORMAL_MS 3000UL
#define SAMPLE_ALERT_MS 1000UL
#define SAMPLE_OUTAGE_MS 8000UL
#define SEND_TIMEOUT_MS 400UL
#define THING_CHANNEL_SCAN_TIMEOUT_MS 8000UL

#define THERMO_CLK 18
#define THERMO_CS 5
#define THERMO_DO 19
#define IR1_PIN 32
#define IR2_PIN 33
#define FSR_PIN 34
#define LOAD_POT_PIN 35
#define LOAD_POT_ENABLED 1
#define DHT_PIN 17
#define FAN_CTRL_PIN 16
#define LED_PIN 4
#define OLED_SDA 21
#define OLED_SCL 22
#define OLED_WIDTH 128
#define OLED_HEIGHT 64
#define DHTTYPE DHT11

#define BASELINE_TEMP_C 30.0f
#define BASELINE_AMBIENT_C 25.0f
#define AMBIENT_COEFF 0.6f
#define WARN_DEVIATION_C 8.0f
#define CRITICAL_ABS_TEMP_C 90.0f
#define TEMP_RISE_RATE_WARN 1.5f
#define FSR_TAMPER_THRESHOLD 2500
#define FAN_VERIFY_MIN_PULSES 2
#define IR1_BROKEN_LEVEL LOW

uint8_t broadcastAddress[] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};

typedef struct __attribute__((packed)) struct_message {
  uint16_t version;
  uint16_t sizeBytes;
  uint32_t sequenceId;
  int nodeId;
  float tempC;
  float tempRiseRate;
  float ambientC;
  int loadPercent;
  int ambientSensorOk;
  int ir1;
  int ir2;
  int fsrValue;
  int fanVerified;
  int fanDriverEnabled;
  int classification;
  int healthScore;
  int buffered;
  uint32_t bufferedAgoMs;
} struct_message;

typedef struct __attribute__((packed)) buffered_record {
  struct_message msg;
  uint32_t capturedAtMs;
} buffered_record;

enum FaultState { NORMAL=0, THERMAL_WARNING=1, COOLING_FAILURE=2, CRITICAL_OVERHEAT=3, TAMPER=4, POSSIBLE_TAMPER=5, SENSOR_FAULT=6 };

const char* stateName(int s) {
  switch (s) {
    case THERMAL_WARNING: return "THERMAL_WARNING";
    case COOLING_FAILURE: return "COOLING_FAILURE";
    case CRITICAL_OVERHEAT: return "CRITICAL_OVERHEAT";
    case TAMPER: return "TAMPER";
    case POSSIBLE_TAMPER: return "POSSIBLE_TAMPER";
    case SENSOR_FAULT: return "SENSOR_FAULT";
    default: return "NORMAL";
  }
}

MAX6675 thermocouple(THERMO_CLK, THERMO_CS, THERMO_DO);
Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
DHT dht(DHT_PIN, DHTTYPE);

float lastTempC = NAN;
unsigned long lastReadMillis = 0;
uint32_t nextSequenceId = 1;
int consecutiveFailures = 0;
bool outageMode = false;
volatile bool sendResultReady = false;
volatile bool lastSendSuccess = false;
const char* BUFFER_FILE = "/buffer.dat";

// ESP-NOW callback API in current Arduino-ESP32/IDF.
void onDataSent(const esp_now_send_info_t *info, esp_now_send_status_t status) {
  (void)info;
  lastSendSuccess = (status == ESP_NOW_SEND_SUCCESS);
  sendResultReady = true;
}

bool setGatewayChannel() {
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(false, true);
  delay(100);
  int found = WiFi.scanNetworks(false, true);
  int selected = -1;
  for (int i = 0; i < found; i++) {
    int ch = WiFi.channel(i);
    if (WiFi.SSID(i) == String(GATEWAY_SSID) && ch >= 1 && ch <= 13) {
      selected = ch;
      break;
    }
  }
  WiFi.scanDelete();
  if (selected < 1 || selected > 13) {
    Serial.printf("Gateway SSID '%s' not found during scan.\n", GATEWAY_SSID);
    return false;
  }
  if (esp_wifi_set_channel((uint8_t)selected, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
    Serial.printf("Failed to set Wi-Fi channel %d.\n", selected);
    return false;
  }
  Serial.printf("ESP-NOW channel locked to gateway AP channel %d.\n", selected);
  return true;
}

String buildJson(const struct_message &r) {
  String loadJson = (r.loadPercent < 0) ? String("null") : String(r.loadPercent);
  String body = String("{") +
    "\"sequenceId\":" + r.sequenceId + "," +
    "\"nodeId\":" + r.nodeId + "," +
    "\"tempC\":" + String(r.tempC, 2) + "," +
    "\"tempRiseRate\":" + String(r.tempRiseRate, 2) + "," +
    "\"ambientC\":" + String(r.ambientC, 2) + "," +
    "\"loadPercent\":" + loadJson + "," +
    "\"ambientSensorOk\":" + String(r.ambientSensorOk ? "true" : "false") + "," +
    "\"ir1\":" + r.ir1 + "," +
    "\"ir2\":" + r.ir2 + "," +
    "\"fsrValue\":" + r.fsrValue + "," +
    "\"fanVerified\":" + String(r.fanVerified ? "true" : "false") + "," +
    "\"fanDriverEnabled\":" + String(r.fanDriverEnabled ? "true" : "false") + "," +
    "\"classification\":\"" + stateName(r.classification) + "\"," +
    "\"healthScore\":" + r.healthScore + "," +
    "\"buffered\":" + String(r.buffered ? "true" : "false") + "," +
    "\"bufferedAgoMs\":" + r.bufferedAgoMs +
    "}";
  return body;
}

#include <WiFiUdp.h>

#if USE_DIRECT_WIFI
WiFiUDP discoveryUdp;
String discoveredBackendHost = "";

String backendHost() {
  return discoveredBackendHost.length() ? discoveredBackendHost : String(BACKEND_HOST);
}

bool discoverBackend() {
  if (WiFi.status() != WL_CONNECTED) return false;
  discoveryUdp.begin(30304);
  IPAddress ip = WiFi.localIP();
  IPAddress mask = WiFi.subnetMask();
  IPAddress bcast(ip[0] | ~mask[0], ip[1] | ~mask[1], ip[2] | ~mask[2], ip[3] | ~mask[3]);

  discoveryUdp.beginPacket(bcast, 30303);
  discoveryUdp.write((const uint8_t*)"GRIDWATCH_DISCOVER_V1", 21);
  discoveryUdp.endPacket();

  unsigned long start = millis();
  char buf[128];
  while (millis() - start < 1500) {
    int len = discoveryUdp.parsePacket();
    if (len > 0) {
      int n = discoveryUdp.read(buf, sizeof(buf) - 1);
      if (n > 0) {
        buf[n] = 0;
        String reply = String(buf);
        String prefix = "GRIDWATCH_BACKEND_V1|";
        if (reply.startsWith(prefix)) {
          discoveredBackendHost = discoveryUdp.remoteIP().toString();
          Serial.printf("UDP Auto-Discovery: backend found at %s:8080\n", discoveredBackendHost.c_str());
          discoveryUdp.stop();
          return true;
        }
      }
    }
    delay(10);
  }
  discoveryUdp.stop();
  return false;
}

bool postReadingDirect(const struct_message &r) {
  if (WiFi.status() != WL_CONNECTED) {
    static unsigned long lastRecon = 0;
    if (millis() - lastRecon > 6000) {
      lastRecon = millis();
      WiFi.reconnect();
    }
    return false;
  }
  WiFiClient client;
  HTTPClient http;
  client.setTimeout(8000);   // was 2500 — allow backend up to 8s to respond
  String targetIp = backendHost();
  String url = String("http://") + targetIp + ":" + String(BACKEND_PORT) + BACKEND_PATH;
  if (!http.begin(client, url)) return false;
  http.setTimeout(8000);     // was 2500
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(buildJson(r));
  http.end();
  Serial.printf("Direct HTTP POST to %s seq=%lu -> %d%s\n", targetIp.c_str(), (unsigned long)r.sequenceId, code, r.buffered ? " [BUFFERED]" : "");
  return code >= 200 && code < 300;
}
#endif

bool sendAndAwaitResult(struct_message &msg) {
#if USE_DIRECT_WIFI
  return postReadingDirect(msg);
#else
  sendResultReady = false;
  lastSendSuccess = false;
  esp_err_t err = esp_now_send(broadcastAddress, (uint8_t*)&msg, sizeof(msg));
  if (err != ESP_OK) return false;
  unsigned long start = millis();
  while (!sendResultReady && (millis() - start < SEND_TIMEOUT_MS)) delay(2);
  return sendResultReady && lastSendSuccess;
#endif
}

bool appendBuffer(const struct_message &msg) {
  File f = LittleFS.open(BUFFER_FILE, FILE_APPEND);
  if (!f) {
    Serial.println("ERROR: unable to open outage buffer for append.");
    return false;
  }
  buffered_record rec;
  rec.msg = msg;
  rec.capturedAtMs = millis();
  size_t written = f.write((const uint8_t*)&rec, sizeof(rec));
  f.close();
  if (written != sizeof(rec)) {
    Serial.println("ERROR: outage buffer write was incomplete.");
    return false;
  }
  return true;
}

size_t bufferCount() {
  File f = LittleFS.open(BUFFER_FILE, FILE_READ);
  if (!f) return 0;
  size_t count = f.size() / sizeof(buffered_record);
  f.close();
  return count;
}

void trimBufferIfNeeded() {
  size_t count = bufferCount();
  if (count <= BUFFER_MAX_RECORDS) return;
  Serial.println("Outage buffer full - dropping oldest record to preserve bounded storage.");
  File in = LittleFS.open(BUFFER_FILE, FILE_READ);
  File out = LittleFS.open("/buffer.tmp", FILE_WRITE);
  if (!in || !out) { if (in) in.close(); if (out) out.close(); return; }
  buffered_record rec;
  in.seek(sizeof(buffered_record), SeekSet);
  while (in.available() >= (int)sizeof(rec)) {
    in.read((uint8_t*)&rec, sizeof(rec));
    out.write((const uint8_t*)&rec, sizeof(rec));
  }
  in.close(); out.close();
  LittleFS.remove(BUFFER_FILE);
  LittleFS.rename("/buffer.tmp", BUFFER_FILE);
}

bool flushBuffer() {
  File f = LittleFS.open(BUFFER_FILE, FILE_READ);
  if (!f || f.size() == 0) { if (f) f.close(); return true; }

  Serial.printf("Replaying %u buffered record(s)...\n", (unsigned)(f.size()/sizeof(buffered_record)));
  std::vector<buffered_record> pending;
  pending.reserve(f.size()/sizeof(buffered_record));
  buffered_record rec;
  while (f.available() >= (int)sizeof(rec)) {
    if (f.read((uint8_t*)&rec, sizeof(rec)) == sizeof(rec)) pending.push_back(rec);
    else break;
  }
  f.close();

  size_t firstUnsent = pending.size();
  for (size_t i = 0; i < pending.size(); i++) {
    pending[i].msg.buffered = 1;
    pending[i].msg.bufferedAgoMs = millis() - pending[i].capturedAtMs;
    if (!sendAndAwaitResult(pending[i].msg)) {
      firstUnsent = i;
      Serial.printf("Replay stopped at buffered record %u; retaining it and the remaining records.\n", (unsigned)i);
      break;
    }
    delay(30);
  }

  if (firstUnsent == pending.size()) {
    LittleFS.remove(BUFFER_FILE);
    Serial.println("Buffered replay complete; buffer cleared.");
    return true;
  }

  File out = LittleFS.open("/buffer.tmp", FILE_WRITE);
  if (!out) { Serial.println("ERROR: unable to rewrite retained outage buffer."); return false; }
  for (size_t i = firstUnsent; i < pending.size(); i++) out.write((const uint8_t*)&pending[i], sizeof(buffered_record));
  out.close();
  LittleFS.remove(BUFFER_FILE);
  LittleFS.rename("/buffer.tmp", BUFFER_FILE);
  return false;
}

bool verifyFanSpinning() {
#if FAN_DRIVER_ENABLED
  digitalWrite(FAN_CTRL_PIN, HIGH);
  delay(300);
  int pulses = 0;
  int lastState = digitalRead(IR2_PIN);
  unsigned long endAt = millis() + 600;
  while ((long)(millis() - endAt) < 0) {
    int s = digitalRead(IR2_PIN);
    if (s != lastState) pulses++;
    lastState = s;
    delay(10);
  }
  digitalWrite(FAN_CTRL_PIN, LOW);
  return pulses >= FAN_VERIFY_MIN_PULSES;
#else
  digitalWrite(FAN_CTRL_PIN, LOW);
  return false;
#endif
}

bool verifyTamperCorroborated(int initialFsr) {
  delay(150);
  int fsrRecheck = analogRead(FSR_PIN);
  int ir1Recheck = digitalRead(IR1_PIN);
  return (ir1Recheck == IR1_BROKEN_LEVEL) && (max(initialFsr, fsrRecheck) > FSR_TAMPER_THRESHOLD);
}

int computeHealthScore(int state, float deviation, float riseRate) {
  if (state == SENSOR_FAULT) return 0;
  if (state == CRITICAL_OVERHEAT) return 15;
  int thermalRisk = deviation > 0 ? (int)min(40.0f, deviation * 2.0f) : 0;
  int coolingRisk = state == COOLING_FAILURE ? 25 : 0;
  int tamperRisk = state == TAMPER ? 20 : (state == POSSIBLE_TAMPER ? 8 : 0);
  int criticalRisk = state == CRITICAL_OVERHEAT ? 50 : 0;
  int riseRisk = riseRate > TEMP_RISE_RATE_WARN ? 10 : 0;
  return constrain(100 - thermalRisk - coolingRisk - tamperRisk - criticalRisk - riseRisk, 0, 100);
}

int classifyState(float tempC, float deviation, float riseRate, int ir1, int fsrValue, bool ambientOk, bool &fanVerifiedOut) {
  fanVerifiedOut = false;
  if (isnan(tempC) || tempC < -10.0f || tempC > 250.0f) return SENSOR_FAULT;

  // Safety precedence: a valid critical thermocouple reading wins even if the
  // ambient sensor is unavailable.
  if (tempC >= CRITICAL_ABS_TEMP_C) return CRITICAL_OVERHEAT;
  if (!ambientOk) return SENSOR_FAULT;

  if (ir1 == IR1_BROKEN_LEVEL) {
    if (verifyTamperCorroborated(fsrValue)) return TAMPER;
    return POSSIBLE_TAMPER;
  }

  bool thermalConcern = (deviation > WARN_DEVIATION_C) || (riseRate > TEMP_RISE_RATE_WARN);
  if (!thermalConcern) return NORMAL;

#if FAN_DRIVER_ENABLED
  bool fanOk = verifyFanSpinning();
  fanVerifiedOut = fanOk;
  return fanOk ? THERMAL_WARNING : COOLING_FAILURE;
#else
  return THERMAL_WARNING;
#endif
}

void showDisplay(float tempC, float ambientC, float deviation, int health, int state, int load) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0,0);
  display.printf("Node %d HS:%d\n", NODE_ID, health);
  display.printf("T:%.1fC d:%+.1f\n", tempC, deviation);
  if (load >= 0) {
    display.printf("Amb:%.1fC L:%d%%\n", ambientC, load);
  } else {
    display.printf("Amb:%.1fC\n", ambientC);
  }
  display.printf("%s\n", outageMode ? "OUTAGE-BUFFERING" : "LINK OK");
  display.setTextSize(1);
  display.printf("FAN:%s\n", FAN_DRIVER_ENABLED ? "DIAGNOSTIC" : "DRIVER OFF");
  display.setTextSize(1);
  display.print(stateName(state));
  display.display();
}

void setup() {
  Serial.begin(115200);
  pinMode(IR1_PIN, INPUT);
  pinMode(IR2_PIN, INPUT);
  pinMode(FSR_PIN, INPUT);
#if LOAD_POT_ENABLED
  pinMode(LOAD_POT_PIN, INPUT);
#endif
  pinMode(LED_PIN, OUTPUT);
  pinMode(FAN_CTRL_PIN, OUTPUT);
  digitalWrite(FAN_CTRL_PIN, LOW);
  dht.begin();

  if (!LittleFS.begin(true)) Serial.println("ERROR: LittleFS mount failed.");

  Wire.begin(OLED_SDA, OLED_SCL);
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) Serial.println("WARNING: OLED init failed; continuing without display.");
  display.setTextColor(SSD1306_WHITE);

#if USE_DIRECT_WIFI
  Serial.printf("Direct Wi-Fi Mode: connecting to '%s'...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - t0 < 8000)) {
    delay(200);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nWi-Fi Connected! Node IP: %s\n", WiFi.localIP().toString().c_str());
    if (discoverBackend()) {
      Serial.printf("Auto-discovered backend at: %s:%d\n", backendHost().c_str(), BACKEND_PORT);
    } else {
      Serial.printf("UDP discovery silent; using target: %s:%d\n", backendHost().c_str(), BACKEND_PORT);
    }
  } else {
    Serial.println("\nWi-Fi not connected yet; node will buffer to LittleFS and retry in background.");
  }
#else
  if (!setGatewayChannel()) {
    Serial.println("WARNING: gateway channel not discovered. ESP-NOW may not work until the SSID is visible.");
  }
  if (esp_now_init() != ESP_OK) { Serial.println("FATAL: ESP-NOW init failed"); return; }
  if (esp_now_register_send_cb(onDataSent) != ESP_OK) Serial.println("FATAL: ESP-NOW send callback registration failed");

  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, broadcastAddress, 6);
  peerInfo.channel = 0; // current Wi-Fi channel, set above to the gateway AP channel
  peerInfo.encrypt = false;
  peerInfo.ifidx = WIFI_IF_STA;
  if (esp_now_add_peer(&peerInfo) != ESP_OK && !esp_now_is_peer_exist(broadcastAddress)) Serial.println("FATAL: failed to add ESP-NOW broadcast peer");
#endif

  Serial.printf("GridWatch Node %d ready. directWiFi=%d fanDriverEnabled=%d loadPotEnabled=%d\n", NODE_ID, USE_DIRECT_WIFI, FAN_DRIVER_ENABLED, LOAD_POT_ENABLED);
}

void loop() {
  float tempC = thermocouple.readCelsius();
  float ambientRaw = dht.readTemperature();
  bool ambientOk = !isnan(ambientRaw) && ambientRaw > -40.0f && ambientRaw < 85.0f;
  float ambientC = ambientOk ? ambientRaw : BASELINE_AMBIENT_C;

  unsigned long now = millis();
  float dtSec = lastReadMillis == 0 ? 0.0f : (now - lastReadMillis) / 1000.0f;
  float riseRate = (isnan(lastTempC) || dtSec <= 0.0f) ? 0.0f : (tempC - lastTempC) / dtSec;
  lastTempC = tempC;
  lastReadMillis = now;

  int loadPercent = -1;
  float loadRise = 0.0f;
#if LOAD_POT_ENABLED
  int rawLoad = analogRead(LOAD_POT_PIN);
  loadPercent = constrain(map(rawLoad, 0, 4095, 0, 100), 0, 100);
  loadRise = (loadPercent / 100.0f) * 15.0f;
#endif

  float expectedTemp = BASELINE_TEMP_C + AMBIENT_COEFF * max(0.0f, ambientC - BASELINE_AMBIENT_C) + loadRise;
  float deviation = tempC - expectedTemp;
  int ir1 = digitalRead(IR1_PIN);
  int ir2 = digitalRead(IR2_PIN);
  int fsrValue = analogRead(FSR_PIN);

  bool fanVerified = false;
  int state = classifyState(tempC, deviation, riseRate, ir1, fsrValue, ambientOk, fanVerified);
  int health = computeHealthScore(state, deviation, riseRate);
  digitalWrite(LED_PIN, (state != NORMAL && state != POSSIBLE_TAMPER) ? HIGH : LOW);
  digitalWrite(FAN_CTRL_PIN, LOW); // invariant when driver is unavailable

  showDisplay(tempC, ambientC, deviation, health, state, loadPercent);
  Serial.printf("seq=%lu,node=%d,T=%.2f,dev=%.2f,rise=%.2f,amb=%.2f,load=%d,ambOK=%d,ir1=%d,ir2=%d,fsr=%d,fan=%d,state=%d,health=%d,outage=%d\n",
    (unsigned long)nextSequenceId, NODE_ID, tempC, deviation, riseRate, ambientC, loadPercent, ambientOk, ir1, ir2, fsrValue, fanVerified, state, health, outageMode);

  struct_message msg = {};
  msg.version = 1;
  msg.sizeBytes = sizeof(struct_message);
  msg.sequenceId = nextSequenceId++;
  msg.nodeId = NODE_ID;
  msg.tempC = tempC;
  msg.tempRiseRate = riseRate;
  msg.ambientC = ambientC;
  msg.loadPercent = loadPercent;
  msg.ambientSensorOk = ambientOk ? 1 : 0;
  msg.ir1 = ir1;
  msg.ir2 = ir2;
  msg.fsrValue = fsrValue;
  msg.fanVerified = fanVerified ? 1 : 0;
  msg.fanDriverEnabled = FAN_DRIVER_ENABLED ? 1 : 0;
  msg.classification = state;
  msg.healthScore = health;
  msg.buffered = 0;
  msg.bufferedAgoMs = 0;

  bool delivered = sendAndAwaitResult(msg);
  if (delivered) {
    consecutiveFailures = 0;
    if (outageMode) {
      bool replayComplete = flushBuffer();
      outageMode = !replayComplete;
      if (!replayComplete) Serial.println("Replay still pending; will retry while link remains available.");
    }
  } else {
    consecutiveFailures++;
    outageMode = true;
    if (!appendBuffer(msg)) Serial.println("WARNING: failed to persist an outage reading.");
    trimBufferIfNeeded();
  }

  bool alarming = (state != NORMAL && state != POSSIBLE_TAMPER);
  delay(alarming ? SAMPLE_ALERT_MS : (outageMode ? SAMPLE_OUTAGE_MS : SAMPLE_NORMAL_MS));
}
