package com.example.androidagent

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.android.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json

class GeminiService {

    private val client = HttpClient(Android) {
        install(ContentNegotiation) {
            json(Json {
                prettyPrint = true
                isLenient = true
                ignoreUnknownKeys = true // Important for robust parsing
            })
        }
        // Optionally, add defaultRequest or logging plugins here
    }

    private val geminiApiBaseUrl = "https.generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"

    suspend fun generateContent(prompt: String, apiKey: String): GeminiResponse {
        val requestBody = GeminiRequest(
            contents = listOf(
                Content(parts = listOf(Part(text = prompt)))
            )
        )

        return try {
            val response: GeminiResponse = client.post(geminiApiBaseUrl) {
                url {
                    parameters.append("key", apiKey)
                }
                contentType(ContentType.Application.Json)
                setBody(requestBody)
            }.body()
            response
        } catch (e: Exception) {
            // Log the exception or handle it more gracefully
            // For now, return a response with an error object
            GeminiResponse(error = GeminiError(code = 0, message = e.message ?: "Unknown error", status = "EXCEPTION"))
        }
    }

    fun close() {
        client.close()
    }
}
