# GridWatch Frontend Dashboard

A dependency-free browser dashboard for the final GridWatch physical build: one fully instrumented ESP32 node, one ESP8266 gateway, ThingSpeak telemetry, and the Spring Boot + RAG/LLM backend.

## Run

Start the backend first:

```bash
cd ../backend
mvn spring-boot:run
```

Then serve this folder with any static HTTP server. For example:

```bash
cd ../frontend
python3 -m http.server 5500
```

Open:

```text
http://localhost:5500
```

The dashboard assumes the backend is at `http://localhost:8080/api`.

To point it somewhere else before loading `app.js`, define:

```html
<script>
  window.GRIDWATCH_API_BASE = 'http://192.168.1.50:8080/api';
</script>
<script src="app.js"></script>
```

## API calls used

- `GET /api/readings/node/1`
- `GET /api/llm-status`
- `POST /api/ask`

Incident reports are read directly from each reading's `incidentReport` and `reportProvider` fields, so the dashboard mirrors the backend's current data model.
