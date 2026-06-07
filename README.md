# transcript-fx

Live, self-revising transcription text — done with craft. As speech-to-text streams, words arrive *volatile*, correct themselves in place, redact sensitive spans, and settle when final.

**One spec, multiple native runtimes:**

| Path | What | Status |
|---|---|---|
| [`SPEC.md`](./SPEC.md) | The shared contract — token model, behaviour, config, fixtures | — |
| `src/` | React reference lab (the visual playground) | runs (`npm i && npm run dev`) |
| `core/` | **`@transcript-fx/core`** — framework-agnostic `<revising-text>` Web Component | builds + renders |
| `swift/` | **`TranscriptFX`** — SwiftUI port (Text Renderer per-glyph) | compiles, tests pass |

## The signature
- **Ink-settle** — confidence renders as type *weight*: volatile is light/hairline, final gains ink.
- **Diff-morph** — on a correction, only the *changed* characters animate; the rest stay anchored.
- **Swipe redaction** — a green block sweeps across to mask sensitive spans.
- **Correction flash** — a brief highlight so every revision is legible.

## Providers
Deepgram adapter ships on both runtimes (web + Swift), unit-tested against the same fixtures so they produce identical event sequences. Apple SpeechAnalyzer / AssemblyAI map onto the same model (see SPEC §2).

## Quick start (Web Component)
```js
import '@transcript-fx/core'
const el = document.querySelector('revising-text')
el.pushToken('0-0', 'cue', 0.4)
el.revise('0-0', 'Q3')
el.redact('0-1')
el.finalize()
// live: createDeepgramConsumer(el.asSink())
```

## Quick start (SwiftUI)
```swift
import TranscriptFX
@StateObject var model = TranscriptModel()
RevisingText(tokens: model.tokens)   // drive via DeepgramConsumer(model:)
```

MIT.
