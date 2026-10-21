#!/usr/bin/env bash
# GridWatch backend smoke test - simulates what the ESP8266 gateway sends,
# so you can verify the whole ingestion -> RAG -> report pipeline before
# any hardware is wired up. Run this AFTER `mvn spring-boot:run` is up.
#
# Usage: bash test-requests.sh [backend_host:port]
# Default host: localhost:8080

HOST="${1:-localhost:8080}"
BASE="http://$HOST/api"

hr() { echo "----------------------------------------------------------------"; }
post() { curl -s -X POST "$BASE$1" -H "Content-Type: application/json" -d "$2"; echo; }
get()  { curl -s "$BASE$1"; echo; }

echo "GridWatch backend smoke test against $BASE"
hr

echo "[1] NORMAL reading (should NOT trigger a RAG report - fast)"
post "/readings" '{
  "sequenceId": 1, "nodeId": 1, "tempC": 34.2, "tempRiseRate": 0.1, "ambientC": 28.0, "ir1": 1, "ir2": 1, "fsrValue": 300,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "NORMAL", "healthScore": 98,
  "buffered": false, "bufferedAgoMs": 0
}'
hr

echo "[2] COOLING_FAILURE (simulated backend event) - triggers a RAG report"
echo "    (this call will take a few seconds - it's actually calling the LLM)"
post "/readings" '{
  "sequenceId": 2, "nodeId": 1, "tempC": 79.5, "tempRiseRate": 2.1, "ambientC": 29.0, "ir1": 1, "ir2": 1, "fsrValue": 300,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "COOLING_FAILURE", "healthScore": 41,
  "buffered": false, "bufferedAgoMs": 0
}'
hr

echo "[3] THERMAL_WARNING (fan verified spinning, elevated temperature)"
post "/readings" '{
  "sequenceId": 3, "nodeId": 1, "tempC": 68.0, "tempRiseRate": 1.2, "ambientC": 31.0, "ir1": 1, "ir2": 1, "fsrValue": 300,
  "fanVerified": true, "fanDriverEnabled": true, "ambientSensorOk": true, "classification": "THERMAL_WARNING", "healthScore": 66,
  "buffered": false, "bufferedAgoMs": 0
}'
hr

echo "[4] POSSIBLE_TAMPER (IR1 broken, FSR did NOT corroborate - low confidence)"
post "/readings" '{
  "sequenceId": 4, "nodeId": 1, "tempC": 35.0, "tempRiseRate": 0.0, "ambientC": 30.0, "ir1": 0, "ir2": 1, "fsrValue": 200,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "POSSIBLE_TAMPER", "healthScore": 90,
  "buffered": false, "bufferedAgoMs": 0
}'
hr

echo "[5] TAMPER confirmed (IR1 broken AND FSR spike together)"
post "/readings" '{
  "sequenceId": 5, "nodeId": 1, "tempC": 35.2, "tempRiseRate": 0.0, "ambientC": 30.0, "ir1": 0, "ir2": 1, "fsrValue": 3100,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "TAMPER", "healthScore": 78,
  "buffered": false, "bufferedAgoMs": 0
}'
hr

echo "[6] SENSOR_FAULT (thermocouple disconnected - unrealistic reading)"
post "/readings" '{
  "sequenceId": 6, "nodeId": 1, "tempC": 999.0, "tempRiseRate": 0.0, "ambientC": 30.0, "ir1": 1, "ir2": 1, "fsrValue": 300,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "SENSOR_FAULT", "healthScore": 60,
  "buffered": false, "bufferedAgoMs": 0
}'
hr

echo "[7] Buffered/replayed event - simulates the physical node syncing after a 14-minute outage"
post "/readings" '{
  "sequenceId": 7, "nodeId": 1, "tempC": 81.0, "tempRiseRate": 1.8, "ambientC": 29.0, "ir1": 1, "ir2": 1, "fsrValue": 300,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "COOLING_FAILURE", "healthScore": 38,
  "buffered": true, "bufferedAgoMs": 840000
}'
hr

echo "[8] Recent readings for node 1"
get "/readings/node/1"
hr

echo "[9] Latest incident report for node 1 (should already be cached from step 2/7)"
get "/incident-report/1"
hr

echo "[10] Live Q&A - grounded in the maintenance SOP"
post "/ask" '{"question": "What should I do if the cooling fan does not spin up?"}'
hr

echo "[11] Which LLM provider is currently active"
get "/llm-status"
hr

echo "Done. Check the provider fields above to see whether NVIDIA (nvidia-cloud) or local Ollama (ollama-local) answered."
hr
echo "[12] Duplicate-ingestion guard (sequenceId 7 is already stored; backend should return the existing reading, not create another one)"
post "/readings" '{
  "sequenceId": 7, "nodeId": 1, "tempC": 81.0, "tempRiseRate": 1.8, "ambientC": 29.0, "ir1": 1, "ir2": 1, "fsrValue": 300,
  "fanVerified": false, "fanDriverEnabled": false, "ambientSensorOk": true, "classification": "COOLING_FAILURE", "healthScore": 38,
  "buffered": true, "bufferedAgoMs": 840000
}'
