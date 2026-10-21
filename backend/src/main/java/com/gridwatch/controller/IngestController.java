package com.gridwatch.controller;

import com.gridwatch.model.SensorReading;
import com.gridwatch.repository.SensorReadingRepository;
import com.gridwatch.service.RagService;
import org.springframework.scheduling.annotation.Async;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.List;

@RestController
@RequestMapping("/api/readings")
@CrossOrigin(origins = "*")
public class IngestController {

    private final SensorReadingRepository repo;
    private final RagService ragService;

    public IngestController(SensorReadingRepository repo, RagService ragService) {
        this.repo = repo;
        this.ragService = ragService;
    }

    // ── Ingest ─────────────────────────────────────────────────────────────────
    // Returns 200 immediately after persisting the reading.
    // RAG report generation happens in a background thread so the ESP32 never
    // waits on AI inference — this eliminates the HTTP -11 timeout during
    // buffered-replay bursts.
    @PostMapping
    public SensorReading ingest(@RequestBody SensorReading incoming) {
        if (incoming.getNodeId() == null || incoming.getNodeId() < 1)
            throw new IllegalArgumentException("nodeId must be positive");

        // Duplicate guard — idempotent replay support
        if (incoming.getSequenceId() != null) {
            SensorReading existing = repo
                    .findFirstByNodeIdAndSequenceId(incoming.getNodeId(), incoming.getSequenceId())
                    .orElse(null);
            if (existing != null) return existing;
        }

        if (incoming.getClassification() == null || incoming.getClassification().isBlank())
            incoming.setClassification("SENSOR_FAULT");
        if (incoming.getHealthScore() != null)
            incoming.setHealthScore(Math.max(0, Math.min(100, incoming.getHealthScore())));
        if (incoming.getCreatedAt() == null)
            incoming.setCreatedAt(Instant.now());

        SensorReading saved = repo.save(incoming);

        // Fire-and-forget: generate the AI report without blocking the HTTP response
        if (!"NORMAL".equals(saved.getClassification())) {
            generateReportAsync(saved.getId());
        } else {
            saved.setIncidentReport(null);
            saved.setReportProvider(null);
            repo.save(saved);
        }

        return saved;
    }

    /** Runs in Spring's task executor thread pool — never on the request thread. */
    @Async
    public void generateReportAsync(Long readingId) {
        SensorReading reading = repo.findById(readingId).orElse(null);
        if (reading == null) return;
        try {
            RagService.Answer answer = ragService.generateIncidentReport(reading);
            reading.setIncidentReport(answer.text());
            reading.setReportProvider(answer.provider());
        } catch (Exception e) {
            reading.setReportProvider("unavailable");
            System.err.println("[GridWatch] Incident AI unavailable; telemetry was persisted: " + e.getMessage());
        }
        repo.save(reading);
    }

    // ── Queries ────────────────────────────────────────────────────────────────

    /**
     * Returns up to 20 most-recent readings (includes buffered replays).
     * Used by the sparkline chart in the dashboard.
     */
    @GetMapping("/node/{nodeId}")
    public List<SensorReading> recentForNode(@PathVariable Integer nodeId) {
        return repo.findTop20ByNodeIdOrderByCreatedAtDesc(nodeId);
    }

    /**
     * Returns the single most-recent reading that arrived via a LIVE link
     * (buffered == false). This is what the dashboard status badge, health ring,
     * and KPI cards should display — it will never be stuck on an old replay.
     * Falls back to the absolute latest reading if no live reading exists yet.
     */
    @GetMapping("/node/{nodeId}/latest-live")
    public SensorReading latestLiveForNode(@PathVariable Integer nodeId) {
        return repo.findTopByNodeIdAndBufferedFalseOrderByCreatedAtDesc(nodeId)
                .or(() -> repo.findTopByNodeIdOrderByCreatedAtDesc(nodeId))
                .orElseThrow(() -> new RuntimeException("No readings for node " + nodeId));
    }
}
