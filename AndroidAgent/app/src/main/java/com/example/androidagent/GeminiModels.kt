package com.example.androidagent

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// --- Request Structures ---
@Serializable
data class GeminiRequest(
    val contents: List<Content>
)

@Serializable
data class Content(
    val parts: List<Part>
)

@Serializable
data class Part(
    val text: String
)

// --- Response Structures (Simplified Example) ---
// Refer to official Gemini API documentation for the exact structure.
@Serializable
data class GeminiResponse(
    val candidates: List<Candidate>? = null,
    val error: GeminiError? = null // For error handling
)

@Serializable
data class Candidate(
    val content: Content? = null, // Reusing Content from request for simplicity here
    @SerialName("finishReason")
    val finishReason: String? = null
    // Potentially other fields like safetyRatings, citationMetadata, etc.
)

@Serializable
data class GeminiError(
    val code: Int,
    val message: String,
    val status: String
)
