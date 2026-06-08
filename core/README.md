# @transcript-fx/core

Framework-agnostic `<revising-text>` Web Component for live, self-revising transcription text — ink-settle, diff-morph corrections, swipe redaction. Works in React, Vue, Svelte, or plain HTML.

## Install
```bash
# local (for now) — auto-builds on install via the prepare script
npm install /ABS/PATH/to/transcript-fx/core
# once published:  npm install @transcript-fx/core
```

## Quickest start
```js
import '@transcript-fx/core'                  // registers the <revising-text> element
import { bindReconciler } from '@transcript-fx/core'

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
import { deepgramToASR } from '@transcript-fx/core'
ws.onmessage = (e) => recon.ingest(deepgramToASR(JSON.parse(e.data)), 'draft')

// Any local model → just build an ASRResult
recon.ingest({ words: myWords.map(w => ({ text: w.t, start: w.s, end: w.e, confidence: w.p })), isFinal }, 'draft')

// Two models: fast draft + slow refiner
recon.ingest(fastResult, 'draft')      // shown instantly, light/low-confidence
recon.ingest(accurateResult, 'refined') // corrections morph in, settle solid
```

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

API: `bindReconciler`, `TranscriptReconciler`, `deepgramToASR`, `createDeepgramConsumer`, `RevisingTextElement`, types `ASRResult` / `ASRWord` / `ReconToken`.
