# transcript-fx

Framework-agnostic `<revising-text>` Web Component for live, self-revising transcription text — ink-settle, diff-morph corrections, swipe redaction. Works in React, Vue, Svelte, or plain HTML.

## Install
```bash
npm install transcript-fx
```
Zero runtime dependencies. Ships ESM + type declarations. Node ≥ 18 for the
test/build toolchain; the package itself runs in any modern browser.

## Quickest start
```js
import 'transcript-fx'                  // registers the <revising-text> element
import { bindReconciler } from 'transcript-fx'

const recon = bindReconciler(document.querySelector('revising-text'))
recon.ingest({ transcript: 'hello wrld', isFinal: false }, 'draft')
recon.ingest({ transcript: 'hello world', isFinal: true }, 'refined')  // "wrld" → "world" diff-morphs
```

## The `ASRResult` you feed
```ts
type ASRWord   = { text: string; start?: number; end?: number; confidence?: number }  // seconds
type ASRResult = { words?: ASRWord[]; transcript?: string; isFinal: boolean }
```
Required: `transcript` (or `words`) + `isFinal`. `confidence` → ink-settle; `start/end` → clean two-source combining.

## Sources
```js
// Deepgram (ready-made)
import { deepgramToASR } from 'transcript-fx'
ws.onmessage = (e) => recon.ingest(deepgramToASR(JSON.parse(e.data)), 'draft')

// Any local model → just build an ASRResult
recon.ingest({ words: myWords.map(w => ({ text: w.t, start: w.s, end: w.e, confidence: w.p })), isFinal }, 'draft')

// Two models: fast draft + slow refiner
recon.ingest(fastResult, 'draft')      // shown instantly, light/low-confidence
recon.ingest(accurateResult, 'refined') // corrections morph in, settle solid
```

## Explicit revision events
Every `ingest` (and the reconciler's imperative `append`/`revise`/`redact`/`finalizeAll`)
returns the semantic `RevisionEvent[]` it produced — no snapshot diffing. Drive
haptics, a11y announcements, analytics, or custom rendering off them:
```js
const recon = new TranscriptReconciler({
  onEvents: (events) => { /* [{ type:'revise', id, oldText, newText }, …] */ },
})
// or read the return value directly:
const events = recon.ingest(refinedResult, 'refined')
```
Event types: `insert · remove · revise · replace · redact · finalize`.
**`revise` (and the per-token `revision` bump the morph/flash keys off) fires only on
a real tier-2 correction** — a volatile preview rewriting its own un-committed word
settles silently, so already-shown text never flashes before a refinement lands.
This is the same contract the SwiftUI runtime pins, so web ≡ Swift.

## Replay a reference fixture
```js
import { replaySession } from 'transcript-fx'
import seed from '../fixtures/seed-session.json' assert { type: 'json' }

const { tokens, events } = replaySession(seed) // deterministic, timing-independent
```
The shared fixtures (SPEC §5) are how parity with the SwiftUI runtime is *tested*.

## Imperative API (no reconciler)
The element is also a direct sink:
```js
const el = document.querySelector('revising-text')
el.pushToken('0', 'cue', 0.4)
el.revise('0', 'Q3')      // diff-morph + flash
el.redact('1')            // swipe
el.finalize()             // ink settles
```

## Styling
Self-contained (shadow DOM). Override via CSS vars on the element:
```css
revising-text { --rt-font: 1.4rem/1.7 system-ui; --rt-fg: #fafafa; }
```

## Framework notes
- **React:** `<revising-text ref={…}/>` then `bindReconciler(ref.current)`; or set `ref.current.tokens = […]`.
- **Vue:** add `revising-text` to `compilerOptions.isCustomElement`, then `:ref` and `bindReconciler`.
- Honours `prefers-reduced-motion`.

## API
`bindReconciler` · `TranscriptReconciler` · `replaySession` · `deepgramToASR` · `createDeepgramConsumer` · `RevisingTextElement`.
Types: `ASRResult` · `ASRWord` · `ReconToken` · `RevisionEvent` · `SessionFixture` · `SessionEvent`.

Part of the [`*-fx` family](https://github.com/davemooney/transcript-fx#readme) (with [reason-fx](https://github.com/davemooney/reason-fx)). MIT.
