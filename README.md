# transcript-fx

Live, self-revising transcription text — done with craft. As speech-to-text streams, words arrive *provisional*, **correct themselves in place**, and settle when final.

Two runtimes at different generations:

- **`swift/` — TranscriptFX v2**, a full transcript **presentation framework**: canonical input model (tiers, timestamps, confidence, speakers), an utterance-based reconciler with explicit revision events (revise/split/merge/speaker-change/sentence- and paragraph-breaks), and a speaker-aware paragraph renderer with rendering modes. → [`swift/README.md`](./swift/README.md)
- **`core/` — `@transcript-fx/core` v0.1** (web), the original flat token renderer + reconciler per [`SPEC.md`](./SPEC.md).

```
   your ASR · Deepgram · WhisperKit · Apple SpeechAnalyzer
                  │  normalize ↓
            TranscriptUpdate                ← the only type you produce (Swift v2)
                  │  ingest ↓
            TranscriptSession / Reconciler  ← aligns tiers, keeps token identity,
                  │  snapshot ↓                emits revision events
            TranscriptView                  ← words · sentences · paragraphs · speakers
```

## The signature
- **Ink-settle** — confidence becomes type *weight*: volatile is light, final gains ink.
- **Diff-morph** — on a correction, only the *changed* characters animate.
- **Swipe redaction** — a green block sweeps to mask sensitive spans.
- **Correction flash** — a brief highlight so every revision is legible.

---

## Integrate (web) — 5 minutes

**Install** (local path for now; `@transcript-fx/core` once published):
```bash
npm install /ABS/PATH/to/transcript-fx/core   # auto-builds on install
```

**Use** — bind a reconciler to the element, feed it any ASR:
```html
<revising-text id="t"></revising-text>
```
```js
import '@transcript-fx/core'                         // registers <revising-text>
import { bindReconciler, deepgramToASR } from '@transcript-fx/core'

const recon = bindReconciler(document.getElementById('t'))

// ── from ANY source: map your model's output to ASRResult ──
recon.ingest({ words: [{ text: 'their', start: 0, end: 0.4, confidence: 0.5 }], isFinal: false }, 'draft')
recon.ingest({ words: [{ text: 'there', start: 0, end: 0.4, confidence: 0.98 }], isFinal: true  }, 'refined')

// ── or Deepgram, ready-made ──
ws.onmessage = (e) => recon.ingest(deepgramToASR(JSON.parse(e.data)), 'draft')
```
Minimum a source must give you: `{ transcript: "...", isFinal }` (or `words`). `confidence` unlocks ink-settle; `start/end` unlock clean two-source combining. → [`core/README.md`](./core/README.md)

## Integrate (SwiftUI) — 5 minutes

**Add the package**: Xcode → *Add Package Dependencies…* → *Add Local…* → pick `transcript-fx/swift`
(or `.package(path: "../transcript-fx/swift")`).

```swift
import SwiftUI
import TranscriptFX

struct LiveView: View {
    @StateObject private var session = TranscriptSession(configuration: .twoTier)

    var body: some View {
        TranscriptView(snapshot: session.snapshot)
    }

    // ── tier-1 fast preview, streamed live ──
    func onPreview(_ words: [TranscriptWord], done: Bool, id: String) {
        session.ingest(TranscriptUpdate(words: words, tier: .preview, isFinal: done, utteranceID: id))
    }
    // ── tier-2 refinement, whenever it lands ──
    func onRefined(_ words: [TranscriptWord], id: String) {
        session.ingest(TranscriptUpdate(words: words, tier: .refined, isFinal: true, utteranceID: id))
    }
}
```
Corrections morph in place, sentences settle, paragraphs break on speaker change. Adapters for Apple Speech, WhisperKit, and Deepgram (with diarization) included. → [`swift/README.md`](./swift/README.md)

## Your local rig (the generic path)
Whatever your model emits, build a `TranscriptUpdate` and `ingest` it:
- **Strings only**: `TranscriptUpdate(text: "the quick brown", tier: .preview, isFinal: false)` — we tokenize; ink by state.
- **Word-level** (better): `words: [TranscriptWord(text:start:end:confidence:speaker:)]` — timestamps unlock surgical alignment, confidence unlocks ink-settle, speakers unlock paragraphs.
- **Two tiers** (fast + accurate): feed the fast one as `tier: .preview`, the accurate one as `tier: .refined` — the reconciler aligns corrections onto the preview (timestamps first, text second) and diff-morphs them. Same path for two tiers of one model or two separate models.

---

## Layout
| Path | What | Status |
|---|---|---|
| `swift/` | **`TranscriptFX` v2** — presentation framework: session + reconciler + TranscriptView + adapters | builds, **34/34 tests** |
| [`SPEC.md`](./SPEC.md) | The v0.1 contract (still what `core/` implements) | — |
| `core/` | **`@transcript-fx/core`** v0.1 — `<revising-text>` + reconciler + adapters | builds, renders, tested |
| `src/` | React reference lab (visual playground: `npm i && npm run dev`) | runs |

The web core still implements the v0.1 flat-token contract; the Swift package has moved to the v2 presentation-framework model documented in [`swift/README.md`](./swift/README.md). MIT.
