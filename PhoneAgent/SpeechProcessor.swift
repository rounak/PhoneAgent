//
//  SpeechProcessor.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/30/25.
//

import Foundation
import SwiftUI
import Speech
import AVFoundation
import Observation

@Observable
final class SpeechProcessor {
    // Published state
    var transcript: String = ""
    var isRecording: Bool = false

    // Private speech objects
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: .current)

    // Silence detection
    private var inactivityTask: Task<Void, Never>?
    private let silenceInterval: TimeInterval = 1.5 // seconds of no updates that count as silence

    @ObservationIgnored
    @AppStorage("alwaysOn") private var alwaysOn = false

    @ObservationIgnored
    private let streamPair = AsyncStream.makeStream(of: String.self)
    var utterances: AsyncStream<String> { streamPair.stream }

    // MARK: - Public control

    /// Start listening and transcribing.
    func start() {
        guard !isRecording else { return }

        requestPermissions { [weak self] granted in
            guard granted, let self else { return }
            Task { @MainActor in
                do {
                    try self.configureSession()
                    try self.startRecognition()
                    self.isRecording = true
                } catch {
                    self.stop()
                    print("SpeechProcessor error: \(error)")
                }
            }
        }
    }

    /// Stop listening.
    private func stop() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        inactivityTask?.cancel()
        inactivityTask = nil

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    @MainActor
    func stopAndQuery() {
        stop()
        deliverUtterance()
    }

    @MainActor
    private func deliverUtterance() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        streamPair.continuation.yield(text)
        transcript = ""
    }

    // MARK: - Helpers

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        func finish(_ speechGranted: Bool) {
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    completion(speechGranted && micGranted)
                }
            }
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            finish(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                finish(status == .authorized)
            }
        default:
            finish(false)
        }
    }

    @MainActor
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    @MainActor
    private func startRecognition() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.transcript = result.bestTranscription.formattedString
                // Each partial update resets the silence timer.
                self.resetInactivityTimer()

                if result.isFinal {
                    self.stop()
                }
            }

            if error != nil {
                self.stop()
            }
        }
    }
}

// MARK: - Inactivity handling

extension SpeechProcessor {
    @MainActor
    private func resetInactivityTimer() {
        inactivityTask?.cancel()
        inactivityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(silenceInterval))
                if alwaysOn {
                    deliverUtterance()
                } else {
                    stopAndQuery()
                }
            } catch is CancellationError {
                // Do nothing
            } catch {
                print("Inactivity timer error: \(error)")
            }
        }
    }
}
