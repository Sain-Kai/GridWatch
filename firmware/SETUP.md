# GridWatch Firmware Setup

## ESP32 DevKit (Single-Board Direct Wi-Fi Architecture)

With **`#define USE_DIRECT_WIFI 1`**, the ESP8266 gateway is **not required**. The ESP32 connects directly to Wi-Fi and sends telemetry straight to the Spring Boot backend (`http://<LAPTOP_LAN_IP>:8080/api/readings`).

In Arduino IDE:

1. Select **Tools > Board > esp32 > ESP32 Dev Module**.
2. Select your USB Port (`/dev/ttyUSB0` or `/dev/ttyACM0`).
3. Open `firmware/esp32_node/esp32_node.ino`.
4. Configure your network credentials at the top of the file:
   ```cpp
   #define USE_DIRECT_WIFI 1
   #define WIFI_SSID "Sain"
   #define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
   #define BACKEND_HOST "172.16.36.163"   // Laptop LAN IP
   #define BACKEND_PORT 8080
   #define BACKEND_PATH "/api/readings"
   ```
5. Choose your hardware options:
   * `FAN_DRIVER_ENABLED`: set to `1` if the transistor & fan are connected, `0` if testing without fan.
   * `LOAD_POT_ENABLED`: set to `1` if potentiometer is wired to GPIO35, `0` if not.
6. Click **Upload**.
7. Open Serial Monitor at `115200 baud`. The node will connect to Wi-Fi and begin streaming readings directly to the Spring Boot backend!

---

## (Optional) Legacy Dual-Tier Mode (with ESP8266 Gateway)

If you ever wish to use the two-board architecture with the ESP8266 acting as an ESP-NOW bridge:
1. In `esp32_node.ino`, set `#define USE_DIRECT_WIFI 0`.
2. Flash `esp8266_gateway.ino` to the NodeMCU ESP8266 with `secrets.h` configured.
3. Node will broadcast via ESP-NOW to the ESP8266 gateway.
