# GridWatch MATLAB Digital Twin (Mode 1)

This folder provides a MATLAB-based simulation of the **ESP32 sensor node + ESP8266 gateway** while keeping the real GridWatch backend, H2 database, RAG pipeline, NVIDIA NIM, and browser dashboard unchanged.

## Architecture

```text
MATLAB digital twin
  ├─ ESP32 sensor model
  │    ├─ MAX6675 temperature
  │    ├─ DHT11 ambient
  │    ├─ FSR tamper/load proxy
  │    ├─ IR1 tamper beam
  │    └─ IR2 fan rotation
  │
  ├─ ESP-NOW loss model + node buffer
  └─ ESP8266 gateway queue model
           │
           │ HTTP JSON
           ▼
   Spring Boot :8080
      ├─ H2
      ├─ RAG / SOP
      └─ NVIDIA NIM → Ollama fallback
           │
           ▼
   Browser dashboard :5500
```

## Prerequisites

1. Start the GridWatch backend first.
2. MATLAB with `webread` / `webwrite` support.
3. No Simulink or Wokwi is required for this Mode 1 implementation.

## Launch

From MATLAB:

```matlab
cd('/path/to/GridWatch/matlab')
addpath(genpath(pwd))
gridwatch_simulator
```

The GUI defaults to:

```text
Backend URL: http://localhost:8080
Node ID:     1
Interval:    1 second
Packet loss: 0%
```

Use the scenario dropdown to run:

- NORMAL
- THERMAL_WARNING
- COOLING_FAILURE
- CRITICAL_OVERHEAT
- POSSIBLE_TAMPER
- TAMPER
- SENSOR_FAULT

`Backend reachable = OFF` simulates the ESP8266 gateway buffering records while the laptop backend is unavailable. Turning it back ON causes queued records to replay.

`ESP-NOW packet loss (%)` models radio delivery failures; failed samples remain in the MATLAB ESP32 node buffer until a later successful delivery.

The MATLAB HTTP adapter omits empty optional scalar fields instead of sending JSON `[]`, preventing type-mismatch errors in Spring/Jackson. The COOLING_FAILURE scenario enables the **simulated** fan diagnostic flag so that the diagnostic state can be demonstrated even though the physical fan driver remains disabled in the current hardware build.

## Full backend integration test

With Spring Boot running:

```matlab
cd('/home/USERNAME/Prototype/GridWatch/matlab')
addpath(genpath(pwd))
results = gridwatch_smoke_test('http://localhost:8080');
```

The smoke test checks:

1. `/api/health`
2. `/api/llm-status`
3. all major GridWatch classifications
4. database ingestion
5. duplicate sequence protection
6. incident report generation
7. RAG Q&A
8. actual NVIDIA/Ollama provider routing through the real backend

## ThingSpeak

The main simulator intentionally does **not** write to the production ThingSpeak channel by default. This prevents an accidental flood of test samples and respects the project's production telemetry separation.

The simulated gateway behavior is still represented in the model. If ThingSpeak testing is required later, it should be added as a separate explicit opt-in test using the environment variable:

```text
GRIDWATCH_THINGSPEAK_WRITE_KEY
```

## Interpretation

Mode 1 validates the application-level system end-to-end. It does not prove physical GPIO/electrical wiring, actual ESP-NOW RF behavior, or sensor calibration. Those remain hardware validation tasks.
