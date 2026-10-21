# GridWatch

Real-time grid monitoring with local LLM insights.

GridWatch is a comprehensive IoT and AI platform that ingests power grid sensor data and diagnoses hardware anomalies. It combines physical ESP32/ESP8266 microcontrollers, a Java Spring Boot backend, and a Retrieval-Augmented Generation (RAG) pipeline powered by local LLMs (Ollama) and cloud APIs (Nvidia NIM) to evaluate sensor readings against standard operating procedures.

```bash
$ ./run-backend.sh
  GridWatch v1.0.0 · Spring Boot Ingest API · VectorStore Active
  ✓ ready on port 8080 · H2 Database connected
```

## Get started in one step

You need a machine with Java 17+, Node.js (optional, for frontend tooling), MATLAB (for simulations), and Arduino IDE (for firmware).

### Linux / macOS

```bash
git clone https://github.com/yourusername/GridWatch
cd GridWatch
./configure.sh
./run-backend.sh
```

### Windows (via Git Bash or WSL)

```bash
./configure.sh
./run-backend.sh
```

Then, in a new terminal, launch the client interface:

```bash
./run-frontend.sh
```

What the setup does, in detail:

1. Configures environments: creates `.env` and `backend/.env` from `backend/.env.example`.
2. Starts the backend: initializes the Spring Boot application (`GridwatchApplication.java`) and the local H2 database (`gridwatch-db.mv.db`).
3. Loads the knowledge base: ingests `transformer_maintenance_sop.md` into the in-memory `VectorStore.java` for RAG-based diagnostics.
4. Starts the frontend: serves `app.js`, `styles.css`, and `index.html` on a local development server.

## What GridWatch is, and why

Power grids require constant telemetry, but interpreting that telemetry against maintenance manuals is traditionally a manual task. GridWatch automates it.

Sensor readings (voltage, temperature, load) are ingested from edge devices. When an anomaly is detected, `InsightController.java` triggers `LlmRouterService.java`. The router decides whether to process the diagnostic request locally via `OllamaService.java` or route it to a larger cloud model via `NvidiaNimService.java`. The prompt is augmented by `RagService.java`, which retrieves relevant sections of `transformer_maintenance_sop.md` from the embedded `VectorStore.java`.

## Component matrix

| Subsystem | Primary Technology | Directory | Function |
| --- | --- | --- | --- |
| Backend API | Java, Spring Boot, Maven | `backend/src/main/java/com/gridwatch/` | Ingests data via `IngestController.java`, queries the DB via `SensorReadingRepository.java`, and routes AI requests |
| Frontend | HTML5, CSS3, Vanilla JS | `frontend/` | Visualizes telemetry and AI diagnostics through `app.js` and `styles.css` |
| Firmware | C++, Arduino Core | `firmware/` | Collects edge data via `esp32_node.ino` and bridges to the backend via `esp8266_gateway.ino` |
| Simulation | MATLAB | `matlab/` | Tests system loads using `gridwatch_simulator.m` and `gridwatch_model_step.m` |

## How it works

Every telemetry packet walks the same steps: sense, ingest, retrieve, and evaluate.

```text
ESP32 node ──RF/WiFi──▶ ESP8266 gateway ──JSON POST──▶ IngestController
                                                            │
                                                     SensorReadingRepository (H2)
                                                            │
Frontend ──diagnose──▶ InsightController ──▶ LlmRouterService
                                                  │
                          VectorStore (SOP chunks) + RagService
                                                  │
                                  ┌───────────────┴───────────────┐
                              OllamaService                NvidiaNimService
                               (local LLM)                   (cloud LLM)
```

- Edge collection: ESP32 nodes (`esp32_node/esp32_node.ino`) collect raw analog data and transmit it over local RF/WiFi to the ESP8266 gateway (`esp8266_gateway/esp8266_gateway.ino`).
- Ingestion and persistence: the gateway formats the data into JSON and posts it to `IngestController.java`. The `SensorReading.java` model maps this data, and `SensorReadingRepository.java` persists it to the `gridwatch-db.mv.db` database.
- RAG and routing: users request diagnostics through the frontend. `LlmRouterService.java` evaluates the request complexity and queries `VectorStore.java` to find relevant text chunks (represented by `VectorStore$Chunk.class` and `VectorStore$ScoredChunk.class`) from the maintenance SOP.
- LLM generation: the system dispatches the prompt and the retrieved context to either `NvidiaNimService` (`EmbedRequest`, `ChatRequest`) or `OllamaService` (`GenerateRequest`).
- Simulation fallback: if physical hardware is unavailable, `matlab/gridwatch_simulator.m` and `gridwatch_post_reading.m` inject synthetic data into the backend.

## Repo layout

```text
GridWatch/
├── backend/                       # Spring Boot application
│   ├── pom.xml                    # Maven dependencies
│   ├── gridwatch-db.mv.db         # Local H2 database file
│   └── src/main/
│       ├── resources/knowledge/   # RAG documents (transformer_maintenance_sop.md)
│       └── java/com/gridwatch/
│           ├── controller/        # REST APIs (IngestController, InsightController)
│           ├── model/             # Data entities (SensorReading.java)
│           ├── repository/        # DB interfaces (SensorReadingRepository.java)
│           └── service/           # LLM and RAG logic (Ollama, NvidiaNim, VectorStore)
├── firmware/                      # Edge device code
│   ├── esp32_node/                # Sensor node logic
│   └── esp8266_gateway/           # Network bridge logic
├── frontend/                      # Web dashboard
│   ├── index.html                 # UI layout
│   ├── app.js                     # Client-side API fetching
│   └── styles.css                 # UI styling
├── matlab/                        # Simulation environment
│   ├── gridwatch_simulator.m      # Main simulation runner
│   └── gridwatch_smoke_test.m     # End-to-end integration tests
└── docs/                          # Architecture diagrams (system_diagram.png)
```

## Hosting and deployment

To move GridWatch from a local environment to a production-ready hosted setup, decouple the database, containerize the backend, and distribute the static frontend.

### 1. The backend (Spring Boot and LLM services)

The Java backend (`GridwatchApplication.java`) handles API traffic and LLM routing.

- Containerization: create a `Dockerfile` in `backend/` using an Eclipse Temurin JDK 17 base image. Run `mvn clean package` to generate the `.jar` in `backend/target/` and copy it into the container.
- Hosting provider: deploy the Docker image to AWS Elastic Container Service (ECS), DigitalOcean App Platform, or Google Cloud Run.
- Environment variables: map the production API keys (for example, Nvidia NIM keys) in the host environment, replacing the local `backend/.env` file.

### 2. The database (migrating from H2)

The repository currently uses a local H2 file database (`gridwatch-db.mv.db`).

- Production setup: provision a managed PostgreSQL or MySQL instance (for example, AWS RDS, Supabase, or DigitalOcean Managed Databases).
- Configuration: update `backend/src/main/resources/application.properties` to replace the H2 JDBC URL with the production database URL, credentials, and dialect.

### 3. The frontend (static hosting)

The `frontend/` directory consists entirely of static assets (`index.html`, `app.js`, `styles.css`).

- Hosting: deploy this directory to Vercel, Netlify, GitHub Pages, or an AWS S3 bucket configured for static website hosting with a CloudFront CDN.
- API connection: modify `app.js` so its `fetch()` calls point to the production URL of your hosted Spring Boot backend, and make sure CORS is properly configured in the Spring Boot application.

### 4. The edge devices and firmware

The microcontrollers must be updated to route traffic over the public internet instead of a local network.

- Gateway configuration: in `firmware/esp8266_gateway/secrets.h`, update the WiFi credentials to the deployment site's network.
- Endpoint update: modify `esp8266_gateway.ino` to point the HTTP POST requests to your production backend domain (for example, `https://api.yourdomain.com/ingest`) instead of `localhost`. Make sure the ESP8266 uses HTTPS/TLS libraries to secure the telemetry in transit.
