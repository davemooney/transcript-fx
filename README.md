# transcript-fx

Live, self-revising transcription text — done with craft. As speech-to-text streams, words arrive *volatile*, **correct themselves in place**, redact sensitive spans, and settle when final. One spec, two native runtimes (**Web** + **SwiftUI**), and **any** ASR drops in via a single mapping.

```
        Deepgram · WhisperKit · Apple SpeechAnalyzer · your local rig
                              │  map to ↓
                          ASRResult                ← the only type you produce
                              │  ingest ↓
                      TranscriptReconciler          ← combines 1+ sources (draft + refiner)
                              │  renders ↓
              <revising-text>  /  RevisingText (SwiftUI)
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
    @StateObject private var transcript = TranscriptStore()

    var body: some View {
        RevisingText(tokens: transcript.tokens)
    }

    // ── feed from any source ──
    func onApple(_ r: SFSpeechRecognitionResult) { transcript.ingest(speechResultToASR(r)) }
    func onWhisper(_ words: [WordTiming])        { transcript.ingest(whisperKitToASR(words, isFinal: true), role: .refined) }
    func onLocalRig(_ text: String, final: Bool) { transcript.ingest(ASRResult(transcript: text, isFinal: final)) }
}
```
WhisperKit glue is one line: `extension WordTiming: WhisperWordTiming {}`. → [`swift/README.md`](./swift/README.md)

## Your local rig (the generic path)
Whatever your local model emits, build an `ASRResult` and `ingest` it:
- **Strings only** (no word timings): `ASRResult(transcript: "the quick brown", isFinal: false)` — we tokenize; ink by state.
- **Word-level** (better): `words: [{ text, start?, end?, confidence? }]`.
- **Two models** (fast + accurate): feed the fast one as `role: draft`, the accurate one as `role: refined` — the reconciler time-aligns the corrections onto the draft and diff-morphs them. (Same path whether it's two tiers of one model or two separate models.)

---

## Layout
| Path | What | Status |
|---|---|---|
| [`SPEC.md`](./SPEC.md) | The shared contract (model · behaviour · reconciler · config) | — |
| `core/` | **`@transcript-fx/core`** — `<revising-text>` + reconciler + adapters | builds, renders, tested |
| `swift/` | **`TranscriptFX`** — SwiftUI + reconciler + adapters (Deepgram/Apple/WhisperKit) | compiles, **9/9 tests** |
| `src/` | React reference lab (visual playground: `npm i && npm run dev`) | runs |

Reconciliation logic is verified **identical** on web + Swift against shared fixtures. MIT.
