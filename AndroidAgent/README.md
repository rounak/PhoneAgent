# AndroidAgent

## Description

AndroidAgent is an Android application designed to interact with Google's Gemini API. Users can input queries via voice or text and receive responses from the generative AI. The application allows users to securely store their Gemini API key and manage basic settings.

This project was bootstrapped by an AI assistant.

## Features

*   **API Key Management**: Securely stores your Gemini API key using Android's SharedPreferences.
*   **Voice Input**: Utilizes Android's built-in speech recognition for hands-free queries.
*   **Text Input**: Allows typed queries for direct interaction.
*   **Gemini API Integration**: Communicates with the Gemini Pro model to get generative AI responses.
*   **Response Display**: Clearly displays responses from the AI.
*   **Basic Settings**:
    *   Toggle for "Always On" listening (UI and persistence only; background feature not implemented).
    *   Customizable "Wake Word" (UI and persistence only; background feature not implemented).

## Setup and Build

1.  **Open in Android Studio**:
    *   Clone or download the repository.
    *   Open Android Studio (ensure you have a recent version, e.g., Hedgehog or later).
    *   Select "Open an Existing Project" and navigate to the `AndroidAgent` directory.
2.  **Android SDK**:
    *   The project is configured with `compileSdk 34` and `targetSdk 34`. Ensure you have the necessary SDK platform installed via Android Studio's SDK Manager.
    *   `minSdk` is set to `24` (Android 7.0 Nougat).
3.  **Build APK**:
    *   Once the project has synced, you can build an APK by navigating to `Build > Build Bundle(s) / APK(s) > Build APK(s)`.
    *   The generated APK can be found in `AndroidAgent/app/build/outputs/apk/debug/`.

## Usage

1.  **Enter API Key**:
    *   On first launch, you will be prompted to enter your Gemini API key.
    *   You can obtain an API key from Google AI Studio (or your relevant Google Cloud project).
    *   Paste or type your key and tap "Save".
2.  **Prompt Screen**:
    *   **Voice Input**: Tap the microphone icon. If prompted, grant microphone permission. Speak your query. The transcribed text will appear and be sent to Gemini.
    *   **Text Input**: Type your query into the text field at the bottom and press enter/send on your keyboard.
    *   The AI's response will be displayed in the main text area.
3.  **Settings Screen**:
    *   Access settings by tapping the gear icon on the Prompt screen.
    *   Here you can:
        *   Delete your currently saved API key (you will be prompted to enter it again).
        *   Toggle the "Always On" listening setting (note: the background listening feature itself is not yet implemented).
        *   Set a custom "Wake Word" (note: the wake word detection feature is not yet implemented).

## Important: API Key

You **must** use your own Gemini API key for this application to function. The application does not come with a pre-configured key.

## Key Dependencies

*   **Kotlin**: Primary programming language.
*   **Ktor Client**: For making HTTP requests to the Gemini API.
*   **Kotlin Coroutines**: For managing asynchronous operations.
*   **Kotlinx Serialization**: For JSON parsing.
*   **Android Navigation Component**: For managing fragment navigation.
*   **Android Material Components**: For UI elements.
*   **Android SpeechRecognizer**: For voice input.

## Future Considerations & TODOs (from development)

This application provides a foundational interface to the Gemini API. Potential future enhancements include:

*   **Full "Always On" Listening**: Implementing a background service for continuous wake word detection and voice commands.
*   **Advanced Error Handling**: More nuanced error messages and recovery options.
*   **UI/UX Polish**: Further refinements to the user interface and experience.
*   **Android Keystore**: Migrating API key storage to the more secure Android Keystore system for production applications.
*   **Tool Integration/Function Calling**: Expanding capabilities to allow the AI to interact with device functions or other apps (would require extensive use of Accessibility Services and/or UI Automator, a significant undertaking).
*   **Conversation History**: Storing and displaying past interactions.
*   **Streaming Responses**: Displaying Gemini responses token by token as they arrive.
