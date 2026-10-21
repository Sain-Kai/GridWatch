package com.gridwatch.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/** NVIDIA hosted OpenAI-compatible API provider. */
@Service
public class NvidiaNimService implements LlmProvider {

    @Value("${nvidia.api-key:}")
    private String apiKey;

    @Value("${nvidia.base-url:https://integrate.api.nvidia.com/v1}")
    private String baseUrl;

    @Value("${nvidia.chat-model:openai/gpt-oss-20b}")
    private String chatModel;

    @Value("${nvidia.embed-model:nvidia/llama-3.2-nv-embedqa-1b-v2}")
    private String embedModel;

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();
    private final ObjectMapper mapper = new ObjectMapper();

    public boolean isConfigured() { return apiKey != null && !apiKey.isBlank(); }

    @Override
    public float[] embed(String text, String inputType) {
        requireConfigured();
        if (!"query".equals(inputType) && !"passage".equals(inputType)) {
            throw new IllegalArgumentException("NVIDIA embedding inputType must be query or passage");
        }
        try {
            String body = mapper.writeValueAsString(new EmbedRequest(
                    embedModel, List.of(text), inputType, "float", "END"));
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(trimBase(baseUrl) + "/embeddings"))
                    .timeout(Duration.ofSeconds(12))
                    .header("Authorization", "Bearer " + apiKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() / 100 != 2) {
                throw new RuntimeException("NVIDIA embeddings HTTP " + resp.statusCode() + ": " + safeBody(resp.body()));
            }
            JsonNode arr = mapper.readTree(resp.body()).path("data").path(0).path("embedding");
            if (!arr.isArray() || arr.isEmpty()) {
                throw new RuntimeException("NVIDIA returned no embedding");
            }
            return toFloatArray(arr);
        } catch (Exception e) {
            throw new RuntimeException("NVIDIA NIM embedding call failed: " + e.getMessage(), e);
        }
    }

    /** One small request used only at startup to select a stable embedding provider. */
    public boolean probeEmbedding() {
        if (!isConfigured()) return false;
        try {
            float[] vector = embed("GridWatch embedding health check", "query");
            return vector.length > 0;
        } catch (Exception e) {
            System.out.println("[NVIDIA] embedding probe failed: " + e.getMessage());
            return false;
        }
    }

    @Override
    public String generate(String prompt) {
        requireConfigured();
        try {
            String body = mapper.writeValueAsString(new ChatRequest(
                    chatModel, List.of(new ChatMessage("user", prompt)), 0.2, 4096, 0.95, false, "low"));
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(trimBase(baseUrl) + "/chat/completions"))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + apiKey)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() / 100 != 2) {
                throw new RuntimeException("NVIDIA chat HTTP " + resp.statusCode() + ": " + safeBody(resp.body()));
            }
            JsonNode root = mapper.readTree(resp.body());
            JsonNode choices = root.path("choices");
            if (!choices.isArray() || choices.isEmpty()) {
                throw new RuntimeException("NVIDIA returned no choices: " + safeBody(resp.body()));
            }
            JsonNode message = choices.get(0).path("message");
            JsonNode content = message.path("content");
            // GPT-OSS may expose internal reasoning separately. Never surface
            // reasoning content as the user-facing answer; require a final text
            // message and fall back cleanly if the endpoint returns only null.
            if (!content.isTextual() || content.asText().isBlank()) {
                throw new RuntimeException("NVIDIA returned no final message content: " + safeBody(resp.body()));
            }
            String answer = content.asText().trim();
            if (answer.equalsIgnoreCase("null")) {
                throw new RuntimeException("NVIDIA returned the literal null as final content: " + safeBody(resp.body()));
            }
            return answer;
        } catch (Exception e) {
            throw new RuntimeException("NVIDIA NIM chat call failed: " + e.getMessage(), e);
        }
    }

    @Override
    public String name() { return "nvidia-cloud"; }

    private void requireConfigured() {
        if (!isConfigured()) throw new IllegalStateException("NVIDIA_API_KEY not set");
    }

    private static float[] toFloatArray(JsonNode arr) {
        List<Float> values = new ArrayList<>(arr.size());
        for (JsonNode v : arr) values.add((float) v.asDouble());
        float[] out = new float[values.size()];
        for (int i = 0; i < out.length; i++) out[i] = values.get(i);
        return out;
    }

    private static String trimBase(String value) {
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private static String safeBody(String body) {
        return body == null ? "" : (body.length() > 500 ? body.substring(0, 500) + "..." : body);
    }

    record ChatMessage(String role, String content) {}
    record ChatRequest(String model, List<ChatMessage> messages, double temperature, int max_tokens, double top_p, boolean stream, String reasoning_effort) {}
    record EmbedRequest(String model, List<String> input, String input_type, String encoding_format, String truncate) {}
}
