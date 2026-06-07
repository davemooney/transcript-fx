# transcript-fx — Spec (v0.1)

The shared contract for "live, self-revising transcription text." Two native implementations (web + SwiftUI) conform to **this** — same input model, same behaviour, same config — so the SwiftUI build is a *port*, not a redesign.

## 1. Input model (normalized, provider-agnostic)
A transcript is an ordered list of **tokens**:

| field | type | meaning |
|---|---|---|
| `id` | string | stable identity across revisions |
| `text` | string | current text |
| `state` | `volatile` \| `final` | volatile = interim/uncommitted; final = committed |
| `confidence` | float 0–1, optional | model confidence |
| `redacted` | bool | sensitive span, masked |

**Events** the source emits (the only API surface a provider adapter must drive):
- `append(id, text, confidence?)` — new volatile token
- `revise(id, text)` — correction; replaces text, bumps confidence
- `redact(id)` — mask a token
- `finalize()` / `commit` — mark all (or up to a point) `final`

## 2. Provider adapters (one per platform, same target model)
- **Deepgram** — `is_final` → `state`; word `confidence`; a word changing between interim results → `revise`.
- **Apple SpeechAnalyzer** — volatile vs finalized results → `state`; `AttributedString` runs → tokens.
- **AssemblyAI / Whisper-stream** — partial→final transcripts → append/revise/finalize.

## 3. Visual behaviour (the signature — implement identically on both platforms)
- **Base — Ink-settle:** confidence + state render as **type weight + opacity**.
  - volatile + low-confidence (<0.6): ultra-light, ~0.4 opacity
  - volatile + ok: light, ~0.6 opacity
  - final: semibold, 1.0 opacity
  - transitions animate (~0.45s, smooth). *(SwiftUI: SF variable font; web: variable-weight font.)*
- **Correction — Diff-morph:** on `revise`, only the **changed characters** animate in (blur+rise+resolve); unchanged chars stay anchored. Plus a brief **indigo flash** (~1s) on the word for legibility. *(SwiftUI v1: word-level `contentTransition(.numericText())`; per-glyph Text Renderer is the upgrade.)*
- **Redaction — Swipe:** a solid green block with a brighter band sweeping left→right (~0.5s). Resting state stays a full block.
- **Caret:** blinking accent caret at the live end while streaming.

## 4. Config surface (same option names both platforms)
`baseFontSize`, weight ramp (`light`/`final`), opacity ramp, `confidenceThreshold` (0.6), correction duration (~0.35s) + flash duration (~1s), redaction color + sweep duration (~0.5s), `reduceMotion` (honour OS setting → no animation), redaction style.

## 5. Reference fixtures (prove the two match)
A recorded session as a JSON timeline of events (`append`/`revise`/`redact`/`finalize` + delays). Both web and SwiftUI demos **replay the same fixture** → identical, deterministic output → side-by-side "same interaction, two runtimes" clip. The current React lab's `SCRIPT` array is the seed fixture (cue→Q3, to→two, their→there, tree→three, ate→eight; redact Acme, Sarah).

## 6. Platforms
- **Web** — framework-agnostic core + React/Vue bindings (reference impl = the React lab in this repo).
- **Apple** — SwiftUI; weight via variable SF font, redaction via overlay, diff via `contentTransition` → Text Renderer (iOS/macOS 18+) for true per-glyph morphs. Dogfooded in offrecørd.
