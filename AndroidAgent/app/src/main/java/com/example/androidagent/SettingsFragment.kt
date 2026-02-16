package com.example.androidagent

import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.navigation.fragment.findNavController
import com.example.androidagent.databinding.FragmentSettingsBinding

class SettingsFragment : Fragment() {

    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        loadSettings()

        binding.deleteApiKeyButton.setOnClickListener {
            ApiKeyManager.deleteApiKey(requireContext())
            Toast.makeText(context, "API Key Deleted", Toast.LENGTH_SHORT).show()
            // Navigate back to EnterAPIKeyFragment, clearing the back stack
             findNavController().navigate(R.id.enterAPIKeyFragment, null, androidx.navigation.NavOptions.Builder()
                .setPopUpTo(R.id.nav_graph, true)
                .build())
        }

        binding.alwaysOnSwitch.setOnCheckedChangeListener { _, isChecked ->
            ApiKeyManager.setAlwaysOn(requireContext(), isChecked)
            Toast.makeText(context, "Always On setting saved", Toast.LENGTH_SHORT).show()
        }

        // Save Wake Word when focus is lost or text changes (using focus for simplicity)
        binding.wakeWordEditText.setOnFocusChangeListener { _, hasFocus ->
            if (!hasFocus) {
                val wakeWord = binding.wakeWordEditText.text.toString().trim()
                if (wakeWord.isNotEmpty()) {
                    ApiKeyManager.setWakeWord(requireContext(), wakeWord.lowercase()) // Store in lowercase
                    Toast.makeText(context, "Wake Word saved", Toast.LENGTH_SHORT).show()
                    binding.wakeWordEditText.setText(wakeWord.lowercase()) // Reflect lowercase change
                } else {
                    // Reset to default or current saved value if input is cleared
                    val currentWakeWord = ApiKeyManager.getWakeWord(requireContext())
                    binding.wakeWordEditText.setText(currentWakeWord)
                    Toast.makeText(context, "Wake Word cannot be empty, reset to: $currentWakeWord", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun loadSettings() {
        binding.alwaysOnSwitch.isChecked = ApiKeyManager.isAlwaysOn(requireContext())
        binding.wakeWordEditText.setText(ApiKeyManager.getWakeWord(requireContext()))
    }

    override fun onDestroyView() {
        super.onDestroyView()
        // Save wake word if it was changed and focus was not lost before destroying view
        val currentSavedWakeWord = ApiKeyManager.getWakeWord(requireContext())
        val editTextWakeWord = binding.wakeWordEditText.text.toString().trim().lowercase()

        if (editTextWakeWord.isNotEmpty() && editTextWakeWord != currentSavedWakeWord) {
             ApiKeyManager.setWakeWord(requireContext(), editTextWakeWord)
             Toast.makeText(context, "Wake Word saved on exit", Toast.LENGTH_SHORT).show()
        } else if (editTextWakeWord.isEmpty() && currentSavedWakeWord != ApiKeyManager.DEFAULT_WAKE_WORD) {
            // If user cleared it and it wasn't already the default, reset to default or last saved.
            // Here, we ensure it's not empty, so we'd revert to the current saved one which is loaded if empty.
            // This case might be redundant if onFocusChange handles empty properly.
        }
        _binding = null
    }
}
