package com.gridwatch.controller;

import com.gridwatch.model.SensorReading;
import com.gridwatch.repository.SensorReadingRepository;
import com.gridwatch.service.LlmRouterService;
import com.gridwatch.service.RagService;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class InsightController {

    private final SensorReadingRepository repo;
    private final RagService ragService;
    private final LlmRouterService llmRouter;

    public InsightController(SensorReadingRepository repo, RagService ragService, LlmRouterService llmRouter) {
        this.repo = repo;
        this.ragService = ragService;
        this.llmRouter = llmRouter;
    }

    @GetMapping("/incident-report/{nodeId}")
    public Map<String, Object> latestReport(@PathVariable Integer nodeId) {
        SensorReading incident = repo.findTopByNodeIdAndClassificationNotOrderByCreatedAtDesc(nodeId, "NORMAL")
                .orElse(null);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("nodeId", String.valueOf(nodeId));
        if (incident == null) {
            out.put("report", null);
            out.put("provider", null);
            out.put("message", "No incident report available");
            return out;
        }

        if (isUsableReport(incident.getIncidentReport())) {
            out.put("report", incident.getIncidentReport());
            out.put("provider", incident.getReportProvider());
            return out;
        }

        try {
            RagService.Answer answer = ragService.generateIncidentReport(incident);
            incident.setIncidentReport(answer.text());
            incident.setReportProvider(answer.provider());
            repo.save(incident);
            out.put("report", answer.text());
            out.put("provider", answer.provider());
        } catch (Exception e) {
            out.put("report", null);
            out.put("provider", "unavailable");
            out.put("message", "Incident exists but an AI report is currently unavailable");
        }
        return out;
    }

    private static boolean isUsableReport(String report) {
        return report != null && !report.isBlank() && !"null".equalsIgnoreCase(report.trim());
    }

    @PostMapping("/ask")
    public Map<String, String> ask(@RequestBody Map<String, String> body) {
        String question = body.getOrDefault("question", "").trim();
        if (question.isBlank()) throw new IllegalArgumentException("question must not be blank");
        RagService.Answer answer = ragService.answerQuestion(question);
        return Map.of("question", question, "answer", answer.text(), "provider", answer.provider());
    }

    @GetMapping("/llm-status")
    public Map<String, Object> llmStatus() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("mode", llmRouter.currentMode());
        out.put("nvidiaKeyConfigured", llmRouter.nvidiaConfigured());
        out.put("embeddingProvider", llmRouter.embeddingProvider());
        out.put("lastGenerationProvider", llmRouter.lastGenerationProvider());
        return out;
    }

    @GetMapping("/health")
    public Map<String, Object> health() {
        return Map.of("status", "UP", "vectorStore", "loaded", "embeddingProvider", llmRouter.embeddingProvider());
    }
}
