@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

enum VoiceTranscriptText {
  static func merging(
    existingText: String,
    transcript: String,
    limit: Int = CaptureInput.bodyLimit
  ) -> String {
    guard limit > 0 else { return "" }

    let spokenText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !spokenText.isEmpty else {
      return String(existingText.prefix(limit))
    }

    let separator =
      existingText.isEmpty || existingText.last?.isWhitespace == true
      ? ""
      : "\n"
    return String("\(existingText)\(separator)\(spokenText)".prefix(limit))
  }
}

@MainActor
@Observable
final class VoiceTranscriptionController {
  enum Phase: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening
  }

  private(set) var phase = Phase.idle
  private(set) var transcribedText: String?
  private(set) var message: String?
  private(set) var hasError = false

  private var audioEngine: AVAudioEngine?
  private var audioBufferSink: VoiceAudioBufferSink?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var sessionID: UUID?

  var isActive: Bool {
    phase != .idle
  }

  func start(currentText: String) async {
    guard !isActive else { return }

    guard currentText.count < CaptureInput.bodyLimit else {
      fail("This note has reached the 50,000 character limit.")
      return
    }

    let newSessionID = UUID()
    sessionID = newSessionID
    transcribedText = nil
    hasError = false
    phase = .requestingPermission
    message = "Preparing voice capture…"

    let speechStatus = await requestSpeechAuthorization()
    guard sessionID == newSessionID else { return }
    guard speechStatus == .authorized else {
      fail("Allow Speech Recognition in Settings to use voice capture.")
      return
    }

    let hasMicrophonePermission = await requestMicrophoneAuthorization()
    guard sessionID == newSessionID else { return }
    guard hasMicrophonePermission else {
      fail("Allow Microphone access in Settings to use voice capture.")
      return
    }

    do {
      try beginRecognition(sessionID: newSessionID, existingText: currentText)
    } catch {
      fail("Voice capture could not start. Check the microphone and try again.")
    }
  }

  func stop(silently: Bool = false) {
    guard isActive else {
      if silently {
        message = nil
        hasError = false
      }
      return
    }

    sessionID = nil
    recognitionRequest?.endAudio()
    recognitionTask?.finish()
    cleanUpAudio()
    recognitionRequest = nil
    recognitionTask = nil
    phase = .idle
    hasError = false
    message = silently ? nil : completionMessage
  }

  private func beginRecognition(sessionID: UUID, existingText: String) throws {
    guard let recognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent), recognizer.isAvailable
    else {
      throw VoiceTranscriptionError.recognizerUnavailable
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
      throw VoiceTranscriptionError.audioInputUnavailable
    }

    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

    let sink = VoiceAudioBufferSink(request: request)
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) {
      buffer,
      _ in
      sink.append(buffer)
    }

    audioEngine = engine
    audioBufferSink = sink
    recognitionRequest = request
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      let transcript = result?.bestTranscription.formattedString
      let isFinal = result?.isFinal == true
      let didFail = error != nil

      Task { @MainActor [weak self] in
        self?.handleRecognitionUpdate(
          transcript: transcript,
          isFinal: isFinal,
          didFail: didFail,
          sessionID: sessionID,
          existingText: existingText
        )
      }
    }

    engine.prepare()
    try engine.start()
    phase = .listening
    message = "Listening… Tap again to stop. Audio is not saved."
  }

  private func handleRecognitionUpdate(
    transcript: String?,
    isFinal: Bool,
    didFail: Bool,
    sessionID: UUID,
    existingText: String
  ) {
    guard self.sessionID == sessionID else { return }

    if let transcript {
      transcribedText = VoiceTranscriptText.merging(
        existingText: existingText,
        transcript: transcript
      )
    }

    if isFinal {
      finish(message: completionMessage)
    } else if didFail {
      if transcribedText == nil {
        fail("Voice capture stopped before any words were recognized. Try again.")
      } else {
        finish(message: completionMessage)
      }
    }
  }

  private var completionMessage: String {
    transcribedText == nil ? "Voice capture stopped." : "Transcription added to this draft."
  }

  private func finish(message: String) {
    sessionID = nil
    cleanUpAudio()
    recognitionRequest = nil
    recognitionTask = nil
    phase = .idle
    hasError = false
    self.message = message
  }

  private func fail(_ message: String) {
    sessionID = nil
    recognitionTask?.cancel()
    cleanUpAudio()
    recognitionRequest = nil
    recognitionTask = nil
    phase = .idle
    hasError = true
    self.message = message
  }

  private func cleanUpAudio() {
    if let audioEngine {
      if audioEngine.isRunning {
        audioEngine.stop()
      }
      audioEngine.inputNode.removeTap(onBus: 0)
    }
    audioEngine = nil
    audioBufferSink = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  private func requestMicrophoneAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }
}

private final class VoiceAudioBufferSink: @unchecked Sendable {
  private let request: SFSpeechAudioBufferRecognitionRequest

  init(request: SFSpeechAudioBufferRecognitionRequest) {
    self.request = request
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    request.append(buffer)
  }
}

private enum VoiceTranscriptionError: Error {
  case audioInputUnavailable
  case recognizerUnavailable
}
