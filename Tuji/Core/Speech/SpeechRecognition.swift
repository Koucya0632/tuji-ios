// What 跟讀 (`ShadowingRecorder`) and 語音輸入 (`Dictation`) both need from
// Apple's recogniser: the two permissions, and its callback turned into plain
// values on the main actor.
//
// Built `nonisolated` on purpose. Under this target's default MainActor
// isolation a closure written inside a recorder method would be MainActor-
// isolated, and the recogniser's thread calling it traps.

import AVFoundation
import Speech

nonisolated enum SpeechRecognition {
    /// Microphone first, then speech recognition; both must be granted.
    static func authorize() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<
            SFSpeechRecognizerAuthorizationStatus,
            Never
        >) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }

    /// The recogniser's result handler, delivering (text, isFinal, failed) on the main actor.
    static func handler(
        _ deliver: @escaping @MainActor (String?, Bool, Bool) -> Void
    )
        -> (SFSpeechRecognitionResult?, Error?) -> Void
    {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in deliver(text, isFinal, failed) }
        }
    }
}
