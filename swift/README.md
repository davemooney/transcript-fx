# TranscriptFX (SwiftUI)

Live, self-revising transcription text for SwiftUI — ink-settle, diff-morph corrections (Text Renderer), swipe redaction. Drop-in for any ASR.

## Add the package
- **Xcode:** *File → Add Package Dependencies… → Add Local…* → select `transcript-fx/swift`.
- **Package.swift:** `.package(path: "../transcript-fx/swift")` then `"TranscriptFX"` in your target deps.

Requires iOS 17 / macOS 14 (Text Renderer per-glyph path: iOS 18 / macOS 15).

## Quickest start
```swift
import SwiftUI
import TranscriptFX

struct LiveView: View {
    @StateObject private var transcript = TranscriptStore()
    var body: some View {
        RevisingText(tokens: transcript.tokens, baseFontSize: 24)
    }
}
```
`TranscriptStore` is an `ObservableObject` — feed it and the view updates.

## The `ASRResult` you feed
```swift
ASRResult(words: [ASRWord(text: "their", start: 0, end: 0.4, confidence: 0.5)], isFinal: false)
ASRResult(transcript: "strings only work too", isFinal: false)   // tokenized; ink by state
```
`confidence` → ink-settle; `start/end` → clean two-source combining.

## Sources (built-in adapters)
```swift
// Apple Speech / SpeechAnalyzer
transcript.ingest(speechResultToASR(result))

// WhisperKit — one-line glue, then map word timings
extension WordTiming: WhisperWordTiming {}
transcript.ingest(whisperKitToASR(segment.words ?? [], isFinal: true), role: .refined)

// Deepgram (decode the JSON message)
transcript.ingest(deepgramToASR(decodedResult), role: .draft)

// Your local rig — just build an ASRResult
transcript.ingest(ASRResult(words: myWords, isFinal: false), role: .draft)
```

## Two models (fast draft + slow refiner)
```swift
transcript.ingest(fast,     role: .draft)    // instant, light/low-confidence
transcript.ingest(accurate, role: .refined)  // corrections diff-morph in, settle solid
```
The reconciler time-aligns the refiner onto the draft (or aligns by index when there are no
timestamps), reusing token ids so corrections animate. See the live `TwoSourceDemo` `#Preview`.

## API
`TranscriptStore` · `RevisingText` · `TranscriptReconciler` · `ASRResult` / `ASRWord` / `SourceRole` ·
adapters `speechResultToASR` / `whisperKitToASR` (`WhisperWordTiming`) / `deepgramToASR` ·
`GlyphDiffText` (iOS 18 / macOS 15 per-glyph). 9/9 unit tests.
