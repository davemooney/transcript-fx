# transcript-fx

> **The `*-fx` family** · **transcript-fx** — live, self-revising *transcription* · [reason-fx](https://github.com/davemooney/reason-fx) — make a model's *reasoning* honest and beautiful. Same house style, same craft, two domains.

Live, self-revising transcription text — done with craft. As speech-to-text streams, words arrive *provisional*, **correct themselves in place**, and settle when final.

<!-- Hero: the seed session correcting itself (cue→Q3, to→two, …) + Acme/Sarah redaction, Diff-morph effect. See assets/README.md to record it. -->
![transcript-fx — live corrections morphing in place](assets/hero.gif)

## The signature
- **Ink-settle** — confidence becomes type *weight*: volatile is light, final gains ink.
- **Diff-morph** — on a correction, only the *changed* characters animate.
- **Swipe redaction** — a green block sweeps to mask sensitive spans.
- **Correction flash** — a brief highlight so every revision is legible.

One spec, two native runtimes — verified identical on a shared fixture, not by claim:

- **`core/` — [`transcript-fx`](./core)** (web): framework-agnostic `<revising-text>` Web Component + reconciler + adapters. Per [`SPEC.md`](./SPEC.md).
- **`swift/` — [TranscriptFX](./swift)** (SwiftUI v2): a full transcript **presentation framework** — canonical input model (tiers, timestamps, confidence, speakers), an utterance-based reconciler with explicit revision events, and a speaker-aware paragraph renderer.

```
   your ASR · Deepgram · WhisperKit · Apple SpeechAnalyzer
                  │  normalize ↓
            ASRResult / TranscriptUpdate     ← the only type you produce
                  │  ingest ↓
            TranscriptReconciler             ← aligns tiers, keeps token identity,
                  │  events ↓                  emits explicit RevisionEvents
            <revising-text> / TranscriptView ← ink-settle · diff-morph · redaction
```

---

## 30-second quickstart (web)

```bash
# in any Vite/webpack/ESM project — or just the repo's own lab:
git clone https://github.com/davemooney/transcript-fx && cd transcript-fx
npm install && npm run dev          # the React lab plays the seed session, looping
```

Drop it into your app:

```js
import 'transcript-fx'                          // registers <revising-text>
import { bindReconciler } from 'transcript-fx'

const recon = bindReconciler(document.querySelector('revising-text'))

// feed it ANY ASR — map your model's output to { transcript|words, isFinal }
recon.ingest({ transcript: 'hello wrld', isFinal: false }, 'draft')
recon.ingest({ transcript: 'hello world', isFinal: true  }, 'refined') // "wrld"→"world" diff-morphs
```

```html
<revising-text></revising-text>
```

That's it — ink-settle, diff-morph, and the correction flash come for free. → full web guide: [`core/README.md`](./core/README.md)

## Integrate (web) — the fuller picture

**Install** (local path for now; `transcript-fx` once published):
```bash
npm install ./path/to/transcript-fx/core   # auto-builds on install
```

**Use** — bind a reconciler, feed it any ASR, read explicit events if you want them:
```js
import 'transcript-fx'
import { bindReconciler, deepgramToASR } from 'transcript-fx'

const recon = bindReconciler(document.getElementById('t'))

// ── from ANY source: map your model's output to ASRResult ──
recon.ingest({ words: [{ text: 'their', start: 0, end: 0.4, confidence: 0.5 }], isFinal: false }, 'draft')
const events = recon.ingest({ words: [{ text: 'there', start: 0, end: 0.4, confidence: 0.98 }], isFinal: true }, 'refined')
// events → [{ type: 'revise', id, oldText: 'their', newText: 'there' }]  (drive haptics / a11y / logging)

// ── or Deepgram, ready-made ──
ws.onmessage = (e) => recon.ingest(deepgramToASR(JSON.parse(e.data)), 'draft')
```
Minimum a source must give you: `{ transcript: "...", isFinal }` (or `words`). `confidence` unlocks ink-settle; `start/end` unlock clean two-source combining.

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
Whatever your model emits, build the canonical result and `ingest` it:
- **Strings only**: `{ transcript: "the quick brown", isFinal: false }` — we tokenize; ink by state.
- **Word-level** (better): `words: [{ text, start, end, confidence }]` — timestamps unlock surgical alignment, confidence unlocks ink-settle.
- **Two tiers** (fast + accurate): feed the fast one as `'draft'`, the accurate one as `'refined'` — the reconciler aligns corrections onto the preview (timestamps first, text second) and diff-morphs them. Same path for two tiers of one model or two separate models.

---

## Parity is a test, not a claim

Both runtimes replay the **same** recorded session — [`fixtures/seed-session.json`](./fixtures) (SPEC §5): 5 self-corrections + 2 redactions. The web core's [`fixture.test.ts`](./core/src/fixture.test.ts) asserts the exact `RevisionEvent` timeline (a frozen golden); the SwiftUI runtime asserts the same sequence. The React lab animates that very fixture, so the web playground and the Swift demo are the *same interaction, two runtimes*.

```bash
cd core && npm install && npm test     # 11/11 — incl. the cross-runtime parity golden
```

## Layout
| Path | What | Status |
|---|---|---|
| `core/` | **[`transcript-fx`](./core)** `v0.1` — `<revising-text>` + reconciler + adapters + `RevisionEvent`s | builds, tested (11/11) |
| `swift/` | **[TranscriptFX](./swift) v2** — presentation framework: session + reconciler + TranscriptView + adapters | builds, **34/34 tests** |
| `fixtures/` | shared reference sessions both runtimes replay ([SPEC §5](./SPEC.md)) | — |
| [`SPEC.md`](./SPEC.md) | the cross-runtime contract | — |
| `src/` | React reference lab (visual playground: `npm i && npm run dev`) | runs |

Dogfooded in **offrecørd**. MIT licensed — see [`LICENSE`](./LICENSE).
