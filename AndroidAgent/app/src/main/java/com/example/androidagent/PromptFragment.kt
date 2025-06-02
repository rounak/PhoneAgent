package com.example.androidagent

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope // Import for lifecycleScope
import androidx.navigation.fragment.findNavController
import com.example.androidagent.databinding.FragmentPromptBinding
import kotlinx.coroutines.launch // Import for launch
import java.util.Locale

class PromptFragment : Fragment() {

    private var _binding: FragmentPromptBinding? = null
    private val binding get() = _binding!!

    // private var speechRecognizer: SpeechRecognizer? = null // Not used with intent launcher
    private var isListening = false
    private lateinit var geminiService: GeminiService
    private var currentApiKey: String? = null

    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted: Boolean ->
            if (isGranted) {
                startListening()
            } else {
                Toast.makeText(context, "Record audio permission denied", Toast.LENGTH_SHORT).show()
            }
        }

    private val speechRecognitionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                val data: Intent? = result.data
                val results = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                if (!results.isNullOrEmpty()) {
                    val recognizedText = results[0]
                    binding.largeTextDisplay.text = "You said: $recognizedText" // Update display
                    binding.queryInputText.setText(recognizedText)
                    submitQueryToGemini(recognizedText) // Send to Gemini
                }
            }
            updateMicrophoneButtonState(false)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        geminiService = GeminiService()
        currentApiKey = ApiKeyManager.getApiKey(requireContext())
        if (currentApiKey == null) {
            Toast.makeText(requireContext(), "API Key not found. Please set it in settings.", Toast.LENGTH_LONG).show()
            // Optionally navigate back to EnterAPIKeyFragment or disable functionality
            findNavController().popBackStack(R.id.enterAPIKeyFragment, false)
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentPromptBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        binding.settingsButton.setOnClickListener {
            findNavController().navigate(R.id.action_promptFragment_to_settingsFragment)
        }

        binding.microphoneButton.setOnClickListener {
            if (isListening) {
                stopListening()
            } else {
                checkPermissionAndStartListening()
            }
        }

        binding.queryInputText.setOnEditorActionListener { _, _, _ ->
            val query = binding.queryInputText.text.toString().trim()
            if (query.isNotEmpty()) {
                binding.largeTextDisplay.text = "You typed: $query" // Update display
                submitQueryToGemini(query)
                binding.queryInputText.text.clear()
            }
            true
        }
    }

    private fun submitQueryToGemini(query: String) {
        if (query.isBlank()) return

        if (currentApiKey == null) {
            Toast.makeText(requireContext(), "API Key is missing.", Toast.LENGTH_SHORT).show()
            return
        }

        binding.largeTextDisplay.text = "Thinking..." // Show loading state
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val response = geminiService.generateContent(query, currentApiKey!!)
                if (response.error != null) {
                    binding.largeTextDisplay.text = "Error: ${response.error.message}"
                } else {
                    val responseText = response.candidates?.firstOrNull()?.content?.parts?.firstOrNull()?.text ?: "No content received."
                    binding.largeTextDisplay.text = responseText
                }
            } catch (e: Exception) {
                binding.largeTextDisplay.text = "Exception: ${e.message}"
                e.printStackTrace()
            }
        }
    }

    private fun checkPermissionAndStartListening() {
        // ... (permission logic remains the same)
        when {
            ContextCompat.checkSelfPermission(
                requireContext(),
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED -> {
                startListening()
            }
            shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) -> {
                 Toast.makeText(context, "Record audio permission is required for voice input.", Toast.LENGTH_LONG).show()
                requestPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
            else -> {
                requestPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        }
    }

    private fun startListening() {
        // ... (startListening logic remains the same)
         if (!SpeechRecognizer.isRecognitionAvailable(requireContext())) {
            Toast.makeText(context, "Speech recognition is not available on this device.", Toast.LENGTH_LONG).show()
            return
        }
        updateMicrophoneButtonState(true)

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak now...")
        }
        speechRecognitionLauncher.launch(intent)
    }

    private fun stopListening() {
        updateMicrophoneButtonState(false)
    }

    private fun updateMicrophoneButtonState(isNowListening: Boolean) {
        // ... (button state update logic remains the same)
        isListening = isNowListening
        if (isListening) {
            binding.microphoneButton.setImageResource(android.R.drawable.ic_media_pause)
        } else {
            binding.microphoneButton.setImageResource(android.R.drawable.ic_btn_speak_now)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
        // geminiService.close() // Ktor client is usually managed by its scope, but explicit close can be added if needed
    }

    override fun onStop() {
        super.onStop()
        // Potentially close client here if fragment is being stopped for a long time
        // geminiService.close()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Clean up Ktor client if it's still open and tied to fragment lifecycle
        // This is tricky with object/singleton clients. For per-fragment instance:
        if (::geminiService.isInitialized) { // Check if initialized
             geminiService.close()
        }
    }
}
