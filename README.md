# GridWatch — Transformer Guardian

GridWatch is a two-layer resilient monitoring system:

**ESP32 DevKit sensor node → ESP-NOW → NodeMCU ESP8266 gateway → Spring Boot → H2 + RAG → NVIDIA NIM / Ollama → browser dashboard**

The final hardware inventory intentionally does **not** include a transistor/MOSFET driver yet. The fan-control path is therefore disabled in firmware until that component is added; GPIO16 is held LOW and no fan-drive voltage is produced by the ESP32.

## What is fixed in this release

### ESP32
- Current Arduino-ESP32 ESP-NOW send-callback signature.
- Automatic scan for the `Sain` Wi-Fi AP and selection of its 2.4 GHz channel, so the hotspot channel does not need to be hard-coded.
- Versioned/packed ESP-NOW packet with sequence number.
- Safety-first classification precedence: valid critical thermocouple temperature wins over tamper; invalid ambient sensor becomes `SENSOR_FAULT` below the critical ceiling.
- Safe fan-driver gate: `FAN_DRIVER_ENABLED=0` for the current hardware.
- Transactional LittleFS outage buffering. Failed replay items are retained; successfully replayed items are removed.
- Bounded outage buffer.

### ESP8266 gateway
- NodeMCU ESP8266 receives and validates the versioned packet.
- Persistent LittleFS gateway queue survives backend outages and gateway reboot.
- Backend data is removed from the gateway queue only after a 2xx response.
- Duplicate sequence IDs are safely ignored by the backend.
- ThingSpeak is sent over HTTPS and limited to one update every 15 seconds for a free channel.
- Buffered outage records are kept in the backend but not re-sent to ThingSpeak as historical replay points.

### Backend / RAG / AI
- NVIDIA hosted endpoint: `https://integrate.api.nvidia.com/v1`.
- Default NVIDIA generation model: `openai/gpt-oss-20b`.
- Default NVIDIA embedding model: `nvidia/llama-3.2-nv-embedqa-1b-v2`.
- Embeddings are stable: `auto` probes NVIDIA once at startup and then locks the application to either NVIDIA embeddings or Ollama embeddings. It never switches embedding spaces mid-run.
- NVIDIA embeddings use `passage` for knowledge-base indexing and `query` for retrieval.
- Ollama embeddings use the current `/api/embed` endpoint.
- NVIDIA generation automatically falls back to local Ollama when configured for `nvidia-with-fallback`; invalid/empty NVIDIA responses also trigger the fallback.
- Telemetry ingestion is never lost just because both AI providers are temporarily unavailable; the reading remains persisted and its report can be generated later.
- Incident-report lookup correctly chooses the newest non-normal event instead of blindly using the newest normal reading.
- `/api/health` and `/api/llm-status` expose actual provider configuration/selection.
- A small UDP discovery responder lets the ESP8266 discover the laptop backend address automatically; the laptop IP does not need to be hard-coded.

## Current deployment values

```text
Wi-Fi SSID: Sain
ThingSpeak Channel ID: 3477485
ThingSpeak write key: stored locally only; do not commit it
ESP32 board: ESP32 DevKit
Gateway board: NodeMCU ESP8266
```

The Wi-Fi password, NVIDIA API key and ThingSpeak write key are deliberately not stored in this repository/archive.

## 1. Linux software prerequisites

```bash
sudo apt update
sudo apt install -y openjdk-17-jdk maven python3 curl
```

Java 21 also works with the current project.

Install Ollama from the official installer if it is not already installed. The backend only needs Ollama as the local generation/embedding fallback.

Pull the local models:

```bash
ollama pull nomic-embed-text
ollama pull phi3
```

Start it if it is not already running:

```bash
ollama serve
```

## 2. Backend configuration

```bash
cd backend
cp .env.example .env
nano .env
```

Put the NVIDIA key in `.env`:

```bash
export NVIDIA_API_KEY="nvapi-..."
```

Do not put the key into `application.properties` or commit `.env`.

By default:

```text
Generation: NVIDIA first → Ollama fallback
Embeddings: NVIDIA if a startup probe succeeds → otherwise Ollama
```

For fully local operation:

```bash
export LLM_MODE=ollama-only
export LLM_EMBEDDING_PROVIDER=ollama
```

For a strict NVIDIA test:

```bash
export LLM_MODE=nvidia-only
export LLM_EMBEDDING_PROVIDER=nvidia
```

## 3. Start backend

From the project root:

```bash
./run-backend.sh
```

Or manually:

```bash
cd backend
source .env
mvn spring-boot:run
```

The backend is available at:

```text
http://localhost:8080
```

Health check:

```bash
curl http://localhost:8080/api/health
curl http://localhost:8080/api/llm-status
```

On startup, look for:

```text
VectorStore: loaded ... chunks ... using ...
```

That confirms the SOP has been embedded successfully.

## 4. Test backend before hardware

```bash
cd backend
bash test-requests.sh
```

This exercises normal telemetry, all fault classes, buffered replay, incident reporting, grounded Q&A and LLM status.

## 5. Start dashboard

```bash
./run-frontend.sh
```

Open:

```text
http://localhost:5500
```

The dashboard expects the backend at `http://localhost:8080/api`.

## 6. ESP8266 gateway configuration

Copy the template:

```bash
cd firmware/esp8266_gateway
cp secrets.h.example secrets.h
nano secrets.h
```

Set:

```cpp
#define GW_WIFI_SSID "Sain"
#define GW_WIFI_PASSWORD "YOUR_REAL_WIFI_PASSWORD"
#define GW_BACKEND_HOST ""
#define GW_BACKEND_PORT 8080
#define GW_DISCOVERY_PORT 30303
#define GW_THINGSPEAK_WRITE_KEY "YOUR_THINGSPEAK_WRITE_KEY"
```

`GW_BACKEND_HOST` is only a fallback. Normally the ESP8266 asks the GridWatch backend over UDP and learns the laptop's current hotspot IP automatically, so reconnecting the phone hotspot does not require a firmware edit.

The gateway prints its Wi-Fi channel. The ESP32 independently scans for `Sain` and locks to the same 2.4 GHz AP channel.

## 7. ESP32 configuration

The current firmware already contains:

```cpp
#define NODE_ID 1
#define GATEWAY_SSID "Sain"
#define FAN_DRIVER_ENABLED 0
```

Upload `firmware/esp32_node/esp32_node.ino` to the ESP32 DevKit.

The sensor pins are documented in `docs/FINAL_HARDWARE.md`.

## 8. Fan hardware is intentionally on hold

There is currently no transistor/MOSFET driver, so the firmware is safe with:

```cpp
#define FAN_DRIVER_ENABLED 0
```

Thermal events are therefore reported as `THERMAL_WARNING` based on the temperature model and rise rate, but the system explicitly states that an active fan-rotation verification was not performed.

After a proper external driver is installed, set:

```cpp
#define FAN_DRIVER_ENABLED 1
```

and then the thermal diagnostic path becomes:

```text
thermal concern → fan ON → IR2 rotation evidence →
  rotation confirmed  → THERMAL_WARNING
  rotation absent     → COOLING_FAILURE
```

Never connect the fan directly to GPIO16.

## 9. Final end-to-end test

1. Start Ollama.
2. Start the Spring Boot backend.
3. Confirm `VectorStore` loaded.
4. Run `backend/test-requests.sh`.
5. Start the frontend.
6. Flash ESP8266 gateway.
7. Flash ESP32 Node 1.
8. Confirm both devices are on the same 2.4 GHz channel.
9. Verify normal readings reach `/api/readings/node/1`.
10. Block IR1 → `POSSIBLE_TAMPER`.
11. Block IR1 and press the FSR → `TAMPER`.
12. Heat the thermocouple → thermal alert.
13. Disconnect the gateway → ESP32 enters outage buffering.
14. Restore gateway → gateway/backend queues replay buffered events exactly once.
15. Ask the dashboard AI a question → answer is grounded in the bundled SOP.
16. With NVIDIA available, generated text should report `nvidia-cloud`.
17. With NVIDIA unavailable, generation should fall back to `ollama-local` while the embedding provider remains unchanged for the running process.

## 10. Network/firewall

If the ESP8266 can join `Sain` but cannot reach the laptop:

```bash
sudo ufw allow 8080/tcp
```

Check the backend locally first:

```bash
curl http://localhost:8080/api/health
```

Then test from another device on the LAN using the laptop's LAN IP:

```bash
curl http://YOUR_LAPTOP_LAN_IP:8080/api/health
```

## 11. Secrets and generated files

The following are intentionally ignored:

```text
backend/.env
firmware/esp8266_gateway/secrets.h
backend/target/
backend/*.mv.db
```

Do not upload real Wi-Fi passwords, NVIDIA keys or ThingSpeak write keys to GitHub or a public submission archive.

## MATLAB Simulation (Mode 1)

For a complete hardware-side digital simulation without Wokwi, use the MATLAB digital twin in `matlab/`.

Start the real backend on port 8080, then from MATLAB run:

```matlab
cd('/path/to/GridWatch/matlab')
addpath(genpath(pwd))
gridwatch_simulator
```

For an automated backend integration test:

```matlab
results = gridwatch_smoke_test('http://localhost:8080');
```

The simulator models the ESP32 sensor values, ESP-NOW packet loss, ESP32 outage buffering, ESP8266 gateway buffering/replay, and sends telemetry to the real GridWatch backend. See `matlab/README.md` for details.
