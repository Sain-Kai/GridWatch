package com.gridwatch.service;

import jakarta.annotation.PostConstruct;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

/** Small in-memory vector store for the bundled SOP corpus. */
@Component
public class VectorStore {

    public record Chunk(String source, String text, float[] embedding) {}

    private final List<Chunk> chunks = new ArrayList<>();
    private final LlmRouterService llm;

    public VectorStore(LlmRouterService llm) { this.llm = llm; }

    @PostConstruct
    public void loadKnowledgeBase() throws Exception {
        PathMatchingResourcePatternResolver resolver = new PathMatchingResourcePatternResolver();
        Resource[] docs = resolver.getResources("classpath:knowledge/*.md");
        if (docs.length == 0) throw new IllegalStateException("No knowledge documents found under classpath:knowledge/*.md");

        List<Chunk> loaded = new ArrayList<>();
        for (Resource doc : docs) {
            String content = readAll(doc);
            for (String para : splitIntoChunks(content)) {
                if (para.isBlank()) continue;
                float[] embedding = llm.embedPassage(para);
                validateEmbedding(embedding, "knowledge document " + doc.getFilename());
                loaded.add(new Chunk(doc.getFilename(), para.trim(), embedding));
            }
        }
        if (loaded.isEmpty()) throw new IllegalStateException("Knowledge base contained no usable chunks");
        chunks.clear();
        chunks.addAll(loaded);
        System.out.println("VectorStore: loaded " + chunks.size() + " chunks from " + docs.length + " doc(s) using " + llm.embeddingProvider());
    }

    public List<Chunk> topK(String query, int k) {
        if (chunks.isEmpty()) throw new IllegalStateException("Vector store is empty");
        if (query == null || query.isBlank()) return List.of();
        float[] qEmb = llm.embedQuery(query);
        validateEmbedding(qEmb, "query");
        return chunks.stream()
                .map(c -> new ScoredChunk(c, cosineSimilarity(qEmb, c.embedding())))
                .sorted(Comparator.comparingDouble(ScoredChunk::score).reversed())
                .limit(Math.max(1, Math.min(k, chunks.size())))
                .map(ScoredChunk::chunk)
                .collect(Collectors.toList());
    }

    private static void validateEmbedding(float[] vector, String what) {
        if (vector == null || vector.length == 0) throw new IllegalStateException("Empty embedding returned for " + what);
        for (float value : vector) if (!Float.isFinite(value)) throw new IllegalStateException("Invalid embedding value returned for " + what);
    }

    private String readAll(Resource r) throws Exception {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(r.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) sb.append(line).append('\n');
        }
        return sb.toString();
    }

    private List<String> splitIntoChunks(String content) {
        return List.of(content.split("\\n\\s*\\n"));
    }

    private double cosineSimilarity(float[] a, float[] b) {
        if (a.length != b.length) throw new IllegalStateException("Embedding dimension mismatch: query=" + a.length + ", document=" + b.length + ". Do not mix embedding models.");
        double dot = 0, normA = 0, normB = 0;
        for (int i = 0; i < a.length; i++) {
            dot += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }
        if (normA == 0 || normB == 0) throw new IllegalStateException("Zero-norm embedding");
        return dot / (Math.sqrt(normA) * Math.sqrt(normB));
    }

    private record ScoredChunk(Chunk chunk, double score) {}
}
