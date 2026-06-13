# TranscriptFX (SwiftUI)

A transcript **presentation framework** for transcription apps. Your app produces normalized ASR output — fast tier-1 previews and slower tier-2 refinements, with timestamps and speakers. TranscriptFX owns everything after that: token identity, revision semantics, sentence/paragraph flow, and the animations that make corrections legible.

```
your ASR (tier-1 preview, tier-2 refined)
        │  normalize → TranscriptUpdate          ← the only type you produce
        ▼
TranscriptSession ──▶ TranscriptReconciler       ← targets utterances, aligns by
        │                                          timestamps→text, keeps token IDs,
        │                                          emits RevisionEvents
        ▼
TranscriptSnapshot (tokens · sentences · paragraphs · speakers)
        ▼
TranscriptView(mode:theme:)                      ← in-place revision morphs, ink-settle,
                                                   speaker-aware paragraphs
```

**Where your app ends and the library begins:** the app does recording, ASR, jobs, persistence — and maps each ASR result to a `TranscriptUpdate`. The library does reconciliation, revision semantics, segmentation, and rendering. You never diff text, manage token IDs, or build animations.

Requires iOS 17 / macOS 14. No dependencies.

## Add the package

- **Xcode:** *File → Add Package Dependencies… → Add Local…* → select `transcript-fx/swift`.
- **Package.swift:** `.package(path: "../transcript-fx/swift")`, then `"TranscriptFX"` in your target deps.

## Integrate — the whole thing

```swift
import SwiftUI
import TranscriptFX

struct LiveTranscriptView: View {
    @StateObject private var session = TranscriptSession(configuration: .twoTier)

    var body: some View {
        ScrollView {
            TranscriptView(snapshot: session.snapshot)   // mode: .liveRevision is the default
        }
    }

    // Tier-1: fast preview, streamed as the user speaks.
    func onPreview(_ words: [TranscriptWord], utteranceDone: Bool, utterance: String) {
        session.ingest(TranscriptUpdate(words: words, tier: .preview,
                                        isFinal: utteranceDone, utteranceID: utterance))
    }

    // Tier-2: refinement, whenever it lands — even while tier-1 streams ahead.
    func onRefined(_ words: [TranscriptWord], utterance: String) {
        session.ingest(TranscriptUpdate(words: words, tier: .refined,
                                        isFinal: true, utteranceID: utterance))
    }
}
```

That's the integration. The refined pass morphs corrections in place (token identity is kept across tiers), merges/splits words whose boundaries changed, settles sentences, and breaks paragraphs on speaker changes and long pauses.

## The input model

`TranscriptUpdate` is the single envelope. Everything beyond `words` + `tier` + `isFinal` is optional and unlocks behavior:

| field | unlocks |
|---|---|
| `words[].start/end` (seconds) | timestamp-first alignment, pause-based paragraph breaks, multi-utterance refinement targeting |
| `words[].confidence` (0–1) | ink-settle (low-confidence words render lighter) |
| `words[].speaker` / update-level `speaker` | speaker labels, speaker-change paragraph breaks |
| `utteranceID` | exact refinement targeting (otherwise targeted by time overlap, then recency) |

No word-level output? `TranscriptUpdate(text: "strings work too", tier: .preview, isFinal: false)` tokenizes for you.

### Token lifecycle

`provisional` (tier-1, may change) → `revised` (tier-2 touched it) → `finalized` (immutable). With the default `FinalizationPolicy.onAnyFinal`, any final update commits its utterance — right for single-tier apps. With `.twoTier` (i.e. `.onRefinedFinal`), a tier-1 final just closes the utterance and leaves it revisable until tier-2 lands.

## Reconciliation & revision events

Refined words are aligned onto existing tokens **timestamps first, text second** (`AlignmentPolicy.hybrid`, the default): overlap clustering when both sides carry times — yielding 1:1 revisions, 1:n merges, m:1 splits — and longest-common-subsequence text anchoring when they don't. Identity is kept wherever possible so the UI morphs instead of redrawing; a correction with no characters in common becomes a `replace` (fade) rather than a weird morph.

Every `ingest` returns (and `session.onEvents` reports) explicit semantics — no snapshot diffing:

```swift
session.onEvents = { events in
    for case let .revise(id, old, new) in events { … }   // haptics, a11y announcements, logging
}
```

`insert · remove · revise · replace · split · merge · finalize · speakerChange · sentenceBreak · paragraphBreak`

**`.revise` is a tier-2 signal.** It (and the `revision` bump / flash that `.liveRevision` keys off) is emitted only when a `.refined` update changes a token's text — i.e. a real correction landed. The volatile tier-1 `.preview` stream rewrites its own un-committed words constantly as it re-decodes; those updates settle the token's text silently (no `.revise`, no `revision` bump, identity kept) so already-shown preview text never flashes before a refinement actually arrives. New preview words still `insert`; shrinking previews still `remove`.

The reconciler is deterministic: same updates in, same tokens and events out. No clocks, no randomness.

## Rendering modes

```swift
TranscriptView(snapshot: session.snapshot, mode: .liveRevision, theme: theme)
```

- **`.livePreview`** — raw live feed: ink-settle + caret, no revision flashes.
- **`.liveRevision`** *(default)* — the signature: in-place morphs with a brief flash so every correction is legible.
- **`.finalText`** — finalized tokens only, full ink, no motion. The settled document.
- **`.debug`** — state borders, tier/confidence captions, boundary markers.

Reduce Motion is honored automatically (`theme.reduceMotion` overrides).

## Speakers & theming

```swift
var theme = TranscriptTheme()
theme.baseFontSize = 26
theme.colorizeSpeakerText = true
theme.speakerStyle = { speaker in
    guard let speaker, let person = People.lookup(speaker.rawValue) else { return SpeakerStyle() }
    return SpeakerStyle(label: person.shortName, color: person.color)
}
```

Speaker styling is a closure — plug in your app's people model. The default cycles a palette keyed by `SpeakerID` and shows the raw ID as the label. Paragraphs break on speaker change (and on pauses ≥ `SegmentationPolicy.paragraphPause`, default 2 s); sentences settle on terminal punctuation and utterance ends. All tunable via `ReconcilerConfiguration.segmentation`.

## Adapters (optional)

Reference mappers for common sources — or conform your own chunk type:

```swift
// Apple Speech / SpeechAnalyzer
session.ingest(speechResultToUpdate(result))                       // tier .preview

// WhisperKit — one-line glue, defaults to tier .refined
extension WordTiming: WhisperWordTiming {}
session.ingest(whisperKitToUpdate(segment.words ?? [], isFinal: true, utteranceID: id))

// Deepgram (decodes diarized speakers into SpeakerIDs)
session.ingest(deepgramToUpdate(jsonData: message)!)

// Your own type, ingestable directly:
extension MyASRChunk: TranscriptUpdateConvertible {
    var transcriptUpdate: TranscriptUpdate { … }
}
session.ingest(chunk)
```

Adapters are plain functions over the canonical model — the core never imports them.

## Demo

`Demo.swift` has an Xcode `#Preview` that scripts the full story: two speakers streaming on tier-1, tier-2 refinements landing mid-stream (including a `"too thirty" → "2:30."` merge), sentence/paragraph settling, and a mode switcher. `GlyphDiffText` (iOS 18 / macOS 15) is the per-glyph Text Renderer upgrade for token morphs.

## API surface

`TranscriptSession` · `TranscriptView` (`RenderingMode`, `TranscriptTheme`, `SpeakerStyle`) · `TranscriptReconciler` (`ReconcilerConfiguration`, `AlignmentPolicy`, `FinalizationPolicy`, `SegmentationPolicy`) · model: `TranscriptUpdate` / `TranscriptWord` / `TranscriptToken` / `TranscriptSnapshot` / `TranscriptSentence` / `TranscriptParagraph` / `SpeakerID` / `SourceTier` / `TokenState` / `RevisionEvent` · `TranscriptUpdateConvertible` · adapters: `speechResultToUpdate` / `whisperKitToUpdate` / `deepgramToUpdate`.

### Migrating from v1 (`ASRResult`/`TranscriptStore`/`RevisingText`)

`ASRResult` → `TranscriptUpdate` (`role:` → `tier:`), `TranscriptStore` → `TranscriptSession`, `RevisingText(tokens:)` → `TranscriptView(snapshot:)`. The event-driven `TranscriptModel`/`DeepgramConsumer` path and token-level redaction were removed; reconciliation is now the only ingestion path.
