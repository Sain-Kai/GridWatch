package com.gridwatch.service;

import com.gridwatch.model.SensorReading;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class RagService {

    public record Answer(String text, String provider) {}

    private final VectorStore vectorStore;
    private final LlmRouterService llm;

    public RagService(VectorStore vectorStore, LlmRouterService llm) {
        this.vectorStore = vectorStore;
        this.llm = llm;
    }

    public Answer generateIncidentReport(SensorReading r) {
        String loadText = (r.getLoadPercent() == null || r.getLoadPercent() < 0)
                ? "not measured in the final hardware build"
                : String.format("%d%%", r.getLoadPercent());
        String situation = String.format(
                "Transformer node %d | classification=%s | health score=%d/100 | temperature=%.1fC | rise rate=%.2fC/s | ambient=%.1fC (sensor=%s) | electrical load=%s | fan verified spinning=%s | fan diagnostic driver enabled=%s | ir1=%d | ir2=%d | fsr=%d",
                r.getNodeId(), r.getClassification(), r.getHealthScore(), safe(r.getTempC()), safe(r.getTempRiseRate()),
                safe(r.getAmbientC()), Boolean.TRUE.equals(r.getAmbientSensorOk()), loadText,
                Boolean.TRUE.equals(r.getFanVerified()), Boolean.TRUE.equals(r.getFanDriverEnabled()),
                safeInt(r.getIr1()), safeInt(r.getIr2()), safeInt(r.getFsrValue()));

        if (Boolean.TRUE.equals(r.getBuffered()) && r.getBufferedAgoMs() != null) {
            long minutesAgo = r.getBufferedAgoMs() / 60000;
            situation += String.format(". This event was captured during a network outage and reached the backend approximately %d minute(s) later.", minutesAgo);
        }

        String contextText = vectorStore.topK(situation, 3).stream()
                .map(c -> "[" + c.source() + "]\n" + c.text())
                .collect(Collectors.joining("\n---\n"));

        String prompt = """
            You are GridWatch's utility infrastructure monitoring assistant.
            Use ONLY the maintenance guideline excerpts supplied below. Do not
            invent procedures, load percentages, sensor values, or safety limits.
            The classification comes from on-device sensor-fusion logic. Explain
            what the classification means using the evidence in the reading.
            IMPORTANT: when fan diagnostic driver is disabled, do not claim that
            a fan spin test was performed; state that cooling verification is not
            currently available in this hardware configuration. When the ambient
            sensor is invalid, do not treat its value as trustworthy. When a reading
            was buffered, make its delayed arrival explicit. Keep the report to 3-5
            sentences and name the relevant guideline section when the excerpts
            identify one. If the excerpts do not cover the requested procedure,
            say so plainly.

            GUIDELINE EXCERPTS:
            %s

            SENSOR READING:
            %s

            INCIDENT REPORT:
            """.formatted(contextText, situation);

        LlmRouterService.GenerationResult result = llm.generate(prompt);
        return new Answer(result.text(), result.provider());
    }

    public Answer answerQuestion(String question) {
        List<VectorStore.Chunk> context = vectorStore.topK(question, 3);
        String contextText = context.stream()
                .map(c -> "[" + c.source() + "]\n" + c.text())
                .collect(Collectors.joining("\n---\n"));

        String prompt = """
            Answer the user's question using ONLY the guideline excerpts below.
            Keep the answer to 2-4 sentences. Do not use general-world knowledge
            to fill gaps. If the excerpts do not contain the answer, say that the
            GridWatch knowledge base does not contain that procedure.

            GUIDELINE EXCERPTS:
            %s

            QUESTION: %s

            ANSWER:
            """.formatted(contextText, question);

        LlmRouterService.GenerationResult result = llm.generate(prompt);
        return new Answer(result.text(), result.provider());
    }

    private static double safe(Double v) { return v == null ? 0.0 : v; }
    private static int safeInt(Integer v) { return v == null ? -1 : v; }
}
