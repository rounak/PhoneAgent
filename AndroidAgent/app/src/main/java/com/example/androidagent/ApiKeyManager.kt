package com.example.androidagent

import android.content.Context
import android.content.SharedPreferences

object ApiKeyManager { // Renaming or splitting this could be a future refactor

    private const val PREFS_NAME = "AndroidAgentPrefs"
    private const val API_KEY = "GEMINI_API_KEY"
    private const val ALWAYS_ON = "ALWAYS_ON_LISTENING"
    private const val WAKE_WORD = "WAKE_WORD"
    // Default Wake Word
    const val DEFAULT_WAKE_WORD = "hey agent"


    private fun getPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    // API Key Management
    fun saveApiKey(context: Context, apiKey: String) {
        getPreferences(context).edit().putString(API_KEY, apiKey).apply()
    }

    fun getApiKey(context: Context): String? {
        return getPreferences(context).getString(API_KEY, null)
    }

    fun deleteApiKey(context: Context) {
        getPreferences(context).edit().remove(API_KEY).apply()
    }

    // Settings Management
    fun setAlwaysOn(context: Context, enabled: Boolean) {
        getPreferences(context).edit().putBoolean(ALWAYS_ON, enabled).apply()
    }

    fun isAlwaysOn(context: Context): Boolean {
        return getPreferences(context).getBoolean(ALWAYS_ON, false) // Default to false
    }

    fun setWakeWord(context: Context, wakeWord: String) {
        getPreferences(context).edit().putString(WAKE_WORD, wakeWord).apply()
    }

    fun getWakeWord(context: Context): String {
        return getPreferences(context).getString(WAKE_WORD, DEFAULT_WAKE_WORD) ?: DEFAULT_WAKE_WORD
    }
}
