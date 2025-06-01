package com.example.androidagent

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.navigation.fragment.findNavController
import com.example.androidagent.databinding.FragmentEnterApiKeyBinding
import com.google.android.material.textfield.TextInputEditText

class EnterAPIKeyFragment : Fragment() {

    private var _binding: FragmentEnterApiKeyBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentEnterApiKeyBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Check if API key already exists
        val existingApiKey = ApiKeyManager.getApiKey(requireContext())
        if (!existingApiKey.isNullOrEmpty()) {
            // Navigate to PromptFragment if key exists
            findNavController().navigate(R.id.action_enterAPIKeyFragment_to_promptFragment)
            return // Skip rest of onViewCreated
        }

        binding.saveApiKeyButton.setOnClickListener {
            val apiKey = binding.apiKeyEditText.text.toString().trim()
            if (apiKey.isNotEmpty()) {
                ApiKeyManager.saveApiKey(requireContext(), apiKey)
                Toast.makeText(context, "API Key Saved", Toast.LENGTH_SHORT).show()
                findNavController().navigate(R.id.action_enterAPIKeyFragment_to_promptFragment)
            } else {
                binding.apiKeyInputLayout.error = "API Key cannot be empty"
            }
        }

        binding.pasteApiKeyButton.setOnClickListener {
            val clipboard = context?.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager?
            val clipData: ClipData? = clipboard?.primaryClip
            if (clipData != null && clipData.itemCount > 0) {
                val pasteData = clipData.getItemAt(0).text
                if (pasteData != null) {
                    binding.apiKeyEditText.setText(pasteData.toString().trim())
                }
            } else {
                Toast.makeText(context, "Clipboard is empty or content is not text", Toast.LENGTH_SHORT).show()
            }
        }

        // Clear error when text changes
        binding.apiKeyEditText.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                binding.apiKeyInputLayout.error = null
            }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
