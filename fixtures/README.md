# Shared reference fixtures

Runtime-agnostic recorded sessions both native runtimes replay to prove
**web ≡ Swift** (SPEC §5). A fixture is a JSON timeline of the four source
events — `append` · `revise` · `redact` · `finalize` (SPEC §1) — with a
presentation-only `gap` (ms) per event so a demo can replay it live.

| File | What |
|---|---|
| [`seed-session.json`](./seed-session.json) | The canonical session: 5 self-corrections (cue→Q3, to→two, their→there, tree→three, ate→eight) + 2 redactions (Acme, Sarah). |
| [`seed-session.schema.json`](./seed-session.schema.json) | The fixture contract (JSON Schema). |

## Replaying it

- **Web core** — `replaySession()` (`transcript-fx`) drives a
  `TranscriptReconciler` through the timeline and returns the emitted
  `RevisionEvent[]`. The parity test `core/src/fixture.test.ts` asserts the
  exact event sequence (a frozen golden) — that golden is the cross-runtime
  contract.
- **React lab** — `src/App.tsx` loads this same file and animates it, so the
  visual playground and the Swift demo are the *same interaction, two runtimes*.
- **SwiftUI** — `swift/` replays the equivalent timeline in `Demo.swift` and
  asserts the matching `RevisionEvent` sequence in its reconciler tests.

The `gap` field is for live playback only; it never affects the reconciled
result, so the parity assertion is deterministic and timing-independent.
