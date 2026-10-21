package com.gridwatch.service;

/** Common contract for generation and embedding providers. */
public interface LlmProvider {
    /** inputType is "query" or "passage" for providers that distinguish them. */
    float[] embed(String text, String inputType);
    String generate(String prompt);
    String name();
}
