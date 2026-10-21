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

/** Local Ollama generation + embedding provider. */
@Service
public class OllamaService implements LlmProvider {

    @Value("${ollama.base-url:http://localhost:11434}")
    private String baseUrl;

    @Value("${ollama.embed-model:nomic-embed-text}")
    private String embedModel;

    @Value("${ollama.chat-model:phi3}")
    private String chatModel;

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(3))
            .build();
    private final ObjectMapper mapper = new ObjectMapper();

    @Override
    public float[] embed(String text, String inputType) {
        try {
            String body = mapper.writeValueAsString(new EmbedRequest(embedModel, text, true));
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(trimBase(baseUrl) + "/api/embed"))
                    .timeout(Duration.ofSeconds(20))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() / 100 != 2) {
                throw new RuntimeException("Ollama embeddings HTTP " + resp.statusCode() + ": " + resp.body());
            }
            JsonNode arr = mapper.readTree(resp.body()).path("embeddings").path(0);
            if (!arr.isArray() || arr.isEmpty()) {
                throw new RuntimeException("Ollama returned no embedding");
            }
            return toFloatArray(arr);
        } catch (Exception e) {
            throw new RuntimeException("Ollama embedding call failed - is `ollama serve` running and model pulled?", e);
        }
    }

    @Override
    public String generate(String prompt) {
        try {
            String body = mapper.writeValueAsString(new GenerateRequest(chatModel, prompt, false));
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(trimBase(baseUrl) + "/api/generate"))
                    .timeout(Duration.ofSeconds(60))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (resp.statusCode() / 100 != 2) {
                throw new RuntimeException("Ollama generation HTTP " + resp.statusCode() + ": " + resp.body());
            }
            JsonNode responseText = mapper.readTree(resp.body()).path("response");
            if (responseText.isMissingNode() || responseText.asText().isBlank()) {
                throw new RuntimeException("Ollama returned an empty response");
            }
            return responseText.asText();
        } catch (Exception e) {
            throw new RuntimeException("Ollama generate call failed - is `ollama serve` running and model pulled?", e);
        }
    }

    @Override
    public String name() { return "ollama-local"; }

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

    record EmbedRequest(String model, String input, boolean truncate) {}
    record GenerateRequest(String model, String prompt, boolean stream) {}
}
