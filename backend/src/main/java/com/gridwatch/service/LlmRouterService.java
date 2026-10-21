package com.gridwatch.service;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/** Routes generation to NVIDIA with local Ollama fallback while keeping the embedding provider stable. */
@Service
public class LlmRouterService {

    public record GenerationResult(String text, String provider) {}

    @Value("${llm.mode:nvidia-with-fallback}")
    private String mode;

    @Value("${llm.embedding-provider:auto}")
    private String embeddingMode;

    private final NvidiaNimService nvidia;
    private final OllamaService ollama;
    private volatile String selectedEmbeddingProvider = "ollama-local";
    private volatile String lastGenerationProvider = "unknown";

    public LlmRouterService(NvidiaNimService nvidia, OllamaService ollama) {
        this.nvidia = nvidia;
        this.ollama = ollama;
    }

    @PostConstruct
    void initializeEmbeddingProvider() {
        selectedEmbeddingProvider = switch (embeddingMode.toLowerCase()) {
            case "ollama", "ollama-only" -> "ollama-local";
            case "nvidia", "nvidia-only" -> {
                if (!nvidia.isConfigured() || !nvidia.probeEmbedding()) {
                    throw new IllegalStateException("NVIDIA embedding provider was explicitly selected but the API is not reachable. Set NVIDIA_API_KEY or use llm.embedding-provider=auto/ollama.");
                }
                yield "nvidia-cloud";
            }
            default -> {
                if (nvidia.isConfigured() && nvidia.probeEmbedding()) yield "nvidia-cloud";
                System.out.println("[LlmRouter] Using Ollama embeddings to keep the vector space stable.");
                yield "ollama-local";
            }
        };
        System.out.println("[LlmRouter] generation=" + mode + ", embeddings=" + selectedEmbeddingProvider);
    }

    public GenerationResult generate(String prompt) {
        if (useNvidiaFirst()) {
            try {
                String text = requireUsableText(nvidia.generate(prompt), nvidia.name());
                GenerationResult result = new GenerationResult(text, nvidia.name());
                lastGenerationProvider = result.provider();
                return result;
            } catch (Exception e) {
                if ("nvidia-only".equalsIgnoreCase(mode)) throw new RuntimeException(e);
                System.out.println("[LlmRouter] NVIDIA generation failed: " + e.getMessage() + " -> Ollama fallback");
            }
        }
        String text = requireUsableText(ollama.generate(prompt), ollama.name());
        GenerationResult result = new GenerationResult(text, ollama.name());
        lastGenerationProvider = result.provider();
        return result;
    }

    public float[] embedQuery(String text) {
        return embedStable(text, "query");
    }

    public float[] embedPassage(String text) {
        return embedStable(text, "passage");
    }

    private float[] embedStable(String text, String inputType) {
        if ("nvidia-cloud".equals(selectedEmbeddingProvider)) return nvidia.embed(text, inputType);
        return ollama.embed(text, inputType);
    }

    private boolean useNvidiaFirst() {
        return !"ollama-only".equalsIgnoreCase(mode) && nvidia.isConfigured();
    }

    private static String requireUsableText(String text, String provider) {
        if (text == null || text.isBlank() || "null".equalsIgnoreCase(text.trim())) {
            throw new IllegalStateException(provider + " returned an empty/invalid generation response");
        }
        return text.trim();
    }

    public String currentMode() { return mode; }
    public boolean nvidiaConfigured() { return nvidia.isConfigured(); }
    public String embeddingProvider() { return selectedEmbeddingProvider; }
    public String lastGenerationProvider() { return lastGenerationProvider; }
}
